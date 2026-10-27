// Binding test of the shared video renderer's libmpv render calls (Phase 15,
// GLX-03): drives the real packages/mpv_kit_video/src/video_renderer.cc
// through the fake libmpv of renderer_harness.h with a backend that has
// thread affinity, and checks that every mpv_render_* call runs on a thread
// the backend has bound.
//
// What it proves (render.h, "Threading": for OpenGL every mpv_render_* call
// must be made on a thread where mpv's GL context is current, one at a time):
//   * the backend's BindThread/UnbindThread model a GL context: a thread is
//     "bound" between its own BindThread and UnbindThread (thread-local),
//     and every one of the eight mpv_render_* calls the renderer makes is
//     checked on entry; a call on an unbound thread is a violation;
//   * the create-time calls (render_context_create, render_context_get_info
//     and the first render_context_set_update_callback) run inside
//     RenderBackend::RunBound, here on a short-lived thread of the backend's
//     own (the shape of the OpenGL backend of 15-05), which is neither the
//     main thread nor the render thread;
//   * render, update, report_swap, set_parameter, the last
//     set_update_callback(nullptr) and render_context_free run on the render
//     thread, which is neither the RunBound thread nor the raster or main
//     thread;
//   * the RunBound thread unbinds before the render thread binds (a context
//     is current on one thread at a time), and binds and unbinds pair up on
//     every thread;
//   * render_context_free runs exactly once.
//
// The fake backend delegates all rendering to the engine's software backend
// and only adds the thread model, so no GPU, EGL or libmpv is needed.
//
// Kept apart from the golden binaries and the Phase 12 affinity test (which
// pins the default backend's create-time calls to the caller of Start)
// because those files, goldens and the harness are frozen
// (evidence/golden-freeze*.sha256): new tests go into new files. No golden
// file: the expectation is the rule above, not a trace.
//
// usage: video_renderer_bind_test
//
// Output: `BIND ok`, otherwise one `BIND violation: ...` line per problem.
// Exit codes: 0 pass, 1 failure.

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
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
using golden::Images;
using mpv_kit::MpvApi;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Frames mpv announces, and the resize after the first half.
constexpr int kFrames = 8;
// How often the raster thread takes a frame: well inside kPresentTimeout
// (50 ms), so the renderer treats it as an active consumer.
constexpr golden::Ms kRasterPeriod{2};

// --- Thread binding model -----------------------------------------------------

/// One BindThread or UnbindThread of the fake backend, in global order.
struct BindEvent {
  int seq;
  std::thread::id thread;
  bool bind;
};

std::mutex g_mu;
std::vector<BindEvent> g_events;                 // guarded by g_mu
std::vector<std::string> g_violations;           // guarded by g_mu
std::thread::id g_runbound_thread;               // guarded by g_mu
int g_runbound_calls = 0;                        // guarded by g_mu
// Whether the calling thread is between its BindThread and UnbindThread:
// the stand-in for "mpv's GL context is current on this thread".
thread_local bool t_bound = false;

void ResetState() {
  std::lock_guard<std::mutex> lock(g_mu);
  g_events.clear();
  g_violations.clear();
  g_runbound_thread = std::thread::id();
  g_runbound_calls = 0;
}

void RecordBind(bool bind) {
  std::lock_guard<std::mutex> lock(g_mu);
  g_events.push_back({static_cast<int>(g_events.size()),
                      std::this_thread::get_id(), bind});
}

/// Checked on entry of every mpv_render_* call: the thread must be bound.
void CheckBound(const char* call) {
  if (t_bound) return;
  std::lock_guard<std::mutex> lock(g_mu);
  g_violations.push_back(std::string(call) +
                         " called on a thread the backend has not bound");
}

// --- The libmpv table with the binding check -----------------------------------

// The fake libmpv table the checked one forwards to.
MpvApi g_real;

MpvApi MakeCheckedApi() {
  g_real = golden::MakeApi();
  MpvApi api = g_real;
  api.render_context_create = [](mpv_render_context** out, mpv_handle* handle,
                                 mpv_render_param* params) {
    CheckBound("render_context_create");
    return g_real.render_context_create(out, handle, params);
  };
  api.render_context_set_update_callback =
      [](mpv_render_context* ctx, mpv_render_update_fn fn, void* cb_ctx) {
        CheckBound("render_context_set_update_callback");
        g_real.render_context_set_update_callback(ctx, fn, cb_ctx);
      };
  api.render_context_update = [](mpv_render_context* ctx) {
    CheckBound("render_context_update");
    return g_real.render_context_update(ctx);
  };
  api.render_context_render = [](mpv_render_context* ctx,
                                 mpv_render_param* params) {
    CheckBound("render_context_render");
    return g_real.render_context_render(ctx, params);
  };
  api.render_context_report_swap = [](mpv_render_context* ctx) {
    CheckBound("render_context_report_swap");
    g_real.render_context_report_swap(ctx);
  };
  api.render_context_free = [](mpv_render_context* ctx) {
    CheckBound("render_context_free");
    g_real.render_context_free(ctx);
  };
  api.render_context_get_info = [](mpv_render_context* ctx,
                                   mpv_render_param param) {
    CheckBound("render_context_get_info");
    return g_real.render_context_get_info(ctx, param);
  };
  api.render_context_set_parameter = [](mpv_render_context* ctx,
                                        mpv_render_param param) {
    CheckBound("render_context_set_parameter");
    return g_real.render_context_set_parameter(ctx, param);
  };
  return api;
}

// --- Fake backend with thread affinity -----------------------------------------

/// The engine's software backend with an OpenGL-like thread model: wire name
/// "opengl", BindThread/UnbindThread set the thread's bound flag, and
/// RunBound runs its function on a thread of its own, bound for the call.
class AffinityBackend final : public mpv_kit::RenderBackend {
 public:
  AffinityBackend() : inner_(mpv_kit::CreateSoftwareBackend(false)) {}

  const char* wire_name() const override { return "opengl"; }
  mpv_kit::Backend frame_kind() const override { return inner_->frame_kind(); }
  bool pipelined() const override { return inner_->pipelined(); }

  bool BindThread() override {
    t_bound = true;
    RecordBind(true);
    return true;
  }
  void UnbindThread() override {
    t_bound = false;
    RecordBind(false);
  }
  void RunBound(const std::function<void()>& fn) override {
    // A thread of its own, as the OpenGL backend will: it makes the context
    // current, runs the create-time calls and releases the context before
    // the render thread binds it.
    std::thread worker([this, &fn] {
      {
        std::lock_guard<std::mutex> lock(g_mu);
        g_runbound_thread = std::this_thread::get_id();
        g_runbound_calls++;
      }
      if (BindThread()) {
        fn();
        UnbindThread();
      }
    });
    worker.join();
  }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    return inner_->Create(api, handle, renderer, out, why);
  }
  std::string device_name() const override { return "fake-gl"; }
  std::string RendererName(const MpvApi& api,
                           mpv_render_context* ctx) const override {
    // Ask mpv like the Vulkan and OpenGL backends do, so get_info is among
    // the checked create-time calls.
    const char* active = nullptr;
    const int info = api.render_context_get_info(
        ctx, {MPV_RENDER_PARAM_VULKAN_RENDERER, &active});
    return info >= 0 && active ? active : "unknown renderer";
  }

  bool AllocTargets(int count, int width, int height, int keep_slot,
                    std::string* error) override {
    return inner_->AllocTargets(count, width, height, keep_slot, error);
  }
  void FreeRetired() override { inner_->FreeRetired(); }
  mpv_kit::TargetView FrameFor(int slot) override {
    return inner_->FrameFor(slot);
  }
  int Render(const MpvApi& api, mpv_render_context* ctx, int slot, int width,
             int height) override {
    return inner_->Render(api, ctx, slot, width, height);
  }
  mpv_kit::WaitResult Wait(int slot) override { return inner_->Wait(slot); }
  void Release(const MpvApi& api, mpv_render_context* ctx) override {
    inner_->Release(api, ctx);
  }

 private:
  std::unique_ptr<mpv_kit::RenderBackend> inner_;
};

/// A platform whose only candidate is the affinity backend ("opengl"/"gpu").
class BindInterop final : public FakeInterop {
 public:
  BindInterop() : FakeInterop(2, false, nullptr) {}

  std::vector<mpv_kit::BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    (void)choice;
    return {{"opengl", "gpu"}};
  }
  std::unique_ptr<mpv_kit::RenderBackend> CreateBackend(
      const char* api) override {
    if (std::strcmp(api, "opengl") != 0) return nullptr;
    return std::make_unique<AffinityBackend>();
  }
};

// --- Scenario -----------------------------------------------------------------

// Renderer log lines are diagnostics only; kept for a failing run.
std::mutex g_log_mu;
std::vector<std::string> g_log;

/// A compositor stand-in: takes the front frame every kRasterPeriod on its
/// own thread until Stop().
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
  /// call. Bounded by kWaitTimeout.
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

/// Whether [what] (a call name) starts with [prefix].
bool Is(const std::string& what, const char* prefix) {
  return what.compare(0, std::strlen(prefix), prefix) == 0;
}

/// Who made a call, for the report.
std::string Role(std::thread::id t, std::thread::id runbound,
                 std::thread::id render, std::thread::id main) {
  if (t == runbound) return "RunBound thread";
  if (t == render) return "render thread";
  if (t == main) return "main thread";
  return "another thread";
}

/// Problems found by the checks, reported once each.
struct Problems {
  std::vector<std::string> lines;
  void Add(const std::string& what) {
    for (const std::string& l : lines)
      if (l == what) return;
    lines.push_back(what);
  }
};

/// Where in [events] [thread]'s first bind and last unbind are, and whether
/// its binds and unbinds alternate and end unbound.
struct ThreadBinds {
  int first_bind = -1;
  int last_unbind = -1;
  bool paired = true;
};

ThreadBinds BindsOf(const std::vector<BindEvent>& events,
                    std::thread::id thread) {
  ThreadBinds out;
  bool bound = false;
  for (const BindEvent& e : events) {
    if (e.thread != thread) continue;
    if (e.bind) {
      if (bound) out.paired = false;
      bound = true;
      if (out.first_bind < 0) out.first_bind = e.seq;
    } else {
      if (!bound) out.paired = false;
      bound = false;
      out.last_unbind = e.seq;
    }
  }
  if (bound) out.paired = false;
  return out;
}

/// Checks the fake libmpv's call log and the bind events against the rule in
/// the file header.
void Check(Problems& p, const std::vector<golden::Call>& calls,
           std::thread::id main) {
  std::vector<BindEvent> events;
  std::vector<std::string> violations;
  std::thread::id runbound;
  int runbound_calls = 0;
  {
    std::lock_guard<std::mutex> lock(g_mu);
    events = g_events;
    violations = g_violations;
    runbound = g_runbound_thread;
    runbound_calls = g_runbound_calls;
  }
  for (const std::string& v : violations) p.Add(v);
  if (runbound_calls != 1)
    p.Add("RunBound ran " + std::to_string(runbound_calls) +
          " time(s) (expected: once)");

  std::thread::id render;
  bool any_render = false;
  for (const golden::Call& c : calls) {
    if (!Is(c.what, "render_context_render")) continue;
    render = c.thread;
    any_render = true;
    break;
  }
  if (!any_render) {
    p.Add("no render_context_render call recorded");
    return;
  }
  if (render == runbound) p.Add("render thread is the RunBound thread");
  if (render == main) p.Add("render thread is the main thread");
  if (runbound == main) p.Add("RunBound ran on the main thread");

  int frees = 0, swaps = 0, set_parameters = 0, updates = 0, callbacks = 0;
  for (const golden::Call& c : calls) {
    const std::string where =
        c.what + " on the " + Role(c.thread, runbound, render, main);
    if (c.what.find("(bad ctx)") != std::string::npos)
      p.Add(where + ": not the renderer's render context");
    if (Is(c.what, "render_context_create") ||
        Is(c.what, "render_context_get_info")) {
      if (c.thread != runbound)
        p.Add(where + " (create-time call, expected: RunBound thread)");
      continue;
    }
    if (Is(c.what, "render_context_set_update_callback")) {
      // The first registers the callback inside RunBound; the second
      // removes it on the render thread.
      if (callbacks++ == 0) {
        if (c.thread != runbound)
          p.Add(where + " (registration, expected: RunBound thread)");
      } else if (c.thread != render) {
        p.Add(where + " (removal, expected: render thread)");
      }
      continue;
    }
    if (Is(c.what, "render_context_free")) frees++;
    if (Is(c.what, "render_context_report_swap")) swaps++;
    if (Is(c.what, "render_context_set_parameter")) set_parameters++;
    if (Is(c.what, "render_context_update")) updates++;
    if (c.thread != render)
      p.Add(where + " (expected: render thread)");
  }
  if (frees != 1)
    p.Add("render_context_free called " + std::to_string(frees) +
          " time(s) (expected: once)");
  if (callbacks != 2)
    p.Add("render_context_set_update_callback called " +
          std::to_string(callbacks) + " time(s) (expected: register, remove)");
  if (swaps == 0) p.Add("no render_context_report_swap call recorded");
  if (set_parameters == 0) p.Add("no render_context_set_parameter recorded");
  if (updates == 0) p.Add("no render_context_update call recorded");

  // A context is current on one thread at a time: the RunBound thread has
  // released it before the render thread binds it.
  const ThreadBinds rb = BindsOf(events, runbound);
  const ThreadBinds rt = BindsOf(events, render);
  if (rb.first_bind < 0) p.Add("the RunBound thread never bound the backend");
  if (rt.first_bind < 0) p.Add("the render thread never bound the backend");
  if (!rb.paired) p.Add("RunBound thread: binds and unbinds do not pair up");
  if (!rt.paired) p.Add("render thread: binds and unbinds do not pair up");
  if (rb.last_unbind >= 0 && rt.first_bind >= 0 &&
      rb.last_unbind > rt.first_bind)
    p.Add("the render thread bound the backend before the RunBound thread "
          "unbound it");
}

/// The scenario: Start on the main thread, a raster thread taking frames,
/// an ICC profile, kFrames frames with a resize halfway, then the main
/// thread destroys the renderer.
void Scenario(Problems& p) {
  const std::thread::id main = std::this_thread::get_id();
  BindInterop interop;
  auto renderer = std::make_unique<VideoRenderer>(
      MakeCheckedApi(), golden::FakeHandle(), &interop,
      [](const std::string& line) {
        std::lock_guard<std::mutex> lock(g_log_mu);
        g_log.push_back(line);
      },
      [](const char*, const std::string&) {});
  if (!renderer->Start(RendererChoice::kAuto)) {
    p.Add("Start failed: " + renderer->backend_reason());
    return;
  }
  renderer->SetSize(64, 48);
  interop.WaitFrameReady(1);
  int acquisitions = 0;
  {
    Raster raster(renderer.get());
    // Applied on the render thread before the next frame.
    renderer->SetIccProfile({1, 2, 3});
    for (int i = 0; i < kFrames; i++) {
      if (i == kFrames / 2) renderer->SetSize(32, 24);
      const int want = interop.frame_ready() + 1;
      Fake().QueueFrames(1);
      Fake().Poke();
      interop.WaitFrameReady(want);
      // Paced like a compositor: the frame is taken before the next one,
      // so each frame's swap is due at the acquisition.
      raster.WaitAcquisitions(2);
    }
    raster.Stop();
    acquisitions = raster.acquisitions();
  }
  if (acquisitions == 0) p.Add("the raster thread took no frame");
  const int renders = Fake().counters().renders;
  if (renders < 3)
    p.Add("only " + std::to_string(renders) + " render call(s) (expected: 3+)");
  Fake().SignalPending();
  renderer.reset();
  Check(p, Fake().calls(), main);
  if (Images().live() != 0)
    p.Add(std::to_string(Images().live()) + " image(s) never destroyed");
}

}  // namespace

int main(int argc, char** argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  (void)argv;
  if (argc != 1) {
    std::fprintf(stderr, "usage: video_renderer_bind_test\n");
    return 1;
  }
  // The scenario runs the platform's own chain.
  golden::SetEnv("MPV_KIT_VIDEO_API", nullptr);
  Fake().Reset();
  Images().Reset();
  ResetState();
  Problems problems;
  try {
    Scenario(problems);
  } catch (const std::exception& e) {
    problems.Add(std::string("timeout waiting for ") + e.what());
  }
  for (const std::string& v : Images().TakeViolations()) problems.Add(v);
  for (const std::string& line : problems.lines)
    std::printf("BIND violation: %s\n", line.c_str());
  if (!problems.lines.empty()) {
    std::lock_guard<std::mutex> lock(g_log_mu);
    for (const std::string& line : g_log)
      std::fprintf(stderr, "  log: %s\n", line.c_str());
    return 1;
  }
  std::printf("BIND ok\n");
  return 0;
}
