// Software-path golden test of the shared video renderer: drives the real
// packages/mpv_kit_video/src/video_renderer.cc through a fake libmpv
// (renderer_harness.h) and compares what it does with golden/sw.txt.
//
// Runs headless and GPU-less on every runner: FakeInterop has no Vulkan
// interop, so the renderer takes its software path (MPV_RENDER_API_TYPE_SW)
// and never touches a Vulkan device. libmpv is neither linked nor loaded.
//
// usage: video_renderer_golden_sw <golden/sw.txt> [--slack-ms=N]
//   --slack-ms  upper tolerance of timing expectations (meson passes 250,
//               or 1000 for sanitizer builds)
//
// Output: `GOLDEN ok scenarios=<n>` on success; otherwise one
// `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure. The golden file is only read.

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <functional>
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
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Waits beyond kPresentTimeout (50 ms) so an unpresented frame's swap has
// been reported by the render thread's own timeout.
constexpr golden::Ms kPastPresentTimeout{60};

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

const char* BackendName(mpv_kit::Backend b) {
  return b == mpv_kit::Backend::kVulkan ? "vulkan" : "software";
}

/// Start() and the resulting backend, reason and create attempts.
bool Start(Run& run, VideoRenderer& r, RendererChoice choice) {
  const bool ok = r.Start(choice);
  if (ok) {
    run.trace.Add(std::string("start ok backend=") + BackendName(r.backend()) +
                  " reason=\"" + r.backend_reason() + "\"");
  } else {
    run.trace.Add("start=false reason=\"" + r.backend_reason() + "\"");
  }
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
/// the platform (rendered, or skipped while sized and not backing off).
void NextFrame(FakeInterop& interop) {
  const int want = interop.frame_ready() + 1;
  Fake().QueueFrames(1);
  Fake().Poke();
  interop.WaitFrameReady(want);
}

/// What the compositor does when it samples the texture.
mpv_kit::Frame Acquire(Run& run, VideoRenderer& r) {
  const mpv_kit::Frame f = r.AcquireFront();
  std::string line = "acquire index=" + std::to_string(f.index) + " " +
                     std::to_string(f.width) + "x" + std::to_string(f.height);
  if (f.pixels) {
    const int frame = f.pixels[0] | f.pixels[1] << 8 | f.pixels[2] << 16;
    line += " frame=" + std::to_string(frame);
    // rgb0/bgr0 leave the padding byte undefined; textures read it as alpha.
    if (f.pixels[3] != 0xff) run.Invariant("padding byte is not 0xff");
  } else {
    line += " frame=none";
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

/// Destroys the renderer (joins its thread, frees the render context).
void Teardown(Run& run, std::unique_ptr<VideoRenderer>& r) {
  r.reset();
  run.trace.Add("teardown frees=" + std::to_string(Fake().counters().frees));
}

// --- Scenarios ---------------------------------------------------------------

// Explicit software renderer: the first frame comes from the initial size,
// then three mpv frames, each taken by the compositor.
void SwRequestedBasic(Run& run) {
  FakeInterop interop(/*latency=*/2, /*bgra=*/false, /*interop_reason=*/nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, *r);
  for (int i = 0; i < 3; i++) {
    NextFrame(interop);
    Sync(run);
    Acquire(run, *r);
  }
  Quiesce(run);
  Teardown(run, r);
}

// Start() under kAuto without Vulkan interop: software, with the reason.
void FallbackScenario(Run& run, const char* interop_reason) {
  FakeInterop interop(2, false, interop_reason);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kAuto)) return;
  Quiesce(run);
  Teardown(run, r);
}

void SwFallbackNoInterop(Run& run) { FallbackScenario(run, nullptr); }

void SwFallbackInteropReason(Run& run) {
  FallbackScenario(run, "probe failed (0x887A0004)");
}

// The software render context cannot be created: Start() fails, no render
// thread runs, nothing is freed.
void SwCreateFails(Run& run) {
  Fake().SetCreateResult(MPV_RENDER_API_TYPE_SW, nullptr,
                         MPV_ERROR_UNSUPPORTED);
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (Start(run, *r, RendererChoice::kSoftware))
    run.Invariant("Start() succeeded without a render context");
  run.trace.Add(std::string("update-callback ") +
                (Fake().callback_set() ? "set" : "none"));
  Quiesce(run);
  Teardown(run, r);
}

/// The test's own model of the ring rules (front, in use, quarantine of the
/// last `latency` images the compositor gave back), in buffer ordinals.
struct RingModel {
  explicit RingModel(int latency) : latency(latency) {}

  /// A render wrote `buf`: it must not be any image the compositor may
  /// still read.
  void Rendered(Run& run, int buf) {
    const bool quarantined =
        std::find(quarantine.begin(), quarantine.end(), buf) != quarantine.end();
    if (buf == front || buf == in_use || quarantined)
      run.Invariant("rendered into busy buffer " + std::to_string(buf));
    front = buf;
  }

  /// The compositor took `buf`; the image it held before is quarantined.
  void Acquired(Run& run, int buf) {
    if (buf != front)
      run.Invariant("acquired buffer " + std::to_string(buf) +
                    " is not the newest frame " + std::to_string(front));
    if (in_use != front && in_use >= 0) {
      quarantine.insert(quarantine.begin(), in_use);
      if (static_cast<int>(quarantine.size()) > latency) quarantine.pop_back();
    }
    in_use = front;
  }

  const int latency;
  int front = -1;
  int in_use = -1;
  std::vector<int> quarantine;  // newest first
};

// Twelve frames, each taken by the compositor: with latency L the ring is
// L + 3 images, and rendering rotates through the L + 2 not held back.
void RingScenario(Run& run, int latency, bool bgra) {
  FakeInterop interop(latency, bgra, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  RingModel model(latency);
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  for (int k = 0; k < 12; k++) {
    if (k > 0) NextFrame(interop);
    Sync(run);
    model.Rendered(run, Fake().last_buf());
    const mpv_kit::Frame f = Acquire(run, *r);
    model.Acquired(run, Fake().BufOf(f.pixels));
  }
  Quiesce(run);
  Teardown(run, r);
}

void SwRingQ2(Run& run) { RingScenario(run, 2, false); }
void SwRingQ4(Run& run) { RingScenario(run, 4, true); }

// A resize keeps the previous generation's last frame on screen until the
// first frame at the new size is published (no black flash). The render at
// the new size is held inside the fake, after the ring was reallocated.
void SwRetireOnResize(Run& run) {
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, *r);
  for (int i = 0; i < 3; i++) {
    NextFrame(interop);
    Sync(run);
    Acquire(run, *r);
  }
  Fake().HoldRenders(true);
  const int want = interop.frame_ready() + 1;
  r->SetSize(32, 18);
  Fake().WaitRenderHeld();
  // The render thread is parked inside the render call: its lines so far
  // are complete.
  run.trace.Add(Fake().DrainAsync());
  // Reads the retired generation's pixels: ASan reports an early free.
  const mpv_kit::Frame old = Acquire(run, *r);
  if (old.index != -2) run.Invariant("expected the retired frame (index -2)");
  Fake().HoldRenders(false);
  interop.WaitFrameReady(want);
  Sync(run);
  Acquire(run, *r);
  for (int i = 0; i < 3; i++) {
    NextFrame(interop);
    Sync(run);
    Acquire(run, *r);
  }
  Quiesce(run);
  Teardown(run, r);
}

/// Integers of `line` after its first word ("backoff-ms 100 200" → 100, 200).
std::vector<long long> ParseNumbers(const std::string& line) {
  std::vector<long long> out;
  size_t at = line.find(' ');
  while (at != std::string::npos && at + 1 < line.size()) {
    out.push_back(std::atoll(line.c_str() + at + 1));
    at = line.find(' ', at + 1);
  }
  return out;
}

std::string JoinNumbers(const std::string& word,
                        const std::vector<long long>& values) {
  std::string out = word;
  for (long long v : values) out += " " + std::to_string(v);
  return out;
}

long long ElapsedMs(golden::Clock::time_point from,
                    golden::Clock::time_point to) {
  return std::chrono::duration_cast<golden::Ms>(to - from).count();
}

// Every render fails: the renderer retries after 100 ms, doubling up to the
// 5 s cap, reports render_error on failure 1, 2, 4, 8, only skips new mpv
// frames while backing off, and reports `recovered` once a retry succeeds.
void SwBackoff(Run& run) {
  // Expected intervals come from the golden; measured ones must lie within
  // [expected - 5 ms, expected + slack] (they are never written anywhere).
  const std::string expected_line =
      golden::ExpectedLine(run.expected, run.name, "backoff-ms ");
  const std::vector<long long> expected = ParseNumbers(expected_line);
  long long budget = 0;
  for (long long ms : expected) budget += ms + run.slack_ms;

  Fake().SetDefaultRenderResult(MPV_ERROR_GENERIC);
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  // The resize renders (and fails) at once; no frame from mpv after that.
  r->SetSize(64, 36);
  const int failures = static_cast<int>(expected.size()) + 1;
  Fake().WaitRenders(failures, golden::Ms(budget) + golden::kWaitTimeout);
  Sync(run);

  const std::vector<golden::Clock::time_point> times = Fake().render_times();
  std::vector<long long> measured;
  for (size_t i = 1; i < times.size() && i < size_t(failures); i++)
    measured.push_back(ElapsedMs(times[i - 1], times[i]));
  bool within = !expected.empty() && measured.size() == expected.size();
  for (size_t i = 0; within && i < measured.size(); i++)
    within = measured[i] >= expected[i] - 5 &&
             measured[i] <= expected[i] + run.slack_ms;
  if (within) {
    run.trace.Add(expected_line);
  } else {
    std::printf("GOLDEN timing scenario=%s: expected %s (slack %d ms), "
                "measured %s\n",
                run.name.c_str(), expected_line.c_str(), run.slack_ms,
                JoinNumbers("backoff-ms", measured).c_str());
    run.trace.Add(JoinNumbers("backoff-ms", measured));
  }

  // Rendering works again, but the renderer is still backing off (5 s): a
  // new mpv frame is only skipped and nothing reaches the platform.
  Fake().SetDefaultRenderResult(0);
  Fake().QueueFrames(1);
  Fake().Poke();
  Fake().WaitSkips(1);
  Sync(run);
  run.trace.Add("frame-ready=" + std::to_string(interop.frame_ready()));
  // The scheduled retry at the cap renders and recovers.
  interop.WaitFrameReady(1, golden::Ms(5000 + run.slack_ms) +
                                golden::kWaitTimeout);
  Sync(run);
  Quiesce(run);
  Teardown(run, r);
}

/// Resizes while backing off and checks that render call `n` (the retry)
/// follows within the slack instead of waiting for the backoff.
void ResizeRetry(Run& run, VideoRenderer& r, int w, int h, int n) {
  const golden::Clock::time_point t0 = golden::Clock::now();
  r.SetSize(w, h);
  Fake().WaitRenders(n);
  const long long ms = ElapsedMs(t0, Fake().render_times()[size_t(n) - 1]);
  Sync(run);
  if (ms <= run.slack_ms) {
    run.trace.Add("resize-retry immediate");
  } else {
    std::printf("GOLDEN timing scenario=%s: retry %lld ms after resize "
                "(slack %d ms)\n",
                run.name.c_str(), ms, run.slack_ms);
    run.trace.Add("resize-retry after-ms=" + std::to_string(ms));
  }
}

// A new size is the usual cure for allocation failures: SetSize ends the
// backoff at once, both while failing and when the retry succeeds.
void SwResizeRetriesAtOnce(Run& run) {
  Fake().SetDefaultRenderResult(MPV_ERROR_GENERIC);
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  r->SetSize(64, 36);
  // Five failures (the resize, then retries after 100 + 200 + 400 + 800 ms):
  // the renderer now backs off 1600 ms, more than the sanitizer slack, so an
  // immediate retry is distinguishable from the scheduled one.
  Fake().WaitRenders(5, golden::Ms(1500 + 5 * run.slack_ms) +
                            golden::kWaitTimeout);
  Sync(run);
  ResizeRetry(run, *r, 32, 18, 6);  // still failing: backs off 3200 ms
  Fake().SetDefaultRenderResult(0);
  ResizeRetry(run, *r, 48, 27, 7);  // succeeds: recovered
  Quiesce(run);
  Teardown(run, r);
}

// The compositor stops taking frames for longer than kIdleTimeout (500 ms):
// new frames are skipped (idle), and the next acquisition ends it (active)
// with one redraw.
void SwIdleActive(Run& run) {
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, *r);
  for (int i = 0; i < 2; i++) {
    NextFrame(interop);
    Sync(run);
    Acquire(run, *r);
  }
  std::this_thread::sleep_for(golden::Ms(600));
  for (int i = 0; i < 3; i++) {
    NextFrame(interop);  // skipped, but still announced to the platform
    Sync(run);
  }
  const int want = interop.frame_ready() + 1;
  Acquire(run, *r);  // the last drawn frame, now stale
  interop.WaitFrameReady(want);
  Sync(run);
  Acquire(run, *r);
  Quiesce(run);
  Teardown(run, r);
}

// SetIccProfile reaches mpv on the render thread before the next frame and
// redraws even without a new frame from mpv (paused).
void SwIcc(Run& run) {
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, *r);
  const std::vector<std::vector<uint8_t>> profiles = {{1, 2, 3}, {}};
  for (const std::vector<uint8_t>& profile : profiles) {
    const int want = interop.frame_ready() + 1;
    r->SetIccProfile(profile);
    interop.WaitFrameReady(want);
    Sync(run);
    Acquire(run, *r);
  }
  Quiesce(run);
  Teardown(run, r);
}

// Non-positive sizes are ignored: no resize, and mpv's frames are advanced
// with SKIP_RENDERING without announcing anything to the platform.
void SwSetSizeInvalid(Run& run) {
  FakeInterop interop(2, false, nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r, RendererChoice::kSoftware)) return;
  r->SetSize(0, 10);
  r->SetSize(-1, -1);
  for (int i = 1; i <= 2; i++) {
    Fake().QueueFrames(1);
    Fake().Poke();
    Fake().WaitSkips(i);
  }
  Sync(run);
  run.trace.Add("frame-ready=" + std::to_string(interop.frame_ready()));
  Acquire(run, *r);
  Quiesce(run);
  Teardown(run, r);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"sw-requested-basic", SwRequestedBasic},
    {"sw-fallback-no-interop", SwFallbackNoInterop},
    {"sw-fallback-interop-reason", SwFallbackInteropReason},
    {"sw-create-fails", SwCreateFails},
    {"sw-ring-q2", SwRingQ2},
    {"sw-ring-q4", SwRingQ4},
    {"sw-retire-on-resize", SwRetireOnResize},
    {"sw-backoff", SwBackoff},
    {"sw-resize-retries-at-once", SwResizeRetriesAtOnce},
    {"sw-idle-active", SwIdleActive},
    {"sw-icc", SwIcc},
    {"sw-setsize-invalid", SwSetSizeInvalid},
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
                 "usage: video_renderer_golden_sw <golden/sw.txt> "
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
