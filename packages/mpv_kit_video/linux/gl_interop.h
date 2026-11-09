// Linux zero-copy interop: Vulkan images are allocated with exportable
// OPAQUE_FD memory and imported into Flutter's OpenGL (ES) context through
// GL_EXT_memory_object_fd, then handed to Flutter as an FlTextureGL — no
// copies. Requires Vulkan and GL to run on the same driver (device and
// driver UUIDs must match), otherwise the renderer falls back to software.
//
// Linux now has two GPU paths, and both end in the same FlTextureGL, GL
// graveyard and compositor quarantine: the Vulkan path above (memory
// objects, vulkan_backend.cc) and the OpenGL path (opengl_backend.cc), where
// mpv renders through its OpenGL render API in a context of its own and each
// frame is blitted into an export texture whose EGLImage Flutter imports with
// glEGLImageTargetTexture2DOES. The OpenGL path needs no Vulkan and no UUID
// match; the chain that orders the two is LinuxBackendCandidates.
//
// GL objects can only be created and deleted while Flutter's context is
// current, i.e. inside FlTextureGL::populate on the raster thread. Retired
// images are therefore queued in this texture's graveyard, drained by its
// own next populate — the engine keeps drawing the texture it got last
// until populate hands out a new one, so another player must never delete
// it. Images of disposed players become orphans, which any populate frees.
#pragma once

#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "../src/linux_candidates.h"
#include "../src/video_renderer.h"
#include "../src/vulkan_backend.h"
// After the project headers on purpose: EGL's platform header pulls in Xlib,
// whose macros (None, Status, ...) must not precede the Vulkan headers.
#include <epoxy/egl.h>

namespace mpv_kit {

/// The same EGL display Flutter's engine renders on (see the engine's
/// fl_opengl_manager.cc): EGL returns one handle per native display. Uses
/// GDK, so it may only be called on the platform thread. Never queries a
/// current context. EGL_NO_DISPLAY when there is none.
EGLDisplay FlutterEglDisplay();

/// "EGL_BAD_ACCESS 0x3002": the error's name and hexadecimal code.
std::string EglErrorText(EGLint error);

class GlInterop;

/// The OpenGL backend (opengl_backend.cc): mpv's OpenGL render API in an EGL
/// context of its own on Flutter's display, frames handed to [interop]'s
/// FlTextureGL as EGLImages.
std::unique_ptr<RenderBackend> CreateOpenGLBackend(GlInterop* interop);

class GlInterop : public Interop, public VulkanInterop {
 public:
  explicit GlInterop(std::function<void()> frame_ready);
  ~GlInterop() override = default;

  // Interop
  VulkanInterop* vulkan() override { return gl_ok_ ? this : nullptr; }
  /// The GL probe failure, which the renderer puts in its reason trails.
  const char* interopReason() const override {
    return gl_reason_.empty() ? nullptr : gl_reason_.c_str();
  }
  bool SoftwareIsBgra() const override { return false; }  // GL_RGBA8
  void FrameReady() override { frame_ready_(); }
  /// The Linux chain (decision A of 15-04): Vulkan and OpenGL candidates.
  std::vector<BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    return LinuxBackendCandidates(choice);
  }
  /// "opengl" is this platform's own backend; the built-in "vulkan" and
  /// "software" return nullptr.
  std::unique_ptr<RenderBackend> CreateBackend(const char* api) override;

  // VulkanInterop
  std::vector<const char*> InstanceExtensions() const override { return {}; }
  std::vector<const char*> DeviceExtensions() const override;
  bool AcceptDevice(VkPhysicalDevice device) override;
  /// The DRM render node of [device] for VA-API interop (HWD-03), from its
  /// VkPhysicalDeviceDrmPropertiesEXT; -1 when the driver, the device or
  /// /dev/dri offers none (llvmpipe/lavapipe, hosted runners).
  int OpenDrmRenderNode(VkPhysicalDevice device) override;
  void CloseDrmRenderNode(int fd) override;
  bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width, int height,
                   SharedImage* out) override;
  void DestroyImage(VkDevice dev, SharedImage* img) override;

  /// Platform data of one shared image (SharedImage::platform for Vulkan,
  /// TargetView::platform for OpenGL). Two sources, told apart by egl_image:
  ///   * Vulkan: fd + size, imported as a memory object (egl_image empty).
  ///   * OpenGL: egl_image, an EGLImage made by OpenGLBackend from its export
  ///     texture; imported with glEGLImageTargetTexture2DOES and destroyed
  ///     with the image (fd stays -1).
  struct Image {
    int fd = -1;            // exported memory; GL takes ownership on import
    uint64_t size = 0;      // allocation size passed to glImportMemoryFdEXT
    int width = 0;
    int height = 0;
    uint32_t memory = 0;    // GL memory object (raster thread only)
    uint32_t texture = 0;   // GL texture name (raster thread only)
    bool failed = false;    // import failed; not retried every frame
    // OpenGL backend only: non-empty means OpenGLBackend produced this
    // image. The EGLImage is a display-level object, so the raster thread
    // can destroy it; its source texture was deleted on the render thread
    // already, which an EGLImage sibling survives.
    EGLImageKHR egl_image = EGL_NO_IMAGE_KHR;
    EGLDisplay egl_display = EGL_NO_DISPLAY;
  };

  /// Raster thread, Flutter's GL context current: returns the GL texture of
  /// [img], importing it on first use. 0 on failure (logged once).
  static uint32_t TextureFor(Image* img);
  /// Queues GL-side cleanup of [img] (any thread).
  void Bury(Image* img);
  /// Raster thread, Flutter's GL context current: frees this texture's
  /// retired images and every orphan.
  void DrainGraveyard();
  /// Hands the remaining graveyard to the orphan list. Call once the
  /// engine has dropped the texture (after unregistering it).
  void Orphan();

  /// Why Vulkan sharing is unavailable (empty when it is available).
  const char* gl_reason() const { return gl_reason_.c_str(); }

 private:
  /// Probes Flutter's EGL [display] (taken on the platform thread) with a
  /// throwaway context created on a short-lived thread of its own: extension
  /// support and the GL device/driver UUIDs to match against Vulkan. The
  /// members are written after that thread has been joined.
  void ProbeGl(EGLDisplay display);

  std::function<void()> frame_ready_;
  std::mutex graveyard_mutex_;
  std::vector<Image*> graveyard_;
  bool gl_ok_ = false;
  // Owned by this interop (one per controller), so interopReason() stays
  // valid for as long as VideoRenderer::Start reads it.
  std::string gl_reason_;
  std::vector<std::array<uint8_t, 16>> gl_device_uuids_;
  std::array<uint8_t, 16> gl_driver_uuid_{};
};

}  // namespace mpv_kit
