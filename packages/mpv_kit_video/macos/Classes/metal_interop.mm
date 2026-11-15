#include "metal_interop.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dlfcn.h>

#include <cstring>

namespace mpv_kit {
namespace {

// Matches kCVPixelFormatType_32BGRA, the format Flutter's Metal external
// texture path expects.
constexpr VkFormat kVkFormat = VK_FORMAT_B8G8R8A8_UNORM;

PFN_vkGetInstanceProcAddr LoadFrom(NSString* path) {
  void* lib = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  if (!lib) return nullptr;
  // Intentionally never closed: Vulkan objects outlive any single renderer.
  return reinterpret_cast<PFN_vkGetInstanceProcAddr>(
      dlsym(lib, "vkGetInstanceProcAddr"));
}

// Carrier reported when the loaded Vulkan driver cannot be named.
constexpr char kUnknownCarrier[] = "unknown Vulkan driver";

/// The built-in Vulkan backend with one change: device_name() also names
/// the Vulkan driver that carries the rendering onto Metal. On macOS every
/// Vulkan device is a translation layer (MoltenVK in the bundle), and the
/// reason would otherwise read as native Vulkan. Every other virtual
/// forwards untouched, including the three with a default body: dropping
/// one would silently change the failure paths (video_renderer.cc Start).
/// Going through Interop::CreateBackend leaves the shared engine unchanged.
class MetalVulkanBackend final : public RenderBackend {
 public:
  MetalVulkanBackend(std::unique_ptr<RenderBackend> inner,
                     const MetalInterop* interop)
      : inner_(std::move(inner)), interop_(interop) {}

  const char* wire_name() const override { return inner_->wire_name(); }
  Backend frame_kind() const override { return inner_->frame_kind(); }
  bool pipelined() const override { return inner_->pipelined(); }
  bool BindThread() override { return inner_->BindThread(); }
  void UnbindThread() override { inner_->UnbindThread(); }
  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    return inner_->Create(api, handle, renderer, out, why);
  }
  bool device_failed() const override { return inner_->device_failed(); }
  std::string device_name() const override {
    const std::string name = inner_->device_name();
    // Before the device exists there is nothing to attribute.
    if (name.empty()) return name;
    return name + " via " + interop_->CarrierFor(name);
  }
  std::string RendererName(const MpvApi& api,
                           mpv_render_context* ctx) const override {
    return inner_->RendererName(api, ctx);
  }
  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    return inner_->AllocTargets(count, width, height, keep_slot, error);
  }
  void FreeRetired() override { inner_->FreeRetired(); }
  TargetView FrameFor(int slot) override { return inner_->FrameFor(slot); }
  int Render(const MpvApi& api, mpv_render_context* ctx, int slot, int width,
             int height) override {
    return inner_->Render(api, ctx, slot, width, height);
  }
  WaitResult Wait(int slot) override { return inner_->Wait(slot); }
  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    inner_->Release(api, ctx);
  }

 private:
  // Destroyed with this object: the inner backend frees its targets and
  // device exactly as it would unwrapped.
  std::unique_ptr<RenderBackend> inner_;
  const MetalInterop* interop_;  // outlives the backend (owned by the plugin)
};

}  // namespace

MetalInterop::MetalInterop(std::function<void()> frame_ready)
    : frame_ready_(std::move(frame_ready)) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    metal_ok_ = device != nil;
    if (!metal_ok_) {
      // Honest fallback reason (OBS-03) instead of a generic platform string.
      metal_reason_ = "no Metal device";
    }
    if (device) registry_id_ = device.registryID;
  }
}

PFN_vkGetInstanceProcAddr MetalInterop::Loader() {
  // Prefer the Vulkan implementation bundled with the app (mpv_kit_libs
  // ships MoltenVK in Contents/Frameworks); otherwise volk searches the
  // usual library names (e.g. a Homebrew vulkan-loader during development).
  NSString* frameworks = NSBundle.mainBundle.privateFrameworksPath;
  // mpv_kit_libs' native assets become MoltenVK.framework; plain dylibs
  // are what a manually embedded MoltenVK looks like.
  for (NSString* name in @[ @"MoltenVK.framework/MoltenVK",
                            @"libMoltenVK.dylib", @"libvulkan.1.dylib" ]) {
    if (!frameworks) break;
    if (PFN_vkGetInstanceProcAddr gipa =
            LoadFrom([frameworks stringByAppendingPathComponent:name]))
      return gipa;
  }
  return nullptr;
}

bool MetalInterop::AcceptDevice(VkPhysicalDevice device) {
  // Same GPU as the compositor: on dual-GPU Macs an image rendered on the
  // other GPU would be migrated by the system on every frame.
  // VkPhysicalDeviceDriverProperties (Vulkan 1.2 core, always available on
  // the 1.3 devices PickDevice accepts) rides the same query: it names the
  // driver for the reason's "via <carrier>".
  VkPhysicalDeviceDriverProperties driver{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES};
  VkPhysicalDeviceIDProperties id{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES, &driver};
  VkPhysicalDeviceProperties2 props{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &id};
  vkGetPhysicalDeviceProperties2(device, &props);
  bool accepted = true;  // cannot tell without a valid LUID; accept
  if (id.deviceLUIDValid) {
    uint64_t luid = 0;
    std::memcpy(&luid, id.deviceLUID, sizeof(luid));
    accepted = NSSwapBigLongLongToHost(luid) == registry_id_;
  }
  if (accepted) {
    // Report only what the driver says: the fixed id for MoltenVK, else its
    // own (bounded) name. driverName is not guaranteed to be terminated.
    std::string carrier = kUnknownCarrier;
    if (driver.driverID == VK_DRIVER_ID_MOLTENVK) {
      carrier = "MoltenVK";
    } else if (const size_t n =
                   strnlen(driver.driverName, VK_MAX_DRIVER_NAME_SIZE)) {
      carrier.assign(driver.driverName, n);
    }
    carriers_.emplace_back(props.properties.deviceName, std::move(carrier));
  }
  return accepted;
}

std::unique_ptr<RenderBackend> MetalInterop::CreateBackend(const char* api) {
  // Without a Metal device MoltenVK aborts the process, so the built-in
  // branch (and its "no Metal device" trail) must stay in charge.
  if (std::strcmp(api, "vulkan") != 0 || !metal_ok_) return nullptr;
  return std::make_unique<MetalVulkanBackend>(CreateVulkanBackend(this), this);
}

std::string MetalInterop::CarrierFor(const std::string& device_name) const {
  // Several devices can share a name; only a single distinct driver among
  // them identifies the carrier of the winner without guessing.
  const std::string* found = nullptr;
  for (const auto& [name, carrier] : carriers_) {
    if (name != device_name) continue;
    if (found && *found != carrier) return kUnknownCarrier;
    found = &carrier;
  }
  return found ? *found : std::string(kUnknownCarrier);
}

std::vector<const char*> MetalInterop::DeviceExtensions() const {
  return {VK_EXT_METAL_OBJECTS_EXTENSION_NAME};
}

CVPixelBufferRef MetalInterop::CreatePixelBuffer(int width, int height) {
  NSDictionary* attrs = @{
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
    (id)kCVPixelBufferMetalCompatibilityKey : @YES,
  };
  CVPixelBufferRef pb = nullptr;
  if (CVPixelBufferCreate(kCFAllocatorDefault, static_cast<size_t>(width),
                          static_cast<size_t>(height),
                          kCVPixelFormatType_32BGRA,
                          (__bridge CFDictionaryRef)attrs,
                          &pb) != kCVReturnSuccess)
    return nullptr;
  return pb;
}

bool MetalInterop::CreateImage(VkPhysicalDevice pd, VkDevice dev, int width,
                               int height, SharedImage* out) {
  CVPixelBufferRef pb = CreatePixelBuffer(width, height);
  IOSurfaceRef surface = pb ? CVPixelBufferGetIOSurface(pb) : nullptr;
  if (!surface) {
    if (pb) CVPixelBufferRelease(pb);
    return false;
  }

  // MoltenVK backs the image's MTLTexture with this IOSurface.
  VkImportMetalIOSurfaceInfoEXT import{
      VK_STRUCTURE_TYPE_IMPORT_METAL_IO_SURFACE_INFO_EXT};
  import.ioSurface = surface;
  VkImageCreateInfo ici{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, &import};
  ici.imageType = VK_IMAGE_TYPE_2D;
  ici.format = kVkFormat;
  ici.extent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1};
  ici.mipLevels = 1;
  ici.arrayLayers = 1;
  ici.samples = VK_SAMPLE_COUNT_1_BIT;
  ici.tiling = VK_IMAGE_TILING_OPTIMAL;
  ici.usage = kSharedImageUsage;
  ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  if (vkCreateImage(dev, &ici, nullptr, &out->image) != VK_SUCCESS) {
    CVPixelBufferRelease(pb);
    return false;
  }

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
  VkMemoryDedicatedAllocateInfo dedicated{
      VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
  dedicated.image = out->image;
  VkMemoryAllocateInfo mai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, &dedicated};
  mai.allocationSize = req.size;
  mai.memoryTypeIndex = type;
  if (type == UINT32_MAX ||
      vkAllocateMemory(dev, &mai, nullptr, &out->memory) != VK_SUCCESS ||
      vkBindImageMemory(dev, out->image, out->memory, 0) != VK_SUCCESS) {
    if (out->memory) vkFreeMemory(dev, out->memory, nullptr);
    vkDestroyImage(dev, out->image, nullptr);
    out->image = VK_NULL_HANDLE;
    out->memory = VK_NULL_HANDLE;
    CVPixelBufferRelease(pb);
    return false;
  }
  out->format = kVkFormat;
  out->width = width;
  out->height = height;
  out->platform = pb;
  return true;
}

void MetalInterop::DestroyImage(VkDevice dev, SharedImage* img) {
  if (img->image) vkDestroyImage(dev, img->image, nullptr);
  if (img->memory) vkFreeMemory(dev, img->memory, nullptr);
  // Flutter may still hold references from copyPixelBuffer; the IOSurface
  // lives until the last one is released.
  if (img->platform) CVPixelBufferRelease(static_cast<CVPixelBufferRef>(img->platform));
  *img = SharedImage{};
}

}  // namespace mpv_kit
