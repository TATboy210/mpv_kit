// Platform-independent video renderer: owns the mpv render context, a render
// thread and a small ring of shared images. Two backends:
//   * Vulkan  — mpv renders into images shared zero-copy with the platform
//               compositor via a platform Interop (D3D11 / GL / Metal).
//   * Software — MPV_RENDER_API_TYPE_SW into CPU buffers, used when Vulkan
//               (or the interop extensions) are unavailable.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "mpv_api.h"

namespace mpv_kit {

enum class Backend { kVulkan, kSoftware };

/// Shared frame description handed to the platform texture.
struct Frame {
  int index = -1;
  int width = 0;
  int height = 0;
  // Software backend only: tightly packed RGBA/BGRA pixels (stride = width*4).
  const uint8_t* pixels = nullptr;
  // Vulkan backend: SharedImage::platform of the frame (already retained).
  void* platform = nullptr;
};

class VulkanInterop;  // vulkan_backend.h

/// Implemented per platform.
class Interop {
 public:
  virtual ~Interop() = default;
  /// Zero-copy Vulkan sharing, or nullptr if this platform/GPU cannot do it.
  virtual VulkanInterop* vulkan() = 0;
  /// Software backend pixel order: true = BGRA, false = RGBA.
  virtual bool SoftwareIsBgra() const = 0;
  /// A completed frame is ready; the platform marks its texture dirty.
  /// Called from the render thread.
  virtual void FrameReady() = 0;
  /// Takes a reference on a shared image for the compositor. Called with the
  /// renderer lock held, so the image cannot be freed concurrently.
  virtual void RetainFrame(void* platform) { (void)platform; }
};

class VulkanContext;  // vulkan_backend.cc

/// Owns rendering for one mpv instance.
class VideoRenderer {
 public:
  using LogFn = std::function<void(const std::string&)>;

  VideoRenderer(const MpvApi& api, mpv_handle* handle, Interop* interop,
                LogFn log);
  ~VideoRenderer();

  VideoRenderer(const VideoRenderer&) = delete;
  VideoRenderer& operator=(const VideoRenderer&) = delete;

  /// Creates the render context and starts the render thread. Tries Vulkan
  /// first unless [force_software]. Returns false if no backend works.
  bool Start(bool force_software);

  /// Target output size in pixels; images are reallocated lazily.
  void SetSize(int width, int height);

  /// Most recent completed frame (index into the ring). Thread-safe; the
  /// returned index stays valid until the next AcquireFront() call, so the
  /// renderer never writes into the image the compositor is reading.
  Frame AcquireFront();

  Backend backend() const { return backend_; }
  const std::string& backend_reason() const { return backend_reason_; }

  /// Vulkan backend: access to the shared images for the platform layer.
  VulkanContext* vulkan() const { return vulkan_.get(); }

 private:
  static void OnMpvUpdate(void* self);
  void RenderLoop();
  bool RenderOnce();
  bool StartVulkan();
  bool StartSoftware();
  int PickBackBuffer();

  const MpvApi api_;
  mpv_handle* const handle_;
  Interop* const interop_;
  LogFn log_;

  Backend backend_ = Backend::kSoftware;
  std::string backend_reason_;
  mpv_render_context* render_ctx_ = nullptr;
  std::unique_ptr<VulkanContext> vulkan_;

  // Software ring.
  std::vector<std::vector<uint8_t>> sw_buffers_;
  // Previous generation, kept one resize longer: the compositor may still be
  // uploading from it after its copy callback returned.
  std::vector<std::vector<uint8_t>> sw_retired_;

  std::thread thread_;
  std::mutex mutex_;
  std::condition_variable cv_;
  bool update_pending_ = false;
  bool quit_ = false;

  // Ring state, guarded by mutex_.
  //
  // The compositor samples an image on the GPU some time after taking it,
  // and no platform tells us when it is done. An image it gave back is
  // therefore quarantined for kQuarantine further acquisitions (frames)
  // before it is rendered into again — bounded by the compositor's frame
  // latency. Ring = front + in use + quarantine + one free image.
  static constexpr int kQuarantine = 2;
  static constexpr int kRingSize = kQuarantine + 3;
  int width_ = 0, height_ = 0;          // requested
  int ring_w_ = 0, ring_h_ = 0;         // allocated
  int front_ = -1;                      // last completed frame
  int in_use_ = -1;                     // frame the compositor holds
  int quarantine_[kQuarantine] = {-1, -1};  // most recently given back first
  std::atomic<bool> resize_pending_{false};
};

}  // namespace mpv_kit
