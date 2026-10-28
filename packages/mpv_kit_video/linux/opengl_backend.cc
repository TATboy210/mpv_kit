// OpenGLBackend: the Linux plugin's second GPU path (Phase 15, GLX-03).
//
// What it is: a RenderBackend that drives mpv through the upstream OpenGL
// render API (MPV_RENDER_API_TYPE_OPENGL, render_gl.h) and hands every frame
// to Flutter as an EGLImage inside the plugin's FlTextureGL. Only mpv's `gpu`
// renderer is served over GL (gpu-next over GL is GLX-F1), so the chain gives
// opengl a single `gpu` entry (src/linux_candidates.h).
//
// Per frame (render thread, our EGL context current):
//   mpv renders into a private texture P (MPV_RENDER_PARAM_OPENGL_FBO)
//     -> glBlitFramebuffer into the ring slot's own export texture E
//     -> an EGLImage that was created from E (never from P)
//     -> an EGL fence (eglCreateSyncKHR) that Wait(slot) waits on, 1 s at most
// The engine publishes the slot as front only after Wait succeeded, so the
// compositor never samples a slot whose blit is still in flight. populate()
// (raster thread, Flutter's context) only imports the EGLImage once per image
// with glEGLImageTargetTexture2DOES; it never renders and never waits on the
// GPU (gl_interop.cc, GlInterop::TextureFor).
//
// Why the private texture and the blit: on Mesa an EGLImage taken from the
// texture mpv renders into can read back black (media-kit#1463). A blit into
// a plain export texture avoids that, and native/tests/render_gl_smoke.c
// proves the same handoff on CI (evidence/spike-gl.txt, run 40627862148).
//
// Why our own context and no share group: the context is created on Flutter's
// EGLDisplay (FlutterEglDisplay(), never a query of whatever context happens
// to be current) with share context EGL_NO_CONTEXT, so mpv's thousands of GL
// state changes can never leak into Flutter's context, and the two sides
// exchange nothing but EGLImage storage.
//
// Threads: the context is bound to one thread at a time. Create-time calls
// run in RunBound, on a short-lived thread of this backend (the same shape
// as the platform interop's probe thread): evidence/spike-flutter-linux.txt
// D-THREAD shows that eglMakeCurrent on the platform thread fails
// (EGL_BAD_ACCESS 0x3002: a GDK GL context is current there) while a fresh
// thread succeeds (IMPLICATION=helper-thread). RunBound unbinds before it
// returns; the render thread then binds the same context for its whole life
// (BindThread ... Release ... UnbindThread). The destructor runs on the
// platform thread with the context current nowhere.
//
// Verified only on Mesa llvmpipe (software GL on the CI runners). Real GL
// drivers (NVIDIA, AMD, Intel), Mesa Xe2, and Wayland's EGL platform are not
// verified: the fence wait in particular has no device-lost signal without a
// robust context, see Wait().

#include <mpv/render_gl.h>

#include <cassert>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <system_error>
#include <thread>
#include <utility>
#include <vector>

#include "../src/render_backend.h"
#include "gl_interop.h"
// Last on purpose (see gl_interop.h): EGL's platform header pulls in Xlib.
#include <epoxy/gl.h>

namespace mpv_kit {
namespace {

// FLIP_Y handed to mpv. evidence/spike-gl.txt D-FLIP-MPV=row0-top-when-flip_y=0
// (run 40627862148): with FLIP_Y 0 the first row of the export texture's
// memory is the image top. Flutter shows the first row of an external texture
// at the top (evidence/spike-flutter-linux.txt D-FLUTTER-ORIGIN=top-left, static
// reading of the Skia path; D-ORIENT is unknown there because the Vulkan
// control did not run), so no flip is needed. Plan 15-05's rule for
// D-ORIENT=unknown: take the D-FLIP-MPV value.
constexpr int kFlipY = 0;

// Same 1 s bound as the Vulkan timeline wait (vulkan_backend.cc): a stuck GPU
// must not wedge the render thread forever.
constexpr uint64_t kSyncTimeoutNs = 1'000'000'000ull;

/// One context API the backend may create, in the order evidence/spike-gl.txt
/// D-GL-API=gl,gles gives (run 40627862148): desktop GL first, because the
/// GLES vo_gpu has driver-dependent precision issues and is only a fallback.
struct ContextApi {
  EGLenum api;
  EGLint renderable_bit;
};
constexpr ContextApi kContextApis[] = {
    {EGL_OPENGL_API, EGL_OPENGL_BIT},
    {EGL_OPENGL_ES_API, EGL_OPENGL_ES3_BIT},
};

// mpv resolves every GL function through this callback; it links no GL
// library itself.
void* GetProcAddress(void* ctx, const char* name) {
  (void)ctx;
  // memcpy: ISO C++ has no function-pointer to void* conversion.
  auto fn = eglGetProcAddress(name);
  void* p = nullptr;
  static_assert(sizeof(p) == sizeof(fn), "function and object pointers differ");
  std::memcpy(&p, &fn, sizeof(p));
  return p;
}

/// True if [name] is one of the space-separated tokens of an EGL extension
/// string (a plain strstr would also match prefixes of longer names).
bool HasEglExtension(const char* list, const char* name) {
  if (!list) return false;
  const size_t length = std::strlen(name);
  for (const char* p = list; (p = std::strstr(p, name)) != nullptr; p += length) {
    const bool starts = p == list || p[-1] == ' ';
    const bool ends = p[length] == '\0' || p[length] == ' ';
    if (starts && ends) return true;
  }
  return false;
}

/// One ring slot: the export texture that the slot's EGLImage is made from,
/// its FBO (the blit target) and the fence of the slot's latest render.
struct Slot {
  GLuint texture = 0;
  GLuint fbo = 0;
  EGLImageKHR image = EGL_NO_IMAGE_KHR;
  // Handed to the platform texture; owned by the GlInterop graveyard once
  // the slot is freed (GlInterop::Bury).
  GlInterop::Image* platform = nullptr;
  // Fence of the latest render, still to be waited on (Wait destroys it).
  EGLSyncKHR sync = EGL_NO_SYNC_KHR;
};

/// An RGBA8 texture and an FBO with it as colour attachment.
struct Target {
  GLuint texture = 0;
  GLuint fbo = 0;
};

class OpenGLBackend final : public RenderBackend {
 public:
  explicit OpenGLBackend(GlInterop* interop)
      : interop_(interop),
        // The constructor runs on the platform thread (NewBackend), the only
        // thread GDK may be used on; the display handle is shared with
        // Flutter's engine and used on other threads afterwards.
        display_(FlutterEglDisplay()) {}

  ~OpenGLBackend() override {
    // Platform thread, after the render thread was joined: the context is
    // current nowhere. Everything made from it was freed in Release (or
    // never existed).
    assert(ring_.empty() && retired_.empty() && private_.texture == 0);
    if (context_ != EGL_NO_CONTEXT) eglDestroyContext(display_, context_);
  }

  const char* wire_name() const override { return "opengl"; }
  // The enum predates non-Vulkan GPU backends: Backend::kVulkan means "frames
  // are shared GPU images", which is what the plugin keys FlTextureGL on.
  Backend frame_kind() const override { return Backend::kVulkan; }
  bool pipelined() const override { return true; }

  /// Render thread, once for its whole lifetime. Returns false (and the
  /// engine, which ignores the result, then gets failures from AllocTargets
  /// and Render) when the context cannot be made current.
  bool BindThread() override {
    render_thread_bound_ = false;
    bind_error_.clear();
    if (device_failed_ || context_ == EGL_NO_CONTEXT) {
      bind_error_ = device_failed_ ? device_error_ : "no OpenGL context";
      return false;
    }
    eglBindAPI(context_api_);
    if (!eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, context_)) {
      bind_error_ = EglErrorText(eglGetError());
      return false;
    }
    render_thread_bound_ = true;
    return true;
  }
  void UnbindThread() override {
    if (render_thread_bound_) ClearCurrent();
    render_thread_bound_ = false;
    eglReleaseThread();  // drops this thread's EGL bookkeeping
  }

  /// Runs [fn] on a thread of this backend with the context current, then
  /// unbinds, so the render thread can bind the same context afterwards.
  void RunBound(const std::function<void()>& fn) override {
    try {
      std::thread worker([this, &fn] {
        EnsureDevice();
        bool bound = false;
        if (!device_failed_) {
          eglBindAPI(context_api_);
          bound =
              eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, context_);
          if (!bound) {
            // Mpv must not be asked to create a GL context with none current.
            device_failed_ = true;
            device_error_ = "eglMakeCurrent failed on the OpenGL thread (" +
                            EglErrorText(eglGetError()) + ")";
          }
        }
        // A failed device still runs [fn]: Create then reports device_failed.
        fn();
        if (bound) ClearCurrent();
        eglReleaseThread();
      });
      worker.join();  // device state is read only after the join
    } catch (const std::system_error&) {
      device_failed_ = true;
      device_error_ = "cannot start the OpenGL thread";
      fn();
    }
  }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    *out = nullptr;
    if (device_failed_ || context_ == EGL_NO_CONTEXT) {
      *why = device_failed_ ? device_error_ : "OpenGL device not initialised";
      return MPV_ERROR_GENERIC;  // mpv was not asked (see device_failed())
    }
    if (std::strcmp(renderer, "gpu") != 0) {
      // Not in the chain: upstream's GL render API is served by vo_gpu only.
      *why = "opengl serves only the gpu renderer";
      return MPV_ERROR_NOT_IMPLEMENTED;
    }
    AssertCurrent();
    mpv_opengl_init_params init{};
    init.get_proc_address = &GetProcAddress;
    // Same promise as the Vulkan and software backends: the render thread
    // only calls mpv_render_*, so render.h's advanced-control rules hold.
    int advanced = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &init},
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
    // Ask mpv which renderer it really built, as the Vulkan backend does
    // (the parameter name is historical; it reports vo_gpu's renderer too).
    const char* active = nullptr;
    const int info = api.render_context_get_info(
        ctx, {MPV_RENDER_PARAM_VULKAN_RENDERER, &active});
    return info >= 0 && active ? active : "unknown renderer";
  }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    if (!render_thread_bound_) {
      *error = "eglMakeCurrent failed on the render thread (" + bind_error_ + ")";
      return false;
    }
    AssertCurrent();
    FreeRetired();  // the previous generation's survivor had its quarantine
    // Only keep_slot (the retired front, maybe still on screen) survives into
    // retirement; the others were already waited on by the publish gate.
    for (size_t i = 0; i < ring_.size(); i++) {
      if (static_cast<int>(i) == keep_slot) {
        retired_.push_back(ring_[i]);
      } else {
        FreeSlot(&ring_[i]);
      }
    }
    ring_.clear();
    DeleteTarget(&private_);

    GLint max_size = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_size);
    if (width > max_size || height > max_size) {
      *error = "OpenGL texture size limit " + std::to_string(max_size) +
               " is below " + std::to_string(width) + "x" +
               std::to_string(height);
      FreeAllTargets();
      return false;
    }
    private_w_ = width;
    private_h_ = height;
    if (!CreateTarget(width, height, &private_, error)) {
      FreeAllTargets();
      return false;
    }
    ring_.reserve(static_cast<size_t>(count));
    for (int i = 0; i < count; i++) {
      Slot slot;
      if (!CreateSlot(width, height, &slot, error)) {
        FreeAllTargets();  // nothing is left, as on the Vulkan path
        return false;
      }
      ring_.push_back(slot);
    }
    return true;
  }
  void FreeRetired() override {
    if (retired_.empty()) return;
    AssertCurrent();
    for (Slot& slot : retired_) FreeSlot(&slot);
    retired_.clear();
  }
  TargetView FrameFor(int slot) override {
    TargetView view;
    view.platform = ring_[static_cast<size_t>(slot)].platform;
    return view;
  }

  int Render(const MpvApi& api, mpv_render_context* ctx, int slot, int width,
             int height) override {
    // The private target and the slots all have the ring's size.
    (void)width;
    (void)height;
    if (!render_thread_bound_) return MPV_ERROR_GENERIC;
    AssertCurrent();
    Slot& s = ring_[static_cast<size_t>(slot)];
    mpv_opengl_fbo target{};
    target.fbo = static_cast<int>(private_.fbo);
    target.w = private_w_;
    target.h = private_h_;
    target.internal_format = GL_RGBA8;
    int flip = kFlipY;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &target},
        {MPV_RENDER_PARAM_FLIP_Y, &flip},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_render(ctx, params);
    if (err < 0) return err;

    // mpv leaves arbitrary GL state behind; the blit must not be scissored.
    glDisable(GL_SCISSOR_TEST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, private_.fbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, s.fbo);
    glBlitFramebuffer(0, 0, private_w_, private_h_, 0, 0, private_w_,
                      private_h_, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    // The fence replaces any older one (Wait normally destroyed it already).
    if (s.sync != EGL_NO_SYNC_KHR) eglDestroySyncKHR(display_, s.sync);
    s.sync = eglCreateSyncKHR(display_, EGL_SYNC_FENCE_KHR, nullptr);
    glFlush();  // a fence only signals once its commands are submitted
    // Device init requires the fence extension, so this is an exceptional
    // fallback: no fence, no way to wait but the blunt one.
    if (s.sync == EGL_NO_SYNC_KHR) glFinish();
    return err;
  }
  WaitResult Wait(int slot) override {
    Slot& s = ring_[static_cast<size_t>(slot)];
    if (s.sync == EGL_NO_SYNC_KHR) return WaitResult::kOk;
    const EGLint result = eglClientWaitSyncKHR(
        display_, s.sync, EGL_SYNC_FLUSH_COMMANDS_BIT_KHR, kSyncTimeoutNs);
    if (result == EGL_TIMEOUT_EXPIRED_KHR) {
      return WaitResult::kTimeout;  // fence kept: the next Wait keeps waiting
    }
    eglDestroySyncKHR(display_, s.sync);
    s.sync = EGL_NO_SYNC_KHR;
    // EGL_FALSE (the wait itself failed) is reported as a timeout too: there
    // is no robust context here, so a lost device cannot be told apart from
    // other failures. Not verified on real drivers.
    return result == EGL_CONDITION_SATISFIED_KHR ? WaitResult::kOk
                                                 : WaitResult::kTimeout;
  }

  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    // Render thread (or RunBound), context current: mpv frees its GL objects
    // here. When the thread could not bind, the free still has to happen or
    // mpv could never terminate; GL calls without a context are no-ops.
    if (render_thread_bound_) AssertCurrent();
    api.render_context_free(ctx);
    if (render_thread_bound_) FreeAllTargets();
  }

 private:
  /// Context creation and capability checks, once, on the backend's thread.
  /// Sets device_failed_ and device_error_ (one line) on failure; on success
  /// the context exists and is not current.
  void EnsureDevice() {
    if (device_initialised_) return;
    device_initialised_ = true;
    if (display_ == EGL_NO_DISPLAY) return Fail("no EGL display");
    // eglInitialize on an initialised display is a no-op. Never terminated:
    // the handle is shared with Flutter's engine.
    if (!eglInitialize(display_, nullptr, nullptr))
      return Fail("eglInitialize failed (" + EglErrorText(eglGetError()) + ")");
    const char* extensions = eglQueryString(display_, EGL_EXTENSIONS);
    for (const char* name :
         {"EGL_KHR_surfaceless_context", "EGL_KHR_image_base",
          "EGL_KHR_gl_texture_2D_image", "EGL_KHR_fence_sync"}) {
      if (!HasEglExtension(extensions, name))
        return Fail(std::string("EGL lacks ") + name);
    }
    std::string last_error = "no OpenGL context API";
    for (const ContextApi& api : kContextApis) {
      if (TryContext(api, extensions, &last_error)) return;
    }
    Fail(last_error);
  }

  void Fail(const std::string& why) {
    device_failed_ = true;
    device_error_ = SanitizeReasonField(why);
  }

  /// Creates a context for [api], makes it current, checks that it has
  /// glBlitFramebuffer (GL or GLES 3) and reads GL_RENDERER; the context is
  /// released again and kept. False with *error set otherwise.
  bool TryContext(const ContextApi& api, const char* extensions,
                  std::string* error) {
    if (!eglBindAPI(api.api)) {
      *error = "eglBindAPI failed (" + EglErrorText(eglGetError()) + ")";
      return false;
    }
    // ClearCurrent below, and every later thread, bind this API first.
    context_api_ = api.api;
    EGLConfig config = nullptr;
    EGLint count = 0;
    const EGLint config_attrs[] = {EGL_RENDERABLE_TYPE, api.renderable_bit,
                                   EGL_SURFACE_TYPE, EGL_DONT_CARE, EGL_NONE};
    if (!eglChooseConfig(display_, config_attrs, &config, 1, &count) ||
        count < 1) {
      // A config-less context is the alternative where the display has one.
      if (!HasEglExtension(extensions, "EGL_KHR_no_config_context")) {
        *error = "cannot create an OpenGL context (no EGL config, " +
                 EglErrorText(eglGetError()) + ")";
        return false;
      }
      config = nullptr;  // EGL_NO_CONFIG_KHR
    }
    EGLContext context = EGL_NO_CONTEXT;
    // The share context is always EGL_NO_CONTEXT: no share group with
    // Flutter's contexts.
    if (api.api == EGL_OPENGL_API) {
      // 3.3 core first (what a modern host asks for); the driver's default
      // version when it refuses.
      const EGLint core[] = {EGL_CONTEXT_MAJOR_VERSION, 3,
                             EGL_CONTEXT_MINOR_VERSION, 3,
                             EGL_CONTEXT_OPENGL_PROFILE_MASK,
                             EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE};
      context = eglCreateContext(display_, config, EGL_NO_CONTEXT, core);
      if (context == EGL_NO_CONTEXT) {
        const EGLint plain[] = {EGL_NONE};
        context = eglCreateContext(display_, config, EGL_NO_CONTEXT, plain);
      }
    } else {
      const EGLint es3[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE};
      context = eglCreateContext(display_, config, EGL_NO_CONTEXT, es3);
    }
    if (context == EGL_NO_CONTEXT) {
      *error = "cannot create an OpenGL context (" +
               EglErrorText(eglGetError()) + ")";
      return false;
    }
    if (!eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) {
      *error = "eglMakeCurrent failed (" + EglErrorText(eglGetError()) + ")";
      eglDestroyContext(display_, context);
      return false;
    }
    // GL_MAJOR_VERSION exists from GL 3 / GLES 3, the versions that have
    // glBlitFramebuffer; an older context leaves it at 0.
    GLint major = 0;
    glGetIntegerv(GL_MAJOR_VERSION, &major);
    const char* version = reinterpret_cast<const char*>(glGetString(GL_VERSION));
    const char* renderer =
        reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    const std::string version_text = version ? version : "unknown version";
    const std::string renderer_text = renderer ? renderer : "unknown renderer";
    ClearCurrent();
    if (major < 3) {
      *error = "OpenGL context lacks glBlitFramebuffer (" + version_text + ")";
      eglDestroyContext(display_, context);
      return false;
    }
    context_ = context;
    device_name_ = SanitizeReasonField(renderer_text);
    return true;
  }

  /// Releases the calling thread's current context of this backend's API.
  void ClearCurrent() {
    eglBindAPI(context_api_);
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  /// Debug builds: GL work only happens with our context current.
  void AssertCurrent() const { assert(eglGetCurrentContext() == context_); }

  /// A [width]x[height] RGBA8 texture with an FBO (Flutter accepts RGBA8
  /// only). False with *error set, nothing left allocated.
  static bool CreateTarget(int width, int height, Target* out,
                           std::string* error) {
    while (glGetError() != GL_NO_ERROR) {
    }
    glGenTextures(1, &out->texture);
    glBindTexture(GL_TEXTURE_2D, out->texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, nullptr);
    // Level 0 only: the texture must be complete without mipmaps, both as an
    // FBO attachment and as an EGLImage source.
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glGenFramebuffers(1, &out->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, out->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           out->texture, 0);
    const bool complete =
        glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    const GLenum gl_error = glGetError();
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    if (complete && gl_error == GL_NO_ERROR) return true;
    *error = complete ? "OpenGL texture allocation failed (GL error " +
                            std::to_string(gl_error) + ")"
                      : "OpenGL render target is not complete";
    DeleteTarget(out);
    return false;
  }

  static void DeleteTarget(Target* target) {
    if (target->fbo) glDeleteFramebuffers(1, &target->fbo);
    if (target->texture) glDeleteTextures(1, &target->texture);
    *target = Target{};
  }

  /// One ring slot: export texture and FBO, the EGLImage of the texture and
  /// the platform image that carries it to FlTextureGL.
  bool CreateSlot(int width, int height, Slot* slot, std::string* error) {
    Target target;
    if (!CreateTarget(width, height, &target, error)) return false;
    // The image source is the export texture only, never the private render
    // texture (see the file header).
    const EGLint attrs[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    EGLImageKHR image = eglCreateImageKHR(
        display_, context_, EGL_GL_TEXTURE_2D_KHR,
        reinterpret_cast<EGLClientBuffer>(static_cast<uintptr_t>(target.texture)),
        attrs);
    if (image == EGL_NO_IMAGE_KHR) {
      *error = "eglCreateImageKHR failed (" + EglErrorText(eglGetError()) + ")";
      DeleteTarget(&target);
      return false;
    }
    auto* platform = new GlInterop::Image();
    platform->width = width;
    platform->height = height;
    platform->egl_image = image;
    platform->egl_display = display_;
    slot->texture = target.texture;
    slot->fbo = target.fbo;
    slot->image = image;
    slot->platform = platform;
    return true;
  }

  /// Render thread, context current. The Flutter-side texture and the
  /// EGLImage are released by the graveyard in a populate (the platform
  /// texture the compositor may still hold stays valid until then).
  void FreeSlot(Slot* slot) {
    if (slot->sync != EGL_NO_SYNC_KHR) eglDestroySyncKHR(display_, slot->sync);
    if (slot->fbo) glDeleteFramebuffers(1, &slot->fbo);
    if (slot->texture) glDeleteTextures(1, &slot->texture);
    if (slot->platform) interop_->Bury(slot->platform);
    *slot = Slot{};
  }

  /// Everything allocated: the ring, the retired generation, the private
  /// target. Render thread, context current.
  void FreeAllTargets() {
    for (Slot& slot : ring_) FreeSlot(&slot);
    ring_.clear();
    for (Slot& slot : retired_) FreeSlot(&slot);
    retired_.clear();
    DeleteTarget(&private_);
  }

  GlInterop* const interop_;
  const EGLDisplay display_;
  EGLContext context_ = EGL_NO_CONTEXT;
  EGLenum context_api_ = EGL_OPENGL_API;  // bound per thread before use

  // Written on the backend's thread in RunBound, read after its join.
  bool device_initialised_ = false;
  bool device_failed_ = false;
  std::string device_error_;  // why the device failed, one sanitized line
  std::string device_name_;   // GL_RENDERER, sanitized

  // Render thread only, after BindThread.
  bool render_thread_bound_ = false;
  std::string bind_error_;
  Target private_;  // mpv renders here, never the source of an EGLImage
  int private_w_ = 0;
  int private_h_ = 0;
  std::vector<Slot> ring_;
  std::vector<Slot> retired_;  // at most the surviving front slot
};

}  // namespace

std::unique_ptr<RenderBackend> CreateOpenGLBackend(GlInterop* interop) {
  return std::make_unique<OpenGLBackend>(interop);
}

}  // namespace mpv_kit
