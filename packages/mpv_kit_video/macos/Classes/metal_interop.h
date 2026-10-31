// macOS zero-copy interop: every shared image is an IOSurface-backed
// CVPixelBuffer that MoltenVK binds as the VkImage's storage
// (VK_EXT_metal_objects, VkImportMetalIOSurfaceInfoEXT). Flutter's Metal
// compositor wraps the same CVPixelBuffer through CVMetalTextureCache, so
// frames are never copied.
#pragma once

#include <CoreVideo/CoreVideo.h>

#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "render_backend.h"
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
  const char* interopReason() const override {
    return metal_reason_.empty() ? nullptr : metal_reason_.c_str();
  }
  bool SoftwareIsBgra() const override { return true; }  // kCVPixelFormatType_32BGRA
  void FrameReady() override { frame_ready_(); }
  /// +1 for Flutter: copyPixelBuffer returns an owned reference.
  void RetainFrame(void* platform) override {
    CVPixelBufferRetain(static_cast<CVPixelBufferRef>(platform));
  }
  /// For "vulkan" with a Metal device present: the built-in Vulkan backend
  /// (CreateVulkanBackend(this)) wrapped so that device_name() also names
  /// the Vulkan driver that carries the rendering onto Metal ("... via
  /// MoltenVK"; ROADMAP Phase 13 SC2, ADR 0004 Decision 3, ADR 0005). The
  /// wrapper changes nothing else. Any other api, or no Metal device,
  /// returns nullptr so the engine takes its unchanged built-in branch
  /// (and the unchanged "no Metal device" trail).
  std::unique_ptr<RenderBackend> CreateBackend(const char* api) override;
  /// The Vulkan driver recorded for the physical device called
  /// [device_name]: the single distinct driver name AcceptDevice saw for
  /// that name, or "unknown Vulkan driver" when there is none or the name
  /// does not identify one driver.
  std::string CarrierFor(const std::string& device_name) const;

  // VulkanInterop
  PFN_vkGetInstanceProcAddr Loader() override;
  std::vector<const char*> InstanceExtensions() const override { return {}; }
  std::vector<const char*> DeviceExtensions() const override;
  /// The system default Metal device, which Flutter composites on (and
  /// which MoltenVK reports as deviceLUID = big-endian registryID).
  bool AcceptDevice(VkPhysicalDevice device) override;
  bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width, int height,
                   SharedImage* out) override;
  void DestroyImage(VkDevice dev, SharedImage* img) override;

  /// Creates an IOSurface-backed BGRA pixel buffer Flutter can sample.
  static CVPixelBufferRef CreatePixelBuffer(int width, int height);

 private:
  std::function<void()> frame_ready_;
  bool metal_ok_ = false;
  // Why zero-copy sharing is unavailable (probe failure), empty when Metal
  // came up (OBS-03).
  std::string metal_reason_;
  uint64_t registry_id_ = 0;  // of MTLCreateSystemDefaultDevice()
  // (device name, driver name) of every device AcceptDevice accepted.
  // Written inside VulkanContext::Init and read while VideoRenderer::Start
  // composes the reason head, both on the platform thread, so no lock.
  std::vector<std::pair<std::string, std::string>> carriers_;
};

}  // namespace mpv_kit
