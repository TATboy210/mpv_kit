// Windows plugin: one Flutter texture per mpv instance.
//
// Method channel "mpv_kit_video" (same contract on every platform):
//   create  {symbols: List<int>, handle: int, renderer: String}
//           renderer: "auto" | "gpu-next" | "gpu" | "software"
//           -> {textureId: int, backend: "d3d11"|"opengl"|"vulkan"|"software",
//               reason: String}
//           backend is the winning backend's own wire name
//           (VideoRenderer::wire_name(), ADR 0004 Decision 2). When no
//           backend works: error render_init / "no usable render backend",
//           details: String, the reason trails (why each candidate failed).
//   setSize {textureId: int, width: int, height: int}
//   setIccProfile {textureId: int, profile: Uint8List} (empty: clear)
//   dispose {textureId: int}
// Native -> Dart:
//   event   {textureId: int, kind: String, message: String}
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

#include "d3d11_interop.h"
#include "include/mpv_kit_video/mpv_kit_video_plugin_c_api.h"

namespace mpv_kit {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

int64_t ToInt(const EncodableValue& v) {
  if (auto* i = std::get_if<int32_t>(&v)) return *i;
  if (auto* l = std::get_if<int64_t>(&v)) return *l;
  return 0;
}

const EncodableValue* Arg(const EncodableMap& m, const char* key) {
  auto it = m.find(EncodableValue(key));
  return it == m.end() ? nullptr : &it->second;
}

/// Renderer log sink: DebugView, and stderr, which `flutter run` attaches
/// so the probe lines are visible in the terminal without DebugView.
void LogLine(const std::string& msg) {
  OutputDebugStringA((msg + "\n").c_str());
  if (stderr) fprintf(stderr, "%s\n", msg.c_str());
}

/// Frames between two compositor pickup log lines (same window as the
/// renderer's `render waits avg/over` probe).
constexpr int kPickupWindow = 120;

/// Nanoseconds on the steady clock; the pickup latency's time base.
int64_t SteadyNowNs() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

// Hand-over between Describe and the engine's release callback, both on the
// raster thread (measurement only). The callback's only context is the
// texture, and Flutter 3.47.8 calls it synchronously right after its
// per-handle EGL surface update (external_texture_d3d.cc:84-115), so the
// time since Describe returned brackets that update. The owners are
// compared, never dereferenced: a callback on another thread, or another
// instance's Describe in between, drops the sample (binds= counts the
// matched ones only).
/// Instance of the last descriptor this thread handed out, and when.
thread_local const void* t_descriptor_owner = nullptr;
thread_local int64_t t_descriptor_ns = 0;
/// Instance and duration (ms) of the last bracketed engine update.
thread_local const void* t_bound_owner = nullptr;
thread_local double t_bound_ms = 0;

/// Everything belonging to one MpvVideoController.
struct Instance {
  // Guards dead/renderer against the raster thread's texture callbacks.
  std::mutex mutex;
  bool dead = false;
  std::atomic<int64_t> texture_id{-1};
  // Compositor pickup latency (measurement only, ADR 0003 Q4): the render
  // thread stamps the newest FrameReady; Describe, on the raster thread and
  // under [mutex], accounts the time until the compositor asked for it.
  std::atomic<int64_t> frame_ready_ns{0};
  int64_t picked_ready_ns = 0;  // the stamp Describe last accounted
  int pickup_count = 0;
  double pickup_total_ms = 0;
  double pickup_max_ms = 0;
  // Describe probe (measurement only; raster thread under [mutex]; reset with
  // the pickup line, except [last_handle], which spans windows): Describe
  // calls and their duration from entry through AcquireFront, how many
  // handed Flutter a different shared handle than the call before, and the
  // time from Describe's return to the engine's release callback.
  int describe_count = 0;
  double describe_total_ms = 0;
  double describe_max_ms = 0;
  int handle_changes = 0;
  HANDLE last_handle = nullptr;
  int bind_count = 0;
  double bind_total_ms = 0;
  double bind_max_ms = 0;
  std::unique_ptr<D3D11Interop> interop;
  std::unique_ptr<VideoRenderer> renderer;
  std::unique_ptr<flutter::TextureVariant> texture;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
  FlutterDesktopPixelBuffer pixels{};
};

/// A renderer event on its way from the render thread to Dart.
struct PendingEvent {
  int64_t texture_id;
  std::string kind, message;
};

class MpvKitVideoPlugin : public flutter::Plugin {
 public:
  explicit MpvKitVideoPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar), textures_(registrar->texture_registrar()) {
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar->messenger(), "mpv_kit_video",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Handle(call, std::move(result));
    });
    // Events are raised on render threads; the channel may only be used on
    // the platform thread. Post them to the top-level window and pick them
    // up in its window procedure (the usual Win32 way to marshal work).
    event_message_ = RegisterWindowMessageW(L"mpv_kit_video.event");
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND, UINT message, WPARAM, LPARAM lparam)
            -> std::optional<LRESULT> {
          if (message != event_message_) return std::nullopt;
          std::unique_ptr<PendingEvent> e(
              reinterpret_cast<PendingEvent*>(lparam));
          channel_->InvokeMethod(
              "event", std::make_unique<EncodableValue>(EncodableMap{
                           {EncodableValue("textureId"),
                            EncodableValue(e->texture_id)},
                           {EncodableValue("kind"), EncodableValue(e->kind)},
                           {EncodableValue("message"),
                            EncodableValue(e->message)},
                       }));
          return 0;
        });
  }

  ~MpvKitVideoPlugin() override {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    for (auto& [id, inst] : instances_) {
      Stop(inst.get());
      textures_->UnregisterTexture(id);
    }
    instances_.clear();
  }

 private:
  void Handle(const flutter::MethodCall<EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (!args) return result->Error("bad_args", "expected a map");
    const std::string& m = call.method_name();
    if (m == "create") return Create(*args, std::move(result));
    // Dart reads the real refresh rate of the display the video window is
    // on: Flutter's Display.refreshRate has long returned 0 on Windows
    // (flutter/flutter #158721), which silently disables mpv's
    // display-fps-override and with it every display-* video-sync mode.
    // Returns 0.0 when the rate cannot be determined (Dart falls back).
    if (m == "getDisplayRefreshRate") {
      HWND view = registrar_->GetView()
                      ? registrar_->GetView()->GetNativeWindow()
                      : nullptr;
      HWND root = view ? GetAncestor(view, GA_ROOT) : nullptr;
      HMONITOR monitor = MonitorFromWindow(
          root ? root : view, MONITOR_DEFAULTTONEAREST);
      MONITORINFOEXW info{};
      info.cbSize = sizeof(info);
      DEVMODEW dm{};
      dm.dmSize = sizeof(dm);
      if (monitor && GetMonitorInfoW(monitor, &info)) {
        // ENUM_CURRENT_SETTINGS: the mode the display is in right now, so
        // a window moved onto a 144 Hz screen reports 144, not the primary.
        if (!EnumDisplaySettingsW(info.szDevice, ENUM_CURRENT_SETTINGS, &dm) ||
            !(dm.dmFields & DM_DISPLAYFREQUENCY) || dm.dmDisplayFrequency == 0)
          return result->Success(EncodableValue(0.0));
        return result->Success(
            EncodableValue(static_cast<double>(dm.dmDisplayFrequency)));
      }
      return result->Success(EncodableValue(0.0));
    }
    const EncodableValue* id_v = Arg(*args, "textureId");
    auto it = id_v ? instances_.find(ToInt(*id_v)) : instances_.end();
    if (it == instances_.end())
      return result->Error("no_texture", "unknown textureId");
    if (m == "setSize") {
      const EncodableValue* w = Arg(*args, "width");
      const EncodableValue* h = Arg(*args, "height");
      if (!w || !h) return result->Error("bad_args", "width/height");
      it->second->renderer->SetSize(static_cast<int>(ToInt(*w)),
                                    static_cast<int>(ToInt(*h)));
      return result->Success();
    }
    if (m == "setIccProfile") {
      const EncodableValue* p = Arg(*args, "profile");
      const auto* bytes = p ? std::get_if<std::vector<uint8_t>>(p) : nullptr;
      it->second->renderer->SetIccProfile(
          bytes ? *bytes : std::vector<uint8_t>());
      return result->Success();
    }
    if (m == "dispose") {
      Instance* raw = it->second.release();
      instances_.erase(it);
      // Free the render context *now*: Dart destroys the mpv core right
      // after this call returns, and libmpv requires the render context to
      // be gone by then. Images the compositor still holds stay alive
      // through their D3D11 references.
      const int64_t id = raw->texture_id.load();
      Stop(raw);
      // The struct itself waits until Flutter guarantees that no raster
      // callback is running.
      textures_->UnregisterTexture(id, [raw] { delete raw; });
      return result->Success();
    }
    result->NotImplemented();
  }

  void Create(const EncodableMap& args,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* syms = Arg(args, "symbols");
    const auto* list = syms ? std::get_if<EncodableList>(syms) : nullptr;
    const auto* handle = Arg(args, "handle");
    if (!list || !handle) return result->Error("bad_args", "symbols/handle");
    std::vector<int64_t> addrs;
    for (const auto& v : *list) addrs.push_back(ToInt(v));
    MpvApi api;
    if (!api.Load(addrs.data(), static_cast<int>(addrs.size())))
      return result->Error("bad_symbols", "libmpv symbol table incomplete");
    const auto* rv = Arg(args, "renderer");
    const auto* rs = rv ? std::get_if<std::string>(rv) : nullptr;
    const RendererChoice choice = ParseRendererChoice(rs ? *rs : "auto");

    auto inst = std::make_unique<Instance>();
    Instance* raw = inst.get();
    flutter::TextureRegistrar* textures = textures_;
    IDXGIAdapter* adapter =
        registrar_->GetView() ? registrar_->GetView()->GetGraphicsAdapter()
                              : nullptr;
    inst->interop = std::make_unique<D3D11Interop>(adapter, [raw, textures] {
      const int64_t id = raw->texture_id.load();
      // Stamped before the compositor is told, so the pickup latency also
      // contains the notification itself.
      raw->frame_ready_ns.store(SteadyNowNs());
      if (id >= 0) textures->MarkTextureFrameAvailable(id);
    });
    inst->renderer = std::make_unique<VideoRenderer>(
        api, reinterpret_cast<mpv_handle*>(static_cast<intptr_t>(ToInt(*handle))),
        inst->interop.get(),
        LogLine,
        [this, raw](const char* kind, const std::string& msg) {
          PostEvent(raw->texture_id.load(), kind, msg);
        });
    if (!inst->renderer->Start(choice))
      return result->Error("render_init", "no usable render backend",
                           EncodableValue(inst->renderer->backend_reason()));

    if (inst->renderer->backend() == Backend::kVulkan) {
      inst->texture = std::make_unique<flutter::TextureVariant>(
          flutter::GpuSurfaceTexture(
              kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
              [raw](size_t, size_t) -> const FlutterDesktopGpuSurfaceDescriptor* {
                return Describe(raw);
              }));
    } else {
      inst->texture = std::make_unique<flutter::TextureVariant>(
          flutter::PixelBufferTexture([raw](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
            std::lock_guard<std::mutex> lock(raw->mutex);
            if (raw->dead) return nullptr;
            const Frame f = raw->renderer->AcquireFront();
            if (!f.pixels) return nullptr;
            raw->pixels.buffer = f.pixels;
            raw->pixels.width = static_cast<size_t>(f.width);
            raw->pixels.height = static_cast<size_t>(f.height);
            return &raw->pixels;
          }));
    }
    const int64_t id = textures_->RegisterTexture(inst->texture.get());
    inst->texture_id = id;
    const std::string wire = inst->renderer->wire_name();
    const std::string reason = inst->renderer->backend_reason();
    instances_.emplace(id, std::move(inst));
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("textureId"), EncodableValue(id)},
        {EncodableValue("backend"), EncodableValue(wire)},
        {EncodableValue("reason"), EncodableValue(reason)},
    }));
  }

  /// Joins the render thread and frees the render context. Afterwards the
  /// texture callbacks return no frame.
  static void Stop(Instance* inst) {
    {
      std::lock_guard<std::mutex> lock(inst->mutex);
      inst->dead = true;
    }
    inst->texture_id = -1;  // no more frame/event notifications
    inst->renderer.reset();
  }

  /// Any thread. The window procedure delegate takes ownership.
  void PostEvent(int64_t texture_id, const char* kind,
                 const std::string& message) {
    if (texture_id < 0) return;
    HWND view = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow()
                                      : nullptr;
    HWND root = view ? GetAncestor(view, GA_ROOT) : nullptr;
    auto* e = new PendingEvent{texture_id, kind, message};
    if (!root || !PostMessageW(root, event_message_, 0,
                               reinterpret_cast<LPARAM>(e)))
      delete e;
  }

  /// Raster thread, [inst]->mutex held: accounts FrameReady -> Describe for
  /// a frame not yet counted ([ready] is the FrameReady stamp read before
  /// AcquireFront) and logs one line per kPickupWindow frames
  /// (count, sum and maximum reset after each line), followed by the
  /// Describe probe fields of [inst] (describe call time, shared-handle
  /// changes, release-callback bracket). Measurement only: no publish,
  /// quarantine or delivery decision reads these numbers.
  static void RecordPickup(Instance* inst, int64_t ready) {
    if (ready == 0 || ready == inst->picked_ready_ns) return;
    inst->picked_ready_ns = ready;
    const double ms = static_cast<double>(SteadyNowNs() - ready) / 1e6;
    inst->pickup_total_ms += ms;
    inst->pickup_max_ms = std::max(inst->pickup_max_ms, ms);
    if (++inst->pickup_count < kPickupWindow) return;
    char line[320];
    snprintf(line, sizeof(line),
             "mpv_kit: compositor pickup avg/over %d frames: %.2fms "
             "max=%.2fms backend=%s describes=%d describe=%.3fms "
             "max_describe=%.3fms handle_changes=%d binds=%d bind=%.3fms "
             "max_bind=%.3fms",
             inst->pickup_count, inst->pickup_total_ms / inst->pickup_count,
             inst->pickup_max_ms, inst->renderer->wire_name(),
             inst->describe_count,
             inst->describe_count > 0
                 ? inst->describe_total_ms / inst->describe_count
                 : 0.0,
             inst->describe_max_ms, inst->handle_changes, inst->bind_count,
             inst->bind_count > 0 ? inst->bind_total_ms / inst->bind_count
                                  : 0.0,
             inst->bind_max_ms);
    LogLine(line);
    inst->pickup_count = 0;
    inst->pickup_total_ms = 0;
    inst->pickup_max_ms = 0;
    inst->describe_count = 0;
    inst->describe_total_ms = 0;
    inst->describe_max_ms = 0;
    inst->handle_changes = 0;
    inst->bind_count = 0;
    inst->bind_total_ms = 0;
    inst->bind_max_ms = 0;
  }

  /// Raster thread: hand Flutter the latest completed shared texture.
  static const FlutterDesktopGpuSurfaceDescriptor* Describe(Instance* inst) {
    // Entry stamp of the Describe probe (measurement only), before the lock.
    const int64_t entry_ns = SteadyNowNs();
    std::lock_guard<std::mutex> lock(inst->mutex);
    if (inst->dead) return nullptr;
    // Read before AcquireFront: it may mark the texture again (and so
    // restamp) for a frame that still waits, which must not hide this pickup.
    const int64_t ready = inst->frame_ready_ns.load();
    const Frame f = inst->renderer->AcquireFront();
    if (!f.platform) return nullptr;
    auto* tex = static_cast<D3D11Interop::Texture*>(f.platform);
    // Engine update of the previous descriptor this thread handed out for
    // this instance, bracketed by the release callback below.
    if (t_bound_owner == inst) {
      inst->bind_count++;
      inst->bind_total_ms += t_bound_ms;
      inst->bind_max_ms = std::max(inst->bind_max_ms, t_bound_ms);
      t_bound_owner = nullptr;
    }
    // Flutter's ExternalTextureD3d recreates its EGL surface whenever the
    // handle differs from the one it last saw: count those changes.
    if (tex->shared_handle != inst->last_handle) inst->handle_changes++;
    inst->last_handle = tex->shared_handle;
    // Duration of this call from entry through AcquireFront and the handle
    // compare. It leaves out the descriptor stores and the window's log write.
    const double describe_ms =
        static_cast<double>(SteadyNowNs() - entry_ns) / 1e6;
    inst->describe_count++;
    inst->describe_total_ms += describe_ms;
    inst->describe_max_ms = std::max(inst->describe_max_ms, describe_ms);
    RecordPickup(inst, ready);
    auto& d = inst->descriptor;
    d.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    d.handle = tex->shared_handle;
    d.width = d.visible_width = static_cast<size_t>(f.width);
    d.height = d.visible_height = static_cast<size_t>(f.height);
    d.format = kFlutterDesktopPixelFormatBGRA8888;
    // Balances the AddRef taken in RetainFrame once Flutter opened it.
    d.release_context = tex->texture.Get();
    d.release_callback = [](void* ctx) {
      // Measurement only: the end of the engine's GL bind and, on a handle
      // change, EGL surface recreate (external_texture_d3d.cc:71-115), which
      // Flutter 3.47.8 runs just before this callback. Only thread-locals are
      // touched; the texture and its single Release below are unchanged.
      if (t_descriptor_ns != 0) {
        t_bound_ms = static_cast<double>(SteadyNowNs() - t_descriptor_ns) / 1e6;
        t_bound_owner = t_descriptor_owner;
        t_descriptor_ns = 0;
      }
      static_cast<ID3D11Texture2D*>(ctx)->Release();
    };
    // Start of the bracket: this instance, handed out on this thread now.
    t_descriptor_owner = inst;
    t_descriptor_ns = SteadyNowNs();
    return &d;
  }

  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* textures_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::map<int64_t, std::unique_ptr<Instance>> instances_;
  UINT event_message_ = 0;
  int window_proc_id_ = -1;
};

}  // namespace
}  // namespace mpv_kit

void MpvKitVideoPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* r = flutter::PluginRegistrarManager::GetInstance()
                ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  r->AddPlugin(std::make_unique<mpv_kit::MpvKitVideoPlugin>(r));
}
