#include "video_renderer.h"

#include <mpv/render_vk.h>

#include "vulkan_backend.h"

namespace mpv_kit {
namespace {

}  // namespace

VideoRenderer::VideoRenderer(const MpvApi& api, mpv_handle* handle,
                             Interop* interop, LogFn log)
    : api_(api), handle_(handle), interop_(interop), log_(std::move(log)) {}

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

bool VideoRenderer::Start(bool force_software) {
  bool ok = false;
  if (!force_software && interop_->vulkan()) {
    ok = StartVulkan();
    if (!ok) log_("mpv_kit: Vulkan backend unavailable (" + backend_reason_ +
                  "), falling back to software rendering");
  } else {
    backend_reason_ = force_software ? "software rendering forced"
                                     : "platform has no Vulkan interop";
  }
  if (!ok) ok = StartSoftware();
  if (!ok) return false;

  api_.render_context_set_update_callback(render_ctx_, &OnMpvUpdate, this);
  thread_ = std::thread(&VideoRenderer::RenderLoop, this);
  return true;
}

bool VideoRenderer::StartVulkan() {
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
  init.queue_graphics = {vk.graphics_family(), vk.graphics_count()};
  init.queue_compute = {vk.graphics_family(), vk.graphics_count()};
  init.queue_transfer = {vk.graphics_family(), vk.graphics_count()};

  int advanced = 1;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE,
       const_cast<char*>(MPV_RENDER_API_TYPE_VULKAN)},
      {MPV_RENDER_PARAM_VULKAN_INIT_PARAMS, &init},
      {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  const int err = api_.render_context_create(&render_ctx_, handle_, params);
  if (err < 0) {
    backend_reason_ = std::string("mpv_render_context_create: ") +
                      api_.error_string(err);
    render_ctx_ = nullptr;
    vulkan_.reset();
    return false;
  }
  backend_ = Backend::kVulkan;
  backend_reason_ = "vulkan on " + vk.device_name();
  return true;
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

Frame VideoRenderer::AcquireFront() {
  std::unique_lock<std::mutex> lock(mutex_);
  // The compositor takes the newest frame for display: that is when mpv's
  // frame counts as presented (vsync timing / display-resample).
  const bool presented = swap_pending_ && front_ >= 0;
  if (presented) swap_pending_ = false;
  last_acquire_ = std::chrono::steady_clock::now();
  if (in_use_ != front_ && in_use_ >= 0) {
    // The compositor moves on from in_use_: quarantine it (see header).
    for (int i = kQuarantine - 1; i > 0; i--) quarantine_[i] = quarantine_[i - 1];
    quarantine_[0] = in_use_;
  }
  in_use_ = front_;
  Frame f;
  f.index = front_;
  f.width = ring_w_;
  f.height = ring_h_;
  if (front_ < 0) return f;
  if (backend_ == Backend::kSoftware) {
    f.pixels = sw_buffers_[front_].data();
  } else {
    f.platform = vulkan_->ring()[front_].platform;
    interop_->RetainFrame(f.platform);
  }
  lock.unlock();
  // Outside our lock: mpv takes its own lock and may call OnMpvUpdate.
  if (presented) api_.render_context_report_swap(render_ctx_);
  return f;
}

int VideoRenderer::PickBackBuffer() {
  // Never the frame being displayed, the one the compositor holds, or one
  // it may still be sampling (quarantined).
  for (int i = 0; i < kRingSize; i++) {
    bool busy = i == front_ || i == in_use_;
    for (int q : quarantine_) busy = busy || i == q;
    if (!busy) return i;
  }
  return 0;  // unreachable: kRingSize leaves one image free
}

void VideoRenderer::RenderLoop() {
  for (;;) {
    bool resized = false;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      auto ready = [&] { return quit_ || update_pending_ || resize_pending_; };
      if (swap_pending_) {
        // Nobody displayed the last frame in time (hidden window, paused
        // raster): report it anyway so mpv's flip_page never stalls.
        if (!cv_.wait_for(lock, kPresentTimeout, ready) && swap_pending_) {
          swap_pending_ = false;
          lock.unlock();
          api_.render_context_report_swap(render_ctx_);
          continue;
        }
      } else {
        cv_.wait(lock, ready);
      }
      if (quit_) return;
      update_pending_ = false;
      resized = resize_pending_.exchange(false);
    }
    const uint64_t flags = api_.render_context_update(render_ctx_);
    // A resize must redraw even when paused (no new frame from mpv).
    if ((flags & MPV_RENDER_UPDATE_FRAME) || resized) {
      bool sized;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        sized = width_ > 0 && height_ > 0;
      }
      if (sized) {
        if (!RenderOnce()) log_("mpv_kit: frame render failed");
      } else {
        SkipFrame();
      }
    }
  }
}

void VideoRenderer::SkipFrame() {
  // No target size yet (widget not laid out): let mpv advance its frame
  // state without drawing, instead of rendering (and compiling shaders
  // for) a throwaway placeholder. vo_libmpv still expects a render call
  // and a swap for every frame.
  int skip = 1;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SKIP_RENDERING, &skip},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  api_.render_context_render(render_ctx_, params);
  api_.render_context_report_swap(render_ctx_);
}

bool VideoRenderer::RenderOnce() {
  int w, h, back;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    w = width_;
    h = height_;
    if (w != ring_w_ || h != ring_h_) {
      front_ = in_use_ = -1;  // old images are about to be replaced
      for (int& q : quarantine_) q = -1;
    }
    back = PickBackBuffer();
  }

  if (w != ring_w_ || h != ring_h_) {
    // Under the lock: AcquireFront() must never observe a half-built ring.
    std::lock_guard<std::mutex> lock(mutex_);
    if (backend_ == Backend::kVulkan) {
      std::string error;
      if (!vulkan_->AllocateRing(kRingSize, w, h, &error)) {
        log_("mpv_kit: " + error);
        ring_w_ = ring_h_ = 0;
        return false;
      }
    } else {
      sw_retired_ = std::move(sw_buffers_);
      sw_buffers_.assign(kRingSize, std::vector<uint8_t>(size_t(w) * h * 4));
    }
    ring_w_ = w;
    ring_h_ = h;
  }

  int err;
  if (backend_ == Backend::kVulkan) {
    SharedImage& img = vulkan_->ring()[back];
    // Previous use of this image must be finished before we write to it.
    vulkan_->WaitImage(back);
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
    // The compositor reads without GPU sync, so complete the frame first.
    if (err >= 0 && !vulkan_->WaitImage(back)) {
      log_("mpv_kit: GPU did not finish the frame within 1 s");
      return false;
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
    log_(std::string("mpv_kit: render: ") + api_.error_string(err));
    return false;
  }
  int swaps = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    front_ = back;
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
  return true;
}

}  // namespace mpv_kit
