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
#include <cstring>
#include <deque>
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
// VulkanContext::WaitImage gives the GPU 1 s before it reports a timeout.
constexpr long long kGpuTimeoutMs = 1000;
// Frames each ring-rotation scenario renders: two full turns of a 5 ring,
// almost two of a 7 ring.
constexpr int kRotationFrames = 12;

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

// Time the renderer raised its gpu_timeout event (render thread), for the
// vk-gpu-timeout scenario's split timing (17-01): cleared at its start.
std::mutex g_timeout_mu;
bool g_timeout_seen = false;
golden::Clock::time_point g_timeout_at;

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
          if (std::strcmp(kind, "gpu_timeout") == 0) {
            std::lock_guard<std::mutex> lock(g_timeout_mu);
            g_timeout_seen = true;
            g_timeout_at = golden::Clock::now();
          }
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

long long ElapsedMs(golden::Clock::time_point from,
                    golden::Clock::time_point to) {
  return std::chrono::duration_cast<golden::Ms>(to - from).count();
}

/// 64x36, the first frame plus three more, each taken by the compositor.
void FourFrames(Run& run, Rig& rig) {
  rig.renderer->SetSize(64, 36);
  rig.interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, rig);
  for (int i = 0; i < 3; i++) {
    NextFrame(rig);
    Sync(run);
    Acquire(run, rig);
  }
}

/// Renders kRotationFrames frames at 64x36 that complete at once, each
/// taken by the compositor right after it was published, and checks every
/// render against a model of the compositor: it may still sample the frame
/// it holds and the `quarantine` frames it held before, so a render never
/// targets one of the last `quarantine` + 1 acquired images.
void Rotate(Run& run, Rig& rig, int quarantine) {
  std::deque<int> acquired;  // serials, newest first
  auto check = [&](const std::vector<std::string>& lines) {
    static const std::string kRender = "render serial=";
    for (const std::string& l : lines) {
      if (l.compare(0, kRender.size(), kRender) != 0) continue;
      const int serial = std::atoi(l.c_str() + kRender.size());
      for (size_t i = 0; i < acquired.size() && i <= size_t(quarantine); i++)
        if (acquired[i] == serial)
          run.Invariant("render into serial=" + std::to_string(serial) +
                        ", acquired " + std::to_string(i) +
                        " acquisition(s) ago (quarantine " +
                        std::to_string(quarantine) + ")");
    }
  };
  rig.renderer->SetSize(64, 36);
  rig.interop.WaitFrameReady(1);
  check(Sync(run));
  acquired.push_front(SerialOf(Acquire(run, rig)));
  for (int i = 1; i < kRotationFrames; i++) {
    NextFrame(rig);
    check(Sync(run));
    acquired.push_front(SerialOf(Acquire(run, rig)));
  }
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

// Backend reasons on the Vulkan path (ADR 0004 grammar): every candidate
// ranked before the winner leaves one trail, in chain order.
void VkReasons(Run& run) {
  struct Case {
    const char* name;
    RendererChoice choice;
    bool accept_device;  // FakeVulkanInterop::AcceptDevice
    int gpu_next_err;    // render_context_create result; 0: success
    int gpu_err;
    const char* info;    // what get_info(VULKAN_RENDERER) reports
    int info_err;
  };
  const Case cases[] = {
      {"gpu-next-create-fails", RendererChoice::kAuto, true,
       MPV_ERROR_UNSUPPORTED, 0, "gpu", 0},
      {"both-creates-fail", RendererChoice::kAuto, true,
       MPV_ERROR_UNSUPPORTED, MPV_ERROR_VO_INIT_FAILED, "gpu-next", 0},
      {"device-not-shareable", RendererChoice::kAuto, false, 0, 0,
       "gpu-next", 0},
      {"get-info-fails", RendererChoice::kAuto, true, 0, 0, "gpu-next",
       MPV_ERROR_NOT_IMPLEMENTED},
      {"gpu-next-only-fails", RendererChoice::kGpuNext, true,
       MPV_ERROR_UNSUPPORTED, 0, "gpu-next", 0},
  };
  for (const Case& c : cases) {
    // A fresh renderer per case; none is alive across the reset.
    Fake().Reset();
    Images().Reset();
    run.trace.Add(std::string("case ") + c.name);
    if (c.gpu_next_err)
      Fake().SetCreateResult(MPV_RENDER_API_TYPE_VULKAN, "gpu-next",
                             c.gpu_next_err);
    if (c.gpu_err)
      Fake().SetCreateResult(MPV_RENDER_API_TYPE_VULKAN, "gpu", c.gpu_err);
    Fake().SetInfoRenderer(c.info, c.info_err);
    Rig rig(2, c.accept_device);
    Start(run, rig, c.choice);
    Teardown(run, rig);
  }
}

// Ring rotation under the compositor quarantine: latency 2 -> ring 5.
void VkRingQ2(Run& run) {
  Rig rig(2);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  Rotate(run, rig, 2);
  Quiesce(run);
  Teardown(run, rig);
}

// Ring rotation under the compositor quarantine: latency 4 -> ring 7.
void VkRingQ4(Run& run) {
  Rig rig(4);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  Rotate(run, rig, 4);
  Quiesce(run);
  Teardown(run, rig);
}

// A frame whose GPU work never completes: the render thread gives up after
// VulkanContext's 1 s timeout, reports gpu_timeout, backs off 100 ms and
// retries on its own; the GPU is back by then, the retry succeeds and the
// renderer reports `recovered`. No mpv frame triggers the retry: one that
// arrived during the backoff would only be skipped.
//
// The render-to-retry interval is judged in two parts (17-01; run
// 40679129407 measured 1396 ms on a hosted macos-15 against the 1100 ms the
// golden expects, because one interval mixed two clocks):
//   * wait = first render -> gpu_timeout event: VulkanContext's device wait,
//     whose 1 s value is pinned by the Phase 12 constants audit. The driver
//     or VM decides how much longer than 1 s it takes, so it has a lower bound
//     (the timeout is honoured: >= 1000 ms) and an upper bound that still
//     tells 1 s from 2 s and more ([.., 2 * 1000 ms]).
//   * backoff = gpu_timeout event -> retry render: the engine's first backoff
//     (golden retry-ms minus the 1 s timeout, 100 ms). It lies in
//     [expected - 5 ms, expected + slack]: no device noise can hide a longer
//     backoff behind the wait any more.
// When both hold the golden's retry-ms line enters the trace (so golden/vk.txt
// is unchanged); otherwise the measured line does and both parts are printed.
// Every run prints one `GOLDEN timing-info` line either way, for the
// distribution the 17-05 summary reports.
void VkGpuTimeout(Run& run) {
  const std::string expected_line =
      golden::ExpectedLine(run.expected, run.name, "retry-ms ");
  const long long expected_ms =
      expected_line.empty() ? -1 : std::atoll(expected_line.c_str() + 9);
  {
    std::lock_guard<std::mutex> lock(g_timeout_mu);
    g_timeout_seen = false;
  }
  Rig rig(2);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  Fake().SetSignalMode(SignalMode::kNever);
  rig.renderer->SetSize(64, 36);
  Fake().WaitNoted("event gpu_timeout gpu timeout",
                   golden::Ms(kGpuTimeoutMs + run.slack_ms) +
                       golden::kWaitTimeout);
  // The GPU finishes after all; later renders complete at once.
  Fake().SetSignalMode(SignalMode::kImmediate);
  Fake().SignalPending();
  rig.interop.WaitFrameReady(1);
  Sync(run);
  const std::vector<golden::Clock::time_point> times = Fake().render_times();
  golden::Clock::time_point timeout_at;
  bool timeout_seen;
  {
    std::lock_guard<std::mutex> lock(g_timeout_mu);
    timeout_seen = g_timeout_seen;
    timeout_at = g_timeout_at;
  }
  const bool have_times = times.size() >= 2 && timeout_seen;
  const long long measured =
      times.size() >= 2 ? ElapsedMs(times[0], times[1]) : -1;
  const long long wait_ms = have_times ? ElapsedMs(times[0], timeout_at) : -1;
  const long long backoff_ms = have_times ? ElapsedMs(timeout_at, times[1]) : -1;
  std::printf("GOLDEN timing-info scenario=%s wait-ms=%lld backoff-ms=%lld "
              "retry-ms=%lld\n",
              run.name.c_str(), wait_ms, backoff_ms, measured);
  const long long expected_backoff_ms = expected_ms - kGpuTimeoutMs;
  if (expected_ms > 0 && have_times && wait_ms >= kGpuTimeoutMs - 5 &&
      wait_ms <= 2 * kGpuTimeoutMs - 5 &&
      backoff_ms >= expected_backoff_ms - 5 &&
      backoff_ms <= expected_backoff_ms + run.slack_ms) {
    run.trace.Add(expected_line);
  } else {
    std::printf("GOLDEN timing scenario=%s: expected %s (slack %d ms), "
                "measured retry-ms %lld (wait-ms %lld, backoff-ms %lld)\n",
                run.name.c_str(), expected_line.c_str(), run.slack_ms,
                measured, wait_ms, backoff_ms);
    run.trace.Add("retry-ms " + std::to_string(measured));
  }
  Acquire(run, rig);
  Quiesce(run);
  Teardown(run, rig);
}

// 8K on a small GPU: the full ring (latency 4 -> 7 images) does not fit.
// The 6th CreateImage fails, the images already created are destroyed,
// and the renderer retries once with ring 5 / quarantine 2 instead of
// dropping to software; the rotation then follows quarantine 2.
void VkRingFallback(Run& run) {
  Rig rig(4);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  rig.vk.FailCreate(6);
  Rotate(run, rig, 2);
  Quiesce(run);
  Teardown(run, rig);
}

// Retire-on-resize: after a reallocation the old generation's front image
// stays on screen (AcquireFront returns it) until the first new-size frame
// is published, and is destroyed exactly once after quarantine + 1 further
// acquisitions. The new-size render is held inside the fake to observe the
// reallocated-but-unpublished window.
void VkRetireOnResize(Run& run) {
  Rig rig(2);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  FourFrames(run, rig);
  Fake().HoldRenders(true);
  const int want = rig.interop.frame_ready() + 1;
  rig.renderer->SetSize(32, 18);
  Fake().WaitRenderHeld();
  run.trace.Add(Fake().DrainAsync());
  const mpv_kit::Frame old = Acquire(run, rig);
  if (old.index != -2) run.Invariant("expected the retired frame (index -2)");
  Fake().HoldRenders(false);
  rig.interop.WaitFrameReady(want);
  Sync(run);
  Acquire(run, rig);
  for (int i = 0; i < 3; i++) {
    NextFrame(rig);
    Sync(run);
    Acquire(run, rig);
  }
  Quiesce(run);
  Teardown(run, rig);
}

// The renderer is destroyed while the old generation's front image is
// still retired (reallocated, the new size rendered, never acquired):
// every image is destroyed exactly once.
void VkTeardownWhileRetired(Run& run) {
  Rig rig(2);
  if (!Start(run, rig, RendererChoice::kGpuNext)) return;
  FourFrames(run, rig);
  const golden::Counters before = Fake().counters();
  rig.renderer->SetSize(32, 18);
  Fake().WaitRenders(before.renders - before.skips + 1);
  Sync(run);
  Quiesce(run);
  Teardown(run, rig);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"vk-publish-gate", VkPublishGate},
    {"vk-reasons", VkReasons},
    {"vk-ring-q2", VkRingQ2},
    {"vk-ring-q4", VkRingQ4},
    {"vk-gpu-timeout", VkGpuTimeout},
    {"vk-ring-fallback", VkRingFallback},
    {"vk-retire-on-resize", VkRetireOnResize},
    {"vk-teardown-while-retired", VkTeardownWhileRetired},
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
