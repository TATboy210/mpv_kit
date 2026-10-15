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
  /// Vulkan entry point to use instead of the system loader (e.g. the
  /// MoltenVK bundled inside a macOS app). nullptr: let volk find it.
  virtual PFN_vkGetInstanceProcAddr Loader() { return nullptr; }
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

  /// (Re)allocates [count] images of the given size. The previous ring is
  /// kept (retired) until FreeRetired() or the next reallocation, so its
  /// last frame can stay on screen meanwhile. Waits for the GPU.
  bool AllocateRing(int count, int width, int height, std::string* error);
  void FreeRing();
  void FreeRetired();

  /// Reserves the next timeline value for a render into ring[i].
  uint64_t NextSignalValue(int i);
  /// Waits until rendering into ring[i] has completed on the GPU:
  /// VK_SUCCESS, VK_TIMEOUT (1 s) or an error such as VK_ERROR_DEVICE_LOST.
  VkResult WaitImage(int i);
  VkSemaphore timeline() const { return timeline_; }

  VkInstance instance() const { return instance_; }
  VkPhysicalDevice physical_device() const { return physical_device_; }
  VkDevice device() const { return device_; }
  uint32_t api_version() const { return api_version_; }
  /// Queue family index and number of queues created in it.
  struct QueueFamily {
    uint32_t index = 0;
    uint32_t count = 0;
  };
  QueueFamily graphics_queues() const { return graphics_; }
  /// Dedicated async families, or the graphics family if the GPU has none.
  QueueFamily compute_queues() const { return compute_; }
  QueueFamily transfer_queues() const { return transfer_; }
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
  QueueFamily graphics_, compute_, transfer_;
  std::string device_name_;
  std::vector<std::string> extension_storage_;
  std::vector<const char*> device_extensions_;
  // Feature chain kept alive for libplacebo (it reads it during import).
  VkPhysicalDeviceFeatures2 features_{};
  VkPhysicalDeviceVulkan11Features features11_{};
  VkPhysicalDeviceVulkan12Features features12_{};
  VkPhysicalDeviceVulkan13Features features13_{};
  // Extension feature structs, chained after features13_ when their
  // extension is enabled (see CreateDevice).
  struct {
    VkPhysicalDeviceDescriptorBufferFeaturesEXT descriptor_buffer;
    VkPhysicalDeviceShaderAtomicFloatFeaturesEXT atomic_float;
    VkPhysicalDeviceShaderObjectFeaturesEXT shader_object;
    VkPhysicalDeviceCooperativeMatrixFeaturesKHR cooperative_matrix;
    VkPhysicalDeviceVideoMaintenance1FeaturesKHR video_maintenance1;
    VkPhysicalDeviceShaderExpectAssumeFeaturesKHR expect_assume;
    VkPhysicalDeviceShaderSubgroupRotateFeaturesKHR subgroup_rotate;
    VkPhysicalDeviceShaderRelaxedExtendedInstructionFeaturesKHR
        relaxed_extended_instruction;
    VkPhysicalDeviceVideoMaintenance2FeaturesKHR video_maintenance2;
    VkPhysicalDeviceVideoDecodeVP9FeaturesKHR video_decode_vp9;
  } ext_{};
  std::vector<SharedImage> ring_;
  std::vector<SharedImage> retired_;
  VkSemaphore timeline_ = VK_NULL_HANDLE;
  uint64_t timeline_value_ = 0;
};

}  // namespace mpv_kit
