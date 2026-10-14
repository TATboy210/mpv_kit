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

}  // namespace

MetalInterop::MetalInterop(std::function<void()> frame_ready)
    : frame_ready_(std::move(frame_ready)) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    metal_ok_ = device != nil;
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
  VkPhysicalDeviceIDProperties id{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
  VkPhysicalDeviceProperties2 props{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &id};
  vkGetPhysicalDeviceProperties2(device, &props);
  if (!id.deviceLUIDValid) return true;  // cannot tell; accept
  uint64_t luid = 0;
  std::memcpy(&luid, id.deviceLUID, sizeof(luid));
  return NSSwapBigLongLongToHost(luid) == registry_id_;
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
