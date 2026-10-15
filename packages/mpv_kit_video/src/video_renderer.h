// Platform-independent video renderer: owns the mpv render context, a render
// thread and a small ring of shared images. Two backends:
//   * Vulkan  — mpv renders into images shared zero-copy with the platform
//               compositor via a platform Interop (D3D11 / GL / Metal).
//   * Software — MPV_RENDER_API_TYPE_SW into CPU buffers, used when Vulkan
//               (or the interop extensions) are unavailable.
#pragma once

#include <atomic>
#include <chrono>
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

/// Renderer requested by the API user. Every choice except kSoftware falls
/// back to the software backend when Vulkan cannot be used.
enum class RendererChoice {
  kAuto,     // gpu-next, then gpu
  kGpuNext,  // libplacebo's renderer only
  kGpu,      // mpv's older gl_video renderer only
  kSoftware, // MPV_RENDER_API_TYPE_SW
};

/// Parses the method channel spelling ("auto", "gpu-next", "gpu",
/// "software"); unknown values mean kAuto.
RendererChoice ParseRendererChoice(const std::string& name);

/// Diagnostic events, delivered to Dart as MpvVideoEvent. Called on the
/// render thread; platforms marshal them to the platform thread.
///   resize       ring reallocated, message "WxH"
///   idle/active  compositor stopped/resumed taking frames
///   render_error a frame failed; retried with backoff (message: reason)
///   recovered    rendering works again after render_error
///   gpu_timeout  the GPU did not finish a frame within 1 s
///   device_lost  Vulkan device lost: rendering stopped for good; recreate
///                the controller (e.g. with the software renderer)
using EventFn = std::function<void(const char* kind, const std::string& msg)>;

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
                LogFn log, EventFn event = nullptr);
  ~VideoRenderer();

  VideoRenderer(const VideoRenderer&) = delete;
  VideoRenderer& operator=(const VideoRenderer&) = delete;

  /// Creates the render context and starts the render thread. Tries the
  /// requested Vulkan renderer(s), then software. False if nothing works.
  bool Start(RendererChoice choice);

  /// ICC profile for color management (gpu-next / gpu), applied on the
  /// render thread before the next frame. Empty clears it.
  void SetIccProfile(std::vector<uint8_t> profile);

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
  enum class RenderResult { kOk, kFailed, kDeviceLost };
  RenderResult RenderOnce(std::string* error);
  void OnRenderResult(RenderResult result, const std::string& error);
  void ApplyIccProfile();
  void Emit(const char* kind, const std::string& msg = {});
  void SkipFrame();
  bool StartVulkan(RendererChoice choice);
  bool StartSoftware();
  int PickBackBuffer();

  const MpvApi api_;
  mpv_handle* const handle_;
  Interop* const interop_;
  LogFn log_;
  EventFn event_;

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
  // A rendered frame awaits mpv_render_context_report_swap(): reported when
  // the compositor first takes it, or after kPresentTimeout without one.
  bool swap_pending_ = false;
  static constexpr std::chrono::milliseconds kPresentTimeout{50};
  // Last time the compositor took a frame. Swaps are only deferred to the
  // compositor while it is actively consuming (not before the texture is
  // first shown, not while the window is hidden).
  std::chrono::steady_clock::time_point last_acquire_{};
  // No frame taken for kIdleTimeout (window hidden/minimised, texture off
  // screen): frames are advanced with SKIP_RENDERING instead of drawn.
  // The next acquisition triggers one redraw (redraw_pending_), so the
  // picture is current again even while paused.
  static constexpr std::chrono::milliseconds kIdleTimeout{500};
  bool idle_ = false;
  bool reported_idle_ = false;  // last state sent as an idle/active event
  bool redraw_pending_ = false;
  bool quit_ = false;

  // Failure handling (render thread only). After a failed frame, frames are
  // advanced with SKIP_RENDERING until retry_at_; the delay doubles per
  // consecutive failure up to kMaxBackoff (mpv itself keeps a broken VO
  // alive the same way rather than tearing the player down). A resize
  // retries at once: a new size is the usual cure for allocation failures.
  static constexpr std::chrono::milliseconds kMinBackoff{100};
  static constexpr std::chrono::milliseconds kMaxBackoff{5000};
  int failures_ = 0;
  std::chrono::steady_clock::time_point retry_at_{};
  bool device_lost_ = false;

  // Pending ICC profile (guarded by mutex_).
  bool icc_pending_ = false;
  std::vector<uint8_t> icc_profile_;

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
