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
//
// Exit codes of the golden binaries: 0 pass, 1 mismatch, invariant
// violation, timeout or usage error.
#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
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
  int renders = 0;
  int skips = 0;
  int swaps = 0;
  int frees = 0;
  int creates = 0;
  int updates = 0;
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
  std::underlying_type_t<mpv_render_param_type> want;
  std::memcpy(&want, &type, sizeof want);
  return ParamType(p) == want;
}

/// Data of the first parameter of `type` in an INVALID-terminated list.
inline void* FindParam(mpv_render_param* params, mpv_render_param_type type) {
  for (mpv_render_param* p = params; p && ParamType(*p) != 0; p++)
    if (IsParam(*p, type)) return p->data;
  return nullptr;
}

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
    info_err_ = 0;
    render_results_.clear();
    default_render_result_ = 0;
    queued_frames_ = 0;
    hold_ = false;
    held_ = false;
    callback_ = nullptr;
    callback_ctx_ = nullptr;
    poke_seq_ = 0;
    seen_seq_ = 0;
    counters_ = Counters{};
    calls_.clear();
    creates_.clear();
    async_.clear();
    render_times_.clear();
    buf_ids_.clear();
    gen_w_ = gen_h_ = 0;
    last_buf_ = -1;
    frame_counter_ = 0;
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
    std::unique_lock<std::mutex> lock(mu_);
    if (!cv_.wait_for(lock, kWaitTimeout, [&] { return held_; }))
      throw TimeoutError("render to be held");
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
    std::unique_lock<std::mutex> lock(mu_);
    if (!cv_.wait_for(lock, kWaitTimeout, [&] { return seen_seq_ >= seq; }))
      throw TimeoutError("render loop to observe poke " + std::to_string(seq));
  }

  /// Waits until `n` non-skip renders have been entered.
  void WaitRenders(int n, Ms timeout = kWaitTimeout) {
    std::unique_lock<std::mutex> lock(mu_);
    if (!cv_.wait_for(lock, timeout, [&] {
          return counters_.renders - counters_.skips >= n;
        }))
      throw TimeoutError(std::to_string(n) + " non-skip renders");
  }

  void WaitSkips(int n) {
    std::unique_lock<std::mutex> lock(mu_);
    if (!cv_.wait_for(lock, kWaitTimeout,
                      [&] { return counters_.skips >= n; }))
      throw TimeoutError(std::to_string(n) + " skipped renders");
  }

  // --- Observations ---

  Counters counters() {
    std::lock_guard<std::mutex> lock(mu_);
    return counters_;
  }

  /// Entry times of the non-skip renders, in order.
  std::vector<Clock::time_point> render_times() {
    std::lock_guard<std::mutex> lock(mu_);
    return render_times_;
  }

  std::vector<Call> calls() {
    std::lock_guard<std::mutex> lock(mu_);
    return calls_;
  }

  /// API types (and renderer names) passed to render_context_create, in
  /// order, e.g. "sw" or "vulkan/gpu-next,vulkan/gpu,sw".
  std::string creates() {
    std::lock_guard<std::mutex> lock(mu_);
    std::string out;
    for (const std::string& c : creates_) out += (out.empty() ? "" : ",") + c;
    return out.empty() ? "none" : out;
  }

  bool callback_set() {
    std::lock_guard<std::mutex> lock(mu_);
    return callback_ != nullptr;
  }

  /// Ordinal of the software buffer at `p` within the current generation
  /// (order of first use by a render), or -1 if never rendered into.
  int BufOf(const void* p) {
    std::lock_guard<std::mutex> lock(mu_);
    auto it = buf_ids_.find(p);
    return it == buf_ids_.end() ? -1 : it->second;
  }

  /// Buffer ordinal written by the most recent non-skip software render.
  int last_buf() {
    std::lock_guard<std::mutex> lock(mu_);
    return last_buf_;
  }

  /// Adds a render-thread line (events go through here).
  void Note(std::string line) {
    std::lock_guard<std::mutex> lock(mu_);
    async_.push_back(std::move(line));
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
    if (auto* vk = static_cast<const mpv_vulkan_image*>(
            FindParam(params, MPV_RENDER_PARAM_VULKAN_IMAGE))) {
      const int err = VulkanTarget(*vk);
      lock.unlock();
      cv_.notify_all();
      return err;
    }
    const int err = SoftwareTarget(params);
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
    int err = default_render_result_;
    if (!render_results_.empty()) {
      err = render_results_.front();
      render_results_.erase(render_results_.begin());
    }
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

  // Vulkan target entry point, reserved for the Vulkan golden (12-07),
  // which renders into the real shared images. The software golden never
  // reaches it; if it does, the trace shows it and the render fails.
  int VulkanTarget(const mpv_vulkan_image& image) {
    async_.push_back("render vulkan-image " + std::to_string(image.width) +
                     "x" + std::to_string(image.height) + " unsupported");
    return MPV_ERROR_NOT_IMPLEMENTED;
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
};

inline FakeMpv& Fake() {
  static FakeMpv fake;
  return fake;
}

// --- MakeApi -----------------------------------------------------------------

namespace detail {
inline int Create(mpv_render_context** out, mpv_handle* handle,
                  mpv_render_param* params) {
  return Fake().Create(out, handle, params);
}
inline void SetUpdateCallback(mpv_render_context* ctx, mpv_render_update_fn fn,
                              void* cb_ctx) {
  Fake().SetUpdateCallback(ctx, fn, cb_ctx);
}
inline uint64_t Update(mpv_render_context* ctx) { return Fake().Update(ctx); }
inline int Render(mpv_render_context* ctx, mpv_render_param* params) {
  return Fake().Render(ctx, params);
}
inline void ReportSwap(mpv_render_context* ctx) { Fake().ReportSwap(ctx); }
inline void Free(mpv_render_context* ctx) { Fake().Free(ctx); }
inline const char* ErrorString(int err) { return FakeMpv::ErrorString(err); }
inline int GetInfo(mpv_render_context* ctx, mpv_render_param param) {
  return Fake().GetInfo(ctx, param);
}
inline int SetParameter(mpv_render_context* ctx, mpv_render_param param) {
  return Fake().SetParameter(ctx, param);
}
}  // namespace detail

/// The renderer's libmpv function table, bound to Fake().
inline mpv_kit::MpvApi MakeApi() {
  mpv_kit::MpvApi api;
  api.render_context_create = &detail::Create;
  api.render_context_set_update_callback = &detail::SetUpdateCallback;
  api.render_context_update = &detail::Update;
  api.render_context_render = &detail::Render;
  api.render_context_report_swap = &detail::ReportSwap;
  api.render_context_free = &detail::Free;
  api.error_string = &detail::ErrorString;
  api.render_context_get_info = &detail::GetInfo;
  api.render_context_set_parameter = &detail::SetParameter;
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
    (void)platform;
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
