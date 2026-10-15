// Windows plugin: one Flutter texture per mpv instance.
//
// Method channel "mpv_kit_video" (same contract on every platform):
//   create  {symbols: List<int>, handle: int, renderer: String}
//           renderer: "auto" | "gpu-next" | "gpu" | "software"
//           -> {textureId: int, backend: "vulkan"|"software", reason: String}
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

#include <atomic>
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

/// Everything belonging to one MpvVideoController.
struct Instance {
  // Guards dead/renderer against the raster thread's texture callbacks.
  std::mutex mutex;
  bool dead = false;
  std::atomic<int64_t> texture_id{-1};
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
      if (id >= 0) textures->MarkTextureFrameAvailable(id);
    });
    inst->renderer = std::make_unique<VideoRenderer>(
        api, reinterpret_cast<mpv_handle*>(static_cast<intptr_t>(ToInt(*handle))),
        inst->interop.get(),
        [](const std::string& msg) {
          OutputDebugStringA((msg + "\n").c_str());
        },
        [this, raw](const char* kind, const std::string& msg) {
          PostEvent(raw->texture_id.load(), kind, msg);
        });
    if (!inst->renderer->Start(choice))
      return result->Error("render_init", "no usable render backend");

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
    const bool vk = inst->renderer->backend() == Backend::kVulkan;
    const std::string reason = inst->renderer->backend_reason();
    instances_.emplace(id, std::move(inst));
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("textureId"), EncodableValue(id)},
        {EncodableValue("backend"), EncodableValue(vk ? "vulkan" : "software")},
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

  /// Raster thread: hand Flutter the latest completed shared texture.
  static const FlutterDesktopGpuSurfaceDescriptor* Describe(Instance* inst) {
    std::lock_guard<std::mutex> lock(inst->mutex);
    if (inst->dead) return nullptr;
    const Frame f = inst->renderer->AcquireFront();
    if (!f.platform) return nullptr;
    auto* tex = static_cast<D3D11Interop::Texture*>(f.platform);
    auto& d = inst->descriptor;
    d.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    d.handle = tex->shared_handle;
    d.width = d.visible_width = static_cast<size_t>(f.width);
    d.height = d.visible_height = static_cast<size_t>(f.height);
    d.format = kFlutterDesktopPixelFormatBGRA8888;
    // Balances the AddRef taken in RetainFrame once Flutter opened it.
    d.release_context = tex->texture.Get();
    d.release_callback = [](void* ctx) {
      static_cast<ID3D11Texture2D*>(ctx)->Release();
    };
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
