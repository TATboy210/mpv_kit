#include "gl_interop.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <thread>

namespace mpv_kit {
namespace {

constexpr VkExternalMemoryHandleTypeFlagBits kHandleType =
    VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT;
// Flutter only accepts GL_RGBA8 textures.
constexpr VkFormat kVkFormat = VK_FORMAT_R8G8B8A8_UNORM;

// Images of disposed players; safe to free from any populate.
std::mutex orphans_mutex;
std::vector<GlInterop::Image*> orphans;

void FreeImages(const std::vector<GlInterop::Image*>& images) {
  for (GlInterop::Image* img : images) {
    if (img->texture) glDeleteTextures(1, &img->texture);
    // OpenGL backend: the producer's export texture was deleted on its render
    // thread already; the EGLImage (display-level, so any thread may destroy
    // it) goes after the Flutter-side texture that was bound to it.
    if (img->egl_image != EGL_NO_IMAGE_KHR)
      eglDestroyImageKHR(img->egl_display, img->egl_image);
    if (img->memory) glDeleteMemoryObjectsEXT(1, &img->memory);
    if (img->fd >= 0) close(img->fd);  // never imported
    delete img;
  }
}

/// Outcome of one throwaway-context attempt: the failing EGL call (null on
/// success) and its eglGetError() value, read straight after the failure.
struct ProbeAttempt {
  const char* failed_call = nullptr;
  EGLint error = EGL_SUCCESS;
};

/// Selects a GLES 2 config, creates a context and makes it current
/// surfaceless on [display], for the calling thread. On success the context
/// is returned through [out_ctx] and left current; on failure it is
/// EGL_NO_CONTEXT. The same steps the engine's own context creation takes.
ProbeAttempt TryProbeContext(EGLDisplay display, EGLContext* out_ctx) {
  const EGLint config_attrs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                                 EGL_NONE};
  const EGLint ctx_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  ProbeAttempt attempt;
  EGLConfig config = nullptr;
  EGLint num = 0;
  *out_ctx = EGL_NO_CONTEXT;
  if (!eglChooseConfig(display, config_attrs, &config, 1, &num) || num <= 0) {
    attempt.failed_call = "eglChooseConfig";
    attempt.error = eglGetError();
    return attempt;
  }
  EGLContext ctx = eglCreateContext(display, config, EGL_NO_CONTEXT, ctx_attrs);
  if (ctx == EGL_NO_CONTEXT) {
    attempt.failed_call = "eglCreateContext";
    attempt.error = eglGetError();
    return attempt;
  }
  // Surfaceless: EGL_KHR_surfaceless_context, which the engine also needs.
  if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
    attempt.failed_call = "eglMakeCurrent";
    attempt.error = eglGetError();
    eglDestroyContext(display, ctx);
    return attempt;
  }
  *out_ctx = ctx;
  return attempt;
}

/// What the probe thread found; written there, read only after the join.
struct GlProbeResult {
  bool ok = false;
  /// Empty on success. One line, no semicolons (the reason trail uses them
  /// as field separators and SanitizeReasonField would rewrite them).
  std::string reason;
  std::vector<std::array<uint8_t, 16>> device_uuids;
  std::array<uint8_t, 16> driver_uuid{};
};

/// The probe proper: runs on a thread of its own (see GlInterop::ProbeGl), so
/// no context is current on entry and none needs restoring on exit. Creates
/// a throwaway context on [display], reads the extension support and the GL
/// device/driver UUIDs, and destroys the context again.
GlProbeResult ProbeOnThisThread(EGLDisplay display) {
  GlProbeResult result;
  // eglInitialize on an initialized display is a no-op. Never terminate it:
  // the handle is shared with Flutter's engine.
  if (!eglInitialize(display, nullptr, nullptr)) {
    result.reason = "no EGL display";
    return result;
  }
  eglBindAPI(EGL_OPENGL_ES_API);
  // Mirror the engine's context (ES 2 request; drivers return the highest
  // compatible ES version) so extension support matches what populate sees.
  EGLContext ctx = EGL_NO_CONTEXT;
  const ProbeAttempt attempt = TryProbeContext(display, &ctx);
  if (attempt.failed_call) {
    result.reason = std::string("cannot create a probe EGL context: ") +
                    attempt.failed_call + " failed (" +
                    EglErrorText(attempt.error) + ")";
    return result;
  }
  if (!epoxy_has_gl_extension("GL_EXT_memory_object") ||
      !epoxy_has_gl_extension("GL_EXT_memory_object_fd")) {
    result.reason = "GL lacks GL_EXT_memory_object_fd";
  } else {
    GLint n = 0;
    glGetIntegerv(GL_NUM_DEVICE_UUIDS_EXT, &n);
    for (GLint i = 0; i < n; i++) {
      std::array<uint8_t, 16> uuid{};
      glGetUnsignedBytei_vEXT(GL_DEVICE_UUID_EXT, static_cast<GLuint>(i),
                              uuid.data());
      result.device_uuids.push_back(uuid);
    }
    glGetUnsignedBytevEXT(GL_DRIVER_UUID_EXT, result.driver_uuid.data());
    result.ok = !result.device_uuids.empty();
    if (!result.ok) result.reason = "GL reports no device UUID";
  }
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroyContext(display, ctx);
  return result;
}

void ClearGlErrors() {
  // Bounded: a lost context can report errors forever.
  for (int i = 0; i < 16 && glGetError() != GL_NO_ERROR; i++) {
  }
}

/// Raster thread, Flutter's context current: wraps the EGLImage of an
/// OpenGL-backend image in a GL texture (once per image; the texture then
/// follows the shared storage as the producer re-renders it). 0 on failure,
/// logged once and not retried, like the memory-object import.
uint32_t ImportEglImage(GlInterop::Image* img) {
  if (img->failed) return 0;
  ClearGlErrors();
  glGenTextures(1, &img->texture);
  glBindTexture(GL_TEXTURE_2D, img->texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, img->egl_image);
  const bool ok = glGetError() == GL_NO_ERROR;
  glBindTexture(GL_TEXTURE_2D, 0);
  if (!ok) {
    glDeleteTextures(1, &img->texture);
    img->texture = 0;
    img->failed = true;
    g_warning("mpv_kit: glEGLImageTargetTexture2DOES failed; video stays black");
  }
  return img->texture;
}

}  // namespace

// See gl_interop.h. EGL returns one handle per native display, so this is
// the display of the engine's fl_opengl_manager.cc.
EGLDisplay FlutterEglDisplay() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return EGL_NO_DISPLAY;
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    return eglGetPlatformDisplayEXT(
        EGL_PLATFORM_WAYLAND_EXT, gdk_wayland_display_get_wl_display(display),
        nullptr);
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    return eglGetPlatformDisplayEXT(
        EGL_PLATFORM_X11_EXT, gdk_x11_display_get_xdisplay(display), nullptr);
  }
#endif
  return EGL_NO_DISPLAY;
}

// The error's name and hexadecimal code (see gl_interop.h), so a reason line
// identifies it even for codes missing from the table.
std::string EglErrorText(EGLint error) {
  const char* name = "EGL_UNKNOWN";
  switch (error) {
    case EGL_SUCCESS: name = "EGL_SUCCESS"; break;
    case EGL_NOT_INITIALIZED: name = "EGL_NOT_INITIALIZED"; break;
    case EGL_BAD_ACCESS: name = "EGL_BAD_ACCESS"; break;
    case EGL_BAD_ALLOC: name = "EGL_BAD_ALLOC"; break;
    case EGL_BAD_ATTRIBUTE: name = "EGL_BAD_ATTRIBUTE"; break;
    case EGL_BAD_CONFIG: name = "EGL_BAD_CONFIG"; break;
    case EGL_BAD_CONTEXT: name = "EGL_BAD_CONTEXT"; break;
    case EGL_BAD_CURRENT_SURFACE: name = "EGL_BAD_CURRENT_SURFACE"; break;
    case EGL_BAD_DISPLAY: name = "EGL_BAD_DISPLAY"; break;
    case EGL_BAD_MATCH: name = "EGL_BAD_MATCH"; break;
    case EGL_BAD_NATIVE_PIXMAP: name = "EGL_BAD_NATIVE_PIXMAP"; break;
    case EGL_BAD_NATIVE_WINDOW: name = "EGL_BAD_NATIVE_WINDOW"; break;
    case EGL_BAD_PARAMETER: name = "EGL_BAD_PARAMETER"; break;
    case EGL_BAD_SURFACE: name = "EGL_BAD_SURFACE"; break;
    case EGL_CONTEXT_LOST: name = "EGL_CONTEXT_LOST"; break;
    default: break;
  }
  char hex[16];
  std::snprintf(hex, sizeof(hex), "0x%04x", static_cast<unsigned>(error));
  return std::string(name) + " " + hex;
}

GlInterop::GlInterop(std::function<void()> frame_ready)
    : frame_ready_(std::move(frame_ready)) {
  // Platform thread: the one place GDK may be used. The display handle is
  // all the probe needs from it.
  ProbeGl(FlutterEglDisplay());
}

std::unique_ptr<RenderBackend> GlInterop::CreateBackend(const char* api) {
  if (std::strcmp(api, "opengl") == 0) return CreateOpenGLBackend(this);
  return nullptr;
}

// The probe runs on a short-lived thread of its own, never on the platform
// thread. evidence/spike-flutter-linux.txt D-THREAD (native-verify run
// 40627862148): on the platform thread, eglMakeCurrent of a fresh context
// failed with EGL_BAD_ACCESS in 11 of 12 controllers of that job, while the
// very same steps succeeded on a fresh thread. What
// the platform thread has current (GDK/Flutter state) is not ours to reason
// about, so the probe needs a thread that has nothing current. This is the
// principle OpenGLBackend::RunBound already follows for its create-time EGL
// work. The thread is always joined before this function returns, and the
// result is copied into the members here, on the platform thread, only after
// the join.
void GlInterop::ProbeGl(EGLDisplay display) {
  if (display == EGL_NO_DISPLAY) {
    gl_reason_ = "no EGL display";
    return;
  }
  GlProbeResult result;
  std::thread worker;
  try {
    worker = std::thread([display, &result] {
      result = ProbeOnThisThread(display);
      eglReleaseThread();  // drops this thread's EGL bookkeeping
    });
  } catch (const std::exception&) {
    gl_reason_ = "cannot start the EGL probe thread";
    return;
  }
  worker.join();
  gl_ok_ = result.ok;
  gl_reason_ = std::move(result.reason);
  gl_device_uuids_ = std::move(result.device_uuids);
  gl_driver_uuid_ = result.driver_uuid;
}

std::vector<const char*> GlInterop::DeviceExtensions() const {
  return {VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME};
}

bool GlInterop::AcceptDevice(VkPhysicalDevice device) {
  // Opaque FD memory is only meaningful to the same driver on the same GPU.
  VkPhysicalDeviceIDProperties id{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
  VkPhysicalDeviceProperties2 props{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &id};
  vkGetPhysicalDeviceProperties2(device, &props);
  const bool same_device = std::any_of(
      gl_device_uuids_.begin(), gl_device_uuids_.end(),
      [&](const auto& u) { return std::memcmp(u.data(), id.deviceUUID, 16) == 0; });
  if (!same_device ||
      std::memcmp(gl_driver_uuid_.data(), id.driverUUID, 16) != 0)
    return false;

  VkPhysicalDeviceExternalImageFormatInfo ext{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO};
  ext.handleType = kHandleType;
  VkPhysicalDeviceImageFormatInfo2 info{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2, &ext};
  info.format = kVkFormat;
  info.type = VK_IMAGE_TYPE_2D;
  info.tiling = VK_IMAGE_TILING_OPTIMAL;
  info.usage = kSharedImageUsage;
  VkExternalImageFormatProperties ext_props{
      VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES};
  VkImageFormatProperties2 out{VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2,
                               &ext_props};
  if (vkGetPhysicalDeviceImageFormatProperties2(device, &info, &out) !=
      VK_SUCCESS)
    return false;
  return ext_props.externalMemoryProperties.externalMemoryFeatures &
         VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT;
}

bool GlInterop::CreateImage(VkPhysicalDevice pd, VkDevice dev, int width,
                            int height, SharedImage* out) {
  VkExternalMemoryImageCreateInfo ext{
      VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO};
  ext.handleTypes = kHandleType;
  VkImageCreateInfo ici{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, &ext};
  ici.imageType = VK_IMAGE_TYPE_2D;
  ici.format = kVkFormat;
  ici.extent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1};
  ici.mipLevels = 1;
  ici.arrayLayers = 1;
  ici.samples = VK_SAMPLE_COUNT_1_BIT;
  // GL imports with its default GL_OPTIMAL_TILING_EXT, matching this.
  ici.tiling = VK_IMAGE_TILING_OPTIMAL;
  ici.usage = kSharedImageUsage;
  ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  if (vkCreateImage(dev, &ici, nullptr, &out->image) != VK_SUCCESS) return false;

  VkMemoryRequirements req;
  vkGetImageMemoryRequirements(dev, out->image, &req);
  VkPhysicalDeviceMemoryProperties mp;
  vkGetPhysicalDeviceMemoryProperties(pd, &mp);
  uint32_t type = UINT32_MAX;
  for (uint32_t i = 0; i < mp.memoryTypeCount && type == UINT32_MAX; i++) {
    if ((req.memoryTypeBits & (1u << i)) &&
        (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
      type = i;
  }

  // Dedicated allocation: GL marks the import GL_DEDICATED_MEMORY_OBJECT_EXT.
  VkMemoryDedicatedAllocateInfo dedicated{
      VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
  dedicated.image = out->image;
  VkExportMemoryAllocateInfo exp{VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO,
                                 &dedicated};
  exp.handleTypes = kHandleType;
  VkMemoryAllocateInfo mai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, &exp};
  mai.allocationSize = req.size;
  mai.memoryTypeIndex = type;

  auto* img = new Image();
  VkMemoryGetFdInfoKHR gfi{VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR};
  gfi.handleType = kHandleType;
  if (type == UINT32_MAX ||
      vkAllocateMemory(dev, &mai, nullptr, &out->memory) != VK_SUCCESS ||
      vkBindImageMemory(dev, out->image, out->memory, 0) != VK_SUCCESS ||
      (gfi.memory = out->memory,
       vkGetMemoryFdKHR(dev, &gfi, &img->fd) != VK_SUCCESS)) {
    if (out->memory) vkFreeMemory(dev, out->memory, nullptr);
    vkDestroyImage(dev, out->image, nullptr);
    out->image = VK_NULL_HANDLE;
    out->memory = VK_NULL_HANDLE;
    delete img;
    return false;
  }
  img->size = req.size;
  img->width = width;
  img->height = height;
  out->format = kVkFormat;
  out->width = width;
  out->height = height;
  out->platform = img;
  return true;
}

void GlInterop::DestroyImage(VkDevice dev, SharedImage* img) {
  if (img->image) vkDestroyImage(dev, img->image, nullptr);
  // The exported fd (or GL's import of it) keeps the allocation alive until
  // the graveyard releases the GL side.
  if (img->memory) vkFreeMemory(dev, img->memory, nullptr);
  if (img->platform) Bury(static_cast<Image*>(img->platform));
  *img = SharedImage{};
}

void GlInterop::Bury(Image* img) {
  std::lock_guard<std::mutex> lock(graveyard_mutex_);
  graveyard_.push_back(img);
}

void GlInterop::DrainGraveyard() {
  std::vector<Image*> dead;
  {
    std::lock_guard<std::mutex> lock(graveyard_mutex_);
    dead.swap(graveyard_);
  }
  {
    std::lock_guard<std::mutex> lock(orphans_mutex);
    dead.insert(dead.end(), orphans.begin(), orphans.end());
    orphans.clear();
  }
  FreeImages(dead);
}

void GlInterop::Orphan() {
  std::lock_guard<std::mutex> lock(graveyard_mutex_);
  std::lock_guard<std::mutex> lock2(orphans_mutex);
  orphans.insert(orphans.end(), graveyard_.begin(), graveyard_.end());
  graveyard_.clear();
}

uint32_t GlInterop::TextureFor(Image* img) {
  if (img->texture) return img->texture;
  if (img->egl_image != EGL_NO_IMAGE_KHR) return ImportEglImage(img);
  if (img->failed || img->fd < 0) return 0;
  ClearGlErrors();
  glCreateMemoryObjectsEXT(1, &img->memory);
  const GLint dedicated = GL_TRUE;
  glMemoryObjectParameterivEXT(img->memory, GL_DEDICATED_MEMORY_OBJECT_EXT,
                               &dedicated);
  glImportMemoryFdEXT(img->memory, img->size, GL_HANDLE_TYPE_OPAQUE_FD_EXT,
                      img->fd);
  if (glGetError() != GL_NO_ERROR) {
    img->failed = true;  // fd still ours; closed by the graveyard
    g_warning("mpv_kit: glImportMemoryFdEXT failed; video stays black");
    return 0;
  }
  img->fd = -1;  // owned by GL now

  glGenTextures(1, &img->texture);
  glBindTexture(GL_TEXTURE_2D, img->texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_TILING_EXT, GL_OPTIMAL_TILING_EXT);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexStorageMem2DEXT(GL_TEXTURE_2D, 1, GL_RGBA8, img->width, img->height,
                       img->memory, 0);
  const bool ok = glGetError() == GL_NO_ERROR;
  glBindTexture(GL_TEXTURE_2D, 0);
  if (!ok) {
    glDeleteTextures(1, &img->texture);
    img->texture = 0;
    img->failed = true;
    g_warning("mpv_kit: glTexStorageMem2DEXT failed; video stays black");
  }
  return img->texture;
}

}  // namespace mpv_kit
