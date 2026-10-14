// Vulkan device + shared image ring used by the zero-copy backend.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <volk.h>

namespace mpv_kit {

/// Usage every shared image is created with; also reported to mpv so
/// libplacebo may pick compute/blit paths.
constexpr VkImageUsageFlags kSharedImageUsage =
    VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT |
    VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;

/// One shareable render target.
struct SharedImage {
  VkImage image = VK_NULL_HANDLE;
  VkDeviceMemory memory = VK_NULL_HANDLE;
  VkFormat format = VK_FORMAT_UNDEFINED;
  int width = 0;
  int height = 0;
  uint64_t ready_value = 0;                 // timeline value when rendered
  bool initialized = false;                 // layout no longer UNDEFINED
  void* platform = nullptr;                 // owned by VulkanInterop
};

/// Platform half of zero-copy sharing (D3D11 / GL / Metal).
class VulkanInterop {
 public:
  virtual ~VulkanInterop() = default;
  virtual std::vector<const char*> InstanceExtensions() const = 0;
  virtual std::vector<const char*> DeviceExtensions() const = 0;
  /// Whether this physical device can share with the compositor (e.g. same
  /// adapter LUID / device UUID).
  virtual bool AcceptDevice(VkPhysicalDevice device) = 0;
  /// Allocates image+memory shareable with the compositor. Called on the
  /// render thread; must fill image, memory, format, width, height, platform.
  virtual bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width,
                           int height, SharedImage* out) = 0;
  virtual void DestroyImage(VkDevice dev, SharedImage* img) = 0;
};

/// Instance, device and queues configured for libplacebo + Vulkan video.
class VulkanContext {
 public:
  explicit VulkanContext(VulkanInterop* interop) : interop_(interop) {}
  ~VulkanContext();

  /// Creates instance + device. On failure [error] explains why.
  bool Init(std::string* error);

  /// (Re)allocates [count] images of the given size. Waits for the GPU.
  bool AllocateRing(int count, int width, int height, std::string* error);
  void FreeRing();

  /// Reserves the next timeline value for a render into ring[i].
  uint64_t NextSignalValue(int i);
  /// Waits until rendering into ring[i] has completed on the GPU.
  bool WaitImage(int i);
  VkSemaphore timeline() const { return timeline_; }

  VkInstance instance() const { return instance_; }
  VkPhysicalDevice physical_device() const { return physical_device_; }
  VkDevice device() const { return device_; }
  uint32_t api_version() const { return api_version_; }
  uint32_t graphics_family() const { return graphics_family_; }
  uint32_t graphics_count() const { return graphics_count_; }
  const std::vector<const char*>& enabled_extensions() const {
    return device_extensions_;
  }
  const VkPhysicalDeviceFeatures2* features() const { return &features_; }
  std::vector<SharedImage>& ring() { return ring_; }
  const std::string& device_name() const { return device_name_; }

 private:
  bool PickDevice(std::string* error);
  bool CreateDevice(std::string* error);

  VulkanInterop* interop_;
  VkInstance instance_ = VK_NULL_HANDLE;
  VkPhysicalDevice physical_device_ = VK_NULL_HANDLE;
  VkDevice device_ = VK_NULL_HANDLE;
  uint32_t api_version_ = 0;
  uint32_t graphics_family_ = 0;
  uint32_t graphics_count_ = 1;
  std::string device_name_;
  std::vector<std::string> extension_storage_;
  std::vector<const char*> device_extensions_;
  // Feature chain kept alive for libplacebo (it reads it during import).
  VkPhysicalDeviceFeatures2 features_{};
  VkPhysicalDeviceVulkan11Features features11_{};
  VkPhysicalDeviceVulkan12Features features12_{};
  VkPhysicalDeviceVulkan13Features features13_{};
  std::vector<SharedImage> ring_;
  VkSemaphore timeline_ = VK_NULL_HANDLE;
  uint64_t timeline_value_ = 0;
};

}  // namespace mpv_kit
