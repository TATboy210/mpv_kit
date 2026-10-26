// Golden-test harness for the shared video renderer
// (packages/mpv_kit_video/src/video_renderer.cc and vulkan_backend.cc).
//
// What it proves: the real renderer state machine — backend fallback and
// its reason, ring rotation under the compositor quarantine, retire-on-
// resize, failure backoff, idle/active, ICC forwarding and the "every frame
// is swapped exactly once" contract with vo_libmpv — behaves exactly as the
// committed golden trace says. The golden tests are the regression gate for
// the RenderBackend refactor: every move commit must pass them unchanged.
//
// How it runs without libmpv: mpv_kit::MpvApi is nine function pointers and
// VideoRenderer reaches libmpv only through that table. MakeApi() fills it
// with the fakes below (FakeMpv), so the renderer runs in a process that
// never links or loads libmpv. The software path (Interop::vulkan() ==
// nullptr) needs no GPU, so it is deterministic on every CI runner.
//
// Why only the public surface: the tests touch the renderer through its
// constructor, Start, SetSize, SetIccProfile, AcquireFront, backend(),
// backend_reason() and destructor — the only parts that survive the
// refactor. Everything else is observed from the outside: the calls the
// renderer makes into the fake libmpv and into FakeInterop.
//
// Determinism: a golden trace only contains what the renderer decides, never
// when the OS scheduled it — no timestamps, thread ids, update counts or log
// text. Lines produced on the render thread (fake render calls, events, ICC
// parameters) are queued in render-thread program order and merged into the
// trace only at barriers (FakeMpv::Poke + WaitPokeSeen, see there), so the
// interleaving with test-thread lines is fixed. Timing-dependent behaviour
// (backoff intervals) is asserted as expectation + bounds; the expectation
// lives in the golden file, the measured value is only printed on failure.
//
// Golden files are only ever read. There is no update/regenerate mode: an
// expectation changes only by editing the golden file in a reviewed commit.
// Golden binaries exit 0 on pass, 1 on mismatch/invariant/timeout/usage.
//
// Vulkan path (12-07): FakeVulkanInterop creates real images on the real
// Vulkan device the renderer picked (lavapipe / MoltenVK / a GPU), so the
// real VulkanContext and its timeline semaphore run unmodified; only mpv's
// GPU work is faked (FakeMpv signals the timeline value of each render, at
// once or when the test says so). The platform objects behind
// SharedImage::platform live in a registry that is never freed (FakeImages),
// so a second destroy or a use after destroy is recorded as an invariant
// violation (`DOUBLE DESTROY` / `USE AFTER DESTROY`) instead of being
// undefined behaviour in the test itself: the defect turns red on plain
// builds too, and the sanitizer job checks the production code around it.
#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <map>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

#include <mpv/render.h>
#include <mpv/render_vk.h>

#include "video_renderer.h"
#include "vulkan_backend.h"

namespace golden {

using Clock = std::chrono::steady_clock;
using Ms = std::chrono::milliseconds;

// Every wait in the harness is bounded: generous enough that a sanitizer
// runner never trips it, finite so a broken renderer fails instead of
// hanging until the meson timeout.
constexpr Ms kWaitTimeout{10000};

/// Thrown when a bounded wait expires; the scenario fails with its message.
struct TimeoutError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

/// One call the renderer made into the fake libmpv. The thread id is
/// recorded from the start so later thread-affinity tests (12-11) need no
/// harness change; it never appears in a golden trace.
struct Call {
  std::string what;
  std::thread::id thread;
};

/// Counters of fake libmpv calls. `renders` counts every
/// mpv_render_context_render call, including SKIP_RENDERING and failed ones.
struct Counters {
  int renders = 0, skips = 0, swaps = 0;
  int frees = 0, creates = 0, updates = 0;
};

// --- Fake handles ------------------------------------------------------------

// Opaque in the mpv headers: only identity matters, so they point at
// distinct static objects and are checked on every call.
inline mpv_handle* FakeHandle() {
  static int storage;
  return reinterpret_cast<mpv_handle*>(&storage);
}

inline mpv_render_context* FakeContext() {
  static int storage;
  return reinterpret_cast<mpv_render_context*>(&storage);
}

// Render parameter types are read through the underlying integer: the Vulkan
// types (0x6d6b000x) lie outside the C enum's value range, and loading them
// as the enum would be undefined behaviour that UBSan reports.
inline std::underlying_type_t<mpv_render_param_type> ParamType(
    const mpv_render_param& p) {
  std::underlying_type_t<mpv_render_param_type> v;
  static_assert(sizeof v == sizeof p.type, "enum layout");
  std::memcpy(&v, &p.type, sizeof v);
  return v;
}

inline bool IsParam(const mpv_render_param& p, mpv_render_param_type type) {
  return ParamType(p) == ParamType(mpv_render_param{type, nullptr});
}

/// Data of the first parameter of `type` in an INVALID-terminated list.
inline void* FindParam(mpv_render_param* params, mpv_render_param_type type) {
  for (mpv_render_param* p = params; p && ParamType(*p) != 0; p++)
    if (IsParam(*p, type)) return p->data;
  return nullptr;
}

// --- Fake Vulkan images ------------------------------------------------------

/// One shared image FakeVulkanInterop created; SharedImage::platform points
/// at it.
struct FakeImage {
  int serial = 0;  // CreateImage order within the scenario, from 1; 0: none
  int width = 0, height = 0;
  VkImage image = VK_NULL_HANDLE;
  bool destroyed = false;
};

/// Process-wide registry of fake images. Entries are never freed (a deque
/// keeps their addresses stable), so a platform pointer the renderer still
/// holds after DestroyImage points at a readable entry that says so.
class FakeImages {
 public:
  /// Starts a scenario: serials restart at 1, violations are cleared.
  void Reset() {
    std::lock_guard<std::mutex> lock(mu_);
    base_ = images_.size();
    violations_.clear();
  }

  void* Add(int width, int height, VkImage image) {
    std::lock_guard<std::mutex> lock(mu_);
    FakeImage e;
    e.serial = static_cast<int>(images_.size() - base_) + 1;
    e.width = width;
    e.height = height;
    e.image = image;
    images_.push_back(e);
    return &images_.back();
  }

  /// Copy of the entry `platform` points at (serial 0 if it is none).
  FakeImage Entry(const void* platform) {
    std::lock_guard<std::mutex> lock(mu_);
    const FakeImage* e = Find(platform);
    return e ? *e : FakeImage{};
  }

  /// Marks the entry destroyed; false if it already was (or is unknown).
  bool MarkDestroyed(const void* platform) {
    std::lock_guard<std::mutex> lock(mu_);
    FakeImage* e = Find(platform);
    if (!e || e->destroyed) return false;
    e->destroyed = true;
    return true;
  }

  /// Newest live entry for a VkImage handle (drivers may reuse handles).
  FakeImage FindLive(VkImage image) {
    std::lock_guard<std::mutex> lock(mu_);
    for (auto it = images_.rbegin(); it != images_.rend(); ++it)
      if (it->image == image && !it->destroyed) return *it;
    return FakeImage{};
  }

  /// Live images of this scenario (created and not yet destroyed).
  int live() {
    std::lock_guard<std::mutex> lock(mu_);
    int n = 0;
    for (size_t i = base_; i < images_.size(); i++) n += !images_[i].destroyed;
    return n;
  }

  /// An invariant violation; every scenario reports and clears them.
  void Violation(std::string what) {
    std::lock_guard<std::mutex> lock(mu_);
    violations_.push_back(std::move(what));
  }

  std::vector<std::string> TakeViolations() {
    std::lock_guard<std::mutex> lock(mu_);
    std::vector<std::string> out = std::move(violations_);
    violations_.clear();
    return out;
  }

  /// Device of the images; the timeline semaphore FakeMpv signals lives on
  /// it too (VulkanContext creates both on one VkDevice).
  void SetDevice(VkDevice device) {
    std::lock_guard<std::mutex> lock(mu_);
    device_ = device;
  }

  VkDevice device() {
    std::lock_guard<std::mutex> lock(mu_);
    return device_;
  }

 private:
  FakeImage* Find(const void* platform) {
    for (FakeImage& e : images_)
      if (&e == platform) return &e;
    return nullptr;
  }

  std::mutex mu_;
  std::deque<FakeImage> images_;
  size_t base_ = 0;
  std::vector<std::string> violations_;
  VkDevice device_ = VK_NULL_HANDLE;
};

inline FakeImages& Images() {
  static FakeImages images;
  return images;
}

/// When a Vulkan render's timeline value is signalled (its "GPU work"
/// completes): during the render call, when the test calls
/// FakeMpv::SignalPending(), or not until then (kNever: the scenario
/// promises not to signal before the renderer's 1 s wait expired).
enum class SignalMode { kImmediate, kDeferred, kNever };

// --- FakeMpv -----------------------------------------------------------------

/// Scriptable stand-in for the nine libmpv render symbols. One per process
/// (Fake()); Reset() at the start of every scenario.
class FakeMpv {
 public:
  // --- Scenario control ---

  void Reset() {
    std::lock_guard<std::mutex> lock(mu_);
    create_results_.clear();
    info_name_ = "gpu-next";
    render_results_.clear();
    info_err_ = default_render_result_ = queued_frames_ = 0;
    hold_ = held_ = false;
    callback_ = nullptr;
    callback_ctx_ = nullptr;
    poke_seq_ = seen_seq_ = 0;
    counters_ = Counters{};
    calls_.clear();
    creates_.clear();
    async_.clear();
    render_times_.clear();
    buf_ids_.clear();
    gen_w_ = gen_h_ = frame_counter_ = 0;
    last_buf_ = -1;
    signal_mode_ = SignalMode::kImmediate;
    pending_signals_.clear();
  }

  void SetSignalMode(SignalMode mode) {
    std::lock_guard<std::mutex> lock(mu_);
    signal_mode_ = mode;
  }

  /// Signals every pending timeline value, oldest first; returns how many.
  int SignalPending() {
    std::lock_guard<std::mutex> lock(mu_);
    return SignalLocked();
  }

  /// Result of mpv_render_context_create for one API type (and Vulkan
  /// renderer name, or nullptr for any). Default: success.
  void SetCreateResult(const char* api, const char* renderer, int err) {
    std::lock_guard<std::mutex> lock(mu_);
    create_results_[CreateKey(api, renderer)] = err;
  }

  /// What mpv_render_context_get_info(VULKAN_RENDERER) reports.
  void SetInfoRenderer(const char* name, int err) {
    std::lock_guard<std::mutex> lock(mu_);
    info_name_ = name ? name : "";
    info_err_ = err;
  }

  /// Results of the next non-skip renders, consumed in order; afterwards
  /// SetDefaultRenderResult applies.
  void SetRenderResults(std::vector<int> results) {
    std::lock_guard<std::mutex> lock(mu_);
    render_results_ = std::move(results);
  }

  void SetDefaultRenderResult(int err) {
    std::lock_guard<std::mutex> lock(mu_);
    default_render_result_ = err;
  }

  /// The next `n` mpv_render_context_update calls report
  /// MPV_RENDER_UPDATE_FRAME (mpv has a new frame).
  void QueueFrames(int n) {
    std::lock_guard<std::mutex> lock(mu_);
    queued_frames_ += n;
  }

  /// While set, each non-skip render blocks inside the fake (after writing
  /// its pixels) until cleared — the window in which the renderer has
  /// reallocated but not yet published. Bounded by kWaitTimeout.
  void HoldRenders(bool hold) {
    {
      std::lock_guard<std::mutex> lock(mu_);
      hold_ = hold;
    }
    cv_.notify_all();
  }

  void WaitRenderHeld() {
    WaitUntil(kWaitTimeout, "render to be held", [&] { return held_; });
  }

  /// Calls mpv's update callback as mpv would on a new frame. Returns the
  /// poke sequence number for WaitPokeSeen, or 0 without a callback.
  uint64_t Poke() {
    mpv_render_update_fn fn;
    void* ctx;
    uint64_t seq;
    {
      std::lock_guard<std::mutex> lock(mu_);
      if (!callback_) return 0;
      fn = callback_;
      ctx = callback_ctx_;
      // Incremented before the callback: an update that observes `seq`
      // therefore runs after this Poke started.
      seq = ++poke_seq_;
    }
    // Outside our lock: the callback takes the renderer's lock.
    fn(ctx);
    return seq;
  }

  /// Barrier: returns once mpv_render_context_update observed poke `seq`.
  /// The renderer calls update at the top of each loop iteration, so every
  /// iteration that started before the poke — its renders, swaps and events
  /// — has completed. Swaps reported by AcquireFront calls made before the
  /// poke are synchronous and complete as well.
  void WaitPokeSeen(uint64_t seq) {
    WaitUntil(kWaitTimeout, "render loop to observe poke " + std::to_string(seq),
              [&] { return seen_seq_ >= seq; });
  }

  /// Waits until `n` non-skip renders have been entered.
  void WaitRenders(int n, Ms timeout = kWaitTimeout) {
    WaitUntil(timeout, std::to_string(n) + " non-skip renders",
              [&] { return counters_.renders - counters_.skips >= n; });
  }

  void WaitSkips(int n) {
    WaitUntil(kWaitTimeout, std::to_string(n) + " skipped renders",
              [&] { return counters_.skips >= n; });
  }

  // --- Observations ---

  Counters counters() { return Locked([&] { return counters_; }); }

  /// Entry times of the non-skip renders, in order.
  std::vector<Clock::time_point> render_times() {
    return Locked([&] { return render_times_; });
  }

  std::vector<Call> calls() { return Locked([&] { return calls_; }); }

  /// API types (and renderer names) passed to render_context_create, in
  /// order, e.g. "sw" or "vulkan/gpu-next,vulkan/gpu,sw".
  std::string creates() {
    std::lock_guard<std::mutex> lock(mu_);
    std::string out;
    for (const std::string& c : creates_) out += (out.empty() ? "" : ",") + c;
    return out.empty() ? "none" : out;
  }

  bool callback_set() { return Locked([&] { return callback_ != nullptr; }); }

  /// Ordinal of the software buffer at `p` within the current generation
  /// (order of first use by a render), or -1 if never rendered into.
  int BufOf(const void* p) {
    std::lock_guard<std::mutex> lock(mu_);
    auto it = buf_ids_.find(p);
    return it == buf_ids_.end() ? -1 : it->second;
  }

  /// Buffer ordinal written by the most recent non-skip software render.
  int last_buf() { return Locked([&] { return last_buf_; }); }

  /// Adds a render-thread line (events go through here).
  void Note(std::string line) {
    {
      std::lock_guard<std::mutex> lock(mu_);
      async_.push_back(std::move(line));
    }
    // WaitNoted may be waiting for exactly this line.
    cv_.notify_all();
  }

  /// Waits until `line` is queued (and not yet drained): for render-thread
  /// lines that no barrier can wait for, e.g. an event raised while the
  /// render thread sits in a timeline wait and cannot observe a poke.
  void WaitNoted(const std::string& line, Ms timeout = kWaitTimeout) {
    WaitUntil(timeout, "line '" + line + "'", [&] {
      return std::find(async_.begin(), async_.end(), line) != async_.end();
    });
  }

  /// Takes the queued render-thread lines. Only meaningful at a barrier.
  std::vector<std::string> DrainAsync() {
    std::lock_guard<std::mutex> lock(mu_);
    std::vector<std::string> out = std::move(async_);
    async_.clear();
    return out;
  }

  // --- Fake libmpv entry points (see MakeApi) ---

  int Create(mpv_render_context** out, mpv_handle* handle,
             mpv_render_param* params) {
    std::lock_guard<std::mutex> lock(mu_);
    Record("render_context_create");
    const char* api = static_cast<const char*>(
        FindParam(params, MPV_RENDER_PARAM_API_TYPE));
    const char* renderer = static_cast<const char*>(
        FindParam(params, MPV_RENDER_PARAM_VULKAN_RENDERER));
    std::string what = api ? api : "(no api type)";
    if (renderer) what += std::string("/") + renderer;
    if (handle != FakeHandle()) what += " (foreign handle)";
    creates_.push_back(what);
    int err = 0;
    auto it = create_results_.find(CreateKey(api, renderer));
    if (it == create_results_.end())
      it = create_results_.find(CreateKey(api, nullptr));
    if (it != create_results_.end()) err = it->second;
    if (err >= 0) {
      *out = FakeContext();
      counters_.creates++;
    }
    return err;
  }

  void SetUpdateCallback(mpv_render_context* ctx, mpv_render_update_fn fn,
                         void* cb_ctx) {
    std::lock_guard<std::mutex> lock(mu_);
    Record("render_context_set_update_callback", ctx);
    callback_ = fn;
    callback_ctx_ = cb_ctx;
  }

  uint64_t Update(mpv_render_context* ctx) {
    uint64_t flags = 0;
    {
      std::lock_guard<std::mutex> lock(mu_);
      Record("render_context_update", ctx);
      counters_.updates++;
      seen_seq_ = poke_seq_;
      if (queued_frames_ > 0) {
        queued_frames_--;
        flags = MPV_RENDER_UPDATE_FRAME;
      }
    }
    cv_.notify_all();
    return flags;
  }

  int Render(mpv_render_context* ctx, mpv_render_param* params) {
    std::unique_lock<std::mutex> lock(mu_);
    Record("render_context_render", ctx);
    counters_.renders++;
    const int* skip = static_cast<const int*>(
        FindParam(params, MPV_RENDER_PARAM_SKIP_RENDERING));
    if (skip && *skip) {
      counters_.skips++;
      async_.push_back("render skip");
      lock.unlock();
      cv_.notify_all();
      return 0;
    }
    render_times_.push_back(Clock::now());
    const auto* vk = static_cast<const mpv_vulkan_image*>(
        FindParam(params, MPV_RENDER_PARAM_VULKAN_IMAGE));
    const int err = vk ? VulkanTarget(*vk) : SoftwareTarget(params);
    // Hold after the pixels are written: the renderer has reallocated (on a
    // resize) but cannot publish until the render call returns.
    if (hold_) {
      held_ = true;
      cv_.notify_all();
      cv_.wait_for(lock, kWaitTimeout, [&] { return !hold_; });
      held_ = false;
    }
    lock.unlock();
    cv_.notify_all();
    return err;
  }

  void ReportSwap(mpv_render_context* ctx) {
    {
      std::lock_guard<std::mutex> lock(mu_);
      Record("render_context_report_swap", ctx);
      counters_.swaps++;
    }
    cv_.notify_all();
  }

  void Free(mpv_render_context* ctx) {
    std::lock_guard<std::mutex> lock(mu_);
    Record("render_context_free", ctx);
    counters_.frees++;
  }

  int GetInfo(mpv_render_context* ctx, mpv_render_param param) {
    std::lock_guard<std::mutex> lock(mu_);
    Record("render_context_get_info", ctx);
    if (!IsParam(param, MPV_RENDER_PARAM_VULKAN_RENDERER))
      return MPV_ERROR_NOT_IMPLEMENTED;
    if (info_err_ < 0) return info_err_;
    // info_name_ lives until the next Reset(), as mpv's string lives as long
    // as its render context.
    *static_cast<const char**>(param.data) = info_name_.c_str();
    return 0;
  }

  int SetParameter(mpv_render_context* ctx, mpv_render_param param) {
    std::lock_guard<std::mutex> lock(mu_);
    Record("render_context_set_parameter", ctx);
    if (!IsParam(param, MPV_RENDER_PARAM_ICC_PROFILE)) {
      async_.push_back("set_parameter type=" + std::to_string(ParamType(param)));
      return 0;
    }
    // mpv copies the profile during the call; read it here, not later.
    const auto* data = static_cast<const mpv_byte_array*>(param.data);
    std::string line = "icc size=" + std::to_string(data ? data->size : 0);
    if (!data || !data->data) {
      line += " data=none";
    } else {
      static const char kHex[] = "0123456789abcdef";
      line += " data=";
      const auto* bytes = static_cast<const uint8_t*>(data->data);
      for (size_t i = 0; i < data->size; i++) {
        line += kHex[bytes[i] >> 4];
        line += kHex[bytes[i] & 15];
      }
    }
    async_.push_back(line);
    return 0;
  }

  /// Fixed text per error code, standing in for mpv_error_string.
  static const char* ErrorString(int err) {
    // Built once; the pointers stay valid for the whole process.
    static const std::vector<std::string> names = [] {
      std::vector<std::string> v;
      for (int i = 0; i <= 20; i++) v.push_back("fake error " + std::to_string(-i));
      return v;
    }();
    if (err > 0 || err < -20) return "fake error (unknown)";
    return names[static_cast<size_t>(-err)].c_str();
  }

 private:
  // Explicit return type: the members above use it before its definition.
  template <typename F>
  auto Locked(F f) -> decltype(f()) {
    std::lock_guard<std::mutex> lock(mu_);
    return f();
  }

  template <typename Pred>
  void WaitUntil(Ms timeout, const std::string& what, Pred pred) {
    std::unique_lock<std::mutex> lock(mu_);
    if (!cv_.wait_for(lock, timeout, pred)) throw TimeoutError(what);
  }

  static std::string CreateKey(const char* api, const char* renderer) {
    return std::string(api ? api : "") + "/" + (renderer ? renderer : "");
  }

  void Record(const char* what, mpv_render_context* ctx = FakeContext()) {
    calls_.push_back({ctx == FakeContext() ? what
                                           : std::string(what) + " (bad ctx)",
                      std::this_thread::get_id()});
  }

  // Software target: validates the SW_* parameters, maps the buffer to a
  // per-generation ordinal and writes an incrementing frame number into the
  // first pixel's colour bytes (0..2; byte 3 is the padding byte the
  // renderer overwrites with 0xff). Called with mu_ held.
  int SoftwareTarget(mpv_render_param* params) {
    const int* size =
        static_cast<const int*>(FindParam(params, MPV_RENDER_PARAM_SW_SIZE));
    const char* format = static_cast<const char*>(
        FindParam(params, MPV_RENDER_PARAM_SW_FORMAT));
    const size_t* stride = static_cast<const size_t*>(
        FindParam(params, MPV_RENDER_PARAM_SW_STRIDE));
    auto* pixels =
        static_cast<uint8_t*>(FindParam(params, MPV_RENDER_PARAM_SW_POINTER));
    if (!size || !format || !stride || !pixels || size[0] <= 0 ||
        size[1] <= 0 || *stride != size_t(size[0]) * 4 ||
        (std::strcmp(format, "rgb0") != 0 && std::strcmp(format, "bgr0") != 0)) {
      async_.push_back("render invalid-sw-params");
      return MPV_ERROR_INVALID_PARAMETER;
    }
    if (size[0] != gen_w_ || size[1] != gen_h_) {
      // New generation: the ring was reallocated at a new size.
      buf_ids_.clear();
      gen_w_ = size[0];
      gen_h_ = size[1];
    }
    auto it = buf_ids_.find(pixels);
    if (it == buf_ids_.end())
      it = buf_ids_.emplace(pixels, static_cast<int>(buf_ids_.size())).first;
    last_buf_ = it->second;
    const int err = TakeRenderResult();
    std::string line = "render buf=" + std::to_string(last_buf_);
    if (err >= 0) {
      const int frame = ++frame_counter_;
      pixels[0] = static_cast<uint8_t>(frame);
      pixels[1] = static_cast<uint8_t>(frame >> 8);
      pixels[2] = static_cast<uint8_t>(frame >> 16);
      line += " frame=" + std::to_string(frame);
    }
    line += " " + std::to_string(size[0]) + "x" + std::to_string(size[1]) +
            " " + format;
    if (err < 0) line += " err=" + std::to_string(err);
    async_.push_back(line);
    return err;
  }

  /// Scripted result of the next non-skip render. Called with mu_ held.
  int TakeRenderResult() {
    if (render_results_.empty()) return default_render_result_;
    const int err = render_results_.front();
    render_results_.erase(render_results_.begin());
    return err;
  }

  // Vulkan target: must be a live FakeVulkanInterop image of the announced
  // size. A successful render queues its timeline value, which "completes
  // the GPU work" when signalled (SignalMode). Called with mu_ held.
  int VulkanTarget(const mpv_vulkan_image& image) {
    const std::string size =
        std::to_string(image.width) + "x" + std::to_string(image.height);
    const FakeImage e = Images().FindLive(image.image);
    if (e.serial == 0 || e.width != image.width || e.height != image.height) {
      async_.push_back("render vulkan-image " + size + " unknown");
      return MPV_ERROR_INVALID_PARAMETER;
    }
    const int err = TakeRenderResult();
    std::string line = "render serial=" + std::to_string(e.serial) + " " + size;
    if (err < 0) line += " err=" + std::to_string(err);
    async_.push_back(line);
    if (err >= 0 && image.signal_semaphore) {
      pending_signals_.emplace_back(image.signal_semaphore, image.signal_value);
      if (signal_mode_ == SignalMode::kImmediate) SignalLocked();
    }
    return err;
  }

  // Timeline values only move forward: a value at or below the counter (a
  // later one was signalled first) is already complete. Called with mu_
  // held.
  int SignalLocked() {
    const VkDevice device = Images().device();
    int n = 0;
    for (const auto& pending : pending_signals_) {
      uint64_t current = 0;
      vkGetSemaphoreCounterValue(device, pending.first, &current);
      if (pending.second <= current) continue;
      VkSemaphoreSignalInfo si{};
      si.sType = VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO;
      si.semaphore = pending.first;
      si.value = pending.second;
      vkSignalSemaphore(device, &si);
      n++;
    }
    pending_signals_.clear();
    return n;
  }

  std::mutex mu_;
  std::condition_variable cv_;
  std::map<std::string, int> create_results_;
  std::string info_name_ = "gpu-next";
  int info_err_ = 0;
  std::vector<int> render_results_;
  int default_render_result_ = 0;
  int queued_frames_ = 0;
  bool hold_ = false;
  bool held_ = false;
  mpv_render_update_fn callback_ = nullptr;
  void* callback_ctx_ = nullptr;
  uint64_t poke_seq_ = 0;
  uint64_t seen_seq_ = 0;
  Counters counters_;
  std::vector<Call> calls_;
  std::vector<std::string> creates_;
  std::vector<std::string> async_;
  std::vector<Clock::time_point> render_times_;
  std::map<const void*, int> buf_ids_;
  int gen_w_ = 0, gen_h_ = 0;
  int last_buf_ = -1;
  int frame_counter_ = 0;
  SignalMode signal_mode_ = SignalMode::kImmediate;
  std::vector<std::pair<VkSemaphore, uint64_t>> pending_signals_;
};

inline FakeMpv& Fake() {
  static FakeMpv fake;
  return fake;
}

// --- MakeApi -----------------------------------------------------------------

/// The renderer's libmpv function table, bound to Fake(). Captureless
/// lambdas convert to the plain function pointers MpvApi holds.
inline mpv_kit::MpvApi MakeApi() {
  mpv_kit::MpvApi api;
  api.render_context_create = [](mpv_render_context** out, mpv_handle* handle,
                                 mpv_render_param* params) {
    return Fake().Create(out, handle, params);
  };
  api.render_context_set_update_callback =
      [](mpv_render_context* ctx, mpv_render_update_fn fn, void* cb_ctx) {
        Fake().SetUpdateCallback(ctx, fn, cb_ctx);
      };
  api.render_context_update = [](mpv_render_context* ctx) {
    return Fake().Update(ctx);
  };
  api.render_context_render = [](mpv_render_context* ctx,
                                 mpv_render_param* params) {
    return Fake().Render(ctx, params);
  };
  api.render_context_report_swap = [](mpv_render_context* ctx) {
    Fake().ReportSwap(ctx);
  };
  api.render_context_free = [](mpv_render_context* ctx) { Fake().Free(ctx); };
  api.error_string = &FakeMpv::ErrorString;
  api.render_context_get_info = [](mpv_render_context* ctx,
                                   mpv_render_param param) {
    return Fake().GetInfo(ctx, param);
  };
  api.render_context_set_parameter = [](mpv_render_context* ctx,
                                        mpv_render_param param) {
    return Fake().SetParameter(ctx, param);
  };
  return api;
}

// --- FakeInterop -------------------------------------------------------------

/// Platform seam with scripted answers; counts what the renderer asks of it.
class FakeInterop : public mpv_kit::Interop {
 public:
  FakeInterop(int latency, bool bgra, const char* interop_reason,
              mpv_kit::VulkanInterop* vk = nullptr)
      : latency_(latency), bgra_(bgra), reason_(interop_reason), vk_(vk) {}

  mpv_kit::VulkanInterop* vulkan() override { return vk_; }
  const char* interopReason() const override { return reason_; }
  bool SoftwareIsBgra() const override { return bgra_; }
  int CompositorLatency() const override { return latency_; }

  void FrameReady() override {
    {
      std::lock_guard<std::mutex> lock(mu_);
      frame_ready_++;
    }
    cv_.notify_all();
  }

  void RetainFrame(void* platform) override {
    // Vulkan path: the compositor would now reference the platform object.
    const FakeImage e = Images().Entry(platform);
    if (e.serial != 0 && e.destroyed)
      Images().Violation("USE AFTER DESTROY serial=" +
                         std::to_string(e.serial) + " (RetainFrame)");
    std::lock_guard<std::mutex> lock(mu_);
    retains_++;
  }

  int frame_ready() const {
    std::lock_guard<std::mutex> lock(mu_);
    return frame_ready_;
  }

  int retains() const {
    std::lock_guard<std::mutex> lock(mu_);
    return retains_;
  }

  /// Waits until FrameReady() has been called `n` times in total.
  void WaitFrameReady(int n, Ms timeout = kWaitTimeout) {
    std::unique_lock<std::mutex> lock(mu_);
    if (!cv_.wait_for(lock, timeout, [&] { return frame_ready_ >= n; }))
      throw TimeoutError("FrameReady #" + std::to_string(n));
  }

 private:
  const int latency_;
  const bool bgra_;
  const char* const reason_;
  mpv_kit::VulkanInterop* const vk_;
  mutable std::mutex mu_;
  std::condition_variable cv_;
  int frame_ready_ = 0;
  int retains_ = 0;
};

// --- FakeVulkanInterop -------------------------------------------------------

/// Vulkan platform seam with no compositor behind it: the system loader,
/// no extra extensions, and plain device-local B8G8R8A8 images. Every
/// CreateImage/DestroyImage is a render-thread (or teardown) trace line.
class FakeVulkanInterop : public mpv_kit::VulkanInterop {
 public:
  explicit FakeVulkanInterop(bool accept_device = true)
      : accept_(accept_device) {}

  std::vector<const char*> InstanceExtensions() const override { return {}; }
  std::vector<const char*> DeviceExtensions() const override { return {}; }

  bool AcceptDevice(VkPhysicalDevice device) override {
    if (!accept_) return false;
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(device, &props);
    std::lock_guard<std::mutex> lock(mu_);
    names_.emplace_back(props.deviceName);
    return true;
  }

  /// The `k`-th CreateImage from now (1 = the next one) fails, once.
  void FailCreate(int k) {
    std::lock_guard<std::mutex> lock(mu_);
    fail_in_ = k;
  }

  /// Names of the devices accepted so far (for NormalizeReason).
  std::vector<std::string> device_names() const {
    std::lock_guard<std::mutex> lock(mu_);
    return names_;
  }

  bool CreateImage(VkPhysicalDevice pd, VkDevice dev, int width, int height,
                   mpv_kit::SharedImage* out) override {
    const std::string size =
        std::to_string(width) + "x" + std::to_string(height);
    {
      std::lock_guard<std::mutex> lock(mu_);
      if (fail_in_ > 0 && --fail_in_ == 0) {
        Fake().Note("create failed " + size);
        return false;
      }
    }
    Images().SetDevice(dev);
    VkImageCreateInfo ici{};
    ici.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = VK_FORMAT_B8G8R8A8_UNORM;
    ici.extent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height),
                  1};
    ici.mipLevels = ici.arrayLayers = 1;
    ici.samples = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = mpv_kit::kSharedImageUsage;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkImage image = VK_NULL_HANDLE;
    if (vkCreateImage(dev, &ici, nullptr, &image) != VK_SUCCESS) {
      Fake().Note("create vkCreateImage-failed " + size);
      return false;
    }
    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(dev, image, &req);
    VkMemoryAllocateInfo mai{};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize = req.size;
    mai.memoryTypeIndex = DeviceLocalType(pd, req.memoryTypeBits);
    VkDeviceMemory memory = VK_NULL_HANDLE;
    if (vkAllocateMemory(dev, &mai, nullptr, &memory) != VK_SUCCESS ||
        vkBindImageMemory(dev, image, memory, 0) != VK_SUCCESS) {
      if (memory) vkFreeMemory(dev, memory, nullptr);
      vkDestroyImage(dev, image, nullptr);
      Fake().Note("create memory-failed " + size);
      return false;
    }
    out->image = image;
    out->memory = memory;
    out->format = ici.format;
    out->width = width;
    out->height = height;
    out->platform = Images().Add(width, height, image);
    Fake().Note("create serial=" +
                std::to_string(Images().Entry(out->platform).serial) + " " +
                size);
    return true;
  }

  void DestroyImage(VkDevice dev, mpv_kit::SharedImage* img) override {
    const FakeImage e = Images().Entry(img->platform);
    if (e.serial == 0) {
      Fake().Note("destroy unknown-image");
      Images().Violation("destroy of an image FakeVulkanInterop never created");
    } else if (!Images().MarkDestroyed(img->platform)) {
      // The handles are already gone: no second driver call.
      const std::string what =
          "DOUBLE DESTROY serial=" + std::to_string(e.serial);
      Fake().Note(what);
      Images().Violation(what);
    } else {
      vkDestroyImage(dev, img->image, nullptr);
      vkFreeMemory(dev, img->memory, nullptr);
      Fake().Note("destroy serial=" + std::to_string(e.serial));
    }
    *img = mpv_kit::SharedImage{};
  }

 private:
  static uint32_t DeviceLocalType(VkPhysicalDevice pd, uint32_t bits) {
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(pd, &mp);
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
      if ((bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags &
                                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
        return i;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
      if (bits & (1u << i)) return i;  // a UMA driver without the flag
    return 0;
  }

  const bool accept_;
  mutable std::mutex mu_;
  std::vector<std::string> names_;
  int fail_in_ = 0;
};

// --- Trace and golden files --------------------------------------------------

/// Expected or actual lines of one scenario.
class Trace {
 public:
  void Add(std::string line) { lines_.push_back(std::move(line)); }
  void Add(const std::vector<std::string>& lines) {
    lines_.insert(lines_.end(), lines.begin(), lines.end());
  }
  const std::vector<std::string>& lines() const { return lines_; }

 private:
  std::vector<std::string> lines_;
};

/// Golden file contents: scenarios in file order.
using Golden = std::vector<std::pair<std::string, std::vector<std::string>>>;

/// Parses a golden file: `[scenario]` headers, one expected line per line.
/// Blank lines and lines starting with '#' are comments. Read-only.
inline bool LoadGolden(const std::string& path, Golden* out,
                       std::string* error) {
  std::ifstream in(path);
  if (!in) {
    *error = "cannot open golden file " + path;
    return false;
  }
  out->clear();
  std::string line;
  int number = 0;
  while (std::getline(in, line)) {
    number++;
    // Tolerate CRLF checkouts.
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty() || line[0] == '#') continue;
    if (line.front() == '[' && line.back() == ']') {
      out->emplace_back(line.substr(1, line.size() - 2),
                        std::vector<std::string>{});
      continue;
    }
    if (out->empty()) {
      *error = path + ":" + std::to_string(number) +
               ": expectation before the first [scenario]";
      return false;
    }
    out->back().second.push_back(line);
  }
  return true;
}

/// Expected lines of `scenario`, or nullptr if the golden has no section.
inline const std::vector<std::string>* FindScenario(const Golden& golden,
                                                    const std::string& name) {
  for (const auto& s : golden)
    if (s.first == name) return &s.second;
  return nullptr;
}

/// First expected line of `scenario` starting with `prefix`, or "".
inline std::string ExpectedLine(const Golden& golden,
                                const std::string& scenario,
                                const std::string& prefix) {
  if (const auto* lines = FindScenario(golden, scenario))
    for (const std::string& l : *lines)
      if (l.compare(0, prefix.size(), prefix) == 0) return l;
  return "";
}

/// Compares actual traces with the golden, line by line and exactly.
/// Missing, extra or differing scenarios/lines are reported as
/// `GOLDEN mismatch scenario=<s> line=<k>` plus expected/actual; the full
/// actual trace of a mismatching scenario follows so CI logs show it.
/// Returns 0 on a full match, 1 otherwise. Never writes any file.
inline int CompareGolden(const Golden& expected, const Golden& actual) {
  int rc = 0;
  auto dump = [](const std::string& name, const std::vector<std::string>& l) {
    std::fprintf(stderr, "  actual trace of [%s]:\n", name.c_str());
    for (const std::string& line : l)
      std::fprintf(stderr, "    %s\n", line.c_str());
  };
  for (const auto& a : actual) {
    const auto* want = FindScenario(expected, a.first);
    if (!want) {
      std::printf("GOLDEN mismatch scenario=%s line=0\n  expected: (no section)\n"
                  "  actual:   %zu line(s)\n",
                  a.first.c_str(), a.second.size());
      dump(a.first, a.second);
      rc = 1;
      continue;
    }
    const size_t n = std::max(want->size(), a.second.size());
    for (size_t k = 0; k < n; k++) {
      const char* e = k < want->size() ? (*want)[k].c_str() : "(end of section)";
      const char* g = k < a.second.size() ? a.second[k].c_str() : "(end of trace)";
      if (std::strcmp(e, g) == 0) continue;
      std::printf("GOLDEN mismatch scenario=%s line=%zu\n  expected: %s\n"
                  "  actual:   %s\n",
                  a.first.c_str(), k + 1, e, g);
      dump(a.first, a.second);
      rc = 1;
      break;
    }
  }
  for (const auto& e : expected) {
    if (FindScenario(actual, e.first)) continue;
    std::printf("GOLDEN mismatch scenario=%s line=0\n  expected: %zu line(s)\n"
                "  actual:   (scenario not run)\n",
                e.first.c_str(), e.second.size());
    rc = 1;
  }
  return rc;
}

/// Convenience overload: loads the golden at `path` first.
inline int CompareGolden(const std::string& path, const Golden& actual) {
  Golden expected;
  std::string error;
  if (!LoadGolden(path, &expected, &error)) {
    std::printf("GOLDEN error: %s\n", error.c_str());
    return 1;
  }
  return CompareGolden(expected, actual);
}

// --- Invariants and helpers --------------------------------------------------

/// vo_libmpv expects one swap per frame: once the renderer is quiet, every
/// render call (including SKIP_RENDERING and failed ones) has been answered
/// by exactly one mpv_render_context_report_swap.
inline bool CheckSwapInvariant() {
  const Counters c = Fake().counters();
  return c.swaps == c.renders;
}

/// Sets (value != nullptr) or removes an environment variable.
inline void SetEnv(const char* name, const char* value) {
#ifdef _WIN32
  _putenv_s(name, value ? value : "");
#else
  if (value)
    setenv(name, value, 1);
  else
    unsetenv(name);
#endif
}

/// Replaces every occurrence of the GPU device name in a backend reason with
/// `<device>`, so a golden line does not depend on the runner's driver.
inline std::string NormalizeReason(std::string reason,
                                   const std::string& device) {
  if (device.empty()) return reason;
  for (size_t at = reason.find(device); at != std::string::npos;
       at = reason.find(device, at + 8))
    reason.replace(at, device.size(), "<device>");
  return reason;
}

}  // namespace golden
