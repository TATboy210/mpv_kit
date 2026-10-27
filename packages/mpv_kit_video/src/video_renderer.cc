#include "video_renderer.h"

#include <algorithm>
#include <cassert>
#include <cstdlib>
#include <cstring>

namespace mpv_kit {

// Reason grammar (docs/adr/0004-render-backend-reporting.md, Decision 3):
//   reason = head *( "; " trail )
//   head   = api " (" renderer ") on " device
//   trail  = api "/" renderer " unavailable: " why

std::string SanitizeReasonField(std::string s) {
  for (char& c : s) {
    if (c == ';') {
      c = ',';
    } else if (static_cast<unsigned char>(c) < 0x20) {
      c = ' ';
    }
  }
  return s;
}

namespace {

/// Joins trails with the grammar's "; " separator.
std::string JoinTrails(const std::vector<std::string>& trails) {
  std::string out;
  for (const std::string& t : trails) {
    if (!out.empty()) out += "; ";
    out += t;
  }
  return out;
}

/// The reason trail of one candidate (ADR 0004).
std::string Trail(const BackendCandidate& c, const std::string& why) {
  return std::string(c.api) + "/" + c.renderer + " unavailable: " + why;
}

/// Whether a candidate after [i] that may be tried uses [api] (its backend
/// is kept for it).
bool UsedLater(const std::vector<BackendCandidate>& candidates,
               const std::vector<bool>& allowed, size_t i, const char* api) {
  for (size_t k = i + 1; k < candidates.size(); k++) {
    if (allowed[k] && std::strcmp(candidates[k].api, api) == 0) return true;
  }
  return false;
}

// --- MPV_KIT_VIDEO_API (docs/adr/0004-render-backend-reporting.md,
// Decision 4) --------------------------------------------------------------

/// Longest accepted value; also the length of its echo.
constexpr size_t kMaxForcedApiLength = 16;

/// The forced graphics API of one Start.
struct ForcedApi {
  bool active = false;  // set and non-empty
  // The value when it matches ^[a-z0-9-]{1,16}$; empty (matches no
  // candidate) when it is malformed.
  std::string api;
  // The value as it appears in trails and the log: characters outside
  // [a-z0-9-] become '?', cut to kMaxForcedApiLength characters.
  std::string echo;
};

/// The raw value of MPV_KIT_VIDEO_API, read at each call; "" when unset.
std::string ForcedApiValue() {
#ifdef _WIN32
  // The CRT's getenv is deprecated on Windows (C4996, an error under the
  // plugin's /WX); _dupenv_s reads the same environment.
  char* value = nullptr;
  size_t size = 0;
  if (_dupenv_s(&value, &size, "MPV_KIT_VIDEO_API") != 0 || !value) return {};
  std::string out(value);
  std::free(value);
  return out;
#else
  const char* value = std::getenv("MPV_KIT_VIDEO_API");
  return value ? value : "";
#endif
}

ForcedApi ParseForcedApi(const std::string& value) {
  ForcedApi forced;
  if (value.empty()) return forced;  // empty means unset
  forced.active = true;
  bool valid = value.size() <= kMaxForcedApiLength;
  for (size_t i = 0; i < value.size(); i++) {
    const char c = value[i];
    const bool ok =
        (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-';
    valid = valid && ok;
    if (i < kMaxForcedApiLength) forced.echo += ok ? c : '?';
  }
  if (valid) forced.api = value;
  return forced;
}

/// Whether a forced run may try [c]: its api is the forced one and its
/// renderer was requested (kAuto requests all of them). The software
/// candidate of a gpu-next or gpu request is only that request's fallback,
/// so it is excluded as well: a forced run never falls back.
bool ForcedAllows(const ForcedApi& forced, RendererChoice choice,
                  const BackendCandidate& c) {
  if (forced.api.empty() || forced.api != c.api) return false;
  switch (choice) {
    case RendererChoice::kAuto:
      return true;
    case RendererChoice::kGpuNext:
      return std::strcmp(c.renderer, "gpu-next") == 0;
    case RendererChoice::kGpu:
      return std::strcmp(c.renderer, "gpu") == 0;
    case RendererChoice::kSoftware:
      return std::strcmp(c.renderer, "sw") == 0;
  }
  return false;
}

/// Log line of a failed mpv_render_context_create; both spellings predate
/// the candidate chain and are kept verbatim.
std::string CreateFailedLog(const BackendCandidate& c, const char* error) {
  if (std::strcmp(c.api, "software") == 0)
    return std::string("mpv_kit: software backend failed: ") + error;
  return std::string("mpv_kit: ") + c.renderer + " unavailable: " + error;
}

/// One api's backend during Start: created at the api's first candidate
/// and kept for its later ones (one device initialisation per api).
struct ApiAttempt {
  std::string api;
  std::unique_ptr<RenderBackend> backend;
  // Non-empty: every remaining candidate of this api fails with this why
  // (no platform backend, or its device failed to initialise).
  std::string why;
  bool asked = false;  // Create was called at least once
};

ApiAttempt& AttemptFor(std::vector<ApiAttempt>* attempts, const char* api) {
  for (ApiAttempt& a : *attempts) {
    if (a.api == api) return a;
  }
  attempts->push_back(ApiAttempt{api, nullptr, {}, false});
  return attempts->back();
}

/// MPV_RENDER_API_TYPE_SW into a ring of CPU buffers (RenderBackend).
class SoftwareBackend final : public RenderBackend {
 public:
  explicit SoftwareBackend(bool bgra) : bgra_(bgra) {}

  const char* wire_name() const override { return "software"; }
  Backend frame_kind() const override { return Backend::kSoftware; }
  bool pipelined() const override { return false; }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    (void)renderer;  // "sw": the software renderer has no variants
    int advanced = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_SW)},
        {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_create(out, handle, params);
    if (err < 0) {
      *why = "mpv_render_context_create: " +
             SanitizeReasonField(api.error_string(err));
      *out = nullptr;
    }
    return err;
  }
  std::string device_name() const override { return "cpu"; }
  std::string RendererName(const MpvApi& api,
                           mpv_render_context* ctx) const override {
    (void)api;
    (void)ctx;
    return "sw";
  }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    // The whole old generation is retired, so keep_slot does not matter:
    // the compositor may still be uploading from its front buffer after its
    // copy callback returned. CPU pixels have no platform reference, and the
    // frame of the last AcquireFront() may lie in the generation retired by
    // the previous reallocation too: the retired front shown after a failed
    // render, or a frame taken before two quick resizes (code review CR-01).
    // So that generation is kept one reallocation longer (older_) and only
    // the one before it is freed here; FreeRetired() drops both once the
    // compositor has moved on. Allocation does not fail (bad_alloc aside).
    (void)keep_slot;
    (void)error;
    older_ = std::move(retired_);
    retired_ = std::move(buffers_);
    buffers_.assign(count, std::vector<uint8_t>(size_t(width) * height * 4));
    return true;
  }
  void FreeRetired() override {
    retired_.clear();
    older_.clear();
  }
  TargetView FrameFor(int slot) override {
    TargetView view;
    view.pixels = buffers_[slot].data();
    return view;
  }

  int Render(const MpvApi& api, mpv_render_context* ctx, int slot, int width,
             int height) override {
    int size[2] = {width, height};
    size_t stride = size_t(width) * 4;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char*>(bgra_ ? "bgr0" : "rgb0")},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, buffers_[slot].data()},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_render(ctx, params);
    // The padding byte of rgb0/bgr0 is undefined; textures treat it as alpha.
    uint8_t* px = buffers_[slot].data();
    for (size_t i = 3, n = size_t(width) * height * 4; i < n; i += 4) px[i] = 0xff;
    return err;
  }
  WaitResult Wait(int slot) override {
    (void)slot;  // software frames are complete when Render returns
    return WaitResult::kOk;
  }

  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    api.render_context_free(ctx);
  }

 private:
  const bool bgra_;
  std::vector<std::vector<uint8_t>> buffers_;
  // Previous generation, kept one resize longer (see AllocTargets).
  std::vector<std::vector<uint8_t>> retired_;
  // The generation before retired_, kept one more resize (see AllocTargets).
  std::vector<std::vector<uint8_t>> older_;
};

}  // namespace

std::unique_ptr<RenderBackend> CreateSoftwareBackend(bool bgra) {
  return std::make_unique<SoftwareBackend>(bgra);
}

std::vector<BackendCandidate> DefaultCandidates(RendererChoice choice) {
  // gpu-next (libplacebo's renderer) first; the older gpu renderer covers
  // devices or libplacebo builds where it cannot initialise. Software last.
  std::vector<BackendCandidate> chain;
  if (choice != RendererChoice::kSoftware) {
    if (choice != RendererChoice::kGpu) chain.push_back({"vulkan", "gpu-next"});
    if (choice != RendererChoice::kGpuNext) chain.push_back({"vulkan", "gpu"});
  }
  chain.push_back({"software", "sw"});
  return chain;
}

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
  // The render thread frees the render context before it exits (RenderLoop).
  if (thread_.joinable()) thread_.join();
  if (render_ctx_) {
    // Only when the render thread never ran: Start created the context and
    // then std::thread threw. No thread ever owned the context, so this one
    // binds the backend and frees it here, as the render thread would.
    render_backend_->BindThread();
    api_.render_context_set_update_callback(render_ctx_, nullptr, nullptr);
    // Must precede device destruction: mpv owns objects on our VkDevice.
    render_backend_->Release(api_, render_ctx_);
    render_ctx_ = nullptr;
    render_backend_->UnbindThread();
  }
  render_backend_.reset();  // device last
}

bool VideoRenderer::Start(RendererChoice choice) {
  quarantine_count_ =
      std::clamp(interop_->CompositorLatency(), 1, kMaxQuarantine);
  ring_size_ = quarantine_count_ + 3;
  const std::vector<BackendCandidate> candidates =
      interop_->BackendCandidates(choice);
  // Read once per Start: a later change affects only later renderers.
  const ForcedApi forced = ParseForcedApi(ForcedApiValue());
  if (forced.active)
    log_("mpv_kit: MPV_KIT_VIDEO_API=" + forced.echo +
         " restricts rendering to that API");
  std::vector<bool> allowed(candidates.size(), true);
  if (forced.active) {
    for (size_t i = 0; i < candidates.size(); i++)
      allowed[i] = ForcedAllows(forced, choice, candidates[i]);
  }
  // Every candidate ranked before the winner leaves one trail, in chain
  // order; an explicit software request has none.
  std::vector<std::string> trails;
  std::vector<ApiAttempt> attempts;
  attempts.reserve(candidates.size());  // AttemptFor's references stay valid
  for (size_t i = 0; i < candidates.size() && !render_backend_; i++) {
    const BackendCandidate& c = candidates[i];
    if (!allowed[i]) {
      // Excluded before its backend exists: no device, no create.
      trails.push_back(
          Trail(c, "excluded by MPV_KIT_VIDEO_API=" + forced.echo));
      continue;
    }
    ApiAttempt& a = AttemptFor(&attempts, c.api);
    if (!a.backend && a.why.empty()) a.backend = NewBackend(c.api, &a.why);
    if (!a.why.empty()) {
      trails.push_back(Trail(c, a.why));
    } else {
      std::string why;
      const int err = a.backend->Create(api_, handle_, c.renderer,
                                        &render_ctx_, &why);
      a.asked = true;
      if (err >= 0) {
        backend_reason_ =
            std::string(a.backend->wire_name()) + " (" +
            SanitizeReasonField(a.backend->RendererName(api_, render_ctx_)) +
            ") on " + SanitizeReasonField(a.backend->device_name());
        // The trails so far are exactly the candidates ranked before it.
        if (!trails.empty()) backend_reason_ += "; " + JoinTrails(trails);
        render_backend_ = std::move(a.backend);
        break;
      }
      // A device that failed to initialise fails every renderer on it the
      // same way; only a failed mpv_render_context_create is logged.
      if (a.backend->device_failed()) {
        a.why = why;
      } else {
        log_(CreateFailedLog(c, api_.error_string(err)));
      }
      trails.push_back(Trail(c, why));
    }
    if (UsedLater(candidates, allowed, i, c.api)) continue;
    // The api's last candidate failed: its device goes before the next api
    // is tried. A forced run tries no other api, so it does not fall back.
    if (a.asked && a.api == "vulkan" && !forced.active)
      log_("mpv_kit: Vulkan backend unavailable (" + JoinTrails(trails) +
           "), falling back to software rendering");
    a.backend.reset();
  }
  if (!render_backend_) {
    // No head when every candidate failed: the reason is the trails only.
    backend_reason_ = JoinTrails(trails);
    return false;
  }

  api_.render_context_set_update_callback(render_ctx_, &OnMpvUpdate, this);
  thread_ = std::thread(&VideoRenderer::RenderLoop, this);
  return true;
}

std::unique_ptr<RenderBackend> VideoRenderer::NewBackend(const char* api,
                                                         std::string* why) {
  if (std::unique_ptr<RenderBackend> platform = interop_->CreateBackend(api))
    return platform;
  if (std::strcmp(api, "software") == 0)
    return CreateSoftwareBackend(interop_->SoftwareIsBgra());
  if (std::strcmp(api, "vulkan") == 0) {
    if (VulkanInterop* vulkan = interop_->vulkan())
      return CreateVulkanBackend(vulkan);
    const char* reason = interop_->interopReason();
    *why = reason ? "platform interop unavailable: " +
                        SanitizeReasonField(reason)
                  : "platform has no Vulkan interop";
    return nullptr;
  }
  // A candidate api neither the platform nor the built-ins provide; no
  // Phase 12 chain names one.
  *why = std::string("platform has no ") + api + " backend";
  return nullptr;
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
  AssertRenderThread();
  const int err = api_.render_context_set_parameter(
      render_ctx_, {MPV_RENDER_PARAM_ICC_PROFILE, &data});
  if (err < 0)
    log_(std::string("mpv_kit: ICC profile rejected: ") +
         api_.error_string(err));
}

Frame VideoRenderer::AcquireFront() {
  std::unique_lock<std::mutex> lock(mutex_);
  // The compositor takes the newest frame for display: that is when mpv's
  // frame counts as presented (vsync timing / display-resample). The swap
  // is reported by the render thread (RenderLoop), the only thread that
  // calls into the render context.
  const bool presented = swap_pending_ && front_ >= 0;
  if (presented) {
    swap_pending_ = false;
    swaps_to_report_++;
  }
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
  const TargetView view = render_backend_->FrameFor(front_);
  f.pixels = view.pixels;
  f.platform = view.platform;
  if (f.platform) interop_->RetainFrame(f.platform);
  lock.unlock();
  if (presented || resumed) cv_.notify_one();
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
  }
  // Outside the lock. Equivalent to the software path's old clear under the
  // lock: retired_front_, the only way AcquireFront reaches the retired
  // targets, was already cleared under it above.
  if (render_backend_) render_backend_->FreeRetired();
}

void VideoRenderer::ReportSwaps(int n) {
  AssertRenderThread();
  for (int i = 0; i < n; i++) api_.render_context_report_swap(render_ctx_);
}

void VideoRenderer::AssertRenderThread() const {
  assert(std::this_thread::get_id() == render_thread_id_.load());
}

void VideoRenderer::RenderLoop() {
  using clock = std::chrono::steady_clock;
  render_thread_id_.store(std::this_thread::get_id());
  // Always true for Vulkan and software. A backend with thread affinity
  // (OpenGL, Phase 15) binds its context here for the thread's lifetime.
  render_backend_->BindThread();
  for (;;) {
    bool resized = false;
    bool redraw = false;
    bool retry = false;
    int swaps = 0;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      auto ready = [&] {
        return quit_ || update_pending_ || resize_pending_ ||
               redraw_pending_ || swaps_to_report_ > 0;
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
          ReportSwaps(1);
          continue;
        }
        // Backoff over: try again even if mpv has no new frame (paused).
        retry = failures_ > 0 && clock::now() >= retry_at_;
        if (!retry) continue;
      }
      if (quit_) break;
      // Swaps the compositor made due (AcquireFront) go first: mpv's
      // flip_page waits for them.
      swaps = swaps_to_report_;
      swaps_to_report_ = 0;
      const bool work =
          update_pending_ || resize_pending_ || redraw_pending_ || retry;
      if (!work) {
        // Woken only to report swaps: no update call, so mpv sees the same
        // update pattern as when the compositor reported them itself.
        lock.unlock();
        ReportSwaps(swaps);
        continue;
      }
      update_pending_ = false;
      resized = resize_pending_.exchange(false);
      redraw = redraw_pending_ || retry;
      redraw_pending_ = false;
    }
    // Outside the lock: mpv takes its own lock and may call OnMpvUpdate.
    ReportSwaps(swaps);
    ApplyIccProfile();
    FreeRetiredIfDone();
    // A new size is the usual cure for allocation failures: retry now.
    if (resized && failures_ > 0) retry_at_ = clock::now();
    AssertRenderThread();
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
  // Still on the render thread, with the backend bound: the render context
  // is freed here, never on the platform thread that destroys the renderer.
  // Swaps not yet reported are dropped with it.
  AssertRenderThread();
  api_.render_context_set_update_callback(render_ctx_, nullptr, nullptr);
  // Must precede device destruction: mpv owns objects on our VkDevice.
  render_backend_->Release(api_, render_ctx_);
  render_ctx_ = nullptr;
  render_backend_->UnbindThread();
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
  AssertRenderThread();
  api_.render_context_render(render_ctx_, params);
  ReportSwaps(1);
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
      // Forget the older survivor first: if the previous generation never
      // published a frame, retired_front_ still names the one before it,
      // which the reallocation below frees (golden *_retire_twice).
      retired_front_ = Frame{};
      // Old images are about to be retired; their last frame stays on
      // screen until a new one exists.
      if (front_ >= 0) {
        keep_front = front_;
        retired_front_ = Frame{};
        retired_front_.index = -2;  // never equal to a ring index
        retired_front_.width = ring_w_;
        retired_front_.height = ring_h_;
        const TargetView view = render_backend_->FrameFor(front_);
        retired_front_.pixels = view.pixels;
        retired_front_.platform = view.platform;
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
      // The compositor may still sample the front frame: only that ring
      // slot survives into retirement, the rest is freed at once (software
      // retires its whole generation and never fails).
      if (!render_backend_->AllocTargets(ring_size_, w, h, keep_front,
                                         error)) {
        // 8K on a small GPU: the full ring may not fit. One retry with
        // the smallest ring whose quarantine (2) still respects the
        // documented tearing constraint beats dropping to software.
        const int fallback_quarantine = 2;
        const int fallback_ring = fallback_quarantine + 3;
        // The failed attempt freed everything, the image it had just
        // retired included: nothing is left to keep (keep_front's slot is
        // gone with the old ring), and the old front must never be
        // handed out again, as on the plain-failure branch below.
        retired_front_ = Frame{};
        if (ring_size_ > fallback_ring &&
            render_backend_->AllocTargets(fallback_ring, w, h, -1, error)) {
          log_("mpv_kit: shared-image allocation failed at ring " +
               std::to_string(ring_size_) + ", retried with a ring of " +
               std::to_string(fallback_ring));
          ring_size_ = fallback_ring;
          quarantine_count_ = fallback_quarantine;
        } else {
          ring_w_ = ring_h_ = 0;
          retired_front_ = Frame{};  // AllocTargets freed everything
          failed_before_render = true;
        }
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

  if (render_backend_->pipelined()) {
    // Previous use of this image must be finished before we write to it.
    const auto wait_prev_begin = std::chrono::steady_clock::now();
    const WaitResult prev = render_backend_->Wait(back);
    probe_wait_prev_ms_ +=
        std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - wait_prev_begin)
            .count();
    if (prev != WaitResult::kOk) {
      SkipFrame();
      *error = prev == WaitResult::kDeviceLost ? "device lost" : "gpu timeout";
      return prev == WaitResult::kDeviceLost ? RenderResult::kDeviceLost
                                             : RenderResult::kFailed;
    }
  }
  AssertRenderThread();
  const int err = render_backend_->Render(api_, render_ctx_, back, w, h);
  if (err < 0) {
    *error = std::string("render: ") + api_.error_string(err);
    // The frame was consumed (unless the target was rejected up front,
    // where an extra swap is harmless): keep vo_libmpv's counts moving.
    ReportSwaps(1);
    return RenderResult::kFailed;
  }
  if (render_backend_->pipelined()) {
    // Publish gate: the compositor samples without GPU sync, so a GPU
    // frame may only become the front (below) once its GPU work finished.
    // The wait sits right after the render call on purpose: deferring it to
    // the next round (857ccc2, pipeline depth 2) let this shared publish
    // block show the unfinished frame at once and count its swap twice
    // (golden vk-publish-gate). Software frames are complete already.
    const auto wait_done_begin = std::chrono::steady_clock::now();
    const WaitResult done = render_backend_->Wait(back);
    const double wait_done_ms = std::chrono::duration<double, std::milli>(
                                    std::chrono::steady_clock::now() -
                                    wait_done_begin)
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
    if (done != WaitResult::kOk) {
      // The frame is consumed either way: keep vo_libmpv's counts moving.
      ReportSwaps(1);
      *error = done == WaitResult::kDeviceLost ? "device lost" : "gpu timeout";
      return done == WaitResult::kDeviceLost ? RenderResult::kDeviceLost
                                             : RenderResult::kFailed;
    }
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
  ReportSwaps(swaps);
  interop_->FrameReady();
  return RenderResult::kOk;
}

}  // namespace mpv_kit
