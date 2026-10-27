#include "d3d11_interop.h"

#include "d3d11_backend.h"

#include <cstring>
#include <cstdio>
#include <string>

namespace mpv_kit {

using Microsoft::WRL::ComPtr;

namespace {
constexpr VkExternalMemoryHandleTypeFlagBits kHandleType =
    VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_KMT_BIT;
// Flutter's DXGI shared-handle path expects BGRA8.
constexpr VkFormat kVkFormat = VK_FORMAT_B8G8R8A8_UNORM;
constexpr DXGI_FORMAT kDxgiFormat = DXGI_FORMAT_B8G8R8A8_UNORM;

// Graphics APIs of one renderer tier, in preference order (ADR 0004,
// Decision 5: within a tier the API preference is unchanged until the switch
// to D3D11-first). Vulkan stays first, so a machine with a usable Vulkan
// behaves as before and one without it uses D3D11 instead of software. The
// switch commit (14-11) only reorders this array.
constexpr const char* kWindowsApiOrder[] = {"vulkan", "d3d11"};
}  // namespace

D3D11Interop::D3D11Interop(IDXGIAdapter* adapter,
                           std::function<void()> frame_ready)
    : adapter_(adapter), frame_ready_(std::move(frame_ready)) {
  if (!adapter) {
    d3d_reason_ = "no DXGI adapter";
    return;
  }
  DXGI_ADAPTER_DESC desc{};
  if (FAILED(adapter->GetDesc(&desc))) {
    d3d_reason_ = "failed to read the DXGI adapter desc";
    return;
  }
  luid_ = desc.AdapterLuid;
  // Our own device on Flutter's adapter, only used to create shareable
  // textures; Flutter opens them on its device via the shared handle.
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0};
  const HRESULT hr =
      D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                        D3D11_CREATE_DEVICE_BGRA_SUPPORT, levels,
                        static_cast<UINT>(std::size(levels)),
                        D3D11_SDK_VERSION, &device_, nullptr, nullptr);
  if (FAILED(hr)) {
    // Record the actual failure instead of letting the renderer report a
    // missing platform interop (OBS-03).
    char code[16];
    snprintf(code, sizeof(code), "0x%08lX", static_cast<unsigned long>(hr));
    d3d_reason_ = std::string("d3d11 device creation failed: ") + code;
  }
}

std::vector<BackendCandidate> D3D11Interop::BackendCandidates(
    RendererChoice choice) const {
  // Renderer quality first (gpu-next, then gpu), then the API order within
  // each tier, then software; an explicit gpu-next / gpu request has no
  // other tier, an explicit software request no GPU entry.
  std::vector<BackendCandidate> chain;
  const auto tier = [&chain](const char* renderer) {
    for (const char* api : kWindowsApiOrder) chain.push_back({api, renderer});
  };
  if (choice != RendererChoice::kSoftware) {
    if (choice != RendererChoice::kGpu) tier("gpu-next");
    if (choice != RendererChoice::kGpuNext) tier("gpu");
  }
  chain.push_back({"software", "sw"});
  return chain;
}

std::unique_ptr<RenderBackend> D3D11Interop::CreateBackend(const char* api) {
  if (std::strcmp(api, "d3d11") != 0) return nullptr;
  return CreateD3D11Backend(adapter_.Get());
}

std::vector<const char*> D3D11Interop::DeviceExtensions() const {
  return {VK_KHR_EXTERNAL_MEMORY_WIN32_EXTENSION_NAME};
}

bool D3D11Interop::AcceptDevice(VkPhysicalDevice device) {
  // Must be the very adapter Flutter renders on, otherwise the shared handle
  // would cross adapters (unsupported for KMT handles).
  VkPhysicalDeviceIDProperties id{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
  VkPhysicalDeviceProperties2 props{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &id};
  vkGetPhysicalDeviceProperties2(device, &props);
  if (!id.deviceLUIDValid ||
      std::memcmp(id.deviceLUID, &luid_, sizeof(luid_)) != 0)
    return false;

  // And it must be able to import D3D11 KMT textures in our format/usage.
  VkPhysicalDeviceExternalImageFormatInfo ext{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO};
  ext.handleType = kHandleType;
  VkPhysicalDeviceImageFormatInfo2 info{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2, &ext};
  info.format = kVkFormat;
  info.type = VK_IMAGE_TYPE_2D;
  info.tiling = VK_IMAGE_TILING_OPTIMAL;
  info.usage = kSharedImageUsage;
  VkExternalImageFormatProperties ext_props{
      VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES};
  VkImageFormatProperties2 out{VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2,
                               &ext_props};
  if (vkGetPhysicalDeviceImageFormatProperties2(device, &info, &out) !=
      VK_SUCCESS)
    return false;
  return ext_props.externalMemoryProperties.externalMemoryFeatures &
         VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT;
}

bool D3D11Interop::CreateImage(VkPhysicalDevice pd, VkDevice dev, int width,
                               int height, SharedImage* out) {
  // Defensive: `vulkan()` gates on device_, but never dereference null.
  if (!device_) return false;
  auto* tex = new Texture();
  D3D11_TEXTURE2D_DESC td{};
  td.Width = static_cast<UINT>(width);
  td.Height = static_cast<UINT>(height);
  td.MipLevels = 1;
  td.ArraySize = 1;
  td.Format = kDxgiFormat;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  td.MiscFlags = D3D11_RESOURCE_MISC_SHARED;  // legacy handle for ANGLE
  ComPtr<IDXGIResource> resource;
  if (FAILED(device_->CreateTexture2D(&td, nullptr, &tex->texture)) ||
      FAILED(tex->texture.As(&resource)) ||
      FAILED(resource->GetSharedHandle(&tex->shared_handle))) {
    delete tex;
    return false;
  }

  VkExternalMemoryImageCreateInfo ext{
      VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO};
  ext.handleTypes = kHandleType;
  VkImageCreateInfo ici{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, &ext};
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
    delete tex;
    return false;
  }

  VkMemoryWin32HandlePropertiesKHR hp{
      VK_STRUCTURE_TYPE_MEMORY_WIN32_HANDLE_PROPERTIES_KHR};
  vkGetMemoryWin32HandlePropertiesKHR(dev, kHandleType, tex->shared_handle, &hp);
  VkMemoryRequirements req;
  vkGetImageMemoryRequirements(dev, out->image, &req);
  const uint32_t bits = req.memoryTypeBits & (hp.memoryTypeBits ? hp.memoryTypeBits : ~0u);
  uint32_t type = 0;
  while (type < 32 && !(bits & (1u << type))) type++;

  // D3D11 textures must be imported as dedicated allocations.
  VkMemoryDedicatedAllocateInfo dedicated{
      VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
  dedicated.image = out->image;
  VkImportMemoryWin32HandleInfoKHR import{
      VK_STRUCTURE_TYPE_IMPORT_MEMORY_WIN32_HANDLE_INFO_KHR, &dedicated};
  import.handleType = kHandleType;
  import.handle = tex->shared_handle;
  VkMemoryAllocateInfo mai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, &import};
  mai.allocationSize = req.size;
  mai.memoryTypeIndex = type;
  if (type >= 32 ||
      vkAllocateMemory(dev, &mai, nullptr, &out->memory) != VK_SUCCESS ||
      vkBindImageMemory(dev, out->image, out->memory, 0) != VK_SUCCESS) {
    if (out->memory) vkFreeMemory(dev, out->memory, nullptr);
    vkDestroyImage(dev, out->image, nullptr);
    out->image = VK_NULL_HANDLE;
    out->memory = VK_NULL_HANDLE;
    delete tex;
    return false;
  }
  (void)pd;
  out->format = kVkFormat;
  out->width = width;
  out->height = height;
  out->platform = tex;
  return true;
}

void D3D11Interop::DestroyImage(VkDevice dev, SharedImage* img) {
  if (img->image) vkDestroyImage(dev, img->image, nullptr);
  if (img->memory) vkFreeMemory(dev, img->memory, nullptr);
  // Flutter may still hold a reference taken in the descriptor callback;
  // the COM refcount keeps the resource alive until it releases it.
  delete static_cast<Texture*>(img->platform);
  *img = SharedImage{};
}

}  // namespace mpv_kit
