#include "vulkan_backend.h"

#include <algorithm>
#include <cstring>
#include <mutex>

namespace mpv_kit {
namespace {

// Same optional device extensions mpv requests in mppl_create_vulkan()
// (video/out/vulkan/context.c) so FFmpeg's Vulkan hwcontext and Vulkan Video
// decoding (--hwdec=vulkan) work, plus what libplacebo uses opportunistically.
constexpr const char* kOptionalDeviceExtensions[] = {
    VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
    VK_EXT_SHADER_ATOMIC_FLOAT_EXTENSION_NAME,
    VK_KHR_VIDEO_QUEUE_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_QUEUE_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_H264_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_H265_EXTENSION_NAME,
    "VK_KHR_video_decode_av1",
    "VK_KHR_video_maintenance1",
    VK_KHR_ZERO_INITIALIZE_WORKGROUP_MEMORY_EXTENSION_NAME,
    VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME,
    VK_EXT_PHYSICAL_DEVICE_DRM_EXTENSION_NAME,
    VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME,
    "VK_KHR_portability_subset",  // required on MoltenVK when exposed
};

bool HasExtension(const std::vector<VkExtensionProperties>& list,
                  const char* name) {
  return std::any_of(list.begin(), list.end(), [&](const auto& e) {
    return std::strcmp(e.extensionName, name) == 0;
  });
}

/// Process-wide Vulkan instance shared by every player.
///
/// volk keeps its function pointers in globals, so they are loaded exactly
/// once, before any render thread exists. volkLoadInstance() resolves the
/// device-level entry points through vkGetInstanceProcAddr, i.e. dispatching
/// trampolines that are valid for every device — players never call
/// volkLoadDevice(), which would retarget the globals at one device.
/// The instance lives until process exit.
struct SharedInstance {
  VkInstance instance = VK_NULL_HANDLE;
  std::string error;
};

SharedInstance CreateSharedInstance(VulkanInterop* interop);

const SharedInstance& GetSharedInstance(VulkanInterop* interop) {
  static SharedInstance shared;
  static std::once_flag once;
  std::call_once(once, [interop] { shared = CreateSharedInstance(interop); });
  return shared;
}

SharedInstance CreateSharedInstance(VulkanInterop* interop) {
  SharedInstance out;
  // volk loads vulkan-1.dll / libvulkan.so.1 / MoltenVK at runtime, so a
  // missing loader degrades to the software backend instead of failing to
  // start the app. The interop is a per-platform type, so its Loader() and
  // extension lists are the same for every player.
  if (PFN_vkGetInstanceProcAddr loader = interop->Loader()) {
    volkInitializeCustom(loader);
  } else if (volkInitialize() != VK_SUCCESS) {
    out.error = "Vulkan loader not found";
    return out;
  }
  uint32_t loader_version = VK_API_VERSION_1_0;
  if (vkEnumerateInstanceVersion) vkEnumerateInstanceVersion(&loader_version);
  if (loader_version < VK_API_VERSION_1_3) {
    out.error = "Vulkan loader older than 1.3";
    return out;
  }

  uint32_t count = 0;
  vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr);
  std::vector<VkExtensionProperties> available(count);
  vkEnumerateInstanceExtensionProperties(nullptr, &count, available.data());

  std::vector<const char*> exts = interop->InstanceExtensions();
  VkInstanceCreateFlags flags = 0;
  if (HasExtension(available, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
    exts.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
  }
  for (const char* e : exts) {
    if (!HasExtension(available, e)) {
      out.error = std::string("missing instance extension ") + e;
      return out;
    }
  }

  VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
  app.pApplicationName = "mpv_kit";
  app.apiVersion = VK_API_VERSION_1_3;
  VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
  ici.flags = flags;
  ici.pApplicationInfo = &app;
  ici.enabledExtensionCount = static_cast<uint32_t>(exts.size());
  ici.ppEnabledExtensionNames = exts.data();
  if (vkCreateInstance(&ici, nullptr, &out.instance) != VK_SUCCESS) {
    out.instance = VK_NULL_HANDLE;
    out.error = "vkCreateInstance failed";
    return out;
  }
  volkLoadInstance(out.instance);
  return out;
}

}  // namespace

VulkanContext::~VulkanContext() {
  FreeRing();
  if (timeline_) vkDestroySemaphore(device_, timeline_, nullptr);
  if (device_) vkDestroyDevice(device_, nullptr);
  // The instance is shared (GetSharedInstance) and outlives every context.
}

bool VulkanContext::Init(std::string* error) {
  const SharedInstance& shared = GetSharedInstance(interop_);
  if (!shared.instance) {
    *error = shared.error;
    return false;
  }
  instance_ = shared.instance;
  api_version_ = VK_API_VERSION_1_3;
  return PickDevice(error) && CreateDevice(error);
}

bool VulkanContext::PickDevice(std::string* error) {
  uint32_t n = 0;
  vkEnumeratePhysicalDevices(instance_, &n, nullptr);
  std::vector<VkPhysicalDevice> devices(n);
  vkEnumeratePhysicalDevices(instance_, &n, devices.data());

  // Prefer the device the compositor uses (interop decides), then discrete.
  VkPhysicalDevice best = VK_NULL_HANDLE;
  int best_score = -1;
  for (VkPhysicalDevice pd : devices) {
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(pd, &props);
    if (props.apiVersion < VK_API_VERSION_1_3) continue;
    if (!interop_->AcceptDevice(pd)) continue;
    int score = props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU   ? 3
                : props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU ? 2
                                                                            : 1;
    if (score > best_score) {
      best = pd;
      best_score = score;
      device_name_ = props.deviceName;
    }
  }
  if (!best) {
    *error = "no Vulkan 1.3 device shareable with the compositor";
    return false;
  }
  physical_device_ = best;
  return true;
}

bool VulkanContext::CreateDevice(std::string* error) {
  uint32_t nqf = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(physical_device_, &nqf, nullptr);
  std::vector<VkQueueFamilyProperties> qfs(nqf);
  vkGetPhysicalDeviceQueueFamilyProperties(physical_device_, &nqf, qfs.data());

  int graphics = -1, decode = -1;
  for (uint32_t i = 0; i < nqf; i++) {
    if (graphics < 0 && (qfs[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) &&
        (qfs[i].queueFlags & VK_QUEUE_COMPUTE_BIT))
      graphics = static_cast<int>(i);
    if (decode < 0 && (qfs[i].queueFlags & VK_QUEUE_VIDEO_DECODE_BIT_KHR))
      decode = static_cast<int>(i);
  }
  if (graphics < 0) {
    *error = "no graphics+compute queue family";
    return false;
  }
  graphics_family_ = static_cast<uint32_t>(graphics);
  // Two graphics queues let libplacebo overlap uploads with rendering.
  graphics_count_ = std::min<uint32_t>(2, qfs[graphics].queueCount);

  // Extensions: interop-required + every supported optional one.
  uint32_t n = 0;
  vkEnumerateDeviceExtensionProperties(physical_device_, nullptr, &n, nullptr);
  std::vector<VkExtensionProperties> available(n);
  vkEnumerateDeviceExtensionProperties(physical_device_, nullptr, &n,
                                       available.data());
  for (const char* e : interop_->DeviceExtensions()) {
    if (!HasExtension(available, e)) {
      *error = std::string("missing device extension ") + e;
      return false;
    }
    extension_storage_.emplace_back(e);
  }
  for (const char* e : kOptionalDeviceExtensions) {
    if (HasExtension(available, e)) extension_storage_.emplace_back(e);
  }
  for (const auto& e : extension_storage_) device_extensions_.push_back(e.c_str());

  // Features: enable everything the device supports except robustness
  // (costly and unneeded); libplacebo and FFmpeg pick what they need.
  features13_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
  features12_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
                 &features13_};
  features11_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
                 &features12_};
  features_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, &features11_};
  vkGetPhysicalDeviceFeatures2(physical_device_, &features_);
  features_.features.robustBufferAccess = VK_FALSE;
  features13_.robustImageAccess = VK_FALSE;
  if (!features12_.timelineSemaphore) {
    *error = "device lacks timeline semaphores";
    return false;
  }

  // mpv hands FFmpeg the decode family with its full queueCount
  // (hwdec_vulkan.c), so every queue of that family must exist.
  const std::vector<float> priorities(
      std::max<uint32_t>(2, decode >= 0 ? qfs[decode].queueCount : 1), 1.0f);
  std::vector<VkDeviceQueueCreateInfo> queues;
  queues.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0,
                    graphics_family_, graphics_count_, priorities.data()});
  if (decode >= 0 && decode != graphics) {
    queues.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0,
                      static_cast<uint32_t>(decode), qfs[decode].queueCount,
                      priorities.data()});
  }

  VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
  dci.pNext = &features_;
  dci.queueCreateInfoCount = static_cast<uint32_t>(queues.size());
  dci.pQueueCreateInfos = queues.data();
  dci.enabledExtensionCount = static_cast<uint32_t>(device_extensions_.size());
  dci.ppEnabledExtensionNames = device_extensions_.data();
  if (vkCreateDevice(physical_device_, &dci, nullptr, &device_) != VK_SUCCESS) {
    *error = "vkCreateDevice failed";
    return false;
  }
  // No volkLoadDevice(): see GetSharedInstance.

  // One timeline semaphore for the whole ring: mpv signals increasing values,
  // the render thread waits on the CPU (no extra queue submissions needed).
  VkSemaphoreTypeCreateInfo tci{VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
  tci.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
  VkSemaphoreCreateInfo sci{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, &tci};
  if (vkCreateSemaphore(device_, &sci, nullptr, &timeline_) != VK_SUCCESS) {
    *error = "failed to create timeline semaphore";
    return false;
  }
  return true;
}

bool VulkanContext::AllocateRing(int count, int width, int height,
                                 std::string* error) {
  FreeRing();
  ring_.resize(count);
  for (auto& img : ring_) {
    if (!interop_->CreateImage(physical_device_, device_, width, height, &img)) {
      *error = "failed to create shared image";
      FreeRing();
      return false;
    }
  }
  return true;
}

void VulkanContext::FreeRing() {
  if (!device_ || ring_.empty()) return;
  vkDeviceWaitIdle(device_);
  for (auto& img : ring_) {
    interop_->DestroyImage(device_, &img);
  }
  ring_.clear();
}

uint64_t VulkanContext::NextSignalValue(int i) {
  ring_[i].ready_value = ++timeline_value_;
  return ring_[i].ready_value;
}

bool VulkanContext::WaitImage(int i) {
  const SharedImage& img = ring_[i];
  if (img.ready_value == 0) return true;
  VkSemaphoreWaitInfo wi{VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO};
  wi.semaphoreCount = 1;
  wi.pSemaphores = &timeline_;
  wi.pValues = &img.ready_value;
  // 1 s timeout: a stuck GPU must not wedge the render thread forever.
  return vkWaitSemaphores(device_, &wi, 1'000'000'000ull) == VK_SUCCESS;
}

}  // namespace mpv_kit
