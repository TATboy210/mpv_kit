// macOS zero-copy interop: every shared image is an IOSurface-backed
// CVPixelBuffer that MoltenVK binds as the VkImage's storage
// (VK_EXT_metal_objects, VkImportMetalIOSurfaceInfoEXT). Flutter's Metal
// compositor wraps the same CVPixelBuffer through CVMetalTextureCache, so
// frames are never copied.
#pragma once

#include <CoreVideo/CoreVideo.h>

#include <functional>
#include <string>
#include <vector>

#include "video_renderer.h"
#include "vulkan_backend.h"

namespace mpv_kit {

class MetalInterop : public Interop, public VulkanInterop {
 public:
  explicit MetalInterop(std::function<void()> frame_ready);
  ~MetalInterop() override = default;

  // Interop
  /// MoltenVK aborts the process (instead of failing) without a Metal
  /// device, so Vulkan is only offered when Metal is present.
  VulkanInterop* vulkan() override { return metal_ok_ ? this : nullptr; }
  bool SoftwareIsBgra() const override { return true; }  // kCVPixelFormatType_32BGRA
  void FrameReady() override { frame_ready_(); }
  /// +1 for Flutter: copyPixelBuffer returns an owned reference.
  void RetainFrame(void* platform) override {
    CVPixelBufferRetain(static_cast<CVPixelBufferRef>(platform));
  }

  // VulkanInterop
  PFN_vkGetInstanceProcAddr Loader() override;
  std::vector<const char*> InstanceExtensions() const override { return {}; }
  std::vector<const char*> DeviceExtensions() const override;
  /// IOSurfaces are shareable between every GPU of the machine.
  bool AcceptDevice(VkPhysicalDevice) override { return true; }
  bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width, int height,
                   SharedImage* out) override;
  void DestroyImage(VkDevice dev, SharedImage* img) override;

  /// Creates an IOSurface-backed BGRA pixel buffer Flutter can sample.
  static CVPixelBufferRef CreatePixelBuffer(int width, int height);

 private:
  std::function<void()> frame_ready_;
  bool metal_ok_ = false;
};

}  // namespace mpv_kit
