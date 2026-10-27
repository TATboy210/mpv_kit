// Golden test of MPV_KIT_VIDEO_API, the native switch that forces one
// graphics API (docs/adr/0004-render-backend-reporting.md, Decision 4):
// drives the real packages/mpv_kit_video/src/video_renderer.cc and
// vulkan_backend.cc through the fake libmpv and fake platform interops of
// renderer_harness.h and compares what VideoRenderer::Start does with
// golden/api_override.txt.
//
// What it proves:
//   * unset or empty: exactly the candidate attempts and reason of a run
//     without the variable;
//   * a valid value: only candidates of that api (and of the requested
//     renderer) are tried; every other one is an `excluded by
//     MPV_KIT_VIDEO_API=<value>` trail, never a fallback (no
//     render_context_create of another api, no other api's device);
//   * an unknown or malformed value: nothing is tried, Start fails, and the
//     echoed value is sanitised (`?` outside [a-z0-9-]) and cut to 16
//     characters;
//   * the variable is read once per Start: changing it between two Starts
//     changes only the second renderer.
//
// Kept apart from the golden_sw / golden_vk binaries because those files,
// their goldens and the harness are frozen (evidence/golden-freeze.sha256
// of phase 12): new scenarios go into new files.
//
// Every scenario except api-vulkan runs everywhere: its expectation does not
// depend on a Vulkan device, either because the rig has no Vulkan interop
// or because the forced value excludes every Vulkan candidate before a
// device would be created. api-vulkan needs a Vulkan 1.3 device (lavapipe,
// MoltenVK or a GPU, as golden_vk); without one it is skipped on its own,
// with `API vk scenarios skipped: <why>`, and the binary still passes on
// the other scenarios.
//
// usage: video_renderer_api_test <golden/api_override.txt> [--slack-ms=N]
//
// Output: `API vk scenarios ok` or `API vk scenarios skipped: <why>`, then
// `GOLDEN ok scenarios=<n>` on success; otherwise one
// `GOLDEN mismatch|invariant|timeout ...` report per problem.
// Exit codes: 0 pass, 1 failure. The golden file is only read.

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
using golden::FakeVulkanInterop;
using golden::Images;
using mpv_kit::RendererChoice;
using mpv_kit::VideoRenderer;

constexpr const char* kApiVariable = "MPV_KIT_VIDEO_API";
// Any mpv error code: the fake returns it from every Vulkan
// render_context_create in the failing api-vulkan case.
constexpr int kCreateError = MPV_ERROR_UNSUPPORTED;

// --- Scenario context --------------------------------------------------------

/// State of one running scenario: its trace and whether it already failed.
struct Run {
  std::string name;
  golden::Trace trace;
  bool ok = true;

  /// Records an invariant violation; the scenario (and the binary) fails.
  void Invariant(const std::string& what) {
    std::printf("GOLDEN invariant scenario=%s: %s\n", name.c_str(),
                what.c_str());
    ok = false;
  }
};

// Renderer log lines. Start's own lines (the MPV_KIT_VIDEO_API notice,
// failed creates, the Vulkan fallback notice) are deterministic and part of
// the trace; nothing else runs before a scenario reads them.
std::mutex g_log_mu;
std::vector<std::string> g_log;

std::vector<std::string> TakeLog() {
  std::lock_guard<std::mutex> lock(g_log_mu);
  std::vector<std::string> out = std::move(g_log);
  g_log.clear();
  return out;
}

/// One platform: a FakeInterop (latency 2, RGBA) with or without the fake
/// Vulkan interop, and the renderers a scenario creates on it.
struct Rig {
  explicit Rig(bool with_vulkan)
      : interop(2, false, nullptr, with_vulkan ? &vk : nullptr) {}

  std::unique_ptr<VideoRenderer> NewRenderer() {
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

  FakeVulkanInterop vk;
  FakeInterop interop;
};

/// backend()/backend_reason() of [r] as one trace line (the GPU device name
/// normalised to `<device>`).
std::string Describe(Rig& rig, VideoRenderer& r, bool started) {
  std::string reason = r.backend_reason();
  for (const std::string& name : rig.vk.device_names())
    reason = golden::NormalizeReason(reason, name);
  if (!started) return "start=false reason=\"" + reason + "\"";
  const bool vulkan = r.backend() == mpv_kit::Backend::kVulkan;
  return std::string("start ok backend=") + (vulkan ? "vulkan" : "software") +
         " reason=\"" + reason + "\"";
}

/// render_context_create calls since [before] (an earlier Fake().creates()).
std::string CreatesSince(const std::string& before) {
  const std::string all = Fake().creates();
  if (before == "none") return all;
  if (all == before) return "none";
  return all.substr(before.size() + 1);  // drops "<before>,"
}

/// Start([choice]) on [r]: result, backend and reason, the creates it made
/// and every line it logged. [vulkan_devices]: also record how many Vulkan
/// devices the fake interop accepted so far (0 proves no Vulkan device was
/// initialised).
bool Start(Run& run, Rig& rig, VideoRenderer& r, RendererChoice choice,
           bool vulkan_devices) {
  TakeLog();
  const std::string before = Fake().creates();
  const bool ok = r.Start(choice);
  run.trace.Add(Describe(rig, r, ok));
  run.trace.Add("create-attempts " + CreatesSince(before));
  if (vulkan_devices)
    run.trace.Add("vulkan-devices-seen=" +
                  std::to_string(rig.vk.device_names().size()));
  const std::vector<std::string> log = TakeLog();
  if (log.empty()) run.trace.Add("log none");
  for (const std::string& line : log) run.trace.Add("log " + line);
  return ok;
}

/// Destroys every renderer in [rs] and records the render_context_free
/// calls since [frees_before] (an earlier Fake().counters().frees).
void Teardown(Run& run, std::vector<std::unique_ptr<VideoRenderer>>* rs,
              int frees_before) {
  Fake().SignalPending();
  rs->clear();
  run.trace.Add("teardown frees=" +
                std::to_string(Fake().counters().frees - frees_before));
  if (Images().live() != 0)
    run.Invariant(std::to_string(Images().live()) +
                  " image(s) never destroyed");
}

/// One Start under [value] (nullptr: unset) with a fresh rig and renderer.
/// [vulkan_devices] as for Start (only where the expectation is 0: the
/// number of accepted devices on a real device depends on the machine).
void StartOnce(Run& run, bool with_vulkan, const char* value,
               RendererChoice choice, bool vulkan_devices) {
  Rig rig(with_vulkan);
  const int frees_before = Fake().counters().frees;
  golden::SetEnv(kApiVariable, value);
  std::vector<std::unique_ptr<VideoRenderer>> rs;
  rs.push_back(rig.NewRenderer());
  Start(run, rig, *rs.back(), choice, vulkan_devices);
  golden::SetEnv(kApiVariable, nullptr);
  Teardown(run, &rs, frees_before);
}

// --- Scenarios ---------------------------------------------------------------

// Unset: the full chain on a platform without Vulkan interop (the same as
// golden_sw's sw-fallback-no-interop), and nothing logged about the switch.
void ApiUnset(Run& run) {
  StartOnce(run, false, nullptr, RendererChoice::kAuto, false);
}

// Empty means unset. (On Windows _putenv_s with "" removes the variable;
// elsewhere it stays set to the empty string. Both must behave as unset.)
void ApiEmpty(Run& run) {
  StartOnce(run, false, "", RendererChoice::kAuto, false);
}

// software with a Vulkan interop present: the Vulkan candidates are
// excluded before their backend exists, so no Vulkan device is initialised
// and the only create is software's.
void ApiSoftware(Run& run) {
  StartOnce(run, true, "software", RendererChoice::kAuto, true);
}

// vulkan on a real device: Vulkan wins as without the switch. Then, with
// every Vulkan create failing, Start fails instead of falling back to
// software: no software create, and no "falling back" log line.
void ApiVulkan(Run& run) {
  StartOnce(run, true, "vulkan", RendererChoice::kAuto, false);
  Fake().SetCreateResult(MPV_RENDER_API_TYPE_VULKAN, nullptr, kCreateError);
  StartOnce(run, true, "vulkan", RendererChoice::kAuto, false);
}

// vulkan without a Vulkan interop: both Vulkan candidates are unavailable
// and software is excluded, so nothing is created and Start fails.
void ApiVulkanUnavailable(Run& run) {
  StartOnce(run, false, "vulkan", RendererChoice::kAuto, false);
}

// A well-formed api no Phase 12 candidate has: every candidate excluded.
void ApiUnknown(Run& run) {
  StartOnce(run, true, "d3d11", RendererChoice::kAuto, true);
}

// Upper case is malformed (no case folding): nothing matches and the echo
// replaces every character outside [a-z0-9-] with '?'.
void ApiCase(Run& run) {
  StartOnce(run, true, "VULKAN", RendererChoice::kAuto, true);
}

// 24 valid characters exceed the 16-character limit: malformed even though
// it starts with "vulkan" (no prefix match); the echo keeps 16 characters.
void ApiOverlong(Run& run) {
  StartOnce(run, true, "vulkanvulkanvulkanvulkan", RendererChoice::kAuto,
            true);
}

// The forced api intersects with the renderer selection. renderer software
// + vulkan: the chain has only software/sw, which is excluded. renderer
// gpu-next + software (ADR 0004's example): software/sw is only gpu-next's
// fallback, and a forced run never falls back, so it is excluded too.
void ApiRendererIntersection(Run& run) {
  StartOnce(run, true, "vulkan", RendererChoice::kSoftware, true);
  StartOnce(run, true, "software", RendererChoice::kGpuNext, true);
}

// Read once per Start: a renderer started under software keeps its backend
// and reason after the variable is removed; a second renderer started
// afterwards runs the full chain.
void ApiReread(Run& run) {
  Rig rig(false);
  std::vector<std::unique_ptr<VideoRenderer>> rs;
  golden::SetEnv(kApiVariable, "software");
  rs.push_back(rig.NewRenderer());
  Start(run, rig, *rs.back(), RendererChoice::kAuto, false);
  golden::SetEnv(kApiVariable, nullptr);
  rs.push_back(rig.NewRenderer());
  Start(run, rig, *rs.back(), RendererChoice::kAuto, false);
  run.trace.Add("first-after-second " + Describe(rig, *rs.front(), true));
  Teardown(run, &rs, 0);
}

struct ScenarioDef {
  const char* name;
  void (*fn)(Run&);
  bool needs_vulkan;  // skipped (on its own) without a Vulkan 1.3 device
};

const ScenarioDef kScenarios[] = {
    {"api-unset", ApiUnset, false},
    {"api-empty", ApiEmpty, false},
    {"api-software", ApiSoftware, false},
    {"api-vulkan", ApiVulkan, true},
    {"api-vulkan-unavailable", ApiVulkanUnavailable, false},
    {"api-unknown", ApiUnknown, false},
    {"api-case", ApiCase, false},
    {"api-overlong", ApiOverlong, false},
    {"api-renderer-intersection", ApiRendererIntersection, false},
    {"api-reread", ApiReread, false},
};

/// Same probe as golden_vk (variable unset): skip the Vulkan scenarios only
/// when the loader, an instance or a Vulkan 1.3 device is missing. Returns
/// the reason to skip, or "" to run them.
std::string Probe() {
  Fake().Reset();
  Images().Reset();
  golden::SetEnv(kApiVariable, nullptr);
  std::string skip;
  {
    Rig rig(true);
    std::unique_ptr<VideoRenderer> r = rig.NewRenderer();
    r->Start(RendererChoice::kGpuNext);
    const std::string reason = r->backend_reason();
    if (r->backend() != mpv_kit::Backend::kVulkan &&
        (reason.find("Vulkan loader") != std::string::npos ||
         reason.find("vkCreateInstance failed") != std::string::npos ||
         reason.find("no Vulkan 1.3 device") != std::string::npos ||
         reason.find("Vulkan < 1.3 on") != std::string::npos))
      skip = reason;
  }
  TakeLog();
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
  // --slack-ms is accepted for symmetry with the other goldens; these
  // scenarios have no timing expectation.
  if (golden_path.empty() || slack_ms <= 0) {
    std::fprintf(stderr,
                 "usage: video_renderer_api_test <golden/api_override.txt> "
                 "[--slack-ms=N]\n");
    return 1;
  }
  golden::Golden expected;
  std::string error;
  if (!golden::LoadGolden(golden_path, &expected, &error)) {
    std::printf("GOLDEN error: %s\n", error.c_str());
    return 1;
  }
  // The scenarios own the variable: whatever the caller set is ignored.
  golden::SetEnv(kApiVariable, nullptr);
  const std::string vk_skip = Probe();

  golden::Golden actual;
  bool ok = true;
  bool vk_ran = false;
  for (const ScenarioDef& def : kScenarios) {
    if (def.needs_vulkan && !vk_skip.empty()) {
      // Not run: its expectation is not compared either.
      for (auto it = expected.begin(); it != expected.end(); ++it) {
        if (it->first == def.name) {
          expected.erase(it);
          break;
        }
      }
      continue;
    }
    vk_ran = vk_ran || def.needs_vulkan;
    Fake().Reset();
    Images().Reset();
    TakeLog();
    Run run{def.name, {}, true};
    try {
      def.fn(run);
    } catch (const std::exception& e) {
      std::printf("GOLDEN timeout scenario=%s: waiting for %s\n", def.name,
                  e.what());
      run.ok = false;
    }
    golden::SetEnv(kApiVariable, nullptr);
    for (const std::string& v : Images().TakeViolations()) run.Invariant(v);
    if (!run.ok) ok = false;
    actual.emplace_back(def.name, run.trace.lines());
  }
  const int rc = golden::CompareGolden(expected, actual);
  if (rc != 0 || !ok) return 1;
  if (vk_ran) {
    std::printf("API vk scenarios ok\n");
  } else {
    std::printf("API vk scenarios skipped: %s\n", vk_skip.c_str());
  }
  std::printf("GOLDEN ok scenarios=%zu\n", actual.size());
  return 0;
}
