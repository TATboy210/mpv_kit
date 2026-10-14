// Windows plugin: one Flutter texture per mpv instance.
//
// Method channel "mpv_kit_video":
//   create  {symbols: List<int>, handle: int, forceSoftware: bool}
//           -> {textureId: int, backend: "vulkan"|"software", reason: String}
//   setSize {textureId: int, width: int, height: int}
//   dispose {textureId: int}
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <atomic>
#include <map>
#include <memory>

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
  std::atomic<int64_t> texture_id{-1};
  std::unique_ptr<D3D11Interop> interop;
  std::unique_ptr<VideoRenderer> renderer;
  std::unique_ptr<flutter::TextureVariant> texture;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
  FlutterDesktopPixelBuffer pixels{};
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
  }

  ~MpvKitVideoPlugin() override {
    for (auto& [id, inst] : instances_) textures_->UnregisterTexture(id);
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
      it->second->renderer->SetSize(
          static_cast<int>(ToInt(*Arg(*args, "width"))),
          static_cast<int>(ToInt(*Arg(*args, "height"))));
      return result->Success();
    }
    if (m == "dispose") {
      // Destroy only after Flutter guarantees no raster callback is running.
      Instance* raw = it->second.release();
      instances_.erase(it);
      textures_->UnregisterTexture(raw->texture_id, [raw] { delete raw; });
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
    const auto* fs = Arg(args, "forceSoftware");
    const bool force_sw = fs && std::get_if<bool>(fs) && std::get<bool>(*fs);

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
        inst->interop.get(), [](const std::string& msg) {
          OutputDebugStringA((msg + "\n").c_str());
        });
    if (!inst->renderer->Start(force_sw))
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

  /// Raster thread: hand Flutter the latest completed shared texture.
  static const FlutterDesktopGpuSurfaceDescriptor* Describe(Instance* inst) {
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
};

}  // namespace
}  // namespace mpv_kit

void MpvKitVideoPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* r = flutter::PluginRegistrarManager::GetInstance()
                ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  r->AddPlugin(std::make_unique<mpv_kit::MpvKitVideoPlugin>(r));
}
