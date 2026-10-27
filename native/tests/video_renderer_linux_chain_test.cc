// Golden test of the Linux candidate chain (Phase 15, GLX-04): drives the
// real packages/mpv_kit_video/src/video_renderer.cc (and, in one scenario,
// vulkan_backend.cc) through the fake libmpv of renderer_harness.h, with an
// Interop whose BackendCandidates is LinuxBackendCandidates(choice)
// (linux_candidates.h) and whose "opengl" backend is a fake, and compares what
// VideoRenderer::Start does with golden/linux_chain.txt.
//
// What it proves, without Linux, EGL, a GPU or libmpv:
//   * auto without a usable Vulkan reaches opengl (gpu) with the reason
//     `opengl (gpu) on fake-gl; vulkan/gpu-next unavailable: <why>`;
//   * an opengl device failure or a failed opengl create leaves its trail and
//     Start moves on to vulkan/gpu and software, every failure with a trail;
//   * the chain of each RendererChoice is the one the user picked at the 15-04
//     checkpoint (decisions.txt `decision=linux-chain`): a gpu-next request
//     has no opengl candidate, gpu starts with opengl, software only software;
//   * MPV_KIT_VIDEO_API=opengl tries opengl only (no fallback), and fails for
//     a gpu-next request because the chain has no opengl candidate;
//   * the renderer in the reason head is what mpv reports (`gpu` when the fake
//     reports it, `unknown renderer` when the query fails): the head never
//     names a renderer other than the reported one;
//   * (needs a Vulkan 1.3 device) a failing vulkan/gpu-next create lets
//     opengl/gpu win before vulkan/gpu is tried.
//
// Why a new file: the Phase 12 goldens, their expectations and the harness
// are frozen (evidence/golden-freeze*.sha256); the harness is only used
// read-only here. The fake opengl backend renders through the software
// parameters of the fake libmpv into CPU buffers and creates its context with
// the API type string "opengl" (upstream MPV_RENDER_API_TYPE_OPENGL) plus the
// renderer name in the same parameter the Vulkan backend uses, so create
// attempts read `opengl/gpu` like the others. "opengl" is only its wire name.
//
// The Vulkan scenario needs a Vulkan 1.3 device (lavapipe, MoltenVK or a GPU,
// as golden_vk); without one only that scenario is skipped, with
// `LINUX-CHAIN vk scenario skipped: <why>`, and the binary still passes.
//
// usage: video_renderer_linux_chain_test <golden/linux_chain.txt>
//        [--slack-ms=N]
//
// Output: `GOLDEN ok scenarios=<n>` then `LINUX-CHAIN ok` on success;
// otherwise one `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure. The golden file is only read.

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "linux_candidates.h"
#include "renderer_harness.h"

namespace {

using golden::Fake;
using golden::FakeInterop;
using golden::FakeVulkanInterop;
using mpv_kit::MpvApi;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

constexpr const char* kApiVariable = "MPV_KIT_VIDEO_API";
// Any mpv error code: the fake returns it from the failing creates.
constexpr int kCreateError = MPV_ERROR_UNSUPPORTED;
// Why the fake Vulkan-less platform has no Vulkan interop (the interop reason
// the engine puts in the trail).
constexpr const char* kNoVulkanReason = "fake: no vulkan interop";
// Why the fake GL device cannot be created.
constexpr const char* kGlDeviceWhy = "fake: no EGL display";
// Upstream MPV_RENDER_API_TYPE_OPENGL ("opengl"), spelled out so the test does
// not need render_gl.h.
constexpr const char* kOpenglApiType = "opengl";

// --- Fake OpenGL backend ------------------------------------------------------

/// What the fake opengl backend does; set per scenario.
struct GlConfig {
  std::string device_why;  // non-empty: the device fails to initialise
};

/// Per-scenario state shared by the interop and its opengl backends.
struct Platform {
  GlConfig gl;
  int gl_backends = 0;  // CreateBackend("opengl") calls
};

/// A GPU-style RenderBackend (pipelined) backed by CPU buffers whose wire
/// name is "opengl". frame_kind() is Backend::kVulkan: that enum value means
/// "a shared GPU image" and predates the non-Vulkan GPU backends.
class FakeGlBackend final : public mpv_kit::RenderBackend {
 public:
  explicit FakeGlBackend(Platform* platform) : platform_(platform) {}

  const char* wire_name() const override { return "opengl"; }
  mpv_kit::Backend frame_kind() const override {
    return mpv_kit::Backend::kVulkan;
  }
  bool pipelined() const override { return true; }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    *out = nullptr;
    if (!device_initialised_) {
      device_initialised_ = true;
      device_error_ = platform_->gl.device_why;
    }
    if (!device_error_.empty()) {
      *why = device_error_;
      return MPV_ERROR_GENERIC;  // mpv was not asked (device_failed())
    }
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(kOpenglApiType)},
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
  std::string device_name() const override { return "fake-gl"; }
  std::string RendererName(const MpvApi& api,
                           mpv_render_context* ctx) const override {
    // The same honest rule as the Vulkan backend: ask mpv, never assume.
    const char* active = nullptr;
    const int info = api.render_context_get_info(
        ctx, {MPV_RENDER_PARAM_VULKAN_RENDERER, &active});
    return info >= 0 && active ? active : "unknown renderer";
  }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    (void)keep_slot;
    (void)error;
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
    return api.render_context_render(ctx, params);
  }
  mpv_kit::WaitResult Wait(int slot) override {
    (void)slot;
    return mpv_kit::WaitResult::kOk;
  }

  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    api.render_context_free(ctx);
  }

 private:
  Platform* const platform_;
  bool device_initialised_ = false;
  std::string device_error_;
  std::vector<std::vector<uint8_t>> buffers_;
};

/// The Linux platform: LinuxBackendCandidates for the chain, the fake opengl
/// backend for "opengl", the engine's own Vulkan (when [vk] is given) and
/// software backends otherwise.
class LinuxFakeInterop final : public FakeInterop {
 public:
  LinuxFakeInterop(Platform* platform, mpv_kit::VulkanInterop* vk)
      : FakeInterop(2, false, vk ? nullptr : kNoVulkanReason, vk),
        platform_(platform) {}

  std::vector<mpv_kit::BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    return mpv_kit::LinuxBackendCandidates(choice);
  }
  std::unique_ptr<mpv_kit::RenderBackend> CreateBackend(
      const char* api) override {
    if (std::string(api) != "opengl") return nullptr;
    platform_->gl_backends++;
    return std::make_unique<FakeGlBackend>(platform_);
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

/// Start([choice]): result, winner and reason, the creates it made, how many
/// opengl backends it asked the platform for and every line it logged.
bool Start(Run& run, Platform& platform, VideoRenderer& r,
           RendererChoice choice) {
  TakeLog();
  const bool ok = r.Start(choice);
  if (ok) {
    run.trace.Add(std::string("start ok backend=") + r.wire_name() +
                  " reason=\"" + r.backend_reason() + "\"");
  } else {
    run.trace.Add("start=false reason=\"" + r.backend_reason() + "\"");
  }
  run.trace.Add("create-attempts " + Fake().creates());
  run.trace.Add("gl-backends=" + std::to_string(platform.gl_backends));
  const std::vector<std::string> log = TakeLog();
  if (log.empty()) run.trace.Add("log none");
  for (const std::string& line : log) run.trace.Add("log " + line);
  return ok;
}

/// Destroys [r] (joins its thread, frees the render context) and records the
/// frees.
void Teardown(Run& run, std::unique_ptr<VideoRenderer>& r) {
  Fake().SignalPending();
  r.reset();
  run.trace.Add("teardown frees=" + std::to_string(Fake().counters().frees));
  if (golden::Images().live() != 0)
    run.Invariant(std::to_string(golden::Images().live()) +
                  " image(s) never destroyed");
}

/// One Start of [choice] on a platform without Vulkan interop and a healthy
/// fake GL that reports [reported] as its renderer (nullptr: the query
/// fails), under MPV_KIT_VIDEO_API=[forced] (nullptr: unset).
void StartNoVulkan(Run& run, Platform& p, RendererChoice choice,
                   const char* reported, const char* forced) {
  Fake().SetInfoRenderer(reported, reported ? 0 : kCreateError);
  LinuxFakeInterop interop(&p, nullptr);
  golden::SetEnv(kApiVariable, forced);
  auto r = MakeRenderer(interop);
  Start(run, p, *r, choice);
  golden::SetEnv(kApiVariable, nullptr);
  Teardown(run, r);
}

// --- Scenarios ---------------------------------------------------------------

// auto without Vulkan: opengl/gpu wins with the gpu-next trail only.
void LinuxAutoNoVulkan(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kAuto, "gpu", nullptr);
}

// The GL device fails: trails of vulkan/gpu-next, opengl/gpu (the device's
// why, no mpv create, no log) and vulkan/gpu; software wins.
void LinuxAutoGlDeviceFails(Run& run) {
  Platform p;
  p.gl.device_why = kGlDeviceWhy;
  StartNoVulkan(run, p, RendererChoice::kAuto, "gpu", nullptr);
}

// The GL device is fine but mpv's create fails: its trail carries the mpv
// error, the failure is logged, then vulkan/gpu and software.
void LinuxAutoGlCreateFails(Run& run) {
  Platform p;
  Fake().SetCreateResult(kOpenglApiType, "gpu", kCreateError);
  StartNoVulkan(run, p, RendererChoice::kAuto, "gpu", nullptr);
}

// gpu: opengl first, no trail (decision A).
void LinuxGpu(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kGpu, "gpu", nullptr);
}

// gpu-next: no opengl candidate in the chain, so no opengl backend is even
// asked for and software wins after the gpu-next trail.
void LinuxGpuNext(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kGpuNext, "gpu", nullptr);
}

// software: only software.
void LinuxSoftware(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kSoftware, "gpu", nullptr);
}

// MPV_KIT_VIDEO_API=opengl: vulkan/gpu-next is an excluded trail, opengl/gpu
// wins; the candidates ranked after the winner leave nothing.
void LinuxForcedOpengl(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kAuto, "gpu", "opengl");
}

// MPV_KIT_VIDEO_API=opengl with a gpu-next request: the chain has no opengl
// candidate, so nothing is tried and Start fails with the excluded trails.
void LinuxForcedOpenglGpuNext(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kGpuNext, "gpu", "opengl");
}

// The renderer query fails: the head says so instead of guessing.
void LinuxRendererUnknown(Run& run) {
  Platform p;
  StartNoVulkan(run, p, RendererChoice::kAuto, nullptr, nullptr);
}

// A real Vulkan device whose gpu-next create fails: opengl/gpu wins before
// vulkan/gpu is tried (auto order), with the gpu-next trail in the head.
void LinuxAutoGpuNextCreateFails(Run& run) {
  Platform p;
  FakeVulkanInterop vk;
  Fake().SetCreateResult("vulkan", "gpu-next", kCreateError);
  Fake().SetInfoRenderer("gpu", 0);
  LinuxFakeInterop interop(&p, &vk);
  auto r = MakeRenderer(interop);
  Start(run, p, *r, RendererChoice::kAuto);
  Teardown(run, r);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
  bool needs_vulkan;  // skipped (on its own) without a Vulkan 1.3 device
};

const ScenarioDef kScenarios[] = {
    {"linux-auto-no-vulkan", LinuxAutoNoVulkan, false},
    {"linux-auto-gl-device-fails", LinuxAutoGlDeviceFails, false},
    {"linux-auto-gl-create-fails", LinuxAutoGlCreateFails, false},
    {"linux-gpu", LinuxGpu, false},
    {"linux-gpu-next", LinuxGpuNext, false},
    {"linux-software", LinuxSoftware, false},
    {"linux-forced-opengl", LinuxForcedOpengl, false},
    {"linux-forced-opengl-gpu-next", LinuxForcedOpenglGpuNext, false},
    {"linux-renderer-unknown", LinuxRendererUnknown, false},
    {"linux-auto-gpu-next-create-fails", LinuxAutoGpuNextCreateFails, true},
};

/// Same probe as golden_vk (variable unset): skip the Vulkan scenario only
/// when the loader, an instance or a Vulkan 1.3 device is missing. Returns
/// the reason to skip, or "" to run it.
std::string Probe() {
  Fake().Reset();
  golden::Images().Reset();
  golden::SetEnv(kApiVariable, nullptr);
  std::string skip;
  {
    Platform p;
    FakeVulkanInterop vk;
    LinuxFakeInterop interop(&p, &vk);
    std::unique_ptr<VideoRenderer> r = MakeRenderer(interop);
    // gpu-next: vulkan/gpu-next, then software; opengl is not in that chain.
    r->Start(RendererChoice::kGpuNext);
    const std::string reason = r->backend_reason();
    if (std::string(r->wire_name()) != "vulkan" &&
        (reason.find("Vulkan loader") != std::string::npos ||
         reason.find("vkCreateInstance failed") != std::string::npos ||
         reason.find("no Vulkan 1.3 device") != std::string::npos ||
         reason.find("Vulkan < 1.3 on") != std::string::npos))
      skip = reason;
  }
  TakeLog();
  return skip;
}

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
                 "usage: video_renderer_linux_chain_test "
                 "<golden/linux_chain.txt> [--slack-ms=N]\n");
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
  const std::string vk_skip = Probe();

  golden::Golden actual;
  bool ok = true;
  for (const ScenarioDef& def : kScenarios) {
    if (def.needs_vulkan && !vk_skip.empty()) {
      // Not run: its expectation is not compared either.
      for (auto it = expected.begin(); it != expected.end(); ++it) {
        if (it->first == def.name) {
          expected.erase(it);
          break;
        }
      }
      continue;
    }
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
  if (!vk_skip.empty())
    std::printf("LINUX-CHAIN vk scenario skipped: %s\n", vk_skip.c_str());
  std::printf("GOLDEN ok scenarios=%zu\n", actual.size());
  std::printf("LINUX-CHAIN ok\n");
  return 0;
}
