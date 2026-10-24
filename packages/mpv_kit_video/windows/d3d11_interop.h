// Windows zero-copy interop: images are D3D11 textures created with a legacy
// (KMT) shared handle, imported into Vulkan, and handed to Flutter's ANGLE
// compositor through FlutterDesktopGpuSurfaceDescriptor — no copies.
#pragma once

#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <functional>

#include "../src/video_renderer.h"
#include "../src/vulkan_backend.h"

namespace mpv_kit {

class D3D11Interop : public Interop, public VulkanInterop {
 public:
  /// [adapter] is Flutter's rendering adapter (may be null: software only).
  D3D11Interop(IDXGIAdapter* adapter, std::function<void()> frame_ready);
  ~D3D11Interop() override = default;

  // Interop
  VulkanInterop* vulkan() override { return device_ ? this : nullptr; }
  const char* interopReason() const override {
    return d3d_reason_.empty() ? nullptr : d3d_reason_.c_str();
  }
  bool SoftwareIsBgra() const override { return false; }  // Flutter wants RGBA
  void FrameReady() override { frame_ready_(); }
  // Flutter (ExternalTextureD3d::CreateOrUpdateTexture, verified by
  // decompiling flutter_windows.dll) binds the shared texture through ANGLE
  // and calls our release callback immediately, with no GPU fence or keyed
  // mutex: the only bound on when ANGLE stops sampling an image is the
  // swap chain queue (DXGI default: 3 frames) plus the frame being built.
  int CompositorLatency() const override { return 4; }
  /// AddRef for Flutter; released by the descriptor's release_callback.
  void RetainFrame(void* platform) override {
    static_cast<Texture*>(platform)->texture->AddRef();
  }

  // VulkanInterop
  std::vector<const char*> InstanceExtensions() const override { return {}; }
  std::vector<const char*> DeviceExtensions() const override;
  bool AcceptDevice(VkPhysicalDevice device) override;
  bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width, int height,
                   SharedImage* out) override;
  void DestroyImage(VkDevice dev, SharedImage* img) override;

  /// Platform data stored in SharedImage::platform.
  struct Texture {
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    HANDLE shared_handle = nullptr;  // KMT handle: not closed, owned by D3D
  };

 private:
  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  // Why zero-copy sharing is unavailable (probe failure with the HRESULT),
  // empty when the device came up (OBS-03).
  std::string d3d_reason_;
  LUID luid_{};
  std::function<void()> frame_ready_;
};

}  // namespace mpv_kit
