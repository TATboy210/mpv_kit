// Vulkan-path golden test of the shared video renderer: drives the real
// packages/mpv_kit_video/src/video_renderer.cc and vulkan_backend.cc through
// a fake libmpv and a fake Vulkan platform interop (renderer_harness.h) and
// compares what they do with golden/vk.txt.
//
// Needs a Vulkan 1.3 device (lavapipe, MoltenVK or a GPU): the real
// VulkanContext creates its device and timeline semaphore, and
// FakeVulkanInterop creates real images on that device. mpv's GPU work is
// faked: FakeMpv signals each render's timeline value at once or when the
// scenario says so. libmpv is neither linked nor loaded.
//
// usage: video_renderer_golden_vk <golden/vk.txt> [--slack-ms=N]
//   --slack-ms  upper tolerance of timing expectations (meson passes 250,
//               or 1000 for sanitizer builds)
//
// Output: `GOLDEN ok scenarios=<n>` on success; `GOLDEN skip: <reason>` and
// exit 77 (meson: skipped) when the runner has no usable Vulkan device;
// otherwise one `GOLDEN mismatch|invariant|timing|timeout ...` report per
// problem. Exit codes: 0 pass, 1 failure, 77 skipped. The golden file is
// only read.

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
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

// Waits beyond kPresentTimeout (50 ms) so an unpresented frame's swap has
// been reported by the render thread's own timeout.
constexpr golden::Ms kPastPresentTimeout{60};
// How long the test lets the render thread sit in a timeline wait before it
// looks: well inside VulkanContext's 1 s GPU timeout.
constexpr golden::Ms kGateObserve{100};

// --- Scenario context --------------------------------------------------------

/// State of one running scenario: its trace and whether it already failed.
struct Run {
  std::string name;
  const golden::Golden& expected;
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

// Renderer log lines are diagnostics only (never part of a trace); kept so
// a failing scenario can show them.
std::mutex g_log_mu;
std::vector<std::string> g_log;

/// The renderer and the two fake platform halves it talks to.
struct Rig {
  explicit Rig(int latency = 2, bool accept_device = true)
      : vk(accept_device), interop(latency, false, nullptr, &vk) {
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

const char* BackendName(mpv_kit::Backend b) {
  return b == mpv_kit::Backend::kVulkan ? "vulkan" : "software";
}

/// The reason with every accepted device name replaced by `<device>`.
std::string Reason(Rig& rig) {
  std::string reason = rig.renderer->backend_reason();
  for (const std::string& name : rig.vk.device_names())
    reason = golden::NormalizeReason(reason, name);
  return reason;
}

/// Start() and the resulting backend, reason and create attempts.
bool Start(Run& run, Rig& rig, RendererChoice choice) {
  const bool ok = rig.renderer->Start(choice);
  if (ok) {
    run.trace.Add(std::string("start ok backend=") +
                  BackendName(rig.renderer->backend()) + " reason=\"" +
                  Reason(rig) + "\"");
  } else {
    run.trace.Add("start=false reason=\"" + Reason(rig) + "\"");
  }
  run.trace.Add("create-attempts " + Fake().creates());
  return ok;
}

/// Barrier (see FakeMpv::WaitPokeSeen), then merges the render-thread lines
/// into the trace and returns them. Never call it while the render thread
/// may be parked in a timeline wait: it cannot observe the poke there, and
/// the barrier would only return after the wait timed out.
std::vector<std::string> Sync(Run& run) {
  if (const uint64_t seq = Fake().Poke()) Fake().WaitPokeSeen(seq);
  std::vector<std::string> lines = Fake().DrainAsync();
  run.trace.Add(lines);
  return lines;
}

/// mpv announces one new frame; waits until the renderer handed a frame to
/// the platform.
void NextFrame(Rig& rig) {
  const int want = rig.interop.frame_ready() + 1;
  Fake().QueueFrames(1);
  Fake().Poke();
  rig.interop.WaitFrameReady(want);
}

/// Serial of the fake image behind a frame's platform pointer, or 0.
int SerialOf(const mpv_kit::Frame& f) {
  return f.platform ? Images().Entry(f.platform).serial : 0;
}

/// What the compositor does when it samples the texture. A frame whose
/// image was already destroyed is a use after free in the real plugin.
mpv_kit::Frame Acquire(Run& run, Rig& rig) {
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
  return f;
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

/// Destroys the renderer (joins its thread, frees the render context and
/// the Vulkan device), records the destroys it made and checks that every
/// image of the scenario is gone exactly once.
void Teardown(Run& run, Rig& rig) {
  // Nothing may stay pending: VulkanContext waits up to 1 s per image.
  Fake().SignalPending();
  rig.renderer.reset();
  run.trace.Add(Fake().DrainAsync());
  run.trace.Add("teardown frees=" + std::to_string(Fake().counters().frees) +
                " live-images=" + std::to_string(Images().live()));
}

// --- Scenarios ---------------------------------------------------------------

// Publish gate: a frame becomes the front (what AcquireFront returns) only
// after its timeline value was signalled, i.e. after its GPU work finished
// — the compositor samples without any GPU synchronisation of its own. The
// render thread waits for that value right after the render call, so the
// test must not use the Sync barrier until the value is signalled.
void VkPublishGate(Run& run) {
  Rig rig(/*latency=*/2);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  Fake().SetSignalMode(SignalMode::kDeferred);
  const int ready = rig.interop.frame_ready();
  rig.renderer->SetSize(64, 36);
  // Frame 1 is rendered; its value stays unsignalled, so the render thread
  // waits for it (bounded by the 1 s GPU timeout).
  Fake().WaitRenders(1);
  run.trace.Add(Fake().DrainAsync());
  std::this_thread::sleep_for(kGateObserve);
  const mpv_kit::Frame early = Acquire(run, rig);
  if (SerialOf(early) == 1)
    run.Invariant("frame 1 was published before its GPU work completed");
  // GPU work done: frame 1 is published and handed to the platform.
  Fake().SignalPending();
  rig.interop.WaitFrameReady(ready + 1);
  Sync(run);
  if (SerialOf(Acquire(run, rig)) != 1)
    run.Invariant("frame 1 is not the front after its value was signalled");
  // From now on every render completes at once.
  Fake().SetSignalMode(SignalMode::kImmediate);
  Fake().SignalPending();
  for (int i = 0; i < 3; i++) {
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
    {"vk-publish-gate", VkPublishGate},
};

/// Whether this runner can run the Vulkan scenarios at all: a renderer
/// asked for gpu-next with a fake mpv that always succeeds ends up on
/// Vulkan unless the loader, an instance or a Vulkan 1.3 device is missing.
/// Returns the reason to skip, or "" to run. Any other way of not reaching
/// Vulkan is not a skip: the scenarios then run and fail loudly.
std::string Probe() {
  Fake().Reset();
  Images().Reset();
  std::string skip;
  {
    Rig rig;
    rig.renderer->Start(RendererChoice::kGpuNext);
    const std::string reason = rig.renderer->backend_reason();
    if (rig.renderer->backend() != mpv_kit::Backend::kVulkan &&
        (reason.find("Vulkan loader") != std::string::npos ||
         reason.find("vkCreateInstance failed") != std::string::npos ||
         reason.find("no Vulkan 1.3 device") != std::string::npos))
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
  if (golden_path.empty() || slack_ms <= 0) {
    std::fprintf(stderr,
                 "usage: video_renderer_golden_vk <golden/vk.txt> "
                 "[--slack-ms=N]\n");
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
    Run run{def.name, expected, slack_ms, {}, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("GOLDEN timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    for (const std::string& v : Images().TakeViolations()) run.Invariant(v);
    if (!run.ok) {
      std::lock_guard<std::mutex> lock(g_log_mu);
      for (const std::string& line : g_log)
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
