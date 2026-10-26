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

#include <chrono>
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
    run.trace.Add("start=false");
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

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"sw-requested-basic", SwRequestedBasic},
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
