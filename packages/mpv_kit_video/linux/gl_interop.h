// Linux zero-copy interop: Vulkan images are allocated with exportable
// OPAQUE_FD memory and imported into Flutter's OpenGL (ES) context through
// GL_EXT_memory_object_fd, then handed to Flutter as an FlTextureGL — no
// copies. Requires Vulkan and GL to run on the same driver (device and
// driver UUIDs must match), otherwise the renderer falls back to software.
//
// GL objects can only be created and deleted while Flutter's context is
// current, i.e. inside FlTextureGL::populate on the raster thread. Retired
// images are therefore queued in a process-wide graveyard that the next
// populate call (of any mpv_kit texture) drains.
#pragma once

#include <array>
#include <cstdint>
#include <functional>
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
  /// [img], importing it on first use. 0 on failure.
  static uint32_t TextureFor(Image* img);
  /// Raster thread, Flutter's GL context current: deletes retired images.
  static void DrainGraveyard();
  /// Queues GL-side cleanup of [img] (any thread).
  static void Bury(Image* img);

  /// Why Vulkan sharing is unavailable (empty when it is available).
  const char* gl_reason() const { return gl_reason_; }

 private:
  /// Probes Flutter's EGL display with a throwaway context: extension
  /// support and the GL device/driver UUIDs to match against Vulkan.
  void ProbeGl();

  std::function<void()> frame_ready_;
  bool gl_ok_ = false;
  const char* gl_reason_ = "";
  std::vector<std::array<uint8_t, 16>> gl_device_uuids_;
  std::array<uint8_t, 16> gl_driver_uuid_{};
};

}  // namespace mpv_kit
