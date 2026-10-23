#include "video_renderer.h"

#include <mpv/render_vk.h>

#include <algorithm>

#include "vulkan_backend.h"

namespace mpv_kit {

RendererChoice ParseRendererChoice(const std::string& name) {
  if (name == "gpu-next") return RendererChoice::kGpuNext;
  if (name == "gpu") return RendererChoice::kGpu;
  if (name == "software") return RendererChoice::kSoftware;
  return RendererChoice::kAuto;
}

VideoRenderer::VideoRenderer(const MpvApi& api, mpv_handle* handle,
                             Interop* interop, LogFn log, EventFn event)
    : api_(api),
      handle_(handle),
      interop_(interop),
      log_(std::move(log)),
      event_(std::move(event)) {}

VideoRenderer::~VideoRenderer() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    quit_ = true;
  }
  cv_.notify_all();
  if (thread_.joinable()) thread_.join();
  if (render_ctx_) {
    api_.render_context_set_update_callback(render_ctx_, nullptr, nullptr);
    // Must precede device destruction: mpv owns objects on our VkDevice.
    api_.render_context_free(render_ctx_);
    render_ctx_ = nullptr;
  }
  vulkan_.reset();
}

bool VideoRenderer::Start(RendererChoice choice) {
  quarantine_count_ =
      std::clamp(interop_->CompositorLatency(), 1, kMaxQuarantine);
  ring_size_ = quarantine_count_ + 3;
  bool ok = false;
  if (choice != RendererChoice::kSoftware && interop_->vulkan()) {
    ok = StartVulkan(choice);
    if (!ok) log_("mpv_kit: Vulkan backend unavailable (" + backend_reason_ +
                  "), falling back to software rendering");
  } else {
    backend_reason_ = choice == RendererChoice::kSoftware
                          ? "software rendering requested"
                          : "platform has no Vulkan interop";
  }
  if (!ok) {
    const std::string why = backend_reason_;
    ok = StartSoftware();
    backend_reason_ = "software (" + why + ")";
  }
  if (!ok) return false;

  api_.render_context_set_update_callback(render_ctx_, &OnMpvUpdate, this);
  thread_ = std::thread(&VideoRenderer::RenderLoop, this);
  return true;
}

bool VideoRenderer::StartVulkan(RendererChoice choice) {
  vulkan_ = std::make_unique<VulkanContext>(interop_->vulkan());
  if (!vulkan_->Init(&backend_reason_)) {
    vulkan_.reset();
    return false;
  }
  VulkanContext& vk = *vulkan_;
  mpv_vulkan_init_params init{};
  init.instance = vk.instance();
  init.get_instance_proc_addr = vkGetInstanceProcAddr;  // from volk
  init.api_version = vk.api_version();
  init.physical_device = vk.physical_device();
  init.device = vk.device();
  init.extensions = vk.enabled_extensions().data();
  init.num_extensions = static_cast<int>(vk.enabled_extensions().size());
  init.features = vk.features();
  init.queue_graphics = {vk.graphics_queues().index, vk.graphics_queues().count};
  init.queue_compute = {vk.compute_queues().index, vk.compute_queues().count};
  init.queue_transfer = {vk.transfer_queues().index,
                         vk.transfer_queues().count};

  // gpu-next (libplacebo's renderer) first; the older gpu renderer covers
  // devices or libplacebo builds where it cannot initialise.
  std::vector<const char*> renderers;
  if (choice != RendererChoice::kGpu) renderers.push_back("gpu-next");
  if (choice != RendererChoice::kGpuNext) renderers.push_back("gpu");

  int advanced = 1;
  int err = 0;
  std::string tried;
  for (const char* renderer : renderers) {
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char*>(MPV_RENDER_API_TYPE_VULKAN)},
        {MPV_RENDER_PARAM_VULKAN_INIT_PARAMS, &init},
        {MPV_RENDER_PARAM_VULKAN_RENDERER, const_cast<char*>(renderer)},
        {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    err = api_.render_context_create(&render_ctx_, handle_, params);
    if (err >= 0) {
      // Ask mpv which renderer it really built: a libmpv without the
      // renderer parameter ignores it and always uses its default.
      const char* active = nullptr;
      const int info = api_.render_context_get_info(
          render_ctx_, {MPV_RENDER_PARAM_VULKAN_RENDERER, &active});
      const std::string name =
          info >= 0 && active ? active : "unknown renderer";
      backend_ = Backend::kVulkan;
      backend_reason_ = "vulkan (" + name + ") on " + vk.device_name();
      if (!tried.empty()) backend_reason_ += "; " + tried;
      return true;
    }
    const std::string why = std::string(renderer) + " unavailable: " +
                            api_.error_string(err);
    log_("mpv_kit: " + why);
    tried += tried.empty() ? why : ", " + why;
    render_ctx_ = nullptr;
  }
  backend_reason_ = "mpv_render_context_create: " + tried;
  vulkan_.reset();
  return false;
}

bool VideoRenderer::StartSoftware() {
  int advanced = 1;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_SW)},
      {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  const int err = api_.render_context_create(&render_ctx_, handle_, params);
  if (err < 0) {
    log_(std::string("mpv_kit: software backend failed: ") +
         api_.error_string(err));
    render_ctx_ = nullptr;
    return false;
  }
  backend_ = Backend::kSoftware;
  return true;
}

void VideoRenderer::OnMpvUpdate(void* self) {
  // Called from arbitrary mpv threads: only signal the render thread.
  auto* r = static_cast<VideoRenderer*>(self);
  {
    std::lock_guard<std::mutex> lock(r->mutex_);
    r->update_pending_ = true;
  }
  r->cv_.notify_one();
}

void VideoRenderer::Emit(const char* kind, const std::string& msg) {
  if (event_) event_(kind, msg);
}

void VideoRenderer::SetSize(int width, int height) {
  if (width <= 0 || height <= 0) return;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (width == width_ && height == height_) return;
    width_ = width;
    height_ = height;
    resize_pending_ = true;
  }
  cv_.notify_one();
}

void VideoRenderer::SetIccProfile(std::vector<uint8_t> profile) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    icc_profile_ = std::move(profile);
    icc_pending_ = true;
    redraw_pending_ = true;  // show the change even while paused
  }
  cv_.notify_one();
}

void VideoRenderer::ApplyIccProfile() {
  std::vector<uint8_t> profile;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!icc_pending_) return;
    icc_pending_ = false;
    profile = std::move(icc_profile_);
  }
  // mpv copies the data. Used when --icc-profile-auto is enabled (the Dart
  // side sets it); the software renderer does not support ICC.
  mpv_byte_array data{profile.empty() ? nullptr : profile.data(),
                      profile.size()};
  const int err = api_.render_context_set_parameter(
      render_ctx_, {MPV_RENDER_PARAM_ICC_PROFILE, &data});
  if (err < 0)
    log_(std::string("mpv_kit: ICC profile rejected: ") +
         api_.error_string(err));
}

Frame VideoRenderer::AcquireFront() {
  std::unique_lock<std::mutex> lock(mutex_);
  // The compositor takes the newest frame for display: that is when mpv's
  // frame counts as presented (vsync timing / display-resample).
  const bool presented = swap_pending_ && front_ >= 0;
  if (presented) swap_pending_ = false;
  last_acquire_ = std::chrono::steady_clock::now();
  // Visible again after skipped frames: the front image is stale.
  const bool resumed = idle_;
  if (resumed) {
    idle_ = false;
    redraw_pending_ = true;
  }
  if (in_use_ != front_ && in_use_ >= 0) {
    // The compositor moves on from in_use_: quarantine it (see header).
    for (int i = quarantine_count_ - 1; i > 0; i--)
      quarantine_[i] = quarantine_[i - 1];
    quarantine_[0] = in_use_;
  }
  if (in_use_ != front_ && retired_countdown_ > 0) retired_countdown_--;
  in_use_ = front_;
  Frame f;
  f.index = front_;
  f.width = ring_w_;
  f.height = ring_h_;
  if (front_ < 0) {
    // Reallocated, nothing rendered at the new size yet: keep showing the
    // previous generation's last frame.
    if (retired_front_.platform) {
      f = retired_front_;
      interop_->RetainFrame(f.platform);
    } else if (retired_front_.pixels) {
      f = retired_front_;
    }
    lock.unlock();
    if (resumed) cv_.notify_one();
    return f;
  }
  if (backend_ == Backend::kSoftware) {
    f.pixels = sw_buffers_[front_].data();
  } else {
    f.platform = vulkan_->ring()[front_].platform;
    interop_->RetainFrame(f.platform);
  }
  lock.unlock();
  if (resumed) cv_.notify_one();
  // Outside our lock: mpv takes its own lock and may call OnMpvUpdate.
  if (presented) api_.render_context_report_swap(render_ctx_);
  return f;
}

int VideoRenderer::PickBackBuffer() {
  // Never the frame being displayed, the one the compositor holds, or one
  // it may still be sampling (quarantined).
  for (int i = 0; i < ring_size_; i++) {
    bool busy = i == front_ || i == in_use_;
    for (int q = 0; q < quarantine_count_; q++) busy = busy || i == quarantine_[q];
    if (!busy) return i;
  }
  return 0;  // unreachable: ring_size_ leaves one image free
}

void VideoRenderer::FreeRetiredIfDone() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (retired_countdown_ != 0) return;
    retired_countdown_ = -1;
    retired_front_ = Frame{};
    // Software: the retired buffers only back retired_front_.
    sw_retired_.clear();
  }
  if (vulkan_) vulkan_->FreeRetired();
}

void VideoRenderer::RenderLoop() {
  using clock = std::chrono::steady_clock;
  for (;;) {
    bool resized = false;
    bool redraw = false;
    bool retry = false;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      auto ready = [&] {
        return quit_ || update_pending_ || resize_pending_ || redraw_pending_;
      };
      // Wake for whichever comes first: a pending swap that nobody
      // displayed, or the end of a failure backoff.
      clock::time_point deadline = clock::time_point::max();
      if (swap_pending_) deadline = clock::now() + kPresentTimeout;
      if (failures_ > 0 && !device_lost_)
        deadline = std::min(deadline, retry_at_);
      if (deadline == clock::time_point::max()) {
        cv_.wait(lock, ready);
      } else if (!cv_.wait_until(lock, deadline, ready)) {
        if (swap_pending_ && clock::now() >= deadline) {
          // Nobody displayed the last frame in time (hidden window, paused
          // raster): report it anyway so mpv's flip_page never stalls.
          swap_pending_ = false;
          lock.unlock();
          api_.render_context_report_swap(render_ctx_);
          continue;
        }
        // Backoff over: try again even if mpv has no new frame (paused).
        retry = failures_ > 0 && clock::now() >= retry_at_;
        if (!retry) continue;
      }
      if (quit_) return;
      update_pending_ = false;
      resized = resize_pending_.exchange(false);
      redraw = redraw_pending_ || retry;
      redraw_pending_ = false;
    }
    ApplyIccProfile();
    FreeRetiredIfDone();
    // A new size is the usual cure for allocation failures: retry now.
    if (resized && failures_ > 0) retry_at_ = clock::now();
    const uint64_t flags = api_.render_context_update(render_ctx_);
    // A resize or a return from idle must redraw even when paused (no new
    // frame from mpv).
    if (!(flags & MPV_RENDER_UPDATE_FRAME) && !resized && !redraw) continue;

    bool sized, visible;
    bool became_idle = false, became_active = false;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sized = width_ > 0 && height_ > 0;
      // Only once a frame exists at the current size: the first frame
      // (and any resize) is always drawn.
      const bool idle = front_ >= 0 && ring_w_ == width_ &&
                        ring_h_ == height_ &&
                        clock::now() - last_acquire_ > kIdleTimeout;
      const bool was_idle = idle_;
      if (resized || redraw) {
        idle_ = false;
      } else if (idle) {
        idle_ = true;
      }
      became_idle = idle_ && !was_idle;
      // AcquireFront clears idle_ when the compositor comes back.
      became_active = !idle_ && reported_idle_;
      reported_idle_ = idle_;
      visible = !idle_;
    }
    if (became_idle) Emit("idle");
    if (became_active) Emit("active");
    const bool backing_off =
        device_lost_ || (failures_ > 0 && clock::now() < retry_at_);
    if (sized && visible && !backing_off) {
      std::string error;
      OnRenderResult(RenderOnce(&error), error);
    } else {
      SkipFrame();
      // Keep notifying: a texture that becomes visible again is only
      // acquired (ending idle) when the compositor sees a new frame.
      if (sized && !backing_off) interop_->FrameReady();
    }
  }
}

void VideoRenderer::OnRenderResult(RenderResult result,
                                   const std::string& error) {
  if (result == RenderResult::kOk) {
    if (failures_ > 0) {
      log_("mpv_kit: rendering recovered after " + std::to_string(failures_) +
           " failed frame(s)");
      Emit("recovered");
    }
    failures_ = 0;
    return;
  }
  if (result == RenderResult::kDeviceLost) {
    device_lost_ = true;
    log_("mpv_kit: Vulkan device lost; video rendering stopped (" + error +
         ")");
    Emit("device_lost", error);
    return;
  }
  failures_++;
  const auto backoff = std::min<std::chrono::milliseconds>(
      kMaxBackoff, kMinBackoff * (1 << std::min(failures_ - 1, 6)));
  retry_at_ = std::chrono::steady_clock::now() + backoff;
  // Report the first failure and then every doubling, not every frame.
  if ((failures_ & (failures_ - 1)) == 0) {
    log_("mpv_kit: frame render failed (" + std::to_string(failures_) +
         "x): " + error);
    Emit(error == "gpu timeout" ? "gpu_timeout" : "render_error", error);
  }
}

void VideoRenderer::SkipFrame() {
  // No target size yet (widget not laid out), hidden, or backing off after
  // a failure: let mpv advance its frame state without drawing. vo_libmpv
  // still expects a render call and a swap for every frame.
  int skip = 1;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SKIP_RENDERING, &skip},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  api_.render_context_render(render_ctx_, params);
  api_.render_context_report_swap(render_ctx_);
}

VideoRenderer::RenderResult VideoRenderer::RenderOnce(std::string* error) {
  int w, h, back;
  bool failed_before_render = false;
  // Old generation's front slot, valid across the realloc below: the one
  // image whose Vulkan side survives into retirement.
  int keep_front = -1;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    w = width_;
    h = height_;
    if (w != ring_w_ || h != ring_h_) {
      // Old images are about to be retired; their last frame stays on
      // screen until a new one exists.
      if (front_ >= 0) {
        keep_front = front_;
        retired_front_ = Frame{};
        retired_front_.index = -2;  // never equal to a ring index
        retired_front_.width = ring_w_;
        retired_front_.height = ring_h_;
        if (backend_ == Backend::kSoftware) {
          retired_front_.pixels = sw_buffers_[front_].data();
        } else {
          retired_front_.platform = vulkan_->ring()[front_].platform;
        }
      }
      retired_countdown_ = -1;
      front_ = in_use_ = -1;
      for (int& q : quarantine_) q = -1;
    }
    back = PickBackBuffer();
  }

  if (w != ring_w_ || h != ring_h_) {
    {
      // Under the lock: AcquireFront() must never observe a half-built ring.
      std::lock_guard<std::mutex> lock(mutex_);
      if (backend_ == Backend::kVulkan) {
        // The compositor may still sample the front frame: only that ring
        // slot survives into retirement, the rest is freed at once.
        SharedImage* keep =
            keep_front >= 0 ? &vulkan_->ring()[keep_front] : nullptr;
        if (!vulkan_->AllocateRing(ring_size_, w, h, keep, error)) {
          // 8K on a small GPU: the full ring may not fit. One retry with
          // the smallest ring whose quarantine (2) still respects the
          // documented tearing constraint beats dropping to software.
          const int fallback_quarantine = 2;
          const int fallback_ring = fallback_quarantine + 3;
          if (ring_size_ > fallback_ring &&
              vulkan_->AllocateRing(fallback_ring, w, h, keep, error)) {
            ring_size_ = fallback_ring;
            quarantine_count_ = fallback_quarantine;
            log_("mpv_kit: shared-image allocation failed at ring " +
                 std::to_string(ring_size_) + ", retried with a ring of " +
                 std::to_string(fallback_ring));
          } else {
            ring_w_ = ring_h_ = 0;
            retired_front_ = Frame{};  // AllocateRing freed everything
            failed_before_render = true;
          }
        }
      } else {
        sw_retired_ = std::move(sw_buffers_);
        sw_buffers_.assign(ring_size_, std::vector<uint8_t>(size_t(w) * h * 4));
      }
      if (!failed_before_render) {
        ring_w_ = w;
        ring_h_ = h;
      }
    }
    if (failed_before_render) {
      SkipFrame();  // mpv still waits for this frame to be consumed
      return RenderResult::kFailed;
    }
    Emit("resize", std::to_string(w) + "x" + std::to_string(h));
  }

  int err;
  if (backend_ == Backend::kVulkan) {
    SharedImage& img = vulkan_->ring()[back];
    // Previous use of this image must be finished before we write to it.
    const auto wait_prev_begin = std::chrono::steady_clock::now();
    const VkResult prev = vulkan_->WaitImage(back);
    probe_wait_prev_ms_ +=
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - wait_prev_begin)
            .count();
    if (prev != VK_SUCCESS) {
      SkipFrame();
      *error = prev == VK_ERROR_DEVICE_LOST ? "device lost" : "gpu timeout";
      return prev == VK_ERROR_DEVICE_LOST ? RenderResult::kDeviceLost
                                          : RenderResult::kFailed;
    }
    mpv_vulkan_image target{};
    target.image = img.image;
    target.format = img.format;
    target.usage = kSharedImageUsage;
    target.width = img.width;
    target.height = img.height;
    // Images are shared with another API: transfer ownership to/from the
    // external queue family and keep them in GENERAL layout between frames.
    target.layout = img.initialized ? VK_IMAGE_LAYOUT_GENERAL
                                    : VK_IMAGE_LAYOUT_UNDEFINED;
    target.queue_family =
        img.initialized ? VK_QUEUE_FAMILY_EXTERNAL : VK_QUEUE_FAMILY_IGNORED;
    target.final_layout = VK_IMAGE_LAYOUT_GENERAL;
    target.signal_semaphore = vulkan_->timeline();
    target.signal_value = vulkan_->NextSignalValue(back);
    int flip = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_VULKAN_IMAGE, &target},
        {MPV_RENDER_PARAM_FLIP_Y, &flip},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    err = api_.render_context_render(render_ctx_, params);
    // Only a successful render transitions the image out of UNDEFINED.
    if (err >= 0) img.initialized = true;
    if (err >= 0) {
      // The compositor reads without GPU sync, so complete the frame first.
      const auto wait_done_begin = std::chrono::steady_clock::now();
      const VkResult done = vulkan_->WaitImage(back);
      const double wait_done_ms = std::chrono::duration<double, std::milli>(
                                      std::chrono::steady_clock::now() - wait_done_begin)
                                      .count();
      probe_wait_done_ms_ += wait_done_ms;
      probe_wait_done_max_ms_ = std::max(probe_wait_done_max_ms_, wait_done_ms);
      // One aggregated line per probe window: avg waits per frame plus the
      // worst single post-render wait, to size the serialisation tax.
      if (++probe_frames_ >= kProbeWindow) {
        log_("mpv_kit: render waits avg/over " + std::to_string(probe_frames_) +
             " frames: prev=" +
             std::to_string(probe_wait_prev_ms_ / probe_frames_) + "ms done=" +
             std::to_string(probe_wait_done_ms_ / probe_frames_) + "ms max_done=" +
             std::to_string(probe_wait_done_max_ms_) + "ms");
        probe_frames_ = 0;
        probe_wait_prev_ms_ = 0;
        probe_wait_done_ms_ = 0;
        probe_wait_done_max_ms_ = 0;
      }
      if (done != VK_SUCCESS) {
        api_.render_context_report_swap(render_ctx_);  // frame consumed
        *error = done == VK_ERROR_DEVICE_LOST ? "device lost" : "gpu timeout";
        return done == VK_ERROR_DEVICE_LOST ? RenderResult::kDeviceLost
                                            : RenderResult::kFailed;
      }
    }
  } else {
    int size[2] = {w, h};
    size_t stride = size_t(w) * 4;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT,
         const_cast<char*>(interop_->SoftwareIsBgra() ? "bgr0" : "rgb0")},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, sw_buffers_[back].data()},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    err = api_.render_context_render(render_ctx_, params);
    // The padding byte of rgb0/bgr0 is undefined; textures treat it as alpha.
    uint8_t* px = sw_buffers_[back].data();
    for (size_t i = 3, n = size_t(w) * h * 4; i < n; i += 4) px[i] = 0xff;
  }
  if (err < 0) {
    *error = std::string("render: ") + api_.error_string(err);
    // The frame was consumed (unless the target was rejected up front,
    // where an extra swap is harmless): keep vo_libmpv's counts moving.
    api_.render_context_report_swap(render_ctx_);
    return RenderResult::kFailed;
  }
  int swaps = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    front_ = back;
    // First frame of a new generation: the retired one may go once the
    // compositor has moved past it (same rule as the quarantine).
    if (retired_countdown_ < 0 && (retired_front_.platform || retired_front_.pixels))
      retired_countdown_ = quarantine_count_ + 1;
    // The previous frame was never displayed: it still counts as swapped.
    if (swap_pending_) swaps++;
    const bool consuming = std::chrono::steady_clock::now() - last_acquire_ <
                           kPresentTimeout;
    // Without an active consumer, report this frame right away.
    swap_pending_ = consuming;
    if (!consuming) swaps++;
  }
  for (int i = 0; i < swaps; i++) api_.render_context_report_swap(render_ctx_);
  interop_->FrameReady();
  return RenderResult::kOk;
}

}  // namespace mpv_kit
