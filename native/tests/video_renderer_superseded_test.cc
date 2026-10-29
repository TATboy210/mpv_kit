// Test of the probe line's `superseded=<n>` count (quick 261029-nwm): frames
// that VideoRenderer published and replaced before the compositor took them
// (rendered but never shown; mpv does not count them as drops).
//
// Runs the real packages/mpv_kit_video/src/video_renderer.cc against the fake
// libmpv of renderer_harness.h, on a fake pipelined backend (CPU buffers
// behind Interop::CreateBackend, modelled on FakeGpuBackend of
// video_renderer_chain_test.cc) because only the GPU path writes the probe
// line. No GPU, no driver, no libmpv; runs on every runner and under the
// sanitizers.
//
// Why a separate binary: the golden set and the harness are frozen
// (evidence/golden-freeze-14.sha256); the harness is used unchanged.
//
// usage: video_renderer_superseded_test
//
// Output: `SUPERSEDED ok scenarios=<n>` on success; otherwise one
// `SUPERSEDED invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure.

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "renderer_harness.h"

namespace {

using golden::Fake;
using golden::FakeInterop;
using mpv_kit::BackendCandidate;
using mpv_kit::MpvApi;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Fake target size; small, the fake never looks at the pixels.
constexpr int kWidth = 64;
constexpr int kHeight = 36;
// Wire name of the fake pipelined backend (never a real api name).
constexpr const char* kFakeApi = "fakegpu";
// VideoRenderer::kProbeWindow (private): the probe line is written in the
// render of this frame.
constexpr int kProbeFrames = 120;
// Prefix and key of the probe line the superseded count is read from.
constexpr const char* kProbePrefix = "mpv_kit: render waits avg/over ";
constexpr const char* kSupersededKey = " superseded=";

// --- Fake pipelined backend ------------------------------------------------

/// A GPU-style RenderBackend (pipelined, shared-image frame class) backed by
/// CPU buffers: Render uses the fake libmpv's software target, so the
/// renderer takes the publish-gate path (Wait after Render) without a GPU.
class FakeGpuBackend final : public mpv_kit::RenderBackend {
 public:
  const char* wire_name() const override { return kFakeApi; }
  mpv_kit::Backend frame_kind() const override {
    return mpv_kit::Backend::kVulkan;
  }
  bool pipelined() const override { return true; }

  int Create(const MpvApi& api, mpv_handle* handle, const char* renderer,
             mpv_render_context** out, std::string* why) override {
    *out = nullptr;
    renderer_ = renderer;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(kFakeApi)},
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
  bool device_failed() const override { return false; }
  std::string device_name() const override { return "fake-gpu"; }
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
  std::string renderer_;
  std::vector<std::vector<uint8_t>> buffers_;
};

/// The platform of the pipelined scenarios: its only candidate is the fake
/// backend, so Start(kAuto) picks it.
class GpuInterop final : public FakeInterop {
 public:
  GpuInterop() : FakeInterop(2, false, nullptr) {}

  std::vector<BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    (void)choice;
    return {{kFakeApi, "gpu-next"}};
  }
  std::unique_ptr<mpv_kit::RenderBackend> CreateBackend(
      const char* api) override {
    if (std::string(api) != kFakeApi) return nullptr;
    return std::make_unique<FakeGpuBackend>();
  }
};

// --- Scenario context --------------------------------------------------------

/// State of one running scenario.
struct Run {
  std::string name;
  bool ok = true;

  /// Records an invariant violation; the scenario (and the binary) fails.
  void Invariant(const std::string& what) {
    std::printf("SUPERSEDED invariant scenario=%s: %s\n", name.c_str(),
                what.c_str());
    ok = false;
  }
};

// Renderer log lines: the probe line is parsed, the rest shown on failure.
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
        Fake().Note(msg.empty() ? std::string("event ") + kind
                                : std::string("event ") + kind + " " + msg);
      });
}

/// Starts [r] on [choice], sizes it and waits for the first published frame
/// (frame 1, drawn because the size is new). Null with an invariant on error.
std::unique_ptr<VideoRenderer> StartWithFirstFrame(Run& run,
                                                   FakeInterop& interop,
                                                   RendererChoice choice,
                                                   const char* want_backend) {
  auto r = MakeRenderer(interop);
  if (!r->Start(choice)) {
    run.Invariant("Start failed: " + r->backend_reason());
    return nullptr;
  }
  if (std::string(r->wire_name()) != want_backend) {
    run.Invariant(std::string("Start picked ") + r->wire_name() +
                  ", expected " + want_backend);
    return nullptr;
  }
  r->SetSize(kWidth, kHeight);
  interop.WaitFrameReady(1);
  return r;
}

/// The compositor takes the newest frame.
void Acquire(VideoRenderer& r) { (void)r.AcquireFront(); }

/// Queues one new mpv frame and wakes the render loop, as mpv's update
/// callback does.
void QueueFrame() {
  Fake().QueueFrames(1);
  (void)Fake().Poke();
}

/// Reads `superseded=` from the one probe line; -1 (with an invariant) if the
/// line is missing, duplicated or malformed.
int ProbeSuperseded(Run& run) {
  int found = -1;
  int lines = 0;
  for (const std::string& line : LogLines()) {
    if (line.compare(0, std::string(kProbePrefix).size(), kProbePrefix) != 0)
      continue;
    lines++;
    const std::size_t at = line.find(kSupersededKey);
    if (at == std::string::npos) {
      run.Invariant("probe line without superseded=: " + line);
      return -1;
    }
    found = std::atoi(line.c_str() + at + std::string(kSupersededKey).size());
  }
  if (lines != 1) {
    run.Invariant("expected exactly one probe line, got " +
                  std::to_string(lines));
    return -1;
  }
  return found;
}

// --- Scenarios ---------------------------------------------------------------

/// Frames 2..kProbeFrames on the fake pipelined backend; the compositor
/// takes frame 1, then every frame ([every_frame]) or only odd ones. Checks
/// the probe line's superseded count against [expect].
void CheckSuperseded(Run& run, bool every_frame, int expect) {
  GpuInterop interop;
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kAuto, kFakeApi);
  if (!r) return;
  Acquire(*r);
  for (int n = 2; n <= kProbeFrames; n++) {
    QueueFrame();
    interop.WaitFrameReady(n);
    if (every_frame || n % 2 == 1) Acquire(*r);
  }
  // The probe line is written in frame kProbeFrames' render, before its
  // publish: it is in the log once that frame's FrameReady was observed.
  const int got = ProbeSuperseded(run);
  if (got >= 0 && got != expect)
    run.Invariant("superseded=" + std::to_string(got) + ", expected " +
                  std::to_string(expect));
  const golden::Counters c = Fake().counters();
  if (c.skips != 0)
    run.Invariant("skipped renders: " + std::to_string(c.skips));
}

// superseded-alternate: frames 3, 5, ..., 119 each replace an unacquired
// frame (59 of them); frame 120's publish comes after the probe line.
void SupersededAlternate(Run& run) {
  CheckSuperseded(run, /*every_frame=*/false, /*expect=*/59);
}

// superseded-none: the compositor takes every frame.
void SupersededNone(Run& run) {
  CheckSuperseded(run, /*every_frame=*/true, /*expect=*/0);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"superseded-alternate", SupersededAlternate},
    {"superseded-none", SupersededNone},
};

}  // namespace

int main(int argc, char** /*argv*/) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  if (argc > 1) {
    std::fprintf(stderr, "usage: video_renderer_superseded_test\n");
    return 1;
  }
  // A restricting MPV_KIT_VIDEO_API would change the candidate chain.
  golden::SetEnv("MPV_KIT_VIDEO_API", nullptr);

  bool ok = true;
  int count = 0;
  for (const ScenarioDef& def : kScenarios) {
    Fake().Reset();
    {
      std::lock_guard<std::mutex> lock(g_log_mu);
      g_log.clear();
    }
    Run run{def.name, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("SUPERSEDED timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    if (!run.ok) {
      for (const std::string& line : LogLines())
        std::fprintf(stderr, "  [%s] log: %s\n", def.name, line.c_str());
      ok = false;
    }
    count++;
  }
  if (!ok) return 1;
  std::printf("SUPERSEDED ok scenarios=%d\n", count);
  return 0;
}
