// Golden test of the candidate chain with a platform-provided backend
// (Phase 14, D3D-07): drives the real packages/mpv_kit_video/src/
// video_renderer.cc through the fake libmpv of renderer_harness.h, with an
// Interop that supplies its own RenderBackend for "d3d11" and "vulkan" (the
// seam Interop::CreateBackend, first used by the Windows plugin) and compares
// what VideoRenderer::Start and the render thread do with golden/chain.txt.
//
// What it proves, without any GPU, driver or libmpv:
//   * a platform backend whose device fails to initialise leaves the
//     `d3d11/<renderer> unavailable: <why>` trail for every candidate of its
//     api and Start moves on to the next candidate (vulkan/gpu-next after the
//     Windows switch), initialising that api's device only once;
//   * candidates interleave quality first (gpu-next on every api before gpu),
//     in whatever order the platform's chain gives them;
//   * with MPV_KIT_VIDEO_API=d3d11 a failed d3d11 device never falls back:
//     every other candidate is an `excluded by` trail and Start fails;
//   * a backend whose Wait reports kDeviceLost makes the engine emit exactly
//     one device_lost event and render nothing afterwards (only skips), and
//     the render context is freed once at teardown.
//
// Why a new file: the Phase 12 goldens, their expectations and the harness
// are frozen (evidence/golden-freeze*.sha256); the harness is only used
// read-only here. The fake GPU backend renders through the software
// parameters of the fake libmpv into CPU buffers; "d3d11" and "vulkan" are
// only its wire names, so reasons and trails have the shape of the real ones.
//
// usage: video_renderer_chain_test <golden/chain.txt> [--slack-ms=N]
//
// Output: `GOLDEN ok scenarios=<n>` on success; otherwise one
// `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure. The golden file is only read.

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

using golden::Fake;
using golden::FakeInterop;
using mpv_kit::BackendCandidate;
using mpv_kit::MpvApi;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

constexpr const char* kApiVariable = "MPV_KIT_VIDEO_API";
// Any mpv error code: the fake returns it from the failing creates.
constexpr int kCreateError = MPV_ERROR_UNSUPPORTED;
// Why the fake d3d11 device cannot be created (the plugin's own wording and
// DXGI_ERROR_UNSUPPORTED).
constexpr const char* kD3d11DeviceWhy =
    "d3d11 device creation failed: 0x887A0004";
// Fake target size; small, the fake never looks at the pixels.
constexpr int kWidth = 64;
constexpr int kHeight = 36;

// --- Fake GPU backend --------------------------------------------------------

/// What one fake api does; set per scenario.
struct ApiConfig {
  std::string device;      // device_name() in the reason head
  std::string device_why;  // non-empty: the device fails to initialise
  int lost_from_wait = 0;  // > 0: Wait returns kDeviceLost from this call on
};

/// Per-scenario state shared by the interop and its backends.
struct Platform {
  std::map<std::string, ApiConfig> apis;
  std::map<std::string, int> device_inits;  // api -> device initialisations
  std::vector<BackendCandidate> chain;
};

/// A GPU-style RenderBackend (pipelined, shared-image frame class) backed by
/// CPU buffers: Render uses the fake libmpv's software target, Create asks
/// the fake for a render context of its own api type, so create attempts read
/// `d3d11/gpu-next` as with the real backend.
class FakeGpuBackend final : public mpv_kit::RenderBackend {
 public:
  FakeGpuBackend(Platform* platform, std::string api)
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
      platform_->device_inits[api_]++;
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
    (void)error;
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
        {MPV_RENDER_PARAM_SW_POINTER, buffers_[static_cast<size_t>(slot)].data()},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    return api.render_context_render(ctx, params);
  }
  mpv_kit::WaitResult Wait(int slot) override {
    (void)slot;
    const int from = Config().lost_from_wait;
    waits_++;
    return from > 0 && waits_ >= from ? mpv_kit::WaitResult::kDeviceLost
                                      : mpv_kit::WaitResult::kOk;
  }

  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    api.render_context_free(ctx);
  }

 private:
  const ApiConfig& Config() const { return platform_->apis[api_]; }

  Platform* const platform_;
  const std::string api_;
  bool device_initialised_ = false;
  std::string device_error_;
  std::string renderer_;
  int waits_ = 0;
  std::vector<std::vector<uint8_t>> buffers_;
};

/// The platform: a scripted candidate chain whose "d3d11" and "vulkan"
/// backends are FakeGpuBackends; software is the engine's own.
class ChainInterop final : public FakeInterop {
 public:
  explicit ChainInterop(Platform* platform)
      : FakeInterop(2, false, nullptr), platform_(platform) {}

  std::vector<BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    (void)choice;  // the scenarios always ask for auto
    return platform_->chain;
  }
  std::unique_ptr<mpv_kit::RenderBackend> CreateBackend(
      const char* api) override {
    const std::string name = api;
    if (name != "d3d11" && name != "vulkan") return nullptr;
    return std::make_unique<FakeGpuBackend>(platform_, name);
  }

 private:
  Platform* const platform_;
};

// --- Scenario context --------------------------------------------------------

/// State of one running scenario: its trace and whether it already failed.
struct Run {
  std::string name;
  golden::Trace trace;
  bool ok = true;

  /// Records an invariant violation; the scenario (and the binary) fails.
  void Invariant(const std::string& what) {
    std::printf("GOLDEN invariant scenario=%s: %s\n", name.c_str(),
                what.c_str());
    ok = false;
  }
};

// Renderer log lines: Start's own lines (the MPV_KIT_VIDEO_API notice,
// failed creates) are deterministic and part of the trace.
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
                std::to_string(platform.device_inits["d3d11"]) +
                " vulkan=" + std::to_string(platform.device_inits["vulkan"]));
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

// --- Chains ------------------------------------------------------------------

// After the Windows switch (14-11): d3d11 ranks first on each renderer.
std::vector<BackendCandidate> PostSwitchChain() {
  return {{"d3d11", "gpu-next"},
          {"vulkan", "gpu-next"},
          {"d3d11", "gpu"},
          {"vulkan", "gpu"},
          {"software", "sw"}};
}

// Before it: vulkan first.
std::vector<BackendCandidate> PreSwitchChain() {
  return {{"vulkan", "gpu-next"},
          {"d3d11", "gpu-next"},
          {"vulkan", "gpu"},
          {"d3d11", "gpu"},
          {"software", "sw"}};
}

/// A platform with both fake apis healthy.
Platform MakePlatform(std::vector<BackendCandidate> chain) {
  Platform p;
  p.chain = std::move(chain);
  p.apis["d3d11"].device = "fake-d3d11";
  p.apis["vulkan"].device = "fake-vk";
  return p;
}

// --- Scenarios ---------------------------------------------------------------

// The d3d11 device cannot be created: both d3d11 candidates carry the trail,
// the next api's gpu-next wins and the d3d11 device was initialised once.
void PostSwitchD3d11DeviceFails(Run& run) {
  Platform p = MakePlatform(PostSwitchChain());
  p.apis["d3d11"].device_why = kD3d11DeviceWhy;
  ChainInterop interop(&p);
  auto r = MakeRenderer(interop);
  if (!Start(run, p, *r)) return;
  Teardown(run, r);
}

// gpu-next fails to create on both apis: the interleaved order tries it on
// each api before any gpu candidate, and d3d11/gpu wins with both gpu-next
// trails in chain order.
void PostSwitchGpuNextFailsEverywhere(Run& run) {
  Platform p = MakePlatform(PostSwitchChain());
  Fake().SetCreateResult("d3d11", "gpu-next", kCreateError);
  Fake().SetCreateResult("vulkan", "gpu-next", kCreateError);
  ChainInterop interop(&p);
  auto r = MakeRenderer(interop);
  if (!Start(run, p, *r)) return;
  Teardown(run, r);
}

// Before the switch the roles swap: the vulkan device fails and d3d11's
// gpu-next wins with one trail.
void PreSwitchVulkanDeviceFails(Run& run) {
  Platform p = MakePlatform(PreSwitchChain());
  p.apis["vulkan"].device_why = "no Vulkan 1.3 device";
  ChainInterop interop(&p);
  auto r = MakeRenderer(interop);
  if (!Start(run, p, *r)) return;
  Teardown(run, r);
}

// MPV_KIT_VIDEO_API=d3d11 with a failing d3d11 device: no fallback to Vulkan
// or software, Start fails with every trail.
void ForcedD3d11DeviceFails(Run& run) {
  Platform p = MakePlatform(PostSwitchChain());
  p.apis["d3d11"].device_why = kD3d11DeviceWhy;
  ChainInterop interop(&p);
  golden::SetEnv(kApiVariable, "d3d11");
  auto r = MakeRenderer(interop);
  if (Start(run, p, *r)) run.Invariant("Start() fell back past a forced api");
  golden::SetEnv(kApiVariable, nullptr);
  Teardown(run, r);
}

// The d3d11 backend loses its device at its third Wait (the previous-use wait
// of the second frame): one device_lost event, no render after it (skips
// only), one render_context_free at teardown.
void D3d11DeviceLost(Run& run) {
  Platform p = MakePlatform({{"d3d11", "gpu-next"}, {"software", "sw"}});
  p.apis["d3d11"].lost_from_wait = 3;
  ChainInterop interop(&p);
  auto r = MakeRenderer(interop);
  if (!Start(run, p, *r)) return;
  // The first frame comes from the initial size (two waits, both fine).
  r->SetSize(kWidth, kHeight);
  interop.WaitFrameReady(1);
  Sync(run);
  // The compositor takes it: the renderer is not idle for the next frame.
  const mpv_kit::Frame f = r->AcquireFront();
  run.trace.Add("acquire index=" + std::to_string(f.index) + " " +
                std::to_string(f.width) + "x" + std::to_string(f.height) +
                " platform=" + (f.platform ? "yes" : "no"));
  // The second frame hits the lost device.
  Fake().QueueFrames(1);
  Fake().Poke();
  Fake().WaitNoted("event device_lost device lost");
  Sync(run);
  // Two more mpv frames: advanced with SKIP_RENDERING, never drawn.
  for (int i = 0; i < 2; i++) {
    Fake().QueueFrames(1);
    Fake().Poke();
    Fake().WaitSkips(2 + i);
    Sync(run);
  }
  const golden::Counters c = Fake().counters();
  run.trace.Add("draws " + std::to_string(c.renders - c.skips));
  Teardown(run, r);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"post-switch-d3d11-device-fails", PostSwitchD3d11DeviceFails},
    {"post-switch-gpu-next-fails-everywhere", PostSwitchGpuNextFailsEverywhere},
    {"pre-switch-vulkan-device-fails", PreSwitchVulkanDeviceFails},
    {"forced-d3d11-device-fails", ForcedD3d11DeviceFails},
    {"d3d11-device-lost", D3d11DeviceLost},
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
  // --slack-ms is accepted for symmetry with the other goldens; these
  // scenarios have no timing expectation.
  if (golden_path.empty() || slack_ms <= 0) {
    std::fprintf(stderr,
                 "usage: video_renderer_chain_test <golden/chain.txt> "
                 "[--slack-ms=N]\n");
    return 1;
  }
  golden::Golden expected;
  std::string error;
  if (!golden::LoadGolden(golden_path, &expected, &error)) {
    std::printf("GOLDEN error: %s\n", error.c_str());
    return 1;
  }
  // The scenarios own the variable: whatever the caller set is ignored.
  golden::SetEnv(kApiVariable, nullptr);

  golden::Golden actual;
  bool ok = true;
  for (const ScenarioDef& def : kScenarios) {
    Fake().Reset();
    golden::Images().Reset();
    TakeLog();
    Run run{def.name, {}, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("GOLDEN timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    golden::SetEnv(kApiVariable, nullptr);
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
