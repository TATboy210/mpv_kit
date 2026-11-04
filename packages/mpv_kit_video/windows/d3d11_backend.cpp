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
/// Consecutive unusable query completions before the renderer reports
/// itself lost (query mode only; the device may still be present).
constexpr int kQueryFailureLimit = 3;

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
  bool create_fail = false;       // device creation fails
  int removed_after = 0;          // > 0: removed after N renders
  bool removed_at_alloc = false;  // next allocation fails, reports removal
  int render_fail_at = 0;         // > 0: this render fails and reports removal
  int signal_fail_at = 0;         // > 0: this Signal fails (query fallback)
  bool query_fail = false;        // GetData always fails (escalation)
  int alloc_fail_at = 0;          // > 0: this AllocTargets fails (no removal)
  bool no_11_1 = false;           // force the 11_0-only creation retry
  bool removed_injected = false;  // set when an injection reports removal
};

/// Reads MPV_KIT_D3D11_INJECT once. An invalid value is logged and treated as
/// unset. Debug builds only; release builds return the empty Injection.
Injection ReadInjection() {
  Injection injection;
#ifndef NDEBUG
  const std::string value = DebugEnv("MPV_KIT_D3D11_INJECT");
  if (value.empty()) return injection;
  const std::string removed = "device-removed:";
  auto is_number = [](const std::string& t) {
    return !t.empty() && t.size() <= 9 &&
           t.find_first_not_of("0123456789") == std::string::npos;
  };
  auto tail = [&](const char* prefix) {
    const std::string p(prefix);
    return value.compare(0, p.size(), p) == 0 ? value.substr(p.size())
                                              : std::string();
  };
  const std::string render_at = tail("device-removed:render:");
  const std::string signal_at = tail("signal-fail:");
  if (value == "create-fail") {
    injection.create_fail = true;
  } else if (value == "create-no-11-1") {
    injection.no_11_1 = true;
  } else if (value == "device-removed:alloc") {
    injection.removed_at_alloc = true;
  } else if (value == "query-getdata-fail") {
    injection.query_fail = true;
  } else if (!tail("alloc-fail:").empty() && is_number(tail("alloc-fail:"))) {
    injection.alloc_fail_at = std::atoi(tail("alloc-fail:").c_str());
  } else if (!render_at.empty() && is_number(render_at)) {
    injection.render_fail_at = std::atoi(render_at.c_str());
  } else if (!signal_at.empty() && is_number(signal_at)) {
    injection.signal_fail_at = std::atoi(signal_at.c_str());
  } else if (value.compare(0, removed.size(), removed) == 0) {
    const std::string digits = value.substr(removed.size());
    const bool numeric =
        !digits.empty() && digits.size() <= 9 &&
        digits.find_first_not_of("0123456789") == std::string::npos;
    injection.removed_after = numeric ? std::atoi(digits.c_str()) : 0;
  }
  if (!injection.create_fail && !injection.no_11_1 &&
      !injection.removed_at_alloc && !injection.query_fail &&
      injection.alloc_fail_at <= 0 &&
      injection.removed_after <= 0 && injection.render_fail_at <= 0 &&
      injection.signal_fail_at <= 0) {
    Log("mpv_kit: MPV_KIT_D3D11_INJECT=" + value +
        " ignored (expected create-fail, create-no-11-1, "
        "device-removed:<n>|alloc|render:<n>, signal-fail:<n>, "
        "query-getdata-fail or alloc-fail:<n>)");
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
enum class SlotSync { kNone, kFence, kQuery };

struct Slot {
  std::unique_ptr<Texture> texture;
  ComPtr<ID3D11Query> query;  // created for every slot (fence fallback)
  uint64_t ready = 0;         // kFence: value the last render signals
  bool pending = false;       // kQuery: End() recorded, GetData outstanding
  SlotSync sync = SlotSync::kNone;
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
    if (fence_mode_ && fence_ && fence_value_ > 0) {
      // A timed-out WaitFence left a SetEventOnCompletion armed on this
      // event; drain it before the handle goes away, or the runtime could
      // later signal a recycled handle.
      ResetEvent(fence_event_);
      if (SUCCEEDED(fence_->SetEventOnCompletion(fence_value_, fence_event_)))
        WaitForSingleObject(fence_event_, kWaitTimeoutMs);
    }
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

  bool keeps_retired_front() const override { return true; }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    if (injection_.removed_at_alloc && !injection_.removed_injected) {
      injection_.removed_injected = true;
      *error = "device removed (injected during allocation)";
      return false;
    }
    if (injection_.alloc_fail_at > 0 && allocs_ == injection_.alloc_fail_at) {
      allocs_++;
      *error = "CreateTexture2D failed: 0x8007000E (injected)";
      slots_.clear();
      return false;
    }
    allocs_++;
    // kKeepRetiredFront: a resize arrived before any new-size frame, so the
    // retired survivor is still the only picture. Keep it; the engine's
    // FreeRetired (after the new-size frame and the quarantine) ends it.
    // Releasing the old ring without a GPU wait (unlike the Vulkan backend's
    // per-image timeline wait) is safe here because: D3D11 Release() defers
    // the actual destruction until in-flight work retires; Flutter's ANGLE
    // consumer holds its own COM reference on any texture it still samples;
    // and fence_value_ is monotonic across reallocations while new slots
    // start at ready = 0, so no wait ever consults a stale value.
    if (keep_slot != kKeepRetiredFront)
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
    if (err < 0) {
      // A failed render signals nothing: leaving the slot's previous fence
      // value alone means the next Wait never waits for a value that will
      // not come (the Vulkan backend's RollbackSignalValue). mpv may still
      // have submitted drawing before reporting the error (patch 0004 turns
      // a late failure into MPV_ERROR_GENERIC after pl_gpu_flush), so record
      // this slot's completion through its query: an End on an empty or
      // aborted command list completes at once, and the slot is never
      // published without a marker regardless of where in mpv it failed.
      s.ready = 0;
      s.sync = SlotSync::kQuery;
      s.pending = true;
      context_->End(s.query.Get());
      context_->Flush();
      return err;
    }
    rendered_++;  // injection clock; render thread only
    if (injection_.render_fail_at > 0 &&
        rendered_ >= injection_.render_fail_at) {
      injection_.removed_injected = true;
      return MPV_ERROR_GENERIC;
    }
    if (fence_mode_) {
      const uint64_t next = fence_value_ + 1;
      HRESULT hr = E_FAIL;
      const bool inject_fail = injection_.signal_fail_at > 0 &&
                               rendered_ >= injection_.signal_fail_at;
      if (!inject_fail) hr = context4_->Signal(fence_.Get(), next);
      if (SUCCEEDED(hr)) {
        fence_value_ = next;
        s.ready = next;
        s.pending = false;
        s.sync = SlotSync::kFence;
      } else {
        // Do not advance fence_value_: no slot may wait on a value that
        // was never signalled. This slot's query records the completion
        // after the render commands instead.
        s.ready = 0;
        s.sync = SlotSync::kQuery;
        s.pending = true;
        context_->End(s.query.Get());
        if (!signal_failed_logged_) {
          signal_failed_logged_ = true;
          Log("mpv_kit: ID3D11Fence Signal failed (" + Hex(hr) +
              "); using the query completion path");
        }
      }
    } else {
      s.sync = SlotSync::kQuery;
      context_->End(s.query.Get());
      s.pending = true;
    }
    // mpv flushed its own work inside render_context_render (done_frame ->
    // ra_d3d11_flush), i.e. BEFORE the Signal/End above; this Flush is
    // what submits the completion marker.
    context_->Flush();
    return err;
  }

  WaitResult Wait(int slot) override {
    if (DeviceRemoved()) return WaitResult::kDeviceLost;
    Slot& s = slots_[static_cast<size_t>(slot)];
    switch (s.sync) {
      case SlotSync::kFence:
        return WaitFence(s);
      case SlotSync::kQuery:
        return WaitQuery(&s);
      case SlotSync::kNone:
        return WaitResult::kOk;
    }
    return WaitResult::kOk;
  }

  bool device_removed() const override { return DeviceRemoved(); }
  const char* sync_mode() const override {
    return fence_mode_ ? "fence" : "query";
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

    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT |
                 D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    HRESULT hr = CreateD3D11DeviceWithFeatureLevelFallback(
        adapter.Get(), flags, injection_.no_11_1, &device_, &context_);
    if (FAILED(hr)) {
      // spikes.txt gate video_support=retry-without: Basic Render Driver and
      // WARP refuse VIDEO_SUPPORT, hardware adapters take it.
      const HRESULT first = hr;
      flags &= ~static_cast<UINT>(D3D11_CREATE_DEVICE_VIDEO_SUPPORT);
      hr = CreateD3D11DeviceWithFeatureLevelFallback(
          adapter.Get(), flags, injection_.no_11_1, &device_, &context_);
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
    if (FAILED(device_.As(&device5)) || FAILED(context_.As(&context4))) {
      Log("mpv_kit: d3d11 fence unavailable (no ID3D11Device5/Context4); "
          "using query completion");
      return;
    }
    ComPtr<ID3D11Fence> fence;
    const HRESULT fence_hr = device5->CreateFence(
        0, D3D11_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence));
    if (FAILED(fence_hr)) {
      Log("mpv_kit: CreateFence failed: " + Hex(fence_hr) +
          "; using query completion");
      return;
    }
    // Auto-reset: SetEventOnCompletion arms it, one wait consumes it.
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!event) {
      Log("mpv_kit: CreateEventW failed; using query completion");
      return;
    }
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
    // Every slot owns a query: the fallback when a fence Signal fails.
    D3D11_QUERY_DESC qd{};
    qd.Query = D3D11_QUERY_EVENT;
    hr = device_->CreateQuery(&qd, &slot->query);
    if (FAILED(hr)) {
      *error = "failed to create completion query: " + Hex(hr);
      return false;
    }
    slot->texture = std::move(tex);
    return true;
  }

  /// The one source of the device removal reason: the real runtime, or in a
  /// debug build the injected DEVICE_REMOVED once enough frames rendered.
  HRESULT RemovedReason() const {
    if (injection_.removed_injected) return DXGI_ERROR_DEVICE_REMOVED;
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
      // A broken handle would otherwise spin hot until the deadline.
      if (WaitForSingleObject(fence_event_,
                              static_cast<DWORD>(left.count())) == WAIT_FAILED)
        return Timeout();
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
      const HRESULT hr = injection_.query_fail
          ? E_FAIL
          : context_->GetData(s->query.Get(), &done, sizeof(done), 0);
      if (hr == S_OK) {
        s->pending = false;
        query_failures_ = 0;
        return WaitResult::kOk;
      }
      if (IsRemovalError(hr)) return WaitResult::kDeviceLost;
      if (FAILED(hr) || Clock::now() >= deadline) {
        // A completion path that never becomes usable wedges the renderer,
        // not just this slot (the ring rotates): count globally so three
        // strikes declare the renderer unusable instead of one per slot.
        if (++query_failures_ >= kQueryFailureLimit)
          return WaitResult::kDeviceLost;
        return Timeout();
      }
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
  bool signal_failed_logged_ = false;  // render thread only
  uint64_t fence_value_ = 0;  // monotonic across ring reallocations
  int query_failures_ = 0;    // consecutive unusable completions (query mode)
  bool device_failed_ = false;
  Injection injection_;       // debug builds only; empty otherwise
  int rendered_ = 0;          // successful renders (injection clock)
  int allocs_ = 0;            // AllocTargets calls (injection clock)
  std::string device_error_;  // why InitDevice failed, sanitized
  std::string device_name_;
  std::vector<Slot> slots_;
  std::vector<std::unique_ptr<Texture>> retired_;
};

}  // namespace

HRESULT CreateD3D11DeviceWithFeatureLevelFallback(
    IDXGIAdapter* adapter, UINT flags, bool skip_11_1,
    ID3D11Device** device, ID3D11DeviceContext** context) {
  const D3D_FEATURE_LEVEL levels_11_1[] = {D3D_FEATURE_LEVEL_11_1,
                                          D3D_FEATURE_LEVEL_11_0};
  const D3D_FEATURE_LEVEL levels_11_0[] = {D3D_FEATURE_LEVEL_11_0};
  ComPtr<ID3D11Device> made;
  ComPtr<ID3D11DeviceContext> made_context;
  HRESULT hr = E_FAIL;
  if (!skip_11_1) {
    hr = D3D11CreateDevice(
        adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags, levels_11_1,
        static_cast<UINT>(std::size(levels_11_1)), D3D11_SDK_VERSION,
        &made, nullptr, &made_context);
    if (SUCCEEDED(hr)) {
      if (device) *device = made.Detach();
      if (context) *context = made_context.Detach();
      return hr;
    }
    if (hr != E_INVALIDARG) return hr;
  }
  made.Reset();
  made_context.Reset();
  hr = D3D11CreateDevice(
      adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags, levels_11_0,
      static_cast<UINT>(std::size(levels_11_0)), D3D11_SDK_VERSION, &made,
      nullptr, &made_context);
  if (SUCCEEDED(hr)) {
    if (device) *device = made.Detach();
    if (context) *context = made_context.Detach();
  }
  return hr;
}

std::unique_ptr<RenderBackend> CreateD3D11Backend(IDXGIAdapter* adapter) {
  return std::make_unique<D3D11RenderBackend>(adapter);
}

}  // namespace mpv_kit
