// Software-path golden test of the shared video renderer's retired front
// when a resize follows a resize that never produced a frame: drives the
// real packages/mpv_kit_video/src/video_renderer.cc through the fake libmpv
// of renderer_harness.h and compares what it does with
// golden/sw_retire_twice.txt.
//
// Kept apart from video_renderer_golden_sw.cc because that file, its golden
// and the harness are frozen (evidence/golden-freeze.sha256 of phase 12):
// new scenarios go into new files. The Vulkan path of the same defect is
// video_renderer_golden_vk_retire_twice.cc. Runs headless and GPU-less on
// every runner, like golden_sw.
//
// usage: video_renderer_golden_sw_retire_twice <golden/sw_retire_twice.txt>
//            [--slack-ms=N]
//   --slack-ms  upper tolerance of timing expectations (meson passes 250,
//               or 1000 for sanitizer builds)
//
// Output: `GOLDEN ok scenarios=<n>` on success; otherwise one
// `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure. The golden file is only read.

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
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Waits beyond kPresentTimeout (50 ms) so an unpresented frame's swap has
// been reported by the render thread's own timeout.
constexpr golden::Ms kPastPresentTimeout{60};
// Failed 32x18 renders before the second resize: the resize itself, then
// retries after 100 + 200 + 400 + 800 ms. The renderer then backs off
// 1600 ms, more than the sanitizer slack, so the second resize (which
// retries at once) cannot race a scheduled retry.
constexpr int kFailures = 5;
constexpr int kFailureBudgetMs = 100 + 200 + 400 + 800;

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

// Renderer log lines are diagnostics only (never part of a trace); kept so
// a failing scenario can show them.
std::mutex g_log_mu;
std::vector<std::string> g_log;

std::vector<std::string> LogLines() {
  std::lock_guard<std::mutex> lock(g_log_mu);
  return g_log;
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

/// Start() and the resulting backend, reason and create attempts.
bool Start(Run& run, VideoRenderer& r) {
  const bool ok = r.Start(RendererChoice::kSoftware);
  const bool vulkan = r.backend() == mpv_kit::Backend::kVulkan;
  run.trace.Add(ok ? std::string("start ok backend=") +
                         (vulkan ? "vulkan" : "software") + " reason=\"" +
                         r.backend_reason() + "\""
                   : "start=false reason=\"" + r.backend_reason() + "\"");
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
void NextFrame(FakeInterop& interop) {
  const int want = interop.frame_ready() + 1;
  Fake().QueueFrames(1);
  Fake().Poke();
  interop.WaitFrameReady(want);
}

/// The acquire line without the pixels: index, size and whether a buffer
/// was handed out.
std::string AcquireLine(const mpv_kit::Frame& f) {
  return "acquire index=" + std::to_string(f.index) + " " +
         std::to_string(f.width) + "x" + std::to_string(f.height);
}

/// What the compositor does when it samples a texture whose buffer is
/// known to be alive: reads the frame number the fake wrote into it.
void Acquire(Run& run, VideoRenderer& r) {
  const mpv_kit::Frame f = r.AcquireFront();
  std::string line = AcquireLine(f);
  if (f.pixels) {
    const int frame = f.pixels[0] | f.pixels[1] << 8 | f.pixels[2] << 16;
    line += " frame=" + std::to_string(frame);
    // rgb0/bgr0 leave the padding byte undefined; textures read it as alpha.
    if (f.pixels[3] != 0xff) run.Invariant("padding byte is not 0xff");
  } else {
    line += " frame=none";
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

/// Destroys the renderer (joins its thread, frees the render context).
void Teardown(Run& run, std::unique_ptr<VideoRenderer>& r) {
  r.reset();
  run.trace.Add("teardown frees=" + std::to_string(Fake().counters().frees));
}

// --- Scenario ----------------------------------------------------------------

// A resize while the previous resize has no frame yet (latency 2, ring 5).
//
// One 64x36 frame is on screen. The resize to 32x18 moves the 64x36
// buffers into retirement and every 32x18 render fails, so the 32x18
// generation never publishes a frame: the retired 64x36 frame is still
// what the compositor shows. A second resize to 48x27 retires the 32x18
// buffers in turn, which frees the 64x36 ones. From then on AcquireFront
// must not hand out the 64x36 frame (its pixels point into freed memory):
// until the first 48x27 frame is published there is nothing to show
// (index -1).
//
// The 48x27 render is held inside the fake to observe the window between
// the reallocation and the publish. That frame is never read through its
// pixel pointer: on the defect it is freed memory, and the line and the
// invariant below report it without touching it.
void SwRetireTwice(Run& run) {
  FakeInterop interop(/*latency=*/2, /*bgra=*/false, /*interop_reason=*/nullptr);
  auto r = MakeRenderer(interop);
  if (!Start(run, *r)) return;
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  Sync(run);
  Acquire(run, *r);
  // Every 32x18 render fails until the backoff is long (see kFailures).
  Fake().SetDefaultRenderResult(MPV_ERROR_GENERIC);
  const int renders = Fake().counters().renders;
  r->SetSize(32, 18);
  Fake().WaitRenders(renders + kFailures,
                     golden::Ms(kFailureBudgetMs + kFailures * run.slack_ms) +
                         golden::kWaitTimeout);
  Sync(run);
  // Nothing at 32x18: the retired 64x36 frame is still shown (and alive).
  Acquire(run, *r);
  // Second resize before any 32x18 frame exists; it retries at once and
  // succeeds, held inside the fake before it can be published.
  Fake().HoldRenders(true);
  Fake().SetDefaultRenderResult(0);
  const int want = interop.frame_ready() + 1;
  r->SetSize(48, 27);
  Fake().WaitRenderHeld();
  run.trace.Add(Fake().DrainAsync());
  const mpv_kit::Frame window = r->AcquireFront();
  run.trace.Add(AcquireLine(window) +
                (window.pixels ? " pixels=set" : " frame=none"));
  if (window.pixels && window.width == 64 && window.height == 36)
    run.Invariant("USE AFTER FREE: retired 64x36 frame handed out after the "
                  "48x27 reallocation freed its buffers");
  Fake().HoldRenders(false);
  interop.WaitFrameReady(want);
  Sync(run);
  Acquire(run, *r);
  for (int i = 0; i < 2; i++) {
    NextFrame(interop);
    Sync(run);
    Acquire(run, *r);
  }
  Quiesce(run);
  Teardown(run, r);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"sw-retire-twice", SwRetireTwice},
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
                 "usage: video_renderer_golden_sw_retire_twice "
                 "<golden/sw_retire_twice.txt> [--slack-ms=N]\n");
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
    Run run{def.name, slack_ms, {}, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("GOLDEN timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
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
