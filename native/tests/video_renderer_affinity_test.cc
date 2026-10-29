// Thread-affinity test of the shared video renderer's libmpv render calls:
// drives the real packages/mpv_kit_video/src/video_renderer.cc and
// vulkan_backend.cc through the fake libmpv of renderer_harness.h, with a
// dedicated "raster" thread that keeps taking frames the way a compositor
// does, and checks on which thread every mpv_render_* call ran.
//
// What it proves (render.h, "Threading": one mpv_render_* call at a time,
// and for OpenGL on the thread whose context is current):
//   * render_context_report_swap, render, update, set_parameter, the final
//     set_update_callback(nullptr) and free all run on one thread, the
//     render thread (the thread of the first render call), which is
//     neither the raster thread nor the main thread;
//   * render_context_free runs exactly once, after the last render call;
//   * render_context_create, get_info and the first set_update_callback run
//     on the main thread, the caller of Start, before the render thread
//     exists;
//   * every call passes the renderer's own render context.
// The check reads the fake's call log (each call carries its thread id),
// so it does not depend on the renderer's debug assertions.
//
// Kept apart from the golden binaries because their files, goldens and the
// harness are frozen (evidence/golden-freeze.sha256 of phase 12): new
// tests go into new files. No golden file: the expectation is the rule
// above, not a trace.
//
// The software scenario runs everywhere. The Vulkan scenario (the publish-
// gated path, with its swaps) needs a Vulkan 1.3 device (lavapipe, MoltenVK
// or a GPU), like golden_vk; without one it is skipped on its own and the
// binary still passes.
//
// usage: video_renderer_affinity_test
//
// Output: `AFFINITY ok sw`, then `AFFINITY ok vk` or
// `AFFINITY vk skipped: <why>`; otherwise one
// `AFFINITY violation <scenario>: ...` line per problem.
// Exit codes: 0 pass, 1 failure.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
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
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Frames mpv announces per scenario, and the resize after the first half.
constexpr int kFrames = 12;
// How often the raster thread takes a frame: well inside the renderer's idle
// timeout (500 ms), so the compositor counts as active and the renderer
// keeps drawing instead of skipping frames.
constexpr golden::Ms kRasterPeriod{2};

/// State of one running scenario: its name and its violations, each
/// reported once with how often it occurred (Report).
struct Run {
  std::string name;
  std::vector<std::pair<std::string, int>> violations;

  bool ok() const { return violations.empty(); }

  void Violation(const std::string& what) {
    for (auto& v : violations) {
      if (v.first == what) {
        v.second++;
        return;
      }
    }
    violations.emplace_back(what, 1);
  }

  void Report() const {
    for (const auto& v : violations)
      std::printf("AFFINITY violation %s: %s (x%d)\n", name.c_str(),
                  v.first.c_str(), v.second);
  }
};

// Renderer log lines are diagnostics only; kept so a failing scenario can
// show them.
std::mutex g_log_mu;
std::vector<std::string> g_log;

std::vector<std::string> TakeLog() {
  std::lock_guard<std::mutex> lock(g_log_mu);
  std::vector<std::string> out = std::move(g_log);
  g_log.clear();
  return out;
}

/// The renderer and its fake platform halves (latency 2, RGBA).
struct Rig {
  explicit Rig(bool with_vulkan)
      : interop(2, false, nullptr, with_vulkan ? &vk : nullptr) {
    renderer = std::make_unique<VideoRenderer>(
        golden::MakeApi(), golden::FakeHandle(), &interop,
        [](const std::string& line) {
          std::lock_guard<std::mutex> lock(g_log_mu);
          g_log.push_back(line);
        },
        [](const char*, const std::string&) {});
  }

  FakeVulkanInterop vk;
  FakeInterop interop;
  std::unique_ptr<VideoRenderer> renderer;
};

/// A compositor stand-in: takes the front frame every kRasterPeriod on its
/// own thread until Stop(). Never outlives the renderer it samples.
class Raster {
 public:
  explicit Raster(VideoRenderer* renderer)
      : thread_([this, renderer] {
          while (!stop_.load()) {
            renderer->AcquireFront();
            acquisitions_.fetch_add(1);
            std::this_thread::sleep_for(kRasterPeriod);
          }
        }) {}

  ~Raster() { Stop(); }

  void Stop() {
    stop_.store(true);
    if (thread_.joinable()) thread_.join();
  }

  std::thread::id id() const { return thread_.get_id(); }
  int acquisitions() const { return acquisitions_.load(); }

  /// Waits until the raster thread took [n] more frames than it had at the
  /// call: the frame published before the call has then been taken (and,
  /// with an active consumer, its swap is due). Bounded by kWaitTimeout.
  void WaitAcquisitions(int n) {
    const int want = acquisitions_.load() + n;
    const auto deadline = golden::Clock::now() + golden::kWaitTimeout;
    while (acquisitions_.load() < want) {
      if (golden::Clock::now() >= deadline)
        throw golden::TimeoutError("raster acquisition #" +
                                   std::to_string(want));
      std::this_thread::sleep_for(golden::Ms(1));
    }
  }

 private:
  std::atomic<bool> stop_{false};
  std::atomic<int> acquisitions_{0};
  std::thread thread_;  // last: starts after the flags exist
};

/// mpv announces one new frame; waits until the renderer published it.
void NextFrame(Rig& rig) {
  const int want = rig.interop.frame_ready() + 1;
  Fake().QueueFrames(1);
  Fake().Poke();
  rig.interop.WaitFrameReady(want);
}

/// Who made a call, for the report.
std::string Role(std::thread::id t, std::thread::id render,
                 std::thread::id raster, std::thread::id main) {
  if (t == render) return "render thread";
  if (t == raster) return "raster thread";
  if (t == main) return "main thread";
  return "another thread";
}

/// Whether [what] (a call name) starts with [prefix].
bool Is(const std::string& what, const char* prefix) {
  return what.compare(0, std::strlen(prefix), prefix) == 0;
}

/// Checks the call log of one scenario against the affinity rule (see the
/// file header).
void CheckCalls(Run& run, const std::vector<golden::Call>& calls,
                std::thread::id raster, std::thread::id main) {
  std::thread::id render;
  size_t last_render = 0;
  bool any_render = false;
  for (size_t i = 0; i < calls.size(); i++) {
    if (!Is(calls[i].what, "render_context_render")) continue;
    if (!any_render) render = calls[i].thread;
    any_render = true;
    last_render = i;
  }
  if (!any_render) {
    run.Violation("no render_context_render call recorded");
    return;
  }
  if (render == raster) run.Violation("render thread is the raster thread");
  if (render == main) run.Violation("render thread is the main thread");

  int frees = 0, swaps = 0, set_parameters = 0, callbacks = 0;
  size_t free_at = 0;
  size_t last_callback = 0;
  for (size_t i = 0; i < calls.size(); i++) {
    const golden::Call& c = calls[i];
    const std::string where =
        c.what + " on the " + Role(c.thread, render, raster, main);
    if (c.what.find("(bad ctx)") != std::string::npos)
      run.Violation(where + ": not the renderer's render context");
    if (Is(c.what, "render_context_create") ||
        Is(c.what, "render_context_get_info")) {
      if (c.thread != main) run.Violation(where + " (expected: main thread)");
      continue;
    }
    if (Is(c.what, "render_context_set_update_callback")) {
      // The first registers the callback in Start; any later one removes it.
      if (callbacks++ == 0) {
        if (c.thread != main)
          run.Violation(where + " (registration, expected: main thread)");
      } else if (c.thread != render) {
        run.Violation(where + " (removal, expected: render thread)");
      }
      last_callback = i;
      continue;
    }
    if (Is(c.what, "render_context_free")) {
      frees++;
      free_at = i;
    } else if (Is(c.what, "render_context_report_swap")) {
      swaps++;
    } else if (Is(c.what, "render_context_set_parameter")) {
      set_parameters++;
    }
    if (c.thread != render) run.Violation(where + " (expected: render thread)");
  }
  if (frees != 1)
    run.Violation("render_context_free called " + std::to_string(frees) +
                  " time(s) (expected: once)");
  if (frees == 1 && free_at < last_render)
    run.Violation("render_context_free before the last render call");
  if (callbacks != 2)
    run.Violation("render_context_set_update_callback called " +
                  std::to_string(callbacks) +
                  " time(s) (expected: register and remove)");
  if (callbacks == 2 && frees == 1 && last_callback > free_at)
    run.Violation("update callback removed after render_context_free");
  if (swaps == 0) run.Violation("no render_context_report_swap call recorded");
  if (set_parameters == 0)
    run.Violation("no render_context_set_parameter call recorded");
  if (Fake().callback_set()) run.Violation("update callback still set");
}

/// One scenario: Start on the main thread, a raster thread taking frames,
/// an ICC profile, kFrames frames with a resize halfway, then the raster
/// thread stops (the platform unregisters the texture) and the main thread
/// destroys the renderer.
void Scenario(Run& run, bool with_vulkan, RendererChoice choice) {
  const std::thread::id main = std::this_thread::get_id();
  Rig rig(with_vulkan);
  if (!rig.renderer->Start(choice)) {
    run.Violation("Start failed: " + rig.renderer->backend_reason());
    return;
  }
  const bool vulkan = rig.renderer->backend() == mpv_kit::Backend::kVulkan;
  if (vulkan != with_vulkan) {
    run.Violation("unexpected backend: " + rig.renderer->backend_reason());
    return;
  }
  rig.renderer->SetSize(64, 36);
  rig.interop.WaitFrameReady(1);
  std::thread::id raster_id;
  int acquisitions = 0;
  {
    Raster raster(rig.renderer.get());
    raster_id = raster.id();
    // Applied on the render thread before the next frame.
    rig.renderer->SetIccProfile({1, 2, 3});
    for (int i = 0; i < kFrames; i++) {
      if (i == kFrames / 2) rig.renderer->SetSize(32, 18);
      NextFrame(rig);
      // Paced like a compositor: the frame is taken before the next one,
      // so each frame's swap is due at the acquisition.
      raster.WaitAcquisitions(2);
    }
    raster.Stop();
    acquisitions = raster.acquisitions();
  }
  if (acquisitions == 0) run.Violation("the raster thread took no frame");
  Fake().SignalPending();
  rig.renderer.reset();
  CheckCalls(run, Fake().calls(), raster_id, main);
  if (Images().live() != 0)
    run.Violation(std::to_string(Images().live()) +
                  " image(s) never destroyed");
}

/// Same probe as golden_vk: skip the Vulkan scenario only when the loader,
/// an instance or a Vulkan 1.3 device is missing. Returns the reason to
/// skip, or "" to run it.
std::string Probe() {
  Fake().Reset();
  Images().Reset();
  std::string skip;
  {
    Rig rig(true);
    rig.renderer->Start(RendererChoice::kGpuNext);
    const std::string reason = rig.renderer->backend_reason();
    if (rig.renderer->backend() != mpv_kit::Backend::kVulkan &&
        (reason.find("Vulkan loader") != std::string::npos ||
         reason.find("vkCreateInstance failed") != std::string::npos ||
         reason.find("no Vulkan 1.3 device") != std::string::npos ||
         reason.find("Vulkan < 1.3 on") != std::string::npos))
      skip = reason;
  }
  TakeLog();
  return skip;
}

/// Runs one scenario with a fresh fake; false if it failed.
bool RunScenario(const char* name, bool with_vulkan, RendererChoice choice) {
  Fake().Reset();
  Images().Reset();
  TakeLog();
  Run run{name, {}};
  try {
    Scenario(run, with_vulkan, choice);
  } catch (const std::exception& e) {
    run.Violation(std::string("timeout waiting for ") + e.what());
  }
  for (const std::string& v : Images().TakeViolations()) run.Violation(v);
  run.Report();
  if (!run.ok()) {
    for (const std::string& line : TakeLog())
      std::fprintf(stderr, "  [%s] log: %s\n", name, line.c_str());
  }
  return run.ok();
}

}  // namespace

int main(int argc, char** argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  (void)argv;
  if (argc != 1) {
    std::fprintf(stderr, "usage: video_renderer_affinity_test\n");
    return 1;
  }
  // The scenarios run the default candidate chain.
  golden::SetEnv("MPV_KIT_VIDEO_API", nullptr);
  bool ok = true;
  if (RunScenario("sw", false, RendererChoice::kSoftware)) {
    std::printf("AFFINITY ok sw\n");
  } else {
    ok = false;
  }
  const std::string skip = Probe();
  if (!skip.empty()) {
    std::printf("AFFINITY vk skipped: %s\n", skip.c_str());
  } else if (RunScenario("vk", true, RendererChoice::kGpuNext)) {
    std::printf("AFFINITY ok vk\n");
  } else {
    ok = false;
  }
  return ok ? 0 : 1;
}
