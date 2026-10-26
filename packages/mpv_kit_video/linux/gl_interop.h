// Linux zero-copy interop: Vulkan images are allocated with exportable
// OPAQUE_FD memory and imported into Flutter's OpenGL (ES) context through
// GL_EXT_memory_object_fd, then handed to Flutter as an FlTextureGL — no
// copies. Requires Vulkan and GL to run on the same driver (device and
// driver UUIDs must match), otherwise the renderer falls back to software.
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
#include <mutex>
#include <vector>

#include "../src/video_renderer.h"
#include "../src/vulkan_backend.h"

namespace mpv_kit {

class GlInterop : public Interop, public VulkanInterop {
 public:
  explicit GlInterop(std::function<void()> frame_ready);
  ~GlInterop() override = default;

  // Interop
  VulkanInterop* vulkan() override { return gl_ok_ ? this : nullptr; }
  /// The GL probe failure, which the renderer puts in its reason trails.
  const char* interopReason() const override {
    return gl_reason_[0] ? gl_reason_ : nullptr;
  }
  bool SoftwareIsBgra() const override { return false; }  // GL_RGBA8
  void FrameReady() override { frame_ready_(); }

  // VulkanInterop
  std::vector<const char*> InstanceExtensions() const override { return {}; }
  std::vector<const char*> DeviceExtensions() const override;
  bool AcceptDevice(VkPhysicalDevice device) override;
  bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width, int height,
                   SharedImage* out) override;
  void DestroyImage(VkDevice dev, SharedImage* img) override;

  /// Platform data stored in SharedImage::platform.
  struct Image {
    int fd = -1;            // exported memory; GL takes ownership on import
    uint64_t size = 0;      // allocation size passed to glImportMemoryFdEXT
    int width = 0;
    int height = 0;
    uint32_t memory = 0;    // GL memory object (raster thread only)
    uint32_t texture = 0;   // GL texture name (raster thread only)
    bool failed = false;    // import failed; not retried every frame
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
  const char* gl_reason() const { return gl_reason_; }

 private:
  /// Probes Flutter's EGL display with a throwaway context: extension
  /// support and the GL device/driver UUIDs to match against Vulkan.
  void ProbeGl();

  std::function<void()> frame_ready_;
  std::mutex graveyard_mutex_;
  std::vector<Image*> graveyard_;
  bool gl_ok_ = false;
  const char* gl_reason_ = "";
  std::vector<std::array<uint8_t, 16>> gl_device_uuids_;
  std::array<uint8_t, 16> gl_driver_uuid_{};
};

}  // namespace mpv_kit
