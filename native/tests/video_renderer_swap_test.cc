// Test of how VideoRenderer reports mpv's swap and hands finished frames to
// the compositor (quick 261029-rcc): each frame's mpv_render_context_report_
// swap is called on the render thread as soon as the frame is published,
// before Interop::FrameReady, so vo_libmpv's flip_page (video-sync=audio)
// never waits for the compositor to pick the frame up; finished frames wait
// in a FIFO of at most two (AcquireFront takes the oldest, repeats the last
// one when nothing is new, re-notifies the platform while a further frame
// waits, and a full queue drops its oldest, counted as superseded). The
// probe line's `superseded=`, `repeated=` and `queued=` counts are checked
// against exact numbers.
//
// Runs the real packages/mpv_kit_video/src/video_renderer.cc against the fake
// libmpv of renderer_harness.h, on two backends: the software backend and a
// fake pipelined backend (CPU buffers behind Interop::CreateBackend, modelled
// on FakeGpuBackend of video_renderer_chain_test.cc) that takes the GPU
// publish-gate path and writes the probe line. No GPU, no driver, no libmpv;
// runs on every runner and under the sanitizers.
//
// Why a separate binary: the golden set and the harness are frozen
// (evidence/golden-freeze-14.sha256); the harness is used unchanged.
//
// usage: video_renderer_swap_test
//
// Output: `SWAP ok scenarios=<n>` on success; otherwise one
// `SWAP invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure.

#include <chrono>
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
using mpv_kit::BackendCandidate;
using mpv_kit::Frame;
using mpv_kit::MpvApi;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Fake target size; small, the fake never looks at the pixels.
constexpr int kWidth = 64;
constexpr int kHeight = 36;
// Size after the resize scenario's SetSize.
constexpr int kResizedWidth = 32;
constexpr int kResizedHeight = 18;
// Wire name of the fake pipelined backend (never a real api name).
constexpr const char* kFakeApi = "fakegpu";
// Frames of one swap-at-publish scenario after the first one.
constexpr int kSwapFrames = 20;
// VideoRenderer::kProbeWindow (private): the probe line is written in the
// render of this frame, before its publish.
constexpr int kProbeFrames = 120;
// CompositorLatency() of the platforms: Linux/macOS and Windows.
constexpr int kLatencyDefault = 2;
constexpr int kLatencyWindows = 4;
// Largest ring the allocation fallback scenario's backend can allocate: the
// ring of 6 (latency 2) does not fit, the fallback ring of 5 does.
constexpr int kMaxFakeRing = 5;
// Past VideoRenderer::kIdleTimeout (500 ms) with a margin: the compositor
// is quiet this long before the idle scenario wakes the render loop.
constexpr std::chrono::milliseconds kPastIdleTimeout{600};
// Prefix of the probe line and its keys.
constexpr const char* kProbePrefix = "mpv_kit: render waits avg/over ";
constexpr const char* kSupersededKey = " superseded=";
constexpr const char* kRepeatedKey = " repeated=";
constexpr const char* kQueuedKey = " queued=";
// The log line of the allocation fallback, and the prefix any allocation
// failure line starts with.
constexpr const char* kAllocFailedPrefix =
    "mpv_kit: shared-image allocation failed";
constexpr const char* kFallbackLine =
    "mpv_kit: shared-image allocation failed at ring 6, retried with a ring "
    "of 5";

// --- Fake pipelined backend ------------------------------------------------

/// A GPU-style RenderBackend (pipelined, shared-image frame class) backed by
/// CPU buffers: Render uses the fake libmpv's software target, so the
/// renderer takes the publish-gate path (Wait after Render) without a GPU.
/// AllocTargets fails for rings larger than [max_ring] (memory pressure).
class FakeGpuBackend final : public mpv_kit::RenderBackend {
 public:
  explicit FakeGpuBackend(int max_ring) : max_ring_(max_ring) {}

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
    if (count > max_ring_) {
      // Like a real backend: a failed attempt leaves nothing allocated.
      buffers_.clear();
      *error = "fake out of memory";
      return false;
    }
    buffers_.assign(static_cast<size_t>(count),
                    std::vector<uint8_t>(size_t(width) * height * 4));
    return true;
  }
  void FreeRetired() override {}
  mpv_kit::TargetView FrameFor(int slot) override {
    mpv_kit::TargetView view;
    // A stable non-null platform object per slot, which is also the slot's
    // pixel buffer: the test reads the frame number the fake libmpv wrote.
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
  const int max_ring_;
  std::string renderer_;
  std::vector<std::vector<uint8_t>> buffers_;
};

/// The platform of the pipelined scenarios: its only candidate is the fake
/// backend, so Start(kAuto) picks it.
class GpuInterop final : public FakeInterop {
 public:
  explicit GpuInterop(int latency, int max_ring = 1 << 20)
      : FakeInterop(latency, false, nullptr), max_ring_(max_ring) {}

  std::vector<BackendCandidate> BackendCandidates(
      RendererChoice choice) const override {
    (void)choice;
    return {{kFakeApi, "gpu-next"}};
  }
  std::unique_ptr<mpv_kit::RenderBackend> CreateBackend(
      const char* api) override {
    if (std::string(api) != kFakeApi) return nullptr;
    return std::make_unique<FakeGpuBackend>(max_ring_);
  }

 private:
  const int max_ring_;
};

// --- Scenario context --------------------------------------------------------

/// State of one running scenario.
struct Run {
  std::string name;
  bool ok = true;

  /// Records an invariant violation; the scenario (and the binary) fails.
  void Invariant(const std::string& what) {
    std::printf("SWAP invariant scenario=%s: %s\n", name.c_str(),
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

/// Barrier (see FakeMpv::WaitPokeSeen); render-thread lines are dropped.
void Sync() {
  if (const uint64_t seq = Fake().Poke()) Fake().WaitPokeSeen(seq);
  (void)Fake().DrainAsync();
}

/// Starts a renderer on [choice], sizes it and waits for the first published
/// frame (frame 1, drawn because the size is new). Null with an invariant on
/// error.
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

/// Queues one new mpv frame and wakes the render loop, as mpv's update
/// callback does.
void QueueFrame() {
  Fake().QueueFrames(1);
  (void)Fake().Poke();
}

/// The pixels of a frame: the software backend hands them out directly, the
/// fake pipelined backend uses the buffer as its platform object.
const uint8_t* PixelsOf(const Frame& f) {
  return f.pixels ? f.pixels : static_cast<const uint8_t*>(f.platform);
}

/// The frame number the fake libmpv wrote into the first pixel's colour
/// bytes; -1 without pixels.
int NumberAt(const uint8_t* p) {
  return p ? p[0] | p[1] << 8 | p[2] << 16 : -1;
}

// --- The compositor side of one scenario ------------------------------------

/// Plays the compositor and the mpv update callback of one scenario: every
/// call checks what the renderer owes at that point. Frames are named by
/// their number (the nth successful non-skip render). Each method returns
/// false after recording an invariant; a scenario stops at the first one.
class Scene {
 public:
  /// [keep]: how many of the last acquired frames must keep their picture
  /// (the compositor may still sample them: in use + quarantine); 0 skips
  /// the tearing check. [swap_at_publish]: also demand that swaps equal
  /// renders as soon as a frame's FrameReady is observed.
  Scene(Run& run, FakeInterop& interop, VideoRenderer& r, int keep,
        bool swap_at_publish)
      : run_(run),
        interop_(interop),
        r_(r),
        keep_(keep),
        swap_at_publish_(swap_at_publish) {}

  /// The compositor takes frame 1, which the renderer drew for the new size.
  bool Begin() { return Take(1); }

  /// mpv has frame [n]: it is rendered, its swap reported and its
  /// FrameReady observed.
  bool Publish(int n) {
    QueueFrame();
    fr_++;
    interop_.WaitFrameReady(fr_);
    const golden::Counters c = Fake().counters();
    if (c.renders - c.skips != n)
      return Fail("publish of frame " + std::to_string(n) + " but " +
                  std::to_string(c.renders - c.skips) + " non-skip renders");
    if (swap_at_publish_ && c.swaps != c.renders)
      return Fail("frame " + std::to_string(n) + " published with swaps=" +
                  std::to_string(c.swaps) + " renders=" +
                  std::to_string(c.renders) +
                  ": its swap was not reported at publish");
    return CheckHeld();
  }

  /// The compositor takes the next frame, which must be [want]. [renotify]:
  /// the renderer marks the texture once more because a newer frame still
  /// waits (a synchronous FrameReady inside AcquireFront).
  bool Take(int want, bool renotify = false) {
    return Check(r_.AcquireFront(), want, renotify, /*repeat=*/false);
  }

  /// The compositor asks again with nothing new: it gets the same frame
  /// ([want]) and the same index, and no FrameReady.
  bool Repeat(int want) {
    return Check(r_.AcquireFront(), want, /*renotify=*/false, /*repeat=*/true);
  }

  /// Frame size the compositor must be handed from now on.
  void SetExpectedSize(int w, int h) {
    w_ = w;
    h_ = h;
  }

  /// FrameReady calls the renderer owes so far (publishes + re-notifies).
  int expected_frame_ready() const { return fr_; }
  /// Accounts for a FrameReady the test saw outside Publish (a frame the
  /// renderer drew by itself: resize, redraw).
  void CountFrameReady(int n) { fr_ += n; }

  bool Fail(const std::string& what) {
    run_.Invariant(what);
    return false;
  }

 private:
  struct Held {
    const uint8_t* pixels;
    int number;
  };

  bool Check(const Frame& f, int want, bool renotify, bool repeat) {
    const int got = NumberAt(PixelsOf(f));
    // The picture first: it is what a wrong order shows, before any wait.
    if (got != want)
      return Fail("acquired frame " + std::to_string(got) + ", expected " +
                  std::to_string(want));
    if (f.index < 0)
      return Fail("acquired frame " + std::to_string(want) + " with index " +
                  std::to_string(f.index));
    if (f.width != w_ || f.height != h_)
      return Fail("acquired frame " + std::to_string(want) + " is " +
                  std::to_string(f.width) + "x" + std::to_string(f.height) +
                  ", expected " + std::to_string(w_) + "x" +
                  std::to_string(h_));
    if (repeat && f.index != last_index_)
      return Fail("repeat of frame " + std::to_string(want) + " moved from " +
                  "index " + std::to_string(last_index_) + " to " +
                  std::to_string(f.index));
    if (renotify) fr_++;
    if (interop_.frame_ready() != fr_)
      return Fail("after acquiring frame " + std::to_string(want) +
                  " FrameReady was called " +
                  std::to_string(interop_.frame_ready()) + " times, expected " +
                  std::to_string(fr_));
    last_index_ = f.index;
    if (!repeat && keep_ > 0) {
      held_.push_back({PixelsOf(f), want});
      if (static_cast<int>(held_.size()) > keep_) held_.erase(held_.begin());
    }
    return CheckHeld();
  }

  /// The compositor may still sample the last [keep_] frames it took: none
  /// of their pictures may have been overwritten.
  bool CheckHeld() {
    for (const Held& h : held_) {
      const int now = NumberAt(h.pixels);
      if (now != h.number)
        return Fail("frame " + std::to_string(h.number) +
                    " was overwritten by frame " + std::to_string(now) +
                    " while the compositor may still sample it");
    }
    return true;
  }

  Run& run_;
  FakeInterop& interop_;
  VideoRenderer& r_;
  const int keep_;
  const bool swap_at_publish_;
  int fr_ = 1;  // frame 1's FrameReady
  int last_index_ = -1;
  int w_ = kWidth, h_ = kHeight;
  std::vector<Held> held_;
};

/// What the one probe line reports; -1 when absent.
struct Probe {
  int superseded = -1, repeated = -1, queued = -1;
};

/// Reads `key` from [line]; false when absent.
bool ReadKey(const std::string& line, const char* key, int* out) {
  const std::size_t at = line.find(key);
  if (at == std::string::npos) return false;
  *out = std::atoi(line.c_str() + at + std::string(key).size());
  return true;
}

/// The probe line's three counts; an invariant when the line is missing,
/// duplicated or lacks a key. [ok] is false then.
Probe ReadProbe(Run& run, bool* ok) {
  Probe p;
  int lines = 0;
  *ok = false;
  for (const std::string& line : LogLines()) {
    if (line.compare(0, std::string(kProbePrefix).size(), kProbePrefix) != 0)
      continue;
    lines++;
    if (!ReadKey(line, kSupersededKey, &p.superseded) ||
        !ReadKey(line, kRepeatedKey, &p.repeated) ||
        !ReadKey(line, kQueuedKey, &p.queued)) {
      run.Invariant("probe line without superseded=, repeated= and queued=: " +
                    line);
      return p;
    }
  }
  if (lines != 1) {
    run.Invariant("expected exactly one probe line, got " +
                  std::to_string(lines));
    return p;
  }
  *ok = true;
  return p;
}

/// Checks the probe line (written in frame kProbeFrames' render, before its
/// publish, so it is in the log once that frame's FrameReady was observed)
/// and that no render was skipped.
void CheckProbe(Run& run, int superseded, int repeated, int queued) {
  bool ok = false;
  const Probe p = ReadProbe(run, &ok);
  if (!ok) return;
  if (p.superseded != superseded || p.repeated != repeated ||
      p.queued != queued)
    run.Invariant("probe superseded=" + std::to_string(p.superseded) +
                  " repeated=" + std::to_string(p.repeated) + " queued=" +
                  std::to_string(p.queued) + ", expected superseded=" +
                  std::to_string(superseded) + " repeated=" +
                  std::to_string(repeated) + " queued=" +
                  std::to_string(queued));
  const golden::Counters c = Fake().counters();
  if (c.skips != 0)
    run.Invariant("skipped renders: " + std::to_string(c.skips));
}

/// After a barrier every render call was answered by exactly one swap.
void CheckSwapsAfterSync(Run& run) {
  Sync();
  const golden::Counters c = Fake().counters();
  if (c.swaps != c.renders)
    run.Invariant("after the barrier swaps=" + std::to_string(c.swaps) +
                  " renders=" + std::to_string(c.renders));
}

// --- Scenarios: swap at publish ---------------------------------------------

/// Frame k's swap must be answered by the time FrameReady(k) is observed: no
/// barrier, so a swap left pending (reported later by the compositor's
/// acquire or a timeout) shows as swaps < renders. The compositor takes a
/// frame before every publish, so it counts as actively consuming.
void CheckSwapsAtPublish(Run& run, FakeInterop& interop, VideoRenderer& r) {
  Scene s(run, interop, r, /*keep=*/0, /*swap_at_publish=*/true);
  if (!s.Begin()) return;
  for (int i = 0; i < kSwapFrames; i++) {
    if (!s.Take(1 + i)) return;
    if (!s.Publish(2 + i)) return;
  }
}

// swap-at-publish-sw: the software backend (no publish gate).
void SwapAtPublishSw(Run& run) {
  FakeInterop interop(kLatencyDefault, /*bgra=*/false,
                      /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kSoftware,
                               "software");
  if (!r) return;
  CheckSwapsAtPublish(run, interop, *r);
}

// swap-at-publish-gpu: the pipelined backend (publish gate path).
void SwapAtPublishGpu(Run& run) {
  GpuInterop interop(kLatencyDefault);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kAuto, kFakeApi);
  if (!r) return;
  CheckSwapsAtPublish(run, interop, *r);
}

// --- Scenarios: the FIFO ------------------------------------------------------

/// Frames 2..kProbeFrames - 1 in cycles [a]; [b, c] ... with [a] taken
/// alone and [b, c] published together, then frame kProbeFrames.
/// fifo-jitter (latency 2): the compositor is up to one frame late; the
/// older of two waiting frames is taken first (with a re-notify) and no
/// frame is lost.
void FifoJitter(Run& run) {
  GpuInterop interop(kLatencyDefault);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kAuto, kFakeApi);
  if (!r) return;
  Scene s(run, interop, *r, kLatencyDefault + 1, /*swap_at_publish=*/false);
  if (!s.Begin()) return;
  int f = 2;
  while (f < kProbeFrames) {
    if (!s.Publish(f) || !s.Take(f)) return;  // a: taken at once
    f++;
    if (f + 1 >= kProbeFrames) break;
    // b and c published before the compositor comes back: b waits, c is
    // front, taking b re-notifies for c.
    if (!s.Publish(f) || !s.Publish(f + 1)) return;
    if (!s.Take(f, /*renotify=*/true) || !s.Take(f + 1)) return;
    f += 2;
  }
  if (!s.Publish(kProbeFrames)) return;
  CheckProbe(run, /*superseded=*/0, /*repeated=*/0, /*queued=*/39);
}

/// Cycles [a, b, c published; b taken with a re-notify; c taken] for
/// a = 2, 5, ..., 116, then frames 119 and kProbeFrames. The compositor
/// misses every third frame: a is the oldest of a full queue and is dropped
/// (superseded), b and c are shown in order.
void CheckCapDrop(Run& run, int latency) {
  GpuInterop interop(latency);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kAuto, kFakeApi);
  if (!r) return;
  Scene s(run, interop, *r, latency + 1, /*swap_at_publish=*/false);
  if (!s.Begin()) return;
  for (int a = 2; a + 2 < kProbeFrames - 1; a += 3) {
    if (!s.Publish(a) || !s.Publish(a + 1) || !s.Publish(a + 2)) return;
    if (!s.Take(a + 1, /*renotify=*/true) || !s.Take(a + 2)) return;
  }
  if (!s.Publish(kProbeFrames - 1) || !s.Publish(kProbeFrames)) return;
  CheckProbe(run, /*superseded=*/39, /*repeated=*/0, /*queued=*/39);
}

// fifo-cap-drop-q2: ring of 6 (quarantine 2).
void FifoCapDropQ2(Run& run) { CheckCapDrop(run, kLatencyDefault); }

// fifo-cap-drop-q4: ring of 8 (quarantine 4, the Windows compositor).
void FifoCapDropQ4(Run& run) { CheckCapDrop(run, kLatencyWindows); }

// fifo-repeat: the compositor asks twice per frame: the second call gets the
// same frame, counted as repeated, without a FrameReady.
void FifoRepeat(Run& run) {
  GpuInterop interop(kLatencyDefault);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kAuto, kFakeApi);
  if (!r) return;
  Scene s(run, interop, *r, kLatencyDefault + 1, /*swap_at_publish=*/false);
  if (!s.Begin()) return;
  for (int f = 2; f < kProbeFrames; f++) {
    if (!s.Publish(f) || !s.Take(f) || !s.Repeat(f)) return;
  }
  if (!s.Publish(kProbeFrames)) return;
  CheckProbe(run, /*superseded=*/0, /*repeated=*/kProbeFrames - 2,
             /*queued=*/0);
}

// --- Scenarios: interplay with resize, idle, failure -------------------------

// resize-with-queue: two frames wait when the size changes; the older one is
// dropped, the newest old frame stays on screen as the retired front until
// the first frame at the new size exists, and frame 2 is never shown.
void ResizeWithQueue(Run& run) {
  FakeInterop interop(kLatencyDefault, /*bgra=*/false,
                      /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kSoftware,
                               "software");
  if (!r) return;
  Scene s(run, interop, *r, /*keep=*/0, /*swap_at_publish=*/false);
  if (!s.Begin() || !s.Publish(2) || !s.Publish(3)) return;

  Fake().HoldRenders(true);
  r->SetSize(kResizedWidth, kResizedHeight);
  Fake().WaitRenderHeld();
  // The ring is reallocated, nothing exists at the new size yet.
  const Frame retired = r->AcquireFront();
  if (retired.index != -2 || retired.width != kWidth ||
      retired.height != kHeight || NumberAt(PixelsOf(retired)) != 3) {
    s.Fail("during the resize the compositor got index " +
           std::to_string(retired.index) + ", " +
           std::to_string(retired.width) + "x" +
           std::to_string(retired.height) + ", frame " +
           std::to_string(NumberAt(PixelsOf(retired))) +
           "; expected the retired frame 3 (index -2, " +
           std::to_string(kWidth) + "x" + std::to_string(kHeight) + ")");
    Fake().HoldRenders(false);
    return;
  }
  Fake().HoldRenders(false);
  interop.WaitFrameReady(4);  // frame 4: the first at the new size
  s.CountFrameReady(1);
  if (interop.frame_ready() != s.expected_frame_ready()) {
    s.Fail("FrameReady was called " + std::to_string(interop.frame_ready()) +
           " times after the resize, expected " +
           std::to_string(s.expected_frame_ready()));
    return;
  }
  s.SetExpectedSize(kResizedWidth, kResizedHeight);
  if (!s.Take(4)) return;
  for (int f = 5; f <= 7; f++) {
    if (!s.Publish(f) || !s.Take(f)) return;
  }
  CheckSwapsAfterSync(run);
}

// idle-no-stall: no swap waits for a consumer; frames pile up while the
// compositor is away; on its return from idle it gets the newest frame (the
// older waiting one is dropped, no re-notify) and the redraw follows.
void IdleNoStall(Run& run) {
  FakeInterop interop(kLatencyDefault, /*bgra=*/false,
                      /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kSoftware,
                               "software");
  if (!r) return;
  Scene s(run, interop, *r, /*keep=*/0, /*swap_at_publish=*/true);
  // Frame 1 is taken once, then the compositor goes away.
  if (!s.Begin()) return;
  for (int f = 2; f <= 6; f++) {
    if (!s.Publish(f)) return;
  }
  std::this_thread::sleep_for(kPastIdleTimeout);
  QueueFrame();
  Fake().WaitNoted("event idle");
  Fake().WaitSkips(1);
  interop.WaitFrameReady(7);  // the skipped frame keeps notifying
  s.CountFrameReady(1);
  // Back from idle: the newest picture first; the redraw is asynchronous, so
  // only the picture is checked until the redraw's own FrameReady.
  const Frame f6 = r->AcquireFront();
  if (NumberAt(PixelsOf(f6)) != 6) {
    s.Fail("back from idle the compositor got frame " +
           std::to_string(NumberAt(PixelsOf(f6))) + ", expected 6");
    return;
  }
  Fake().WaitNoted("event active");
  interop.WaitFrameReady(8);  // the redraw publishes frame 7
  s.CountFrameReady(1);
  if (!s.Take(7)) return;
  CheckSwapsAfterSync(run);
  if (interop.frame_ready() != s.expected_frame_ready())
    s.Fail("FrameReady was called " + std::to_string(interop.frame_ready()) +
           " times, expected " + std::to_string(s.expected_frame_ready()));
}

// failure-keeps-queue: a failed render leaves the waiting frame alone and
// raises no FrameReady; the automatic retry publishes the next frame.
void FailureKeepsQueue(Run& run) {
  FakeInterop interop(kLatencyDefault, /*bgra=*/false,
                      /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kSoftware,
                               "software");
  if (!r) return;
  Scene s(run, interop, *r, /*keep=*/0, /*swap_at_publish=*/false);
  if (!s.Begin() || !s.Publish(2)) return;
  Fake().SetRenderResults({MPV_ERROR_GENERIC});
  QueueFrame();
  Fake().WaitNoted("event render_error render: fake error -20");
  if (!s.Take(2)) return;  // the failed render did not touch frame 2
  Fake().WaitNoted("event recovered");  // the retry after the backoff
  interop.WaitFrameReady(3);
  s.CountFrameReady(1);
  if (!s.Take(3)) return;
  CheckSwapsAfterSync(run);
}

// fallback-newest-wins: the ring of 6 does not fit; the retry with a ring of
// 5 has no waiting frame, so a newer frame replaces an untaken one.
void FallbackNewestWins(Run& run) {
  GpuInterop interop(kLatencyDefault, kMaxFakeRing);
  auto r = StartWithFirstFrame(run, interop, RendererChoice::kAuto, kFakeApi);
  if (!r) return;
  const std::string failed_prefix = kAllocFailedPrefix;
  int fallback_lines = 0, exact = 0;
  for (const std::string& line : LogLines()) {
    if (line.compare(0, failed_prefix.size(), failed_prefix) == 0)
      fallback_lines++;
    if (line == kFallbackLine) exact++;
  }
  if (fallback_lines != 1 || exact != 1) {
    run.Invariant("expected exactly the log line '" +
                  std::string(kFallbackLine) + "', got " +
                  std::to_string(fallback_lines) + " allocation line(s), " +
                  std::to_string(exact) + " matching");
    return;
  }
  Scene s(run, interop, *r, /*keep=*/0, /*swap_at_publish=*/false);
  if (!s.Begin() || !s.Publish(2) || !s.Publish(3)) return;
  if (!s.Take(3)) return;  // 3 replaced 2; no re-notify
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"swap-at-publish-sw", SwapAtPublishSw},
    {"swap-at-publish-gpu", SwapAtPublishGpu},
    {"fifo-jitter", FifoJitter},
    {"fifo-cap-drop-q2", FifoCapDropQ2},
    {"fifo-cap-drop-q4", FifoCapDropQ4},
    {"fifo-repeat", FifoRepeat},
    {"resize-with-queue", ResizeWithQueue},
    {"idle-no-stall", IdleNoStall},
    {"failure-keeps-queue", FailureKeepsQueue},
    {"fallback-newest-wins", FallbackNewestWins},
};

}  // namespace

int main(int argc, char** /*argv*/) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  if (argc > 1) {
    std::fprintf(stderr, "usage: video_renderer_swap_test\n");
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
      std::printf("SWAP timeout scenario=%s: waiting for %s\n", def.name,
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
  std::printf("SWAP ok scenarios=%d\n", count);
  return 0;
}
