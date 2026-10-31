// Windows D3D11 RenderBackend (Phase 14, D3D-06). See d3d11_backend.h.
//
// One ID3D11Device per backend (so per controller), created on Flutter's
// adapter. mpv renders with its D3D11 render API (patch 0010, gpu-next branch
// in patch 0004) into BGRA8 textures created with a legacy KMT shared handle;
// the plugin passes the handle to Flutter. Flutter's ANGLE consumer has no
// fence or keyed mutex, so a frame is published only after its GPU work has
// completed here: an ID3D11Fence signalled after each render, or a
// D3D11_QUERY_EVENT per slot when fences are unavailable.
//
// Thread rules (T-14-17): Create runs on the thread that starts the renderer;
// Render, Wait, AllocTargets, FreeRetired and Release run on the render
// thread. The immediate context is touched only there (render_d3d11.h: mpv
// renders with the immediate context and does not restore its state) plus mpv's
// d3d11va decode thread, which the device's multithread protection serialises.
// The raster thread never reaches this file: it reads the shared handle cached
// in D3D11Interop::Texture.
#include "d3d11_backend.h"

#include <d3d11_4.h>
#include <windows.h>
#include <wrl/client.h>

#include <mpv/render_d3d11.h>
#include <mpv/render_vk.h>  // MPV_RENDER_PARAM_VULKAN_RENDERER (renderer select/report)

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

#include "d3d11_interop.h"

namespace mpv_kit {
namespace {

using Microsoft::WRL::ComPtr;
using Texture = D3D11Interop::Texture;

/// Upper bound of every wait on the GPU (Vulkan's WaitImage uses the same 1 s):
/// a stuck GPU must not wedge the render thread. The timeout becomes
/// gpu_timeout and the engine's backoff.
constexpr DWORD kWaitTimeoutMs = 1000;

/// Polls with SwitchToThread this many times before sleeping 1 ms per poll;
/// a frame normally finishes within a few milliseconds and Sleep(1) can cost
/// a whole timer tick.
constexpr int kQuerySpinPolls = 64;

/// Flutter's DXGI shared-handle path expects BGRA8.
constexpr DXGI_FORMAT kFormat = DXGI_FORMAT_B8G8R8A8_UNORM;

/// Same sinks as the plugin's renderer log: DebugView and stderr.
void Log(const std::string& msg) {
  OutputDebugStringA((msg + "\n").c_str());
  if (stderr) fprintf(stderr, "%s\n", msg.c_str());
}

std::string Hex(HRESULT hr) {
  char code[16];
  snprintf(code, sizeof(code), "0x%08lX", static_cast<unsigned long>(hr));
  return code;
}

std::string Utf8(const wchar_t* wide) {
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr,
                                    nullptr);
  if (n <= 1) return {};
  std::string out(static_cast<size_t>(n - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), n, nullptr, nullptr);
  return out;
}

#ifndef NDEBUG
/// The value of environment variable [name] ("" when unset). Debug builds
/// only. The CRT's getenv is deprecated on Windows (C4996, an error under the
/// plugin's /WX), same as in video_renderer.cc; _dupenv_s reads the same
/// environment.
std::string DebugEnv(const char* name) {
  char* value = nullptr;
  size_t size = 0;
  if (_dupenv_s(&value, &size, name) != 0 || !value) return {};
  std::string out(value);
  std::free(value);
  return out;
}
#endif

/// True when MPV_KIT_D3D11_SYNC=query asked for the query path. Debug builds
/// only (T-14-20): a release plugin cannot be steered by the environment.
bool ForceQuerySync() {
#ifndef NDEBUG
  return DebugEnv("MPV_KIT_D3D11_SYNC") == "query";
#else
  return false;
#endif
}

/// Failure injection of one backend (see the file header). Empty in release
/// builds.
struct Injection {
  bool create_fail = false;  // device creation fails
  int removed_after = 0;     // > 0: removed after this many successful renders
};

/// Reads MPV_KIT_D3D11_INJECT once. An invalid value is logged and treated as
/// unset. Debug builds only; release builds return the empty Injection.
Injection ReadInjection() {
  Injection injection;
#ifndef NDEBUG
  const std::string value = DebugEnv("MPV_KIT_D3D11_INJECT");
  if (value.empty()) return injection;
  const std::string removed = "device-removed:";
  if (value == "create-fail") {
    injection.create_fail = true;
  } else if (value.compare(0, removed.size(), removed) == 0) {
    const std::string digits = value.substr(removed.size());
    const bool numeric =
        !digits.empty() && digits.size() <= 9 &&
        digits.find_first_not_of("0123456789") == std::string::npos;
    injection.removed_after = numeric ? std::atoi(digits.c_str()) : 0;
  }
  if (!injection.create_fail && injection.removed_after <= 0) {
    Log("mpv_kit: MPV_KIT_D3D11_INJECT=" + value +
        " ignored (expected create-fail or device-removed:<n>, n >= 1)");
    return Injection{};
  }
  Log("mpv_kit: D3D11 failure injection active: " + value);
#endif
  return injection;
}

/// True when [hr] says the device is gone (a query's GetData result).
bool IsRemovalError(HRESULT hr) {
  return hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET ||
         hr == DXGI_ERROR_DRIVER_INTERNAL_ERROR;
}

/// One ring slot: the shared texture handed to Flutter plus its completion
/// state. [ready] is the fence value the slot's last successful render
/// signals (0: nothing to wait for); [pending] marks an unfinished query.
struct Slot {
  std::unique_ptr<Texture> texture;
  ComPtr<ID3D11Query> query;  // query mode only
  uint64_t ready = 0;         // fence mode only
  bool pending = false;       // query mode only
};

/// MPV_RENDER_API_TYPE_D3D11 into a ring of KMT-shared BGRA8 textures.
class D3D11RenderBackend final : public RenderBackend {
 public:
  explicit D3D11RenderBackend(IDXGIAdapter* adapter) : adapter_(adapter) {}

  ~D3D11RenderBackend() override {
    // Textures first, then their sync objects, the context, the device last
    // (render_backend.h: the device outlives mpv's objects on it; Release
    // already freed the render context).
    slots_.clear();
    retired_.clear();
    fence_.Reset();
    if (fence_event_) CloseHandle(fence_event_);
    context4_.Reset();
    if (context_) context_->Flush();  // lets the runtime drop the textures
    context_.Reset();
    device_.Reset();
  }

  const char* wire_name() const override { return "d3d11"; }
  // Backend::kVulkan names the frame class "shared GPU image": the plugin
  // hands those to GpuSurfaceTexture. A new enum value would change the
  // shared header; Dart maps the wire name "d3d11" to MpvVideoBackend.vulkan
  // (ADR 0004).
  Backend frame_kind() const override { return Backend::kVulkan; }
  bool pipelined() const override { return true; }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    *out = nullptr;
    if (!device_ && !device_failed_) InitDevice();
    if (device_failed_) {
      *why = device_error_;
      return MPV_ERROR_GENERIC;  // mpv was not asked (see device_failed())
    }
    mpv_d3d11_init_params init{};
    init.device = device_.Get();  // libmpv adds its own reference
    int advanced = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char*>(MPV_RENDER_API_TYPE_D3D11)},
        {MPV_RENDER_PARAM_D3D11_INIT_PARAMS, &init},
        {MPV_RENDER_PARAM_VULKAN_RENDERER, const_cast<char*>(renderer)},
        {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_create(out, handle, params);
    if (err < 0) {
      *why = "mpv_render_context_create: " +
             SanitizeReasonField(api.error_string(err));
      *out = nullptr;
    }
    return err;
  }
  bool device_failed() const override { return device_failed_; }
  std::string device_name() const override { return device_name_; }
  std::string RendererName(const MpvApi& api,
                           mpv_render_context* ctx) const override {
    // Ask mpv which renderer it really built: a libmpv without the renderer
    // parameter ignores it and always uses its default.
    const char* active = nullptr;
    const int info = api.render_context_get_info(
        ctx, {MPV_RENDER_PARAM_VULKAN_RENDERER, &active});
    return info >= 0 && active ? active : "unknown renderer";
  }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    FreeRetired();  // the previous generation's survivor had its quarantine
    if (width > D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION ||
        height > D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION) {
      *error = "texture " + std::to_string(width) + "x" +
               std::to_string(height) + " exceeds the D3D11 limit " +
               std::to_string(D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION);
      slots_.clear();
      return false;
    }
    // Only the compositor-facing front image survives into retirement (its
    // platform pointer may still be handed out until the engine resets its
    // front); the rest of the old ring is released at once. Flutter's own
    // COM reference keeps a texture it still samples alive.
    if (keep_slot >= 0 && keep_slot < static_cast<int>(slots_.size()) &&
        slots_[keep_slot].texture)
      retired_.push_back(std::move(slots_[keep_slot].texture));
    slots_.clear();
    slots_.resize(static_cast<size_t>(count));
    for (Slot& slot : slots_) {
      if (!CreateSlot(width, height, &slot, error)) {
        slots_.clear();  // all or nothing: the engine retries a smaller ring
        retired_.clear();
        return false;
      }
    }
    return true;
  }
  void FreeRetired() override { retired_.clear(); }
  TargetView FrameFor(int slot) override {
    TargetView view;
    view.platform = slots_[static_cast<size_t>(slot)].texture.get();
    return view;
  }

  int Render(const MpvApi& api, mpv_render_context* ctx, int slot, int width,
             int height) override {
    // The texture's own size: it is the ring's, which is [width]x[height].
    (void)width;
    (void)height;
    Slot& s = slots_[static_cast<size_t>(slot)];
    mpv_d3d11_fbo fbo{};
    fbo.tex = s.texture->texture.Get();
    int flip = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_D3D11_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_render(ctx, params);
    // A failed render signals nothing: leaving the slot's previous ready
    // value alone means the next Wait never waits for a value that will not
    // come (the Vulkan backend's RollbackSignalValue).
    if (err < 0) return err;
    rendered_++;  // injection clock (device-removed:<n>); render thread only
    if (fence_mode_) {
      s.ready = ++fence_value_;
      context4_->Signal(fence_.Get(), s.ready);
    } else {
      context_->End(s.query.Get());
      s.pending = true;
    }
    // Submit now: mpv recorded on the immediate context, and nothing else
    // would flush it before Wait.
    context_->Flush();
    return err;
  }

  WaitResult Wait(int slot) override {
    if (DeviceRemoved()) return WaitResult::kDeviceLost;
    Slot& s = slots_[static_cast<size_t>(slot)];
    return fence_mode_ ? WaitFence(s) : WaitQuery(&s);
  }

  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    api.render_context_free(ctx);
  }

 private:
  /// Creates the device on [adapter_], then its multithread protection and
  /// the sync objects; sets device_failed_/device_error_ when it cannot.
  void InitDevice() {
    ComPtr<IDXGIAdapter> adapter = std::move(adapter_);
    if (!adapter) return Fail("no DXGI adapter");
    DXGI_ADAPTER_DESC desc{};
    if (SUCCEEDED(adapter->GetDesc(&desc))) device_name_ = Utf8(desc.Description);
    if (device_name_.empty()) device_name_ = "unknown adapter";
    injection_ = ReadInjection();
    if (injection_.create_fail) {
      // Same path as a real failure: Fail() makes every later candidate of
      // this api carry the same trail. The marker keeps the cause honest.
      return Fail("d3d11 device creation failed: " +
                  Hex(DXGI_ERROR_UNSUPPORTED) + " (injected)");
    }

    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                        D3D_FEATURE_LEVEL_11_0};
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT |
                 D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    HRESULT hr = D3D11CreateDevice(
        adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags, levels,
        static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION, &device_,
        nullptr, &context_);
    if (FAILED(hr)) {
      // spikes.txt gate video_support=retry-without: Basic Render Driver and
      // WARP refuse VIDEO_SUPPORT, hardware adapters take it.
      const HRESULT first = hr;
      flags &= ~static_cast<UINT>(D3D11_CREATE_DEVICE_VIDEO_SUPPORT);
      hr = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                             flags, levels,
                             static_cast<UINT>(std::size(levels)),
                             D3D11_SDK_VERSION, &device_, nullptr, &context_);
      if (SUCCEEDED(hr))
        Log("mpv_kit: d3d11 device created without VIDEO_SUPPORT (" +
            Hex(first) + ")");
    }
    if (FAILED(hr))
      return Fail("d3d11 device creation failed: " + Hex(hr));

    // mpv decodes with d3d11va on its own thread on this device.
    ComPtr<ID3D11Multithread> multithread;
    if (FAILED(device_.As(&multithread)))
      return Fail("d3d11 multithread protection unavailable");
    multithread->SetMultithreadProtected(TRUE);
    InitSync();
  }

  /// Picks the fence path when the device, the context and an event support
  /// it (spikes.txt gate fence=fence), else the D3D11_QUERY_EVENT path.
  void InitSync() {
    if (ForceQuerySync()) return;
    ComPtr<ID3D11Device5> device5;
    ComPtr<ID3D11DeviceContext4> context4;
    if (FAILED(device_.As(&device5)) || FAILED(context_.As(&context4))) return;
    ComPtr<ID3D11Fence> fence;
    if (FAILED(device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                                    IID_PPV_ARGS(&fence))))
      return;
    // Auto-reset: SetEventOnCompletion arms it, one wait consumes it.
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!event) return;
    fence_ = std::move(fence);
    context4_ = std::move(context4);
    fence_event_ = event;
    fence_mode_ = true;
  }

  void Fail(const std::string& why) {
    device_failed_ = true;
    device_error_ = SanitizeReasonField(why);
    context_.Reset();
    device_.Reset();
  }

  bool CreateSlot(int width, int height, Slot* slot, std::string* error) {
    D3D11_TEXTURE2D_DESC td{};
    td.Width = static_cast<UINT>(width);
    td.Height = static_cast<UINT>(height);
    td.MipLevels = 1;
    td.ArraySize = 1;
    td.Format = kFormat;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    // No UNORDERED_ACCESS (spikes.txt gate typed_uav decision=no-uav): mpv
    // renders through a render target view, as the Vulkan path's images.
    td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    td.MiscFlags = D3D11_RESOURCE_MISC_SHARED;  // legacy KMT handle for ANGLE
    auto tex = std::make_unique<Texture>();
    ComPtr<IDXGIResource> resource;
    HRESULT hr = device_->CreateTexture2D(&td, nullptr, &tex->texture);
    if (SUCCEEDED(hr)) hr = tex->texture.As(&resource);
    if (SUCCEEDED(hr)) hr = resource->GetSharedHandle(&tex->shared_handle);
    if (FAILED(hr)) {
      *error = "failed to create shared texture: " + Hex(hr);
      return false;
    }
    if (!fence_mode_) {
      D3D11_QUERY_DESC qd{};
      qd.Query = D3D11_QUERY_EVENT;
      hr = device_->CreateQuery(&qd, &slot->query);
      if (FAILED(hr)) {
        *error = "failed to create completion query: " + Hex(hr);
        return false;
      }
    }
    slot->texture = std::move(tex);
    return true;
  }

  /// The one source of the device removal reason: the real runtime, or in a
  /// debug build the injected DEVICE_REMOVED once enough frames rendered.
  HRESULT RemovedReason() const {
    if (injection_.removed_after > 0 && rendered_ >= injection_.removed_after)
      return DXGI_ERROR_DEVICE_REMOVED;
    return device_ ? device_->GetDeviceRemovedReason() : S_OK;
  }

  bool DeviceRemoved() const { return FAILED(RemovedReason()); }

  /// A wait that ran out of time: device removal is the more precise cause.
  WaitResult Timeout() const {
    return DeviceRemoved() ? WaitResult::kDeviceLost : WaitResult::kTimeout;
  }

  WaitResult WaitFence(const Slot& s) {
    if (s.ready == 0) return WaitResult::kOk;
    using Clock = std::chrono::steady_clock;
    const auto deadline = Clock::now() + std::chrono::milliseconds(kWaitTimeoutMs);
    for (;;) {
      const uint64_t completed = fence_->GetCompletedValue();
      // The runtime reports a removed device as the maximum value.
      if (completed == UINT64_MAX) return WaitResult::kDeviceLost;
      if (completed >= s.ready) return WaitResult::kOk;
      const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(
          deadline - Clock::now());
      if (left.count() <= 0) return Timeout();
      // Clear a signal left by an earlier timed-out wait, then arm for this
      // value; the loop re-checks the fence after every wake-up.
      ResetEvent(fence_event_);
      if (FAILED(fence_->SetEventOnCompletion(s.ready, fence_event_)))
        return Timeout();
      WaitForSingleObject(fence_event_, static_cast<DWORD>(left.count()));
    }
  }

  WaitResult WaitQuery(Slot* s) {
    if (!s->pending) return WaitResult::kOk;
    using Clock = std::chrono::steady_clock;
    const auto deadline = Clock::now() + std::chrono::milliseconds(kWaitTimeoutMs);
    for (int poll = 0;; poll++) {
      BOOL done = FALSE;
      // No D3D11_ASYNC_GETDATA_DONOTFLUSH: Render flushed already, but on the
      // RTX 4060 the event query then stayed S_FALSE for the whole 1 s wait
      // in 5 of 6 runs (gpu_timeout); letting GetData flush as well completed
      // it every time (6 of 6). S_FALSE means not finished yet.
      const HRESULT hr =
          context_->GetData(s->query.Get(), &done, sizeof(done), 0);
      if (hr == S_OK) {
        s->pending = false;
        return WaitResult::kOk;
      }
      if (IsRemovalError(hr)) return WaitResult::kDeviceLost;
      if (FAILED(hr) || Clock::now() >= deadline) return Timeout();
      if (poll < kQuerySpinPolls) {
        SwitchToThread();
      } else {
        Sleep(1);
      }
    }
  }

  ComPtr<IDXGIAdapter> adapter_;  // consumed by InitDevice
  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11DeviceContext4> context4_;  // fence mode only
  ComPtr<ID3D11Fence> fence_;              // fence mode only
  HANDLE fence_event_ = nullptr;           // fence mode only
  bool fence_mode_ = false;
  uint64_t fence_value_ = 0;  // monotonic across ring reallocations
  bool device_failed_ = false;
  Injection injection_;       // debug builds only; empty otherwise
  int rendered_ = 0;          // successful renders (injection clock)
  std::string device_error_;  // why InitDevice failed, sanitized
  std::string device_name_;
  std::vector<Slot> slots_;
  std::vector<std::unique_ptr<Texture>> retired_;
};

}  // namespace

std::unique_ptr<RenderBackend> CreateD3D11Backend(IDXGIAdapter* adapter) {
  return std::make_unique<D3D11RenderBackend>(adapter);
}

}  // namespace mpv_kit
