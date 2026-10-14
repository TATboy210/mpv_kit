// Linux plugin: one Flutter texture per mpv instance.
//
// Method channel "mpv_kit_video" (same contract as Windows):
//   create  {symbols: List<int>, handle: int, forceSoftware: bool}
//           -> {textureId: int, backend: "vulkan"|"software", reason: String}
//   setSize {textureId: int, width: int, height: int}
//   dispose {textureId: int}
#include <epoxy/gl.h>

#include "include/mpv_kit_video/mpv_kit_video_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "gl_interop.h"

namespace mpv_kit {
namespace {

// The engine looks textures up without taking a reference, so a populate
// call may still be in flight right after unregistering. Keep our reference
// this long before dropping it.
constexpr guint kTextureReleaseDelayMs = 1000;

/// Everything belonging to one MpvVideoController. Shared between the
/// plugin (platform thread) and the texture object (raster thread).
struct State {
  std::mutex mutex;  // guards dead/renderer against populate
  bool dead = false;
  FlTextureRegistrar* registrar = nullptr;
  std::atomic<FlTexture*> texture{nullptr};
  std::unique_ptr<GlInterop> interop;
  std::unique_ptr<VideoRenderer> renderer;
  // 1x1 black texture shown before the first frame (raster thread only).
  GlInterop::Image* placeholder = nullptr;
};

using StatePtr = std::shared_ptr<State>;

const uint8_t kBlackPixel[4] = {0, 0, 0, 0xff};

}  // namespace
}  // namespace mpv_kit

using mpv_kit::GlInterop;
using mpv_kit::StatePtr;

// --- GL texture (Vulkan backend) --------------------------------------------

G_DECLARE_FINAL_TYPE(MpvKitGlTexture, mpv_kit_gl_texture, MPV_KIT, GL_TEXTURE,
                     FlTextureGL)

struct _MpvKitGlTexture {
  FlTextureGL parent_instance;
  StatePtr* state;  // heap-allocated so GObject can own a shared_ptr
};

G_DEFINE_TYPE(MpvKitGlTexture, mpv_kit_gl_texture, fl_texture_gl_get_type())

static GLuint PlaceholderTexture(mpv_kit::State* st) {
  if (!st->placeholder) {
    st->placeholder = new GlInterop::Image();
    st->placeholder->failed = true;  // not importable; only owns a texture
    glGenTextures(1, &st->placeholder->texture);
    glBindTexture(GL_TEXTURE_2D, st->placeholder->texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, mpv_kit::kBlackPixel);
    glBindTexture(GL_TEXTURE_2D, 0);
  }
  return st->placeholder->texture;
}

static gboolean mpv_kit_gl_texture_populate(FlTextureGL* texture,
                                            uint32_t* target, uint32_t* name,
                                            uint32_t* width, uint32_t* height,
                                            GError** error) {
  // Flutter's context is current: the only safe place to delete GL objects.
  GlInterop::DrainGraveyard();
  mpv_kit::State* st = MPV_KIT_GL_TEXTURE(texture)->state->get();
  std::lock_guard<std::mutex> lock(st->mutex);
  if (st->dead) {
    g_set_error(error, g_quark_from_static_string("mpv_kit"), 1, "disposed");
    return FALSE;
  }
  const mpv_kit::Frame f = st->renderer->AcquireFront();
  GLuint tex = 0;
  if (f.platform) tex = GlInterop::TextureFor(static_cast<GlInterop::Image*>(f.platform));
  *target = GL_TEXTURE_2D;
  if (tex) {
    *name = tex;
    *width = static_cast<uint32_t>(f.width);
    *height = static_cast<uint32_t>(f.height);
  } else {
    *name = PlaceholderTexture(st);
    *width = *height = 1;
  }
  return TRUE;
}

static void mpv_kit_gl_texture_finalize(GObject* object) {
  delete MPV_KIT_GL_TEXTURE(object)->state;
  G_OBJECT_CLASS(mpv_kit_gl_texture_parent_class)->finalize(object);
}

static void mpv_kit_gl_texture_class_init(MpvKitGlTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = mpv_kit_gl_texture_populate;
  G_OBJECT_CLASS(klass)->finalize = mpv_kit_gl_texture_finalize;
}

static void mpv_kit_gl_texture_init(MpvKitGlTexture* self) {
  self->state = nullptr;
}

// --- Pixel buffer texture (software backend) --------------------------------

G_DECLARE_FINAL_TYPE(MpvKitPixelTexture, mpv_kit_pixel_texture, MPV_KIT,
                     PIXEL_TEXTURE, FlPixelBufferTexture)

struct _MpvKitPixelTexture {
  FlPixelBufferTexture parent_instance;
  StatePtr* state;
};

G_DEFINE_TYPE(MpvKitPixelTexture, mpv_kit_pixel_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean mpv_kit_pixel_texture_copy_pixels(FlPixelBufferTexture* texture,
                                                  const uint8_t** buffer,
                                                  uint32_t* width,
                                                  uint32_t* height,
                                                  GError** error) {
  mpv_kit::State* st = MPV_KIT_PIXEL_TEXTURE(texture)->state->get();
  std::lock_guard<std::mutex> lock(st->mutex);
  if (st->dead) {
    g_set_error(error, g_quark_from_static_string("mpv_kit"), 1, "disposed");
    return FALSE;
  }
  const mpv_kit::Frame f = st->renderer->AcquireFront();
  if (f.pixels) {
    *buffer = f.pixels;  // stays valid until the next AcquireFront()
    *width = static_cast<uint32_t>(f.width);
    *height = static_cast<uint32_t>(f.height);
  } else {
    *buffer = mpv_kit::kBlackPixel;
    *width = *height = 1;
  }
  return TRUE;
}

static void mpv_kit_pixel_texture_finalize(GObject* object) {
  delete MPV_KIT_PIXEL_TEXTURE(object)->state;
  G_OBJECT_CLASS(mpv_kit_pixel_texture_parent_class)->finalize(object);
}

static void mpv_kit_pixel_texture_class_init(MpvKitPixelTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      mpv_kit_pixel_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = mpv_kit_pixel_texture_finalize;
}

static void mpv_kit_pixel_texture_init(MpvKitPixelTexture* self) {
  self->state = nullptr;
}

// --- Plugin -------------------------------------------------------------------

namespace mpv_kit {
namespace {

int64_t IntArg(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_INT ? fl_value_get_int(v)
                                                        : 0;
}

class Plugin {
 public:
  explicit Plugin(FlPluginRegistrar* registrar)
      : textures_(fl_plugin_registrar_get_texture_registrar(registrar)) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                     "mpv_kit_video", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(
        channel_,
        [](FlMethodChannel*, FlMethodCall* call, gpointer self) {
          static_cast<Plugin*>(self)->Handle(call);
        },
        this, nullptr);
  }

 private:
  void Handle(FlMethodCall* call) {
    const std::string m = fl_method_call_get_name(call);
    FlValue* args = fl_method_call_get_args(call);
    if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      Error(call, "bad_args", "expected a map");
      return;
    }
    if (m == "create") {
      Create(call, args);
      return;
    }
    auto it = instances_.find(IntArg(args, "textureId"));
    if (it == instances_.end()) {
      Error(call, "no_texture", "unknown textureId");
      return;
    }
    if (m == "setSize") {
      it->second->renderer->SetSize(static_cast<int>(IntArg(args, "width")),
                                    static_cast<int>(IntArg(args, "height")));
      fl_method_call_respond_success(call, nullptr, nullptr);
    } else if (m == "dispose") {
      StatePtr st = it->second;
      instances_.erase(it);
      Dispose(st);
      fl_method_call_respond_success(call, nullptr, nullptr);
    } else {
      fl_method_call_respond_not_implemented(call, nullptr);
    }
  }

  void Create(FlMethodCall* call, FlValue* args) {
    FlValue* syms = fl_value_lookup_string(args, "symbols");
    if (!syms || fl_value_get_type(syms) != FL_VALUE_TYPE_LIST) {
      Error(call, "bad_args", "symbols/handle");
      return;
    }
    std::vector<int64_t> addrs;
    for (size_t i = 0; i < fl_value_get_length(syms); i++) {
      FlValue* v = fl_value_get_list_value(syms, i);
      addrs.push_back(fl_value_get_type(v) == FL_VALUE_TYPE_INT
                          ? fl_value_get_int(v)
                          : 0);
    }
    MpvApi api;
    if (!api.Load(addrs.data(), static_cast<int>(addrs.size()))) {
      Error(call, "bad_symbols", "libmpv symbol table incomplete");
      return;
    }
    const int64_t handle = IntArg(args, "handle");
    FlValue* fs = fl_value_lookup_string(args, "forceSoftware");
    const bool force_sw = fs && fl_value_get_type(fs) == FL_VALUE_TYPE_BOOL &&
                          fl_value_get_bool(fs);
    if (!handle) {
      Error(call, "bad_args", "symbols/handle");
      return;
    }

    auto st = std::make_shared<State>();
    State* raw = st.get();
    raw->registrar = textures_;
    // Render thread: the texture is registered before the first frame can
    // be published, but guard anyway.
    raw->interop = std::make_unique<GlInterop>([raw] {
      if (FlTexture* t = raw->texture.load())
        fl_texture_registrar_mark_texture_frame_available(raw->registrar, t);
    });
    raw->renderer = std::make_unique<VideoRenderer>(
        api, reinterpret_cast<mpv_handle*>(static_cast<intptr_t>(handle)),
        raw->interop.get(),
        [](const std::string& msg) { g_message("%s", msg.c_str()); });
    if (!raw->renderer->Start(force_sw)) {
      Error(call, "render_init", "no usable render backend");
      return;
    }

    const bool vk = raw->renderer->backend() == Backend::kVulkan;
    FlTexture* texture;
    if (vk) {
      auto* t = MPV_KIT_GL_TEXTURE(g_object_new(mpv_kit_gl_texture_get_type(), nullptr));
      t->state = new StatePtr(st);
      texture = FL_TEXTURE(t);
    } else {
      auto* t = MPV_KIT_PIXEL_TEXTURE(g_object_new(mpv_kit_pixel_texture_get_type(), nullptr));
      t->state = new StatePtr(st);
      texture = FL_TEXTURE(t);
    }
    if (!fl_texture_registrar_register_texture(textures_, texture)) {
      g_object_unref(texture);
      Error(call, "render_init", "texture registration failed");
      return;
    }
    raw->texture = texture;
    const int64_t id = fl_texture_get_id(texture);
    instances_[id] = st;

    std::string reason = raw->renderer->backend_reason();
    if (!vk && raw->interop->gl_reason()[0])
      reason += std::string(": ") + raw->interop->gl_reason();
    g_autoptr(FlValue) out = fl_value_new_map();
    fl_value_set_string_take(out, "textureId", fl_value_new_int(id));
    fl_value_set_string_take(out, "backend",
                             fl_value_new_string(vk ? "vulkan" : "software"));
    fl_value_set_string_take(out, "reason", fl_value_new_string(reason.c_str()));
    fl_method_call_respond_success(call, out, nullptr);
  }

  void Dispose(const StatePtr& st) {
    {
      // Excludes populate; the render thread is joined inside reset() and
      // buries every shared image for GL-side cleanup.
      std::lock_guard<std::mutex> lock(st->mutex);
      st->dead = true;
      st->renderer.reset();
      if (st->placeholder) GlInterop::Bury(st->placeholder);
      st->placeholder = nullptr;
    }
    st->interop.reset();
    FlTexture* texture = st->texture.exchange(nullptr);
    if (!texture) return;
    fl_texture_registrar_unregister_texture(textures_, texture);
    g_timeout_add(
        kTextureReleaseDelayMs,
        [](gpointer t) -> gboolean {
          g_object_unref(t);
          return G_SOURCE_REMOVE;
        },
        texture);
  }

  static void Error(FlMethodCall* call, const char* code, const char* msg) {
    fl_method_call_respond_error(call, code, msg, nullptr, nullptr);
  }

  FlTextureRegistrar* textures_;
  FlMethodChannel* channel_;
  std::map<int64_t, StatePtr> instances_;
};

}  // namespace
}  // namespace mpv_kit

void mpv_kit_video_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // Lives as long as the engine's messenger; plugins are never unregistered.
  new mpv_kit::Plugin(registrar);
}
