---
phase: 12-renderbackend-seam
plan: 10
subsystem: video-output
tags: [cpp17, render-backend, wire-name, method-channel, env-var, mpv-kit-video-api, golden-test, adr-0004]

requires:
  - phase: 12-03
    provides: "Dart wire-name set d3d11|opengl|vulkan|software; ADR 0004 Decision 4 (MPV_KIT_VIDEO_API contract)"
  - phase: 12-06
    provides: "reason grammar: head + `<api>/<renderer> unavailable: <why>` trails, SanitizeReasonField"
  - phase: 12-09
    provides: "RenderBackend::wire_name(), candidate chain as data, Start candidate loop"
provides:
  - "VideoRenderer::wire_name(): the winning backend's own wire name (valid after Start succeeded)"
  - "All three plugins report backend from wire_name(); render_init failures carry the trails as PlatformException.details"
  - "MPV_KIT_VIDEO_API in VideoRenderer::Start: per-Start read, ^[a-z0-9-]{1,16}$, strict filter with no fallback (software included), sanitised and truncated echo, one log line"
  - "native/tests/video_renderer_api_test.cc + golden/api_override.txt (10 scenarios; only api-vulkan needs a Vulkan device), registered in meson"
affects: [12-11, 12-12, 14, 15, 17]

actuals:
  tokens: 7200
  tasks: 2
  commits: 4
plan_head_before: ffb0422679c8d3d5cf445732e396101f5df1efc8
plan_head_after: 598d2878b84b84f15cd657d3758b1d080cc9ec66

tech-stack:
  added: []
  patterns:
    - "Forced-mode candidates are filtered before AttemptFor, so an excluded api never gets a backend or a device"
    - "A golden binary may skip one device-bound scenario on its own: it drops that section from the expected golden and prints `API vk scenarios skipped: <why>`"
    - "Start's log lines are deterministic and part of the api test's trace (`log <line>` / `log none`)"

key-files:
  created:
    - native/tests/video_renderer_api_test.cc
    - native/tests/golden/api_override.txt
    - .planning/phases/12-renderbackend-seam/evidence/red-local-12-10-api-override.log
  modified:
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/src/video_renderer.cc
    - packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp
    - packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc
    - packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm
    - native/tests/meson.build
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt

key-decisions:
  - "A forced run also honours the renderer request strictly: software/sw is only the fallback of a gpu-next or gpu request, so MPV_KIT_VIDEO_API=software with renderer gpu-next fails (ADR 0004's own example). kAuto requests every renderer, so software + auto succeeds"
  - "Candidates removed that way use the same why, `excluded by MPV_KIT_VIDEO_API=<value>`, so the ADR 0004 vocabulary is unchanged"
  - "Windows reads the variable with _dupenv_s; getenv is deprecated in the MSVC CRT (C4996, an error under /WX, and -Wdeprecated-declarations in clang); other platforms use std::getenv"
  - "A forced run no longer logs `falling back to software rendering`, because it never falls back"
  - "RBE-07 and RBE-08 are left Pending: both tasks' hosted CI gates are deferred by the user, and the getenv branch (Linux/macOS) is proven only by those gates"

patterns-established:
  - "Plugin create contract: backend = VideoRenderer::wire_name(); failure = render_init / \"no usable render backend\" / details = trails"

requirements-completed: []  # RBE-07, RBE-08: implemented and locally verified; mark complete once the deferred 12-10 gates are CI-GATE ok

coverage:
  - id: D1
    description: "Plugins report the winning backend's wire_name() (Windows locally on the RTX 4060: vulkan; forced software: software)"
    requirement: RBE-07
    verification:
      - kind: e2e
        ref: "example/integration_test/real_plugin_test.dart -d windows at eec251c and 598d287: All tests passed!, INTEGRATION backend vulkan; with MPV_KIT_VIDEO_API=software backend software"
        status: pass
      - kind: other
        ref: "flutter-plugin 40415740138 on eec251c: build (ubuntu-24.04, linux), build (windows-2025, windows), build (macos-15, macos) success (seen, not waited for)"
        status: pass
      - kind: integration
        ref: "Hosted CI gate for Task 1 on eec251c (build x3 + integration-test x3 with backend vulkan|software): DEFERRED by the user"
        status: unknown
    human_judgment: false
  - id: D2
    description: "render_init failure carries the trails as PlatformException.details, end to end into Dart"
    requirement: RBE-07
    verification:
      - kind: e2e
        ref: "real_plugin_test with MPV_KIT_VIDEO_API=d3d11 at 598d287: PlatformException(render_init, no usable render backend, vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11; ...; software/sw unavailable: excluded by MPV_KIT_VIDEO_API=d3d11, null) (Windows only; Linux/macOS details path compiled on CI, not run)"
        status: pass
    human_judgment: false
  - id: D3
    description: "MPV_KIT_VIDEO_API strict filter: ten scenarios (unset, empty, software, vulkan, vulkan-unavailable, unknown, case, overlong, renderer-intersection, reread)"
    requirement: RBE-08
    verification:
      - kind: unit
        ref: "native/tests/video_renderer_api_test.cc (MSVC /W4 /WX, RTX 4060): API vk scenarios ok, GOLDEN ok scenarios=10, three runs; no-ICD run: API vk scenarios skipped, GOLDEN ok scenarios=9"
        status: pass
      - kind: integration
        ref: "Hosted CI gate for Task 2 on 598d287 (api test OK on linux x64 with API vk scenarios ok, windows-2025, macos-15, sanitizers; golden_vk OK on linux x64): DEFERRED by the user"
        status: unknown
    human_judgment: false
  - id: D4
    description: "Unset or empty behaves exactly as before: frozen goldens unchanged and passing; no new Dart public API"
    requirement: RBE-08
    verification:
      - kind: unit
        ref: "golden_sw 12, golden_vk 8, golden_vk_fallback, golden_vk_retire_twice, golden_sw_retire_twice OK at 598d287; sha256sum -c golden-freeze 5xOK; CONSTANTS ok; no Dart file changed"
        status: pass
    human_judgment: false

duration: 19 min (22:47Z to 23:06Z)
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 10: Native wire names and the MPV_KIT_VIDEO_API force switch Summary

**What this plan delivered:**
- **Wire name.** All three plugins now report the `backend` field from `VideoRenderer::wire_name()`, which is the winning `RenderBackend`'s own `wire_name()`. The plugins no longer derive it from `backend() == kVulkan`. When no backend works, `render_init` carries the reason trails as `details`, so Dart sees why each candidate was unavailable.
- **`MPV_KIT_VIDEO_API`.** `VideoRenderer::Start` reads this native variable once per call. Only candidates of that api, and of the requested renderer, are tried. Every other candidate becomes an `excluded by MPV_KIT_VIDEO_API=<echo>` trail, and nothing falls back. An unknown or malformed value tries nothing and echoes a sanitised value of at most 16 characters.

## Performance

- **Duration:** about 19 min, 2026-10-26T22:47:28Z to 23:06Z (host clock).
- **Tasks:** 2 (Task 1 tracer; Task 2 TDD with RED and GREEN).
- **Files:** 5 product files, 3 test files (2 new), 2 evidence files.

## Task Commits

| Step | Commit | Content | Pushed |
|---|---|---|---|
| Task 1 | `eec251c` | `wire_name()`, three plugins: backend field, `render_init` details, header contract | yes (green head) |
| Task 2 RED | `029da25` | `video_renderer_api_test.cc`, `golden/api_override.txt`, meson registration (tests only) | only as an ancestor of 598d287 |
| RED evidence | `934237b` | `red-local-12-10-api-override.log`, `red_local` line, Task 1 evidence, the orchestrator's 12-09 Task 3 gate line | as an ancestor |
| Task 2 GREEN | `598d287` | `MPV_KIT_VIDEO_API` parsing, validation, echo, filter, log line | yes (green head) |

Plan metadata: this SUMMARY's docs commit. It also holds the Task 2 evidence lines and is not pushed on its own.

## Task 1: wire name into Dart

- **Header:** `video_renderer.h` adds `const char* wire_name() const`. It returns `render_backend_->wire_name()` and is documented as valid only after `Start` returned true.
- **Windows:** the response uses `EncodableValue(wire)`. The `vk` local is gone, and the texture type still comes from `backend() == Backend::kVulkan`. On failure, `result->Error("render_init", "no usable render backend", EncodableValue(backend_reason()))`.
- **Linux:** the response uses `fl_value_new_string(raw->renderer->wire_name())`. `Error()` gains an optional borrowed `FlValue* details`, because `fl_method_call_respond_error` takes its own reference. On failure, the details are a `g_autoptr` string of `backend_reason()`. `vk` stays, since it still chooses the texture type.
- **macOS:** the response uses `[NSString stringWithUTF8String:renderer->wire_name()]`. On failure, the `FlutterError` details are the trails. `copyPixelBuffer`'s `backend()` check is unchanged.
- **Header contract:** all three plugin headers now read `backend: "d3d11"|"opengl"|"vulkan"|"software"`, and say that `details` are the trails on failure.
- **Line endings:** the three plugin files stay CRLF, as they were in the index. The renderer sources and tests stay LF.

**Tracer gate** (interactive, `end-of-phase`, automated-only verify, so no checkpoint):
- **Local verify, passed:** `flutter build windows --debug` had no `error C`/`warning C`, and the plugin DLL was rebuilt after the edit. `real_plugin_test` gave `All tests passed!` with `INTEGRATION {"backend":"vulkan",...}`. The grep gate, golden freeze 5xOK and `CONSTANTS ok` also passed.
- **Hosted CI gate:** deferred by the user. flutter-plugin 40415740138 on eec251c had already finished when I looked: `build` succeeded on ubuntu, windows and macos, so the Linux and macOS plugin edits compile. I did not wait for native-verify, which holds integration-test.

## Task 2: MPV_KIT_VIDEO_API

**Implementation** (`video_renderer.cc`):
- `ForcedApiValue()` reads the variable once per `Start`: `std::getenv("MPV_KIT_VIDEO_API")`, or `_dupenv_s` on Windows.
- `ParseForcedApi`:
  - empty means unset;
  - a value matching `[a-z0-9-]`, 1 to 16 characters, becomes the filter api;
  - anything else gets an empty filter, which matches no candidate;
  - the echo maps characters outside the set to `?` and is cut to 16 characters.
- `ForcedAllows` admits a candidate only when its api equals the filter, and its renderer was requested (`kAuto` requests all of them).
- The candidate loop records excluded candidates as trails before `AttemptFor`, so they get no backend instance and no device.
- `UsedLater` ignores excluded candidates.
- A forced run logs `mpv_kit: MPV_KIT_VIDEO_API=<echo> restricts rendering to that API` once, and drops the misleading `falling back to software rendering` line.
- With the variable unset, every branch reduces to the code before this plan: `allowed` is all true and `forced.active` is false.

**Test** (`video_renderer_api_test.cc`, `golden/api_override.txt`):
- **Harness:** the test only includes the frozen harness. Each scenario resets the variable.
- **Trace:** each `Start` writes the result line, `create-attempts` for that `Start`, and `vulkan-devices-seen=0` where an excluded Vulkan candidate must not have created a device. It also writes every line `Start` logged, then `teardown frees=<n>`.
- **api-vulkan:** this is the only scenario that needs a device. It covers Vulkan winning, then every Vulkan create failing. In the failure case there must be no software create and no fallback line. Without a device only this section is dropped from the expected golden, and the binary still passes on the other nine.
- **api-renderer-intersection:** covers both renderer software + vulkan, and ADR 0004's example renderer gpu-next + software.
- **api-reread:** after the variable is removed, the first renderer's reason is unchanged and a second renderer runs the full chain.

## TDD Gate Compliance (Task 2)

| RED commit (tests only) | RED evidence (local, that exact commit) | GREEN commit | GREEN evidence |
|---|---|---|---|
| 029da25 | `evidence/red-local-12-10-api-override.log`. 8 of 10 scenarios mismatch on the intended lines, for example `api-software line=1` (expected the software head with excluded trails, actual `vulkan (gpu-next) on <device>`), `api-vulkan line=3` (missing restricts log), `api-renderer-intersection line=1` (actual `software (sw) on cpu`). api-unset and api-empty match. All five existing goldens OK on the same build | 598d287 | MSVC: `API vk scenarios ok`, `GOLDEN ok scenarios=10` three times. All goldens OK. No-ICD run: `API vk scenarios skipped`, `GOLDEN ok scenarios=9` |

- **Semantic assessment.** Every failure is an expectation line about the forced-API behaviour. There were no build, discovery or fixture failures, and the two unset/empty scenarios correctly passed before the change.
- **Classifier.** The `tdd-red-evidence` classifier was not run, because the golden output is not one of its formats (as in 12-07 and 12-09).
- **Push.** The RED commit was never pushed alone (`red_evidence=local-only`).

## Decisions Made

See `key-decisions`. The user's words, verbatim: "做好推送即可，CI 验收不着急" (push is enough; CI acceptance can wait).

## Deviations from Plan

**1. [ADR contract] A forced run also excludes the software fallback of a gpu-next or gpu request**
- **Found during:** Task 2, while reading ADR 0004 Decision 4.
- **Issue:** filtering by api alone would let `MPV_KIT_VIDEO_API=software` with renderer gpu-next succeed, because `DefaultCandidates(kGpuNext)` ends in software/sw. ADR 0004 states that this combination fails.
- **Fix:** `ForcedAllows` also requires the candidate's renderer to be one the choice requested. The excluded candidate uses the existing `excluded by MPV_KIT_VIDEO_API=<value>` why.
- **Test:** second case of `api-renderer-intersection`.
- **Commit:** 598d287.

**2. [Rule 3 - Blocking] `_dupenv_s` on Windows instead of `std::getenv`**
- **Issue:** getenv is deprecated in the MSVC CRT, which is an error under the plugin's /W4 /WX. The clang front end, run on the getenv branch, showed `'getenv' is deprecated ... [clang-diagnostic-deprecated-declarations]`.
- **Fix:** an `#ifdef _WIN32` branch. The plan's grep for `getenv("MPV_KIT_VIDEO_API")` still matches the non-Windows branch.
- **Commit:** 598d287.

**3. [Rule 1 - Bug] The `falling back to software rendering` log is suppressed in a forced run**
- **Issue:** a forced Vulkan run whose creates all failed would log that it falls back to software, but it does not.
- **Fix:** `&& !forced.active` on that log. The test pins the exact log lines of that case.
- **Commit:** 598d287.

**4. [Test design]**
- **`api-software` runs everywhere,** not only with a device: the Vulkan candidates are excluded before any device would be touched, so the expectation is device-independent. With a device present it is still the "device available" case, and `vulkan-devices-seen=0` proves no device was initialised.
- **`api-reread` uses a rig without Vulkan interop,** so the second, unset Start's full chain does not depend on the runner. "First renderer unaffected" is checked through its backend and reason after the second Start, because the fake has a single update callback.

**5. [Env] Line endings.** Windows Python rewrote meson.build and the new test as CRLF. Both were converted back to LF before the RED commit. The CRLF plugin files were edited in binary mode and stay CRLF.

**6. [User instruction] Both hosted CI gates are deferred,** and only `pending` lines are in ci-runs.txt. Gate commands for the orchestrator:
- **Task 1** (eec251c): `CI_GATE_SHA=eec251c2e51e16e18b84edbfe5623db5b5d85225 bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh --jobs-success '^build \(' --jobs-success '^integration-test' --log '^integration-test \(ubuntu' '"backend":"(vulkan|software)"' --log '^integration-test \(windows' '"backend":"(vulkan|software)"' --log '^integration-test \(macos' '"backend":"(vulkan|software)"'`
- **Task 2** (598d287): `CI_GATE_SHA=598d2878b84b84f15cd657d3758b1d080cc9ec66 bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh --jobs-success '^build \(' --jobs-success '^integration-test' --jobs-success '^sanitizers' --log '^linux \(ubuntu-24\.04\)' 'video_renderer_api_test +OK' --log '^linux \(ubuntu-24\.04\)' 'API vk scenarios ok' --log '^windows \(windows-2025' 'video_renderer_api_test +OK' --log '^macos \(macos-15\)' 'video_renderer_api_test +OK' --log '^sanitizers' 'video_renderer_api_test +OK' --log '^linux \(ubuntu-24\.04\)' 'video_renderer_golden_vk +OK'`
- **Superseded run:** eec251c's native-verify may be cancelled by 598d287's push if the workflow cancels in progress. In that case the Task 2 gate also covers Task 1's integration-test expectations, since 598d287 contains eec251c.

**Total deviations:** 6
- 1 ADR-contract detail
- 1 blocking (Rule 3)
- 1 bug (Rule 1, a log line)
- 1 test-design note
- 1 local environment issue
- 1 user-directed deferral

**Impact:** no scope creep. Every unset/empty path is byte-identical to before, as the frozen goldens show.

## Issues Encountered

None beyond the deviations. No new product defect was found.

## ADR 0004 follow-up (not edited here)

- **New trail, not yet in the `why` vocabulary:** 12-09 added `<api>/<renderer> unavailable: platform has no <api> backend`. ADR 0004's `why` vocabulary still does not list it, and this plan does not touch the ADR. 12-11 (ADR follow-up) or Phase 13 should add it.
- **Missing sentence:** Decision 4 does not yet say that a forced run also drops the software fallback of a gpu-next/gpu request. Its own example implies it, and the code now follows that.

## Known Stubs

None.

## Threat Flags

None. T-12-20 is mitigated: whitelist, a length cap, no candidate for a malformed value, and an echo that is sanitised and truncated before it reaches a reason, details or the log. T-12-21 is mitigated: the test asserts no other-api create and no Vulkan device, and a failure reaches Dart with the trails as details. T-12-22 is mitigated: backend comes only from `wire_name()`, and Dart's strict set is unchanged.

## Next Phase Readiness

- Phase 17's forced-backend CI matrix can rely on `MPV_KIT_VIDEO_API=vulkan|software`. Phases 14 and 15 only add a candidate and a `CreateBackend` case, and `d3d11`/`opengl` then become valid filters with no further change.
- Before 12-12 relies on these heads, run the two deferred gates above. RBE-07 and RBE-08 can be marked complete once both gates pass.

## Self-Check: PASSED

- Files exist: native/tests/video_renderer_api_test.cc, native/tests/golden/api_override.txt, evidence/red-local-12-10-api-override.log.
- Commits eec251c, 029da25, 934237b and 598d287 are ancestors of HEAD. eec251c and 598d287 are on origin/feat/mpv-master-upgrade.
- `sha256sum -c` gives 5 × OK; `CONSTANTS ok`.

---
*Phase: 12-renderbackend-seam*
*Completed: 2026-10-26*
