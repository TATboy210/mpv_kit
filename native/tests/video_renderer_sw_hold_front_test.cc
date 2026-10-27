// Software-path test of the AcquireFront() lifetime promise
// (video_renderer.h: a returned frame "stays valid until the next
// AcquireFront() call"): drives the real
// packages/mpv_kit_video/src/video_renderer.cc through the fake libmpv of
// renderer_harness.h, keeps the frame of the last AcquireFront() the way a
// compositor does (Flutter on Windows and Linux uploads the pixels after
// its copy callback returned) and checks, until the next AcquireFront(),
// that its buffer was not freed and still holds the frame it showed.
//
// Kept apart from the frozen golden files (evidence/golden-freeze.sha256
// of phase 12); the harness is used unchanged. Liveness is observed by
// this binary's own replacement of the global operator new/delete: large
// heap blocks are recorded with their size, and the free of the block
// that contains the held pixels is noted. The held pixels are only read
// while their block is known to be alive, so a defect is reported without
// a use after free (and without depending on a sanitizer build). Runs
// headless and GPU-less on every runner, like golden_sw.
//
// usage: video_renderer_sw_hold_front_test [--slack-ms=N]
//   --slack-ms  upper tolerance of timing expectations (meson passes 250,
//               or 1000 for sanitizer builds)
//
// Output: `HOLD ok scenarios=<n>` on success; otherwise one
// `HOLD invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure.

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <vector>

#include "renderer_harness.h"

// --- Liveness watch ----------------------------------------------------------
//
// SoftwareBackend's pixel buffers (std::vector<uint8_t>) allocate through
// the global operator new. data() need not be the block's start (MSVC's
// allocator over-aligns large blocks and hands out an offset into them),
// so every large block is recorded with its size, and the free of the
// block that contains the watched pointer is what counts. Blocks are plain
// malloc memory, so an untracked block is freed as usual.

namespace {

// Smaller blocks are never pixel buffers of interest (the smallest frame
// here is 32x18x4 = 2304 bytes) and are not recorded.
constexpr std::size_t kTrackFrom = 2048;
// Live large blocks at once: a few rings of 5 buffers plus harness
// containers; overflowing fails the test rather than missing a free.
constexpr int kMaxBlocks = 1024;

struct Block {
  std::uintptr_t begin;
  std::size_t size;
};

Block g_blocks[kMaxBlocks];
std::atomic_flag g_blocks_lock = ATOMIC_FLAG_INIT;
bool g_blocks_overflow = false;  // under g_blocks_lock

std::atomic<std::uintptr_t> g_watch{0};
std::atomic<bool> g_watch_freed{false};

// A spin lock: std::mutex could allocate on some platforms, and this runs
// inside operator new.
struct BlocksLock {
  BlocksLock() {
    while (g_blocks_lock.test_and_set(std::memory_order_acquire)) {
    }
  }
  ~BlocksLock() { g_blocks_lock.clear(std::memory_order_release); }
  BlocksLock(const BlocksLock&) = delete;
  BlocksLock& operator=(const BlocksLock&) = delete;
};

void* TrackedMalloc(std::size_t n) noexcept {
  void* p = std::malloc(n == 0 ? 1 : n);
  if (p && n >= kTrackFrom) {
    BlocksLock lock;
    int free_slot = -1;
    for (int i = 0; i < kMaxBlocks && free_slot < 0; i++)
      if (g_blocks[i].begin == 0) free_slot = i;
    if (free_slot >= 0) {
      g_blocks[free_slot] = Block{reinterpret_cast<std::uintptr_t>(p), n};
    } else {
      g_blocks_overflow = true;
    }
  }
  return p;
}

void* Allocate(std::size_t n) {
  void* p = TrackedMalloc(n);
  if (!p) throw std::bad_alloc();
  return p;
}

void Deallocate(void* p) noexcept {
  if (!p) return;
  {
    const std::uintptr_t a = reinterpret_cast<std::uintptr_t>(p);
    const std::uintptr_t watch = g_watch.load();
    BlocksLock lock;
    for (Block& b : g_blocks) {
      if (b.begin != a) continue;
      if (watch >= b.begin && watch < b.begin + b.size)
        g_watch_freed.store(true);
      b = Block{0, 0};
      break;
    }
  }
  std::free(p);
}

/// True if [p] lies in a live recorded block: only then can a free of the
/// held frame be observed (otherwise the test would pass blind).
bool Tracked(const void* p) {
  const std::uintptr_t a = reinterpret_cast<std::uintptr_t>(p);
  BlocksLock lock;
  for (const Block& b : g_blocks)
    if (b.begin != 0 && a >= b.begin && a < b.begin + b.size) return true;
  return false;
}

bool BlocksOverflowed() {
  BlocksLock lock;
  return g_blocks_overflow;
}

}  // namespace

void* operator new(std::size_t n) { return Allocate(n); }
void* operator new[](std::size_t n) { return Allocate(n); }
void* operator new(std::size_t n, const std::nothrow_t&) noexcept {
  return TrackedMalloc(n);
}
void* operator new[](std::size_t n, const std::nothrow_t&) noexcept {
  return TrackedMalloc(n);
}
void operator delete(void* p) noexcept { Deallocate(p); }
void operator delete[](void* p) noexcept { Deallocate(p); }
void operator delete(void* p, std::size_t) noexcept { Deallocate(p); }
void operator delete[](void* p, std::size_t) noexcept { Deallocate(p); }
void operator delete(void* p, const std::nothrow_t&) noexcept {
  Deallocate(p);
}
void operator delete[](void* p, const std::nothrow_t&) noexcept {
  Deallocate(p);
}

namespace {

using golden::Fake;
using golden::FakeInterop;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

// Failed 32x18 renders before the second resize (as in
// video_renderer_golden_sw_retire_twice.cc): the resize itself, then
// retries after 100 + 200 + 400 + 800 ms. The renderer then backs off
// 1600 ms, more than the sanitizer slack, so the second resize (which
// retries at once) cannot race a scheduled retry.
constexpr int kFailures = 5;
constexpr int kFailureBudgetMs = 100 + 200 + 400 + 800;

// --- Scenario context --------------------------------------------------------

/// The frame of the last AcquireFront(), as the compositor keeps it.
struct Held {
  mpv_kit::Frame frame;
  int number = -1;  // frame number the fake wrote into the pixels
};

/// State of one running scenario.
struct Run {
  std::string name;
  int slack_ms;
  bool ok = true;
  Held held;

  /// Records an invariant violation; the scenario (and the binary) fails.
  void Invariant(const std::string& what) {
    std::printf("HOLD invariant scenario=%s: %s\n", name.c_str(),
                what.c_str());
    ok = false;
  }
};

// Renderer log lines are diagnostics only; shown when a scenario fails.
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

int FrameNumber(const uint8_t* px) { return px[0] | px[1] << 8 | px[2] << 16; }

std::string Describe(const mpv_kit::Frame& f) {
  return "index=" + std::to_string(f.index) + " " + std::to_string(f.width) +
         "x" + std::to_string(f.height);
}

/// The compositor takes a new frame: the previous one may go, the new one
/// must stay valid until the next call. Fails if [expect_pixels] differs.
void Acquire(Run& run, VideoRenderer& r, bool expect_pixels) {
  g_watch.store(0);
  const mpv_kit::Frame f = r.AcquireFront();
  run.held = Held{};
  run.held.frame = f;
  if (f.pixels) {
    g_watch_freed.store(false);
    g_watch.store(reinterpret_cast<std::uintptr_t>(f.pixels));
    run.held.number = FrameNumber(f.pixels);
    if (!Tracked(f.pixels))
      run.Invariant("acquire " + Describe(f) +
                    ": pixels are not in a recorded heap block, so their "
                    "free could not be observed");
  }
  std::printf("  [%s] acquire %s frame=%s\n", run.name.c_str(),
              Describe(f).c_str(),
              f.pixels ? std::to_string(run.held.number).c_str() : "none");
  if (expect_pixels != (f.pixels != nullptr))
    run.Invariant("acquire " + Describe(f) + ": expected " +
                  (expect_pixels ? "pixels" : "no frame"));
}

/// What the compositor does with the held frame between two AcquireFront()
/// calls: reads (uploads) it. Its buffer must be alive and unchanged.
void ReadHeld(Run& run, const char* where) {
  const mpv_kit::Frame& f = run.held.frame;
  if (!f.pixels) return;
  if (g_watch_freed.load()) {
    run.Invariant(std::string("USE AFTER FREE: frame ") + Describe(f) +
                  " handed out by the last AcquireFront() was freed before "
                  "the next AcquireFront() (" + where + ")");
    // Never read freed memory; report once.
    run.held = Held{};
    g_watch.store(0);
    return;
  }
  const int number = FrameNumber(f.pixels);
  if (number != run.held.number)
    run.Invariant(std::string("held frame ") + Describe(f) + " changed from " +
                  std::to_string(run.held.number) + " to " +
                  std::to_string(number) + " (" + where + ")");
  if (f.pixels[3] != 0xff)
    run.Invariant(std::string("held frame padding byte is not 0xff (") +
                  where + ")");
  std::printf("  [%s] read %s frame=%d alive (%s)\n", run.name.c_str(),
              Describe(f).c_str(), number, where);
}

/// Starts the software renderer and shows one 64x36 frame (frame 1).
std::unique_ptr<VideoRenderer> StartWithFirstFrame(Run& run,
                                                   FakeInterop& interop) {
  auto r = MakeRenderer(interop);
  if (!r->Start(RendererChoice::kSoftware)) {
    run.Invariant("Start(kSoftware) failed: " + r->backend_reason());
    return nullptr;
  }
  r->SetSize(64, 36);
  interop.WaitFrameReady(1);
  Sync();
  return r;
}

/// Resizes to [w]x[h] with the new size's first render held inside the
/// fake: the window between the reallocation and the publish.
void ResizeHeld(VideoRenderer& r, int w, int h) {
  Fake().HoldRenders(true);
  r.SetSize(w, h);
  Fake().WaitRenderHeld();
}

/// Lets the held render publish.
void ReleaseHeld(FakeInterop& interop) {
  const int want = interop.frame_ready() + 1;
  Fake().HoldRenders(false);
  interop.WaitFrameReady(want);
  Sync();
}

void Teardown(std::unique_ptr<VideoRenderer>& r) {
  // The destructor frees every buffer: that is not a compositor read.
  g_watch.store(0);
  r.reset();
}

// --- Scenarios -----------------------------------------------------------------

// Resize, failed render, resize (CR-01 trace 1). The compositor took the
// 64x36 frame; every 32x18 render fails, so the next AcquireFront() hands
// out the retired 64x36 front. A second resize (48x27) then reallocates
// before the compositor takes another frame: the 64x36 buffer it holds
// must survive that until the next AcquireFront().
void HoldRetireTwice(Run& run) {
  FakeInterop interop(/*latency=*/2, /*bgra=*/false, /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop);
  if (!r) return;
  Acquire(run, *r, true);
  Fake().SetDefaultRenderResult(MPV_ERROR_GENERIC);
  const int renders = Fake().counters().renders;
  r->SetSize(32, 18);
  Fake().WaitRenders(renders + kFailures,
                     golden::Ms(kFailureBudgetMs + kFailures * run.slack_ms) +
                         golden::kWaitTimeout);
  Sync();
  Acquire(run, *r, true);  // the retired 64x36 front (index -2)
  ReadHeld(run, "32x18 renders failing");
  Fake().SetDefaultRenderResult(0);
  ResizeHeld(*r, 48, 27);
  ReadHeld(run, "48x27 reallocated, its first render held");
  ReleaseHeld(interop);
  ReadHeld(run, "48x27 frame published");
  Acquire(run, *r, true);
  Teardown(r);
}

// Two resizes before the compositor takes a new frame (CR-01 trace 2).
// The compositor took the 64x36 frame; the 32x18 generation publishes but
// is never acquired; a resize to 48x27 reallocates again. The 64x36
// buffer is still the last one handed out.
void HoldRapidResize(Run& run) {
  FakeInterop interop(/*latency=*/2, /*bgra=*/false, /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop);
  if (!r) return;
  Acquire(run, *r, true);
  ResizeHeld(*r, 32, 18);
  ReadHeld(run, "32x18 reallocated, its first render held");
  ReleaseHeld(interop);
  ReadHeld(run, "32x18 frame published, not acquired");
  ResizeHeld(*r, 48, 27);
  ReadHeld(run, "48x27 reallocated, its first render held");
  ReleaseHeld(interop);
  ReadHeld(run, "48x27 frame published");
  Acquire(run, *r, true);
  Teardown(r);
}

// As above, but what the compositor holds is the retired front: it took a
// frame while the 32x18 generation had none yet (index -2), then the
// 32x18 frame publishes and a resize to 48x27 arrives before the next
// AcquireFront().
void HoldRetiredFrontRapidResize(Run& run) {
  FakeInterop interop(/*latency=*/2, /*bgra=*/false, /*interop_reason=*/nullptr);
  auto r = StartWithFirstFrame(run, interop);
  if (!r) return;
  Acquire(run, *r, true);
  ResizeHeld(*r, 32, 18);
  Acquire(run, *r, true);  // the retired 64x36 front (index -2)
  ReleaseHeld(interop);
  ReadHeld(run, "32x18 frame published, not acquired");
  ResizeHeld(*r, 48, 27);
  ReadHeld(run, "48x27 reallocated, its first render held");
  ReleaseHeld(interop);
  ReadHeld(run, "48x27 frame published");
  Acquire(run, *r, true);
  Teardown(r);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
};

const ScenarioDef kScenarios[] = {
    {"sw-hold-retire-twice", HoldRetireTwice},
    {"sw-hold-rapid-resize", HoldRapidResize},
    {"sw-hold-retired-front-rapid-resize", HoldRetiredFrontRapidResize},
};

}  // namespace

int main(int argc, char** argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  int slack_ms = 250;
  for (int i = 1; i < argc; i++) {
    const std::string arg = argv[i];
    if (arg.compare(0, 11, "--slack-ms=") == 0) {
      slack_ms = std::atoi(arg.c_str() + 11);
    } else {
      slack_ms = 0;
      break;
    }
  }
  if (slack_ms <= 0) {
    std::fprintf(stderr,
                 "usage: video_renderer_sw_hold_front_test [--slack-ms=N]\n");
    return 1;
  }

  bool ok = true;
  int count = 0;
  for (const ScenarioDef& def : kScenarios) {
    Fake().Reset();
    {
      std::lock_guard<std::mutex> lock(g_log_mu);
      g_log.clear();
    }
    Run run{def.name, slack_ms, true, {}};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("HOLD timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    g_watch.store(0);
    if (!run.ok) {
      for (const std::string& line : LogLines())
        std::fprintf(stderr, "  [%s] log: %s\n", def.name, line.c_str());
      ok = false;
    }
    count++;
  }
  if (BlocksOverflowed()) {
    std::printf("HOLD invariant: more than %d live heap blocks of %zu bytes "
                "or more; frees may have gone unobserved\n",
                kMaxBlocks, kTrackFrom);
    ok = false;
  }
  if (!ok) return 1;
  std::printf("HOLD ok scenarios=%d\n", count);
  return 0;
}
