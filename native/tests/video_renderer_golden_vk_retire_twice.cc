// Vulkan-path golden test of the shared video renderer's retired front when
// a resize follows a resize that never produced a frame: drives the real
// packages/mpv_kit_video/src/video_renderer.cc and vulkan_backend.cc through
// the fake libmpv and fake Vulkan platform interop of renderer_harness.h and
// compares what they do with golden/vk_retire_twice.txt.
//
// Kept apart from video_renderer_golden_vk.cc because that file, its golden
// and the harness are frozen (evidence/golden-freeze.sha256 of phase 12):
// new scenarios go into new files. The helpers below repeat the few
// golden_vk ones the scenario needs. The software path of the same defect
// is video_renderer_golden_sw_retire_twice.cc.
//
// Needs a Vulkan 1.3 device (lavapipe, MoltenVK or a GPU), like golden_vk.
//
// usage: video_renderer_golden_vk_retire_twice <golden/vk_retire_twice.txt>
//            [--slack-ms=N]
//
// Output: `GOLDEN ok scenarios=<n>` on success; `GOLDEN skip: <reason>` and
// exit 77 (meson: skipped) when the runner has no usable Vulkan device;
// otherwise one `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure, 77 skipped. The golden file is only read.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "renderer_harness.h"

namespace {

using golden::Fake;
using golden::FakeInterop;
using golden::FakeVulkanInterop;
using golden::Images;
using golden::SignalMode;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Settle margin before the quiesce counts: long enough for the render thread
// to have answered every outstanding render call.
constexpr golden::Ms kPastPresentTimeout{60};
// Any mpv error code: the fake returns it from the first new-size render.
constexpr int kRenderError = MPV_ERROR_GENERIC;

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

// Renderer log lines are diagnostics only (never part of a trace); kept so
// a failing scenario can show them.
std::mutex g_log_mu;
std::vector<std::string> g_log;

std::vector<std::string> LogLines() {
  std::lock_guard<std::mutex> lock(g_log_mu);
  return g_log;
}

/// The renderer and the two fake platform halves it talks to.
struct Rig {
  explicit Rig(int latency) : interop(latency, false, nullptr, &vk) {
    renderer = std::make_unique<VideoRenderer>(
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

  FakeVulkanInterop vk;
  FakeInterop interop;
  std::unique_ptr<VideoRenderer> renderer;
};

/// Start() and the resulting backend, reason and create attempts.
bool Start(Run& run, Rig& rig) {
  const bool ok = rig.renderer->Start(RendererChoice::kGpuNext);
  std::string reason = rig.renderer->backend_reason();
  for (const std::string& name : rig.vk.device_names())
    reason = golden::NormalizeReason(reason, name);
  const bool vulkan = rig.renderer->backend() == mpv_kit::Backend::kVulkan;
  run.trace.Add(ok ? std::string("start ok backend=") +
                         (vulkan ? "vulkan" : "software") + " reason=\"" +
                         reason + "\""
                   : "start=false reason=\"" + reason + "\"");
  run.trace.Add("create-attempts " + Fake().creates());
  return ok;
}

/// Barrier (see FakeMpv::WaitPokeSeen), then merges the render-thread lines
/// into the trace.
void Sync(Run& run) {
  if (const uint64_t seq = Fake().Poke()) Fake().WaitPokeSeen(seq);
  run.trace.Add(Fake().DrainAsync());
}

/// mpv announces one new frame; waits until the renderer handed a frame to
/// the platform.
void NextFrame(Rig& rig) {
  const int want = rig.interop.frame_ready() + 1;
  Fake().QueueFrames(1);
  Fake().Poke();
  rig.interop.WaitFrameReady(want);
}

/// What the compositor does when it samples the texture. A frame whose
/// image was already destroyed is a use after free in the real plugin.
void Acquire(Run& run, Rig& rig) {
  const mpv_kit::Frame f = rig.renderer->AcquireFront();
  std::string line = "acquire index=" + std::to_string(f.index) + " " +
                     std::to_string(f.width) + "x" + std::to_string(f.height);
  if (f.pixels) run.Invariant("Vulkan frame carries software pixels");
  const golden::FakeImage e = Images().Entry(f.platform);
  if (!f.platform) {
    line += " serial=none";
  } else if (e.serial == 0) {
    line += " serial=unknown";
    run.Invariant("frame platform pointer is not a fake image");
  } else {
    line += " serial=" + std::to_string(e.serial);
    if (e.destroyed) {
      line += " USE AFTER DESTROY";
      run.Invariant("USE AFTER DESTROY serial=" + std::to_string(e.serial));
    }
  }
  run.trace.Add(line);
}

/// Lets the renderer settle (pending swaps reported by their timeout), then
/// records the call counts and checks one swap per render call.
void Quiesce(Run& run) {
  std::this_thread::sleep_for(kPastPresentTimeout);
  const auto deadline = golden::Clock::now() + golden::kWaitTimeout;
  while (!golden::CheckSwapInvariant() && golden::Clock::now() < deadline)
    std::this_thread::sleep_for(golden::Ms(5));
  Sync(run);
  const golden::Counters c = Fake().counters();
  run.trace.Add("quiesce renders=" + std::to_string(c.renders) +
                " skips=" + std::to_string(c.skips) +
                " swaps=" + std::to_string(c.swaps));
  if (!golden::CheckSwapInvariant())
    run.Invariant("swaps (" + std::to_string(c.swaps) +
                  ") != render calls (" + std::to_string(c.renders) + ")");
}

/// Destroys the renderer, records the destroys it made and checks that
/// every image of the scenario is gone (DOUBLE DESTROY is reported by the
/// fake interop itself).
void Teardown(Run& run, Rig& rig) {
  Fake().SignalPending();
  rig.renderer.reset();
  run.trace.Add(Fake().DrainAsync());
  const int live = Images().live();
  run.trace.Add("teardown frees=" + std::to_string(Fake().counters().frees) +
                " live-images=" + std::to_string(live));
  if (live != 0)
    run.Invariant(std::to_string(live) + " image(s) never destroyed");
}

// --- Scenario ----------------------------------------------------------------

// A resize while the previous resize has no frame yet (latency 2, ring 6).
//
// One 64x36 frame (serial 1) is on screen. The resize to 32x18 retires
// serial 1, and the first 32x18 render fails, so the 32x18 generation
// never publishes a frame: serial 1 is still what the compositor shows. A
// second resize to 48x27 then reallocates again; AllocateRing frees the
// previous generation's survivor first, which is serial 1. From then on
// AcquireFront must not hand serial 1 out: until the first 48x27 frame is
// published there is nothing to show (index -1).
//
// Determinism: the failing 32x18 render is held inside the fake while the
// second size is set, so the renderer retries at the new size at once
// (resize ends the backoff) and no backoff timer is involved. The 48x27
// frame's timeline value is deferred, so the render thread waits in the
// publish gate: the window between the reallocation and the publish.
void VkRetireTwice(Run& run) {
  Rig rig(/*latency=*/2);
  if (!Start(run, rig)) return;
  rig.renderer->SetSize(64, 36);
  rig.interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, rig);
  // The first 32x18 render fails and is held inside the fake.
  Fake().SetRenderResults({kRenderError});
  Fake().HoldRenders(true);
  rig.renderer->SetSize(32, 18);
  Fake().WaitRenderHeld();
  run.trace.Add(Fake().DrainAsync());
  // Nothing at 32x18 yet: the retired serial 1 is still shown (and alive).
  Acquire(run, rig);
  // Second resize before any 32x18 frame exists.
  rig.renderer->SetSize(48, 27);
  Fake().SetSignalMode(SignalMode::kDeferred);
  const int renders = Fake().counters().renders;
  const int want = rig.interop.frame_ready() + 1;
  Fake().HoldRenders(false);
  // The 48x27 render was issued; the render thread now waits for its
  // timeline value (bounded by the 1 s GPU timeout).
  Fake().WaitRenders(renders + 1);
  run.trace.Add(Fake().DrainAsync());
  Acquire(run, rig);
  Fake().SignalPending();
  rig.interop.WaitFrameReady(want);
  Sync(run);
  Acquire(run, rig);
  Fake().SetSignalMode(SignalMode::kImmediate);
  Fake().SignalPending();
  for (int i = 0; i < 2; i++) {
    NextFrame(rig);
    Sync(run);
    Acquire(run, rig);
  }
  Quiesce(run);
  Teardown(run, rig);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"vk-retire-twice", VkRetireTwice},
};

/// Same probe as golden_vk: skip only when the loader, an instance or a
/// Vulkan 1.3 device is missing. Returns the reason to skip, or "" to run.
std::string Probe() {
  Fake().Reset();
  Images().Reset();
  std::string skip;
  {
    Rig rig(2);
    rig.renderer->Start(RendererChoice::kGpuNext);
    const std::string reason = rig.renderer->backend_reason();
    if (rig.renderer->backend() != mpv_kit::Backend::kVulkan &&
        (reason.find("Vulkan loader") != std::string::npos ||
         reason.find("vkCreateInstance failed") != std::string::npos ||
         reason.find("no Vulkan 1.3 device") != std::string::npos ||
         reason.find("Vulkan < 1.3 on") != std::string::npos))
      skip = reason;
  }
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
  // --slack-ms is accepted for symmetry with golden_vk; this scenario has
  // no timing expectation.
  if (golden_path.empty() || slack_ms <= 0) {
    std::fprintf(stderr,
                 "usage: video_renderer_golden_vk_retire_twice "
                 "<golden/vk_retire_twice.txt> [--slack-ms=N]\n");
    return 1;
  }
  golden::Golden expected;
  std::string error;
  if (!golden::LoadGolden(golden_path, &expected, &error)) {
    std::printf("GOLDEN error: %s\n", error.c_str());
    return 1;
  }
  const std::string skip = Probe();
  if (!skip.empty()) {
    std::printf("GOLDEN skip: %s\n", skip.c_str());
    return 77;
  }

  golden::Golden actual;
  bool ok = true;
  for (const ScenarioDef& def : kScenarios) {
    Fake().Reset();
    Images().Reset();
    {
      std::lock_guard<std::mutex> lock(g_log_mu);
      g_log.clear();
    }
    Run run{def.name, {}, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("GOLDEN timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    for (const std::string& v : Images().TakeViolations()) run.Invariant(v);
    if (!run.ok) {
      for (const std::string& line : LogLines())
        std::fprintf(stderr, "  [%s] log: %s\n", def.name, line.c_str());
      ok = false;
    }
    actual.emplace_back(def.name, run.trace.lines());
  }
  const int rc = golden::CompareGolden(expected, actual);
  if (rc != 0 || !ok) return 1;
  std::printf("GOLDEN ok scenarios=%zu\n", actual.size());
  return 0;
}
