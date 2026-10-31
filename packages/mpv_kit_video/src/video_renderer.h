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
#include "render_backend.h"

namespace mpv_kit {

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
///   device_lost  GPU device lost (Vulkan or D3D11): rendering stopped for
///                good; recreate the controller (e.g. with the software
///                renderer)
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
  /// Why [vulkan()] returns nullptr on this platform/GPU (e.g. a failed
  /// D3D11/Metal device creation), or null when it can share or has nothing
  /// to add. Surfaced in the software fallback reason so a device failure is
  /// not reported as a missing platform interop (OBS-03).
  virtual const char* interopReason() const { return nullptr; }
  /// Software backend pixel order: true = BGRA, false = RGBA.
  virtual bool SoftwareIsBgra() const = 0;
  /// A completed frame is ready; the platform marks its texture dirty.
  /// Called from the render thread, and from AcquireFront's caller (the
  /// compositor thread, without the renderer lock) when a further finished
  /// frame still waits. Implementations only mark the texture and must
  /// accept either thread.
  virtual void FrameReady() = 0;
  /// Takes a reference on a shared image for the compositor. Called with the
  /// renderer lock held, so the image cannot be freed concurrently.
  virtual void RetainFrame(void* platform) { (void)platform; }
  /// How many further frames the compositor may still sample an image it
  /// gave back (its GPU queue depth); see VideoRenderer's quarantine.
  /// Clamped to [1, VideoRenderer::kMaxQuarantine].
  virtual int CompositorLatency() const { return 2; }
  /// Candidates VideoRenderer::Start tries for [choice], in order. A
  /// platform adds or removes one entry to add or roll back a backend;
  /// no platform overrides this in Phase 12.
  virtual std::vector<BackendCandidate> BackendCandidates(
      RendererChoice choice) const {
    return DefaultCandidates(choice);
  }
  /// The platform's own backend for [api] (a native API of Phase 14/15),
  /// or nullptr for the built-in "vulkan" and "software" backends.
  virtual std::unique_ptr<RenderBackend> CreateBackend(const char* api) {
    (void)api;
    return nullptr;
  }
};

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
  /// candidates of Interop::BackendCandidates(choice) in order (requested
  /// Vulkan renderer(s), then software). False if nothing works.
  /// MPV_KIT_VIDEO_API, read once per call, restricts the candidates to one
  /// api and the requested renderer(s), with no fallback; the others become
  /// `excluded by MPV_KIT_VIDEO_API=<value>` trails (ADR 0004, Decision 4).
  bool Start(RendererChoice choice);

  /// ICC profile for color management (gpu-next / gpu), applied on the
  /// render thread before the next frame. Empty clears it.
  void SetIccProfile(std::vector<uint8_t> profile);

  /// Target output size in pixels; images are reallocated lazily.
  void SetSize(int width, int height);

  /// The oldest finished frame the compositor has not taken yet (at most two
  /// wait), or the frame it took last when nothing new was published (index
  /// into the ring). Thread-safe; the returned index stays valid until the
  /// next AcquireFront() call, so the renderer never writes into the image
  /// the compositor is reading. Makes no libmpv call. When it takes the
  /// older of two waiting frames it calls Interop::FrameReady() once, after
  /// releasing its lock, so that the compositor takes the next waiting frame
  /// at its next frame.
  Frame AcquireFront();

  /// What the frames carry; kSoftware when no backend was created.
  Backend backend() const {
    return render_backend_ ? render_backend_->frame_kind() : Backend::kSoftware;
  }
  const std::string& backend_reason() const { return backend_reason_; }
  /// Private wire name of the winning backend for the create response
  /// ("vulkan", "software"; Phase 14/15 add "d3d11", "opengl"), see
  /// docs/adr/0004-render-backend-reporting.md, Decision 2. Only valid
  /// after Start() returned true: before that there is no backend.
  const char* wire_name() const { return render_backend_->wire_name(); }

 private:
  static void OnMpvUpdate(void* self);
  void RenderLoop();
  enum class RenderResult { kOk, kFailed, kDeviceLost };
  RenderResult RenderOnce(std::string* error);
  void OnRenderResult(RenderResult result, const std::string& error);
  void ApplyIccProfile();
  void Emit(const char* kind, const std::string& msg = {});
  void SkipFrame();
  // Reports [n] swaps to mpv (render thread only).
  void ReportSwaps(int n);
  // Debug builds: every mpv_render_* call after Start runs on the render
  // thread (render.h, "Threading"; an OpenGL context is only current there).
  void AssertRenderThread() const;
  // The backend for one candidate api, or nullptr with *why (the reason
  // trail's text) when this platform cannot provide it.
  std::unique_ptr<RenderBackend> NewBackend(const char* api, std::string* why);
  int PickBackBuffer();
  void FreeRetiredIfDone();

  const MpvApi api_;
  mpv_handle* const handle_;
  Interop* const interop_;
  LogFn log_;
  EventFn event_;

  std::string backend_reason_;
  mpv_render_context* render_ctx_ = nullptr;
  // Device, render context targets and API-specific rendering
  // (render_backend.h); null until Start() succeeded.
  std::unique_ptr<RenderBackend> render_backend_;

  std::thread thread_;
  // Set by the render thread when it starts (AssertRenderThread).
  std::atomic<std::thread::id> render_thread_id_{};
  std::mutex mutex_;
  std::condition_variable cv_;
  bool update_pending_ = false;
  // Last time the compositor took a frame (idle detection).
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

  // Sync-wait probe: rolling stats of the two per-frame CPU waits on the
  // GPU timeline (RenderOnce). Aggregated over kProbeWindow frames and
  // emitted via log_ — the numbers decide whether the second (post-render)
  // wait is worth replacing with a keyed-mutex handoff. The line also ends
  // with the average and worst time of the backend's Render call per frame
  // (log only, see probe_render_ms_).
  static constexpr int kProbeWindow = 120;
  int probe_frames_ = 0;
  double probe_wait_prev_ms_ = 0;  // wait before writing the ring image
  double probe_wait_done_ms_ = 0;  // wait after mpv finished rendering
  double probe_wait_done_max_ms_ = 0;
  // Time in RenderBackend::Render per probed frame (log only, render thread
  // only like the wait sums): mpv's render call, which also waits for the
  // frame's target time, plus the backend's completion signal.
  double probe_render_ms_ = 0;
  double probe_render_max_ms_ = 0;
  // Frames rendered and dropped before the compositor took them (mpv does
  // not count them as drops): from a full queue, the older waiting frame at
  // a resize or a return from idle, or a replaced frame on the fallback
  // ring. probe_repeated_ counts acquisitions that found nothing new,
  // probe_queued_ those that took the older of two waiting frames (shown one
  // compositor frame later than a newest-wins queue would have). All three
  // are written under mutex_, read and reset under it by the render thread.
  int probe_superseded_ = 0;
  int probe_repeated_ = 0;
  int probe_queued_ = 0;
  std::chrono::steady_clock::time_point retry_at_{};
  bool device_lost_ = false;

  // Pending ICC profile (guarded by mutex_).
  bool icc_pending_ = false;
  std::vector<uint8_t> icc_profile_;

  // Ring state, guarded by mutex_.
  //
  // The compositor samples an image on the GPU some time after taking it,
  // and no platform tells us when it is done (Flutter's Windows texture
  // path even drops its reference right after binding, before drawing). An
  // image it gave back is therefore quarantined for quarantine_ further
  // acquisitions (frames) before it is rendered into again — bounded by the
  // compositor's frame latency (Interop::CompositorLatency()).
  // Ring = front + one waiting frame + in use + quarantine + one free image.
 public:
  static constexpr int kMaxQuarantine = 4;

 private:
  // Finished frames that may wait for the compositor (front_ and queued_).
  static constexpr int kReadyDepth = 2;
  int quarantine_count_ = 2;
  int ring_size_ = 6;
  int ready_depth_ = kReadyDepth;       // 1 after the allocation fallback
  int width_ = 0, height_ = 0;          // requested
  int ring_w_ = 0, ring_h_ = 0;         // allocated
  int front_ = -1;                      // last completed frame
  int queued_ = -1;                     // older waiting frame, -1 if none
  bool front_acquired_ = false;         // the compositor took front_ (in_use_)
  int in_use_ = -1;                     // frame the compositor holds
  int quarantine_[kMaxQuarantine] = {-1, -1, -1, -1};  // newest first
  // After a reallocation the previous generation's last frame stays on
  // screen until the first frame at the new size exists (no black flash),
  // and is freed once the compositor can no longer sample it.
  Frame retired_front_;
  int retired_countdown_ = -1;  // acquisitions left; 0: free it
  std::atomic<bool> resize_pending_{false};
};

}  // namespace mpv_kit
