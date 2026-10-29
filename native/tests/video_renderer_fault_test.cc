// Golden test of the engine's fallback chain and fault events under injected
// faults (Phase 17, VER-01): drives the real packages/mpv_kit_video/src/
// video_renderer.cc through the fake libmpv of renderer_harness.h, with an
// Interop that supplies fake "d3d11" and "vulkan" RenderBackends (the seam
// Interop::CreateBackend) whose devices, target allocations and publish-gate
// waits fail on command, and compares what VideoRenderer::Start and the
// render thread do with golden/fault.txt.
//
// What it proves, without any GPU, driver or libmpv, for three fault classes:
//   * device lost
//       - while creating: the failing api leaves one trail per candidate and
//         the auto chain moves on to the next api; when every GPU candidate
//         fails the winner is software and its reason lists the whole chain
//         in order (create-* scenarios);
//       - while rendering: exactly one device_lost event, nothing is drawn
//         afterwards (skips only), and a renderer created again while the
//         device is still gone takes the next candidate of the chain;
//   * GPU timeout storm: gpu_timeout is raised on failures 1, 2 and 4 only,
//     every retry waits at least its backoff (100 ms doubling), the backoff
//     is capped at 5 s, and recovery raises exactly one `recovered`;
//   * target allocation failure: the full ring and then the fallback ring are
//     tried, one render_error carries the backend's reason, the frame is
//     skipped, the retry comes after the backoff or at once on a resize, and
//     `recovered` follows.
//   Allocation faults and timeouts do NOT advance the chain: the chain is
//   walked only by Start (see runtime-alloc-fails-persist-recreate-same-
//   backend). A running controller never switches backend (RBE-F1); that is
//   the boundary this test pins, not a fallback it claims.
//
// Why a new file: the Phase 12/14 goldens, their expectations and the harness
// are frozen (evidence/golden-freeze*.sha256); the harness is only used
// read-only here. The faults are injected in fake backends that render
// through the software parameters of the fake libmpv into CPU buffers;
// "d3d11" and "vulkan" are only their wire names, so reasons and trails have
// the shape of the real ones. Nothing here exercises a real driver.
//
// usage: video_renderer_fault_test <golden/fault.txt> [--slack-ms=N]
//
// Output: `GOLDEN ok scenarios=<n>` on success; otherwise one
// `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure. The golden file is only read.

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "renderer_harness.h"

namespace {

using golden::Clock;
using golden::Fake;
using golden::FakeInterop;
using golden::Ms;
using mpv_kit::BackendCandidate;
using mpv_kit::MpvApi;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Any mpv error code: the fake returns it from the failing creates.
constexpr int kCreateError = MPV_ERROR_UNSUPPORTED;
// Why the fake d3d11 device is gone (DXGI_ERROR_DEVICE_REMOVED).
constexpr const char* kD3d11RemovedWhy =
    "d3d11 device removed during initialisation: 0x887A0005 (injected)";
// Fake target sizes; small, the fake never looks at the pixels.
constexpr int kWidth = 64;
constexpr int kHeight = 36;
// Windows-like compositor latency: quarantine 4, so the full ring is
// 4 + 2 + kReadyDepth (2) = 8 images and the allocation fallback is 5.
constexpr int kLatency = 4;

// --- Fake GPU backend --------------------------------------------------------

/// What one fake api does; set per scenario. Fault configuration outlives a
/// renderer: a second renderer of the same Platform meets the same fault.
struct ApiConfig {
  std::string device;       // device_name() in the reason head
  std::string device_why;   // non-empty: the device fails to initialise
  int alloc_fail_first = 0;  // the first n AllocTargets calls fail
  int alloc_fail_width = 0;  // > 0: AllocTargets at this width always fails
  int lost_from_gate = 0;    // > 0: the k-th publish gate and later: device lost
  int timeout_gates = 0;     // the first n publish gates time out
};

/// One AllocTargets call, in call order.
struct AllocRecord {
  Clock::time_point at;
  int ring = 0;
  int width = 0;
  int height = 0;
  bool ok = false;
};

/// Per-scenario state shared by the interop and its backends. Written by the
/// test thread before a renderer starts, read (and counted) by the render
/// thread afterwards; the counters are mutex protected.
class Platform {
 public:
  explicit Platform(std::vector<BackendCandidate> chain)
      : chain_(std::move(chain)) {
    apis["d3d11"].device = "fake-d3d11";
    apis["vulkan"].device = "fake-vk";
  }

  const std::vector<BackendCandidate>& chain() const { return chain_; }
  const ApiConfig& Config(const std::string& api) const { return apis.at(api); }

  void CountDeviceInit(const std::string& api) {
    std::lock_guard<std::mutex> lock(mu_);
    device_inits_[api]++;
  }

  int device_inits(const std::string& api) const {
    std::lock_guard<std::mutex> lock(mu_);
    auto it = device_inits_.find(api);
    return it == device_inits_.end() ? 0 : it->second;
  }

  /// Counts one AllocTargets call of [api] at [width] and says whether the
  /// scenario makes it fail. The count spans renderers: "the first two
  /// allocations fail" means the first two of the scenario.
  bool NextAllocFails(const std::string& api, int width) {
    std::lock_guard<std::mutex> lock(mu_);
    const ApiConfig& config = apis.at(api);
    const int call = ++alloc_calls_[api];
    return call <= config.alloc_fail_first ||
           (config.alloc_fail_width > 0 && width == config.alloc_fail_width);
  }

  void RecordAlloc(const AllocRecord& record) {
    std::lock_guard<std::mutex> lock(mu_);
    allocs_.push_back(record);
  }

  std::vector<AllocRecord> allocs() const {
    std::lock_guard<std::mutex> lock(mu_);
    return allocs_;
  }

  /// Waits (bounded) until AllocTargets was called [n] times in total.
  void WaitAllocCalls(size_t n, Ms timeout = golden::kWaitTimeout) const {
    const auto until = Clock::now() + timeout;
    for (;;) {
      if (allocs().size() >= n) return;
      if (Clock::now() > until)
        throw golden::TimeoutError(std::to_string(n) + " AllocTargets calls");
      std::this_thread::sleep_for(Ms(2));
    }
  }

  std::map<std::string, ApiConfig> apis;

 private:
  const std::vector<BackendCandidate> chain_;
  mutable std::mutex mu_;
  std::map<std::string, int> device_inits_;
  std::map<std::string, int> alloc_calls_;
  std::vector<AllocRecord> allocs_;
};

/// A GPU-style RenderBackend (pipelined, shared-image frame class) backed by
/// CPU buffers, with injectable faults: Render uses the fake libmpv's
/// software target, Create asks the fake for a render context of its own api
/// type, so create attempts read `d3d11/gpu-next` as with the real backend.
class FaultBackend final : public mpv_kit::RenderBackend {
 public:
  FaultBackend(Platform* platform, std::string api)
      : platform_(platform), api_(std::move(api)) {}

  const char* wire_name() const override { return api_.c_str(); }
  mpv_kit::Backend frame_kind() const override {
    return mpv_kit::Backend::kVulkan;
  }
  bool pipelined() const override { return true; }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    *out = nullptr;
    if (!device_initialised_) {
      device_initialised_ = true;
      platform_->CountDeviceInit(api_);
      device_error_ = Config().device_why;
    }
    if (!device_error_.empty()) {
      *why = device_error_;
      return MPV_ERROR_GENERIC;  // mpv was not asked (device_failed())
    }
    renderer_ = renderer;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(api_.c_str())},
        {MPV_RENDER_PARAM_VULKAN_RENDERER, const_cast<char*>(renderer)},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_create(out, handle, params);
    if (err < 0) {
      *why = "mpv_render_context_create: " +
             mpv_kit::SanitizeReasonField(api.error_string(err));
      *out = nullptr;
    }
    return err;
  }
  bool device_failed() const override { return !device_error_.empty(); }
  std::string device_name() const override { return Config().device; }
  std::string RendererName(const MpvApi& api,
                           mpv_render_context* ctx) const override {
    (void)api;
    (void)ctx;
    return renderer_;  // the fake mpv builds what was asked for
  }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    (void)keep_slot;
    const bool fail = platform_->NextAllocFails(api_, width);
    platform_->RecordAlloc({Clock::now(), count, width, height, !fail});
    // Render-thread line: it lands in the trace in call order.
    Fake().Note("alloc ring=" + std::to_string(count) + " " +
                std::to_string(width) + "x" + std::to_string(height) +
                (fail ? " fail" : " ok"));
    if (fail) {
      // Like the real backend after a failed attempt: nothing is allocated.
      // The count is in the text so the event shows which attempt it is.
      buffers_.clear();
      *error = "CreateTexture2D failed: 0x8007000E (injected, ring " +
               std::to_string(count) + ")";
      return false;
    }
    // Whole old generation at once: the fake has no compositor behind it.
    buffers_.assign(static_cast<size_t>(count),
                    std::vector<uint8_t>(size_t(width) * height * 4));
    return true;
  }
  void FreeRetired() override {}
  mpv_kit::TargetView FrameFor(int slot) override {
    mpv_kit::TargetView view;
    // A stable non-null platform object per slot (never dereferenced).
    view.platform = buffers_[static_cast<size_t>(slot)].data();
    return view;
  }

  int Render(const MpvApi& api, mpv_render_context* ctx, int slot, int width,
             int height) override {
    int size[2] = {width, height};
    size_t stride = size_t(width) * 4;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char*>("bgr0")},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER,
         buffers_[static_cast<size_t>(slot)].data()},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int err = api.render_context_render(ctx, params);
    // The next Wait is this frame's publish gate.
    publish_gate_next_ = err >= 0;
    return err;
  }
  mpv_kit::WaitResult Wait(int slot) override {
    (void)slot;
    // RenderOnce waits twice per frame: for the slot's previous use before
    // Render, and for the frame itself (the publish gate) right after it.
    // Only the publish gate is made to fail. The previous-use wait takes the
    // same RenderResult path in the engine (a kTimeout there is a failed
    // frame with the same event and backoff), so one injection point covers
    // both.
    if (!publish_gate_next_) return mpv_kit::WaitResult::kOk;
    publish_gate_next_ = false;
    const int gate = ++gates_;
    const ApiConfig& config = Config();
    if (config.lost_from_gate > 0 && gate >= config.lost_from_gate)
      return mpv_kit::WaitResult::kDeviceLost;
    if (gate <= config.timeout_gates) return mpv_kit::WaitResult::kTimeout;
    return mpv_kit::WaitResult::kOk;
  }

  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    api.render_context_free(ctx);
  }

 private:
  const ApiConfig& Config() const { return platform_->Config(api_); }

  Platform* const platform_;
  const std::string api_;
  bool device_initialised_ = false;
  std::string device_error_;
  std::string renderer_;
  bool publish_gate_next_ = false;  // render thread only
  int gates_ = 0;                   // publish gates seen by this instance
  std::vector<std::vector<uint8_t>> buffers_;
};

/// The platform: a scripted candidate chain whose "d3d11" and "vulkan"
/// backends are FaultBackends; software is the engine's own.
class FaultInterop final : public FakeInterop {
 public:
  explicit FaultInterop(Platform* platform)
      : FakeInterop(kLatency, false, nullptr), platform_(platform) {}

  std::vector<BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    (void)choice;  // the scenarios always ask for auto
    return platform_->chain();
  }
  std::unique_ptr<mpv_kit::RenderBackend> CreateBackend(
      const char* api) override {
    const std::string name = api;
    if (name != "d3d11" && name != "vulkan") return nullptr;
    return std::make_unique<FaultBackend>(platform_, name);
  }

 private:
  Platform* const platform_;
};

// --- Scenario context --------------------------------------------------------

/// State of one running scenario: its trace and whether it already failed.
struct Run {
  std::string name;
  int slack_ms;
  golden::Trace trace;
  bool ok = true;

  /// Records an invariant violation; the scenario (and the binary) fails.
  void Invariant(const std::string& what) {
    std::printf("GOLDEN invariant scenario=%s: %s\n", name.c_str(),
                what.c_str());
    ok = false;
  }
};

// Renderer log lines: Start's own lines (failed creates, the Vulkan
// fall-back notice) are deterministic and part of the trace; the render
// thread's lines are diagnostics only and dropped at the next Start.
std::mutex g_log_mu;
std::vector<std::string> g_log;

std::vector<std::string> TakeLog() {
  std::lock_guard<std::mutex> lock(g_log_mu);
  std::vector<std::string> out = std::move(g_log);
  g_log.clear();
  return out;
}

std::unique_ptr<VideoRenderer> MakeRenderer(FakeInterop& interop) {
  return std::make_unique<VideoRenderer>(
      golden::MakeApi(), golden::FakeHandle(), &interop,
      [](const std::string& line) {
        std::lock_guard<std::mutex> lock(g_log_mu);
        g_log.push_back(line);
      },
      [](const char* kind, const std::string& msg) {
        // Render thread: queued with the fake's render lines, in order.
        Fake().Note(msg.empty() ? std::string("event ") + kind
                                : std::string("event ") + kind + " " + msg);
      });
}

/// Start under kAuto: result, winner and reason, the creates it made, the
/// device initialisations per api and every line it logged.
bool Start(Run& run, Platform& platform, VideoRenderer& r) {
  TakeLog();
  const bool ok = r.Start(RendererChoice::kAuto);
  if (ok) {
    run.trace.Add(std::string("start ok backend=") + r.wire_name() +
                  " reason=\"" + r.backend_reason() + "\"");
  } else {
    run.trace.Add("start=false reason=\"" + r.backend_reason() + "\"");
  }
  run.trace.Add("create-attempts " + Fake().creates());
  run.trace.Add("device-inits d3d11=" +
                std::to_string(platform.device_inits("d3d11")) +
                " vulkan=" + std::to_string(platform.device_inits("vulkan")));
  const std::vector<std::string> log = TakeLog();
  if (log.empty()) run.trace.Add("log none");
  for (const std::string& line : log) run.trace.Add("log " + line);
  return ok;
}

/// Barrier (see FakeMpv::WaitPokeSeen), then merges the render-thread lines
/// into the trace.
void Sync(Run& run) {
  if (const uint64_t seq = Fake().Poke()) Fake().WaitPokeSeen(seq);
  run.trace.Add(Fake().DrainAsync());
}

/// Destroys [r] (joins its thread, frees the render context) and records the
/// frees.
void Teardown(Run& run, std::unique_ptr<VideoRenderer>& r) {
  Fake().SignalPending();
  r.reset();
  run.trace.Add("teardown frees=" + std::to_string(Fake().counters().frees));
}

/// Non-skip render calls in total.
void Draws(Run& run) {
  const golden::Counters c = Fake().counters();
  run.trace.Add("draws " + std::to_string(c.renders - c.skips));
}

// --- Chains ------------------------------------------------------------------

// The auto chain of a platform with two GPU apis, d3d11 ranked first on each
// renderer. The chain is scenario data: the fault logic is independent of
// which api a platform ranks first (Windows ships vulkan first today, 14-11).
std::vector<BackendCandidate> FullChain() {
  return {{"d3d11", "gpu-next"},
          {"vulkan", "gpu-next"},
          {"d3d11", "gpu"},
          {"vulkan", "gpu"},
          {"software", "sw"}};
}

// --- Scenarios ---------------------------------------------------------------

// The d3d11 device is lost while its backend is created: both d3d11
// candidates carry the trail, vulkan's gpu-next wins, the d3d11 device was
// initialised once, and no event is raised (events belong to a running
// renderer).
void CreateDeviceLostNextApi(Run& run) {
  Platform p(FullChain());
  p.apis["d3d11"].device_why = kD3d11RemovedWhy;
  FaultInterop interop(&p);
  auto r = MakeRenderer(interop);
  if (!Start(run, p, *r)) return;
  Sync(run);  // any event the render thread raised would show up here
  Teardown(run, r);
}

// Every GPU candidate fails (d3d11's device is gone, vulkan's mpv creates are
// rejected on both renderers): software wins, its reason lists the four
// failed candidates in chain order, each failed create was logged, the Vulkan
// fall-back notice names the whole trail, and the software renderer draws.
void CreateEveryGpuCandidateFails(Run& run) {
  Platform p(FullChain());
  p.apis["d3d11"].device_why = kD3d11RemovedWhy;
  Fake().SetCreateResult("vulkan", "gpu-next", kCreateError);
  Fake().SetCreateResult("vulkan", "gpu", kCreateError);
  FaultInterop interop(&p);
  auto r = MakeRenderer(interop);
  if (!Start(run, p, *r)) return;
  r->SetSize(kWidth, kHeight);
  interop.WaitFrameReady(1);
  Sync(run);
  Draws(run);
  Teardown(run, r);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"create-device-lost-next-api", CreateDeviceLostNextApi},
    {"create-every-gpu-candidate-fails", CreateEveryGpuCandidateFails},
};

}  // namespace

int main(int argc, char** argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  std::string golden_path;
  int slack_ms = 250;
  for (int i = 1; i < argc; i++) {
    const std::string arg = argv[i];
    if (arg.compare(0, 11, "--slack-ms=") == 0) {
      slack_ms = std::atoi(arg.c_str() + 11);
    } else if (golden_path.empty() && arg.compare(0, 2, "--") != 0) {
      golden_path = arg;
    } else {
      golden_path.clear();
      break;
    }
  }
  if (golden_path.empty() || slack_ms <= 0) {
    std::fprintf(stderr,
                 "usage: video_renderer_fault_test <golden/fault.txt> "
                 "[--slack-ms=N]\n");
    return 1;
  }
  golden::Golden expected;
  std::string error;
  if (!golden::LoadGolden(golden_path, &expected, &error)) {
    std::printf("GOLDEN error: %s\n", error.c_str());
    return 1;
  }

  golden::Golden actual;
  bool ok = true;
  for (const ScenarioDef& def : kScenarios) {
    Fake().Reset();
    golden::Images().Reset();
    TakeLog();
    Run run{def.name, slack_ms, {}, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("GOLDEN timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    for (const std::string& v : golden::Images().TakeViolations())
      run.Invariant(v);
    if (!run.ok) ok = false;
    actual.emplace_back(def.name, run.trace.lines());
  }
  const int rc = golden::CompareGolden(expected, actual);
  if (rc != 0 || !ok) return 1;
  std::printf("GOLDEN ok scenarios=%zu\n", actual.size());
  return 0;
}
