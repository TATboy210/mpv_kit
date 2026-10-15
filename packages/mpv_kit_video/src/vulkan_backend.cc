#include "vulkan_backend.h"

#include <algorithm>
#include <bitset>
#include <cstring>
#include <mutex>

namespace mpv_kit {
namespace {

// Optional device extensions, copied from mpv's mppl_create_vulkan()
// (video/out/vulkan/context.c: FFmpeg Vulkan hwcontext + Vulkan Video) plus
// libplacebo's recommended interop set (vaapi dma-buf import, CUDA/nvdec
// export, host pointers). Each is enabled only when the device has it.
constexpr const char* kOptionalDeviceExtensions[] = {
    // mpv context.c opt_extensions
    VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
    VK_EXT_SHADER_ATOMIC_FLOAT_EXTENSION_NAME,
    VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_QUEUE_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_H264_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_H265_EXTENSION_NAME,
    VK_KHR_VIDEO_QUEUE_EXTENSION_NAME,
    VK_KHR_ZERO_INITIALIZE_WORKGROUP_MEMORY_EXTENSION_NAME,
    VK_EXT_SHADER_OBJECT_EXTENSION_NAME,
    VK_KHR_COOPERATIVE_MATRIX_EXTENSION_NAME,
    VK_KHR_VIDEO_MAINTENANCE_1_EXTENSION_NAME,
    VK_KHR_SHADER_EXPECT_ASSUME_EXTENSION_NAME,
    VK_KHR_SHADER_SUBGROUP_ROTATE_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_AV1_EXTENSION_NAME,
    VK_KHR_SHADER_RELAXED_EXTENDED_INSTRUCTION_EXTENSION_NAME,
    VK_KHR_VIDEO_MAINTENANCE_2_EXTENSION_NAME,
    VK_KHR_VIDEO_DECODE_VP9_EXTENSION_NAME,
    // libplacebo recommended (interop / zero-copy hwdec)
    VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,
    VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME,
    VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME,
    VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME,
    VK_KHR_EXTERNAL_SEMAPHORE_FD_EXTENSION_NAME,
    "VK_KHR_external_memory_win32",
    "VK_KHR_external_semaphore_win32",
    VK_EXT_PHYSICAL_DEVICE_DRM_EXTENSION_NAME,
    VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME,
    VK_EXT_PCI_BUS_INFO_EXTENSION_NAME,
    "VK_KHR_portability_subset",  // required on MoltenVK when exposed
};

/// Queue family with all of [want], none of [avoid] and as few other
/// capabilities as possible (libplacebo's find_qf()), or -1.
int FindQueueFamily(const std::vector<VkQueueFamilyProperties>& qfs,
                    VkQueueFlags want, VkQueueFlags avoid) {
  int best = -1;
  size_t best_extra = 64;
  for (size_t i = 0; i < qfs.size(); i++) {
    const VkQueueFlags f = qfs[i].queueFlags;
    if ((f & want) != want || (f & avoid) || qfs[i].queueCount == 0) continue;
    const size_t extra = std::bitset<32>(f & ~want).count();
    if (extra < best_extra) {
      best = static_cast<int>(i);
      best_extra = extra;
    }
  }
  return best;
}

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

  // Queue layout as libplacebo builds it for mpv (async_transfer and
  // async_compute on, queue_count 1): a graphics+compute family, dedicated
  // compute and transfer families where they exist, and the video decode
  // family for FFmpeg.
  const int graphics = FindQueueFamily(
      qfs, VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT, 0);
  if (graphics < 0) {
    *error = "no graphics+compute queue family";
    return false;
  }
  const int compute =
      FindQueueFamily(qfs, VK_QUEUE_COMPUTE_BIT, VK_QUEUE_GRAPHICS_BIT);
  const int transfer = FindQueueFamily(
      qfs, VK_QUEUE_TRANSFER_BIT,
      VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT |
          VK_QUEUE_VIDEO_DECODE_BIT_KHR | VK_QUEUE_VIDEO_ENCODE_BIT_KHR);
  const int decode = FindQueueFamily(qfs, VK_QUEUE_VIDEO_DECODE_BIT_KHR, 0);
  graphics_ = {static_cast<uint32_t>(graphics), 1};
  compute_ = compute >= 0 ? QueueFamily{static_cast<uint32_t>(compute), 1}
                          : graphics_;
  transfer_ = transfer >= 0 ? QueueFamily{static_cast<uint32_t>(transfer), 1}
                            : graphics_;

  // Extensions: interop-required + every supported optional one.
  uint32_t n = 0;
  vkEnumerateDeviceExtensionProperties(physical_device_, nullptr, &n, nullptr);
  std::vector<VkExtensionProperties> available(n);
  vkEnumerateDeviceExtensionProperties(physical_device_, nullptr, &n,
                                       available.data());
  auto enabled = [&](const char* name) {
    return std::find(extension_storage_.begin(), extension_storage_.end(),
                     name) != extension_storage_.end();
  };
  for (const char* e : interop_->DeviceExtensions()) {
    if (!HasExtension(available, e)) {
      *error = std::string("missing device extension ") + e;
      return false;
    }
    if (!enabled(e)) extension_storage_.emplace_back(e);
  }
  for (const char* e : kOptionalDeviceExtensions) {
    if (HasExtension(available, e) && !enabled(e))
      extension_storage_.emplace_back(e);
  }
  for (const auto& e : extension_storage_) device_extensions_.push_back(e.c_str());

  // Features: mpv requests the feature structs of its optional extensions
  // too (context.c), because FFmpeg reads them from the chain handed over
  // in hwdec_vulkan.c. Query what the device supports and enable all of it
  // except robustness (costly and unneeded).
  features13_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
  features12_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
                 &features13_};
  features11_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
                 &features12_};
  features_ = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, &features11_};
  void** tail = &features13_.pNext;
  auto chain = [&](const char* ext, auto& s, VkStructureType type) {
    if (!enabled(ext)) return;
    s = {};
    s.sType = type;
    *tail = &s;
    tail = &s.pNext;
  };
  chain(VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME, ext_.descriptor_buffer,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT);
  chain(VK_EXT_SHADER_ATOMIC_FLOAT_EXTENSION_NAME, ext_.atomic_float,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_ATOMIC_FLOAT_FEATURES_EXT);
  chain(VK_EXT_SHADER_OBJECT_EXTENSION_NAME, ext_.shader_object,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT);
  chain(VK_KHR_COOPERATIVE_MATRIX_EXTENSION_NAME, ext_.cooperative_matrix,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_COOPERATIVE_MATRIX_FEATURES_KHR);
  chain(VK_KHR_VIDEO_MAINTENANCE_1_EXTENSION_NAME, ext_.video_maintenance1,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VIDEO_MAINTENANCE_1_FEATURES_KHR);
  chain(VK_KHR_SHADER_EXPECT_ASSUME_EXTENSION_NAME, ext_.expect_assume,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_EXPECT_ASSUME_FEATURES_KHR);
  chain(VK_KHR_SHADER_SUBGROUP_ROTATE_EXTENSION_NAME, ext_.subgroup_rotate,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_SUBGROUP_ROTATE_FEATURES_KHR);
  chain(VK_KHR_SHADER_RELAXED_EXTENDED_INSTRUCTION_EXTENSION_NAME,
        ext_.relaxed_extended_instruction,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_RELAXED_EXTENDED_INSTRUCTION_FEATURES_KHR);
  chain(VK_KHR_VIDEO_MAINTENANCE_2_EXTENSION_NAME, ext_.video_maintenance2,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VIDEO_MAINTENANCE_2_FEATURES_KHR);
  chain(VK_KHR_VIDEO_DECODE_VP9_EXTENSION_NAME, ext_.video_decode_vp9,
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VIDEO_DECODE_VP9_FEATURES_KHR);
  vkGetPhysicalDeviceFeatures2(physical_device_, &features_);
  features_.features.robustBufferAccess = VK_FALSE;
  features13_.robustImageAccess = VK_FALSE;
  if (!features12_.timelineSemaphore) {
    *error = "device lacks timeline semaphores";
    return false;
  }

  // One VkDeviceQueueCreateInfo per family. mpv hands FFmpeg the decode
  // family with its full queueCount (hwdec_vulkan.c), so every queue of
  // that family must exist.
  std::vector<uint32_t> counts(nqf, 0);
  auto want = [&](int family, uint32_t count) {
    if (family >= 0) counts[family] = std::max(counts[family], count);
  };
  want(graphics, graphics_.count);
  want(compute, compute_.count);
  want(transfer, transfer_.count);
  if (decode >= 0) want(decode, qfs[decode].queueCount);
  const std::vector<float> priorities(
      *std::max_element(counts.begin(), counts.end()), 1.0f);
  std::vector<VkDeviceQueueCreateInfo> queues;
  for (uint32_t i = 0; i < nqf; i++) {
    if (counts[i])
      queues.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0,
                        i, counts[i], priorities.data()});
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
  FreeRetired();
  retired_ = std::move(ring_);
  ring_.clear();
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

namespace {
void DestroyAll(VkDevice device, VulkanInterop* interop,
                std::vector<SharedImage>* images) {
  if (!device || images->empty()) return;
  vkDeviceWaitIdle(device);
  for (auto& img : *images) {
    if (img.image || img.platform) interop->DestroyImage(device, &img);
  }
  images->clear();
}
}  // namespace

void VulkanContext::FreeRing() {
  DestroyAll(device_, interop_, &ring_);
  FreeRetired();
}

void VulkanContext::FreeRetired() { DestroyAll(device_, interop_, &retired_); }

uint64_t VulkanContext::NextSignalValue(int i) {
  ring_[i].ready_value = ++timeline_value_;
  return ring_[i].ready_value;
}

VkResult VulkanContext::WaitImage(int i) {
  const SharedImage& img = ring_[i];
  if (img.ready_value == 0) return VK_SUCCESS;
  VkSemaphoreWaitInfo wi{VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO};
  wi.semaphoreCount = 1;
  wi.pSemaphores = &timeline_;
  wi.pValues = &img.ready_value;
  // 1 s timeout: a stuck GPU must not wedge the render thread forever.
  return vkWaitSemaphores(device_, &wi, 1'000'000'000ull);
}

}  // namespace mpv_kit
