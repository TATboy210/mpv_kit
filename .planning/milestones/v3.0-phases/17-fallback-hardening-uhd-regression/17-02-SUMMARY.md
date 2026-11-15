---
phase: 17-fallback-hardening-uhd-regression
plan: 02
subsystem: testing
tags: [backend-matrix, forced-backend, softwareFallback, hwdec-guard, ci-gate, integration-test]

requires:
  - phase: 16-hardware-decode-zero-copy
    provides: hwdec_probe.dart classification table, hwdec_zero_copy_test, HWDEC lines
  - phase: 17-fallback-hardening-uhd-regression
    provides: 17-01 push authorization, ci_gate.sh copy, golden-freeze-17 manifest
provides:
  - "tools/backend_matrix.sh: every backend of each platform forced in turn against the real-plugin texture probe (BACKEND-MATRIX lines), in native-verify integration-test on linux, windows, macOS"
  - "texture_probe_test: forced-api assertion and MPV_KIT_EXPECT_BACKEND=unavailable mode (PROBE-UNAVAILABLE)"
  - "MpvVideoEventKind.softwareFallback now reaches the first events listener (private pending state, no API change)"
  - "MPV_KIT_REQUIRE_HWDEC guard (hwdecRequirementError, checkHwdecRequirement, hwdecRequireLine) plus tools/require_hwdec_negative.sh hosted negative leg"
affects: [17-03, 17-04, 17-05]

# Not ticked in REQUIREMENTS.md: VER-02/VER-03 are shared with 17-04 and 17-05 (RTX 4060 cells, SC wording),
# VER-01 is waiting for the SC1 wording approval in 17-05 (see 17-01).
requirements-completed: []
requirements-partial: [VER-02, VER-03, VER-01]

actuals:
  tokens: 10000
  tasks: 3
  commits: 5
plan_head_before: df7942020a96a73717c7ecf4c1ceb6960c741b51
plan_head_after: c7e395a52c4084cb416c2b6d8779adc94df1c28f

tech-stack:
  added: []
  patterns:
    - "Matrix cell = one flutter test run with env-selected expectation; unavailable is an asserted absence (PROBE-UNAVAILABLE), never a pass"
    - "Broadcast stream onListen hands a create-time event to the first listener"
    - "Negative leg: a script inverts an expected test failure and checks the failure line"

key-files:
  created:
    - tools/backend_matrix.sh
    - tools/require_hwdec_negative.sh
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/matrix.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/red-local-17-02-fallback-event.log
  modified:
    - example/integration_test/texture_probe_test.dart
    - example/integration_test/d3d11_device_lost_test.dart
    - example/integration_test/hwdec_probe.dart
    - example/integration_test/hwdec_zero_copy_test.dart
    - example/test/hwdec_probe_test.dart
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - packages/mpv_kit_video/test/controller_channel_test.dart
    - packages/mpv_kit_video/CHANGELOG.md
    - .github/workflows/native-verify.yml
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/ci-runs.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/flake-timing.txt

key-decisions:
  - "The Windows vulkan cell is asserted unavailable on hosted runners (vkCreateInstance failed, every other candidate excluded); the real-GPU Vulkan cell is 17-04 on the RTX 4060."
  - "softwareFallback fix uses only private state (late-final broadcast controller with onListen plus _pendingFallback); API freeze diff and the MpvVideoBackend enum line are unchanged."
  - "MPV_KIT_REQUIRE_HWDEC accepts only the zero-copy methods of hwdecZeroCopyFormats; -copy, no, auto* and typos are errors, never 'no requirement'."

coverage:
  - id: D1
    description: "Forced backend matrix on all three platforms: linux opengl/vulkan/software, windows d3d11/software plus vulkan asserted unavailable, macOS vulkan/software"
    requirement: "VER-02"
    verification:
      - kind: integration
        ref: "native-verify run 40982220052 (and 40984192997): 8 BACKEND-MATRIX lines result ok, PROBE-UNAVAILABLE for windows vulkan; ci_gate.sh CI-GATE ok"
        status: pass
    human_judgment: false
  - id: D2
    description: "softwareFallback delivered to the first events listener, with the full fallback chain on the real plugin (hosted windows create-fail injection)"
    requirement: "VER-01"
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#softwareFallback delivery (VER-01)"
        status: pass
      - kind: integration
        ref: "native-verify run 40984192997 D3D11-INJECT create-fail softwareFallback field"
        status: pass
    human_judgment: false
  - id: D3
    description: "MPV_KIT_REQUIRE_HWDEC guard fails loudly on a host without the required zero-copy decode"
    requirement: "VER-03"
    verification:
      - kind: unit
        ref: "example/test/hwdec_probe_test.dart#MPV_KIT_REQUIRE_HWDEC (VER-03)"
        status: pass
      - kind: integration
        ref: "native-verify run 40984192997 REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=d3d11 exit=1"
        status: pass
    human_judgment: false
  - id: D4
    description: "Positive guard case (real d3d11va zero-copy passes the guard) and the real-GPU Vulkan matrix cell"
    requirement: "VER-03"
    verification: []
    human_judgment: true
    rationale: "Needs the RTX 4060 hardware session (17-04); hosted runners have no hardware decoder or shareable Vulkan device."

duration: ~75min
completed: 2026-10-30
status: complete
---

# Phase 17 Plan 02: forced backend matrix, softwareFallback delivery, hwdec guard Summary

**Every backend of each platform is now forced in turn against the real-plugin texture probe in CI (8 cells, all ok, hosted Windows Vulkan asserted unavailable with its real `vkCreateInstance failed` reason), the create-time `softwareFallback` event finally reaches the first `events` listener with the whole fallback chain, and `MPV_KIT_REQUIRE_HWDEC` fails loudly on hosted WARP.**

## Performance

- **Duration:** about 75 min (start time not recorded at launch; estimated from commit and CI timestamps)
- **Completed:** 2026-10-30T01:28Z (last task commit; CI gate green on 50be7f0)
- **Tasks:** 3 (1 tracer, 2 auto/tdd)
- **Files modified:** 11 outside `.planning/`

## Accomplishments

- **Task 1 (tracer): forced backend matrix.** `tools/backend_matrix.sh <linux|windows|macos>` runs `texture_probe_test` once per cell with `MPV_KIT_VIDEO_API` forced; the probe now asserts that the reason's first token equals the forced api, and `MPV_KIT_EXPECT_BACKEND=unavailable` asserts `render_init` with no head, the forced api's own non-excluded failure and every other candidate only `excluded by MPV_KIT_VIDEO_API=<api>`. New `Backend matrix` step at the end of native-verify `integration-test`, no continue-on-error. CI gate ok on 02af05a (native-verify 40982220052, flutter-plugin 40982219981). Existing steps are untouched.
- **Task 2: softwareFallback delivery.** The event was added to an async broadcast stream inside `create`, before any listener could exist, so it was always lost. It is now held in `_pendingFallback` and handed to the first listener from `onListen` (once; dropped on dispose when nobody listened). RED evidence was taken locally first (`evidence/red-local-17-02-fallback-event.log`), then green. `d3d11_device_lost_test` create-fail now asserts the message `rendering in software: <reason>` and reports it in the `D3D11-INJECT` line.
- **Task 3: `MPV_KIT_REQUIRE_HWDEC`.** `hwdecRequirementError`/`checkHwdecRequirement`/`hwdecRequireLine` in `hwdec_probe.dart` (dart-only imports kept), wired into `hwdec_zero_copy_test` for the first-frame and end report of every default-list run (fail lines printed before the run's other assertions, all samples run, then fail). `tools/require_hwdec_negative.sh` inverts the expected failure and checks the fail line; native-verify windows runs it on WARP. CI gate ok on 50be7f0 (native-verify 40984192997, flutter-plugin 40984192897), which also covers Task 2's real-plugin line.

### Platform x api matrix (native-verify 40982220052, repeated green in 40984192997)

| Platform | opengl | vulkan | d3d11 | software |
|---|---|---|---|---|
| linux (ubuntu-24.04, llvmpipe) | ok (`opengl (gpu)`, upright) | ok (`vulkan (gpu-next)`) | n/a | ok |
| windows (windows-2025, WARP) | n/a | asserted-unavailable (`vulkan/gpu-next unavailable: vkCreateInstance failed`) | ok (`d3d11 (gpu-next) on Microsoft Basic Render Driver`) | ok |
| macos (macos-15, bundle libmpv, MoltenVK) | n/a | ok (`vulkan (gpu-next) on Apple Paravirtual device via MoltenVK`) | n/a | ok |
| windows real GPU (RTX 4060) | n/a | handed to 17-04 | handed to 17-04 | handed to 17-04 |

Raw `BACKEND-MATRIX`/`PROBE` lines per cell with run ids are in `evidence/matrix.txt` (8 cells).

### Guard and event evidence (run 40984192997, `evidence/ci-runs.txt`)

- `REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=d3d11 exit=1`, with `HWDEC-REQUIRE {...,"required":"d3d11va",...,"at":"first-frame","hwdecCurrent":"no","outcome":"software","result":"fail",...}` and the same for `at":"end"`.
- `D3D11-INJECT {"mode":"create-fail",...,"backend":"software",...,"softwareFallback":"rendering in software: software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; d3d11/gpu-next unavailable: d3d11 device creation failed: 0x887A0004 (injected); vulkan/gpu unavailable: ...; d3d11/gpu unavailable: ..."}`.
- `ANGLE-FREE` for `mpv_kit_video_plugin.dll` (build windows-2025) and `libmpv-2.dll` (windows x64 and arm64 ABI audit); `check_matrix.py` passes; `MACOS-DYLD summary staged=37 homebrew=0`.

## Task Commits

1. **Task 1: forced backend matrix** - `02af05a` (test); evidence `50be7f0` (docs)
2. **Task 2: softwareFallback to the first listener** - `5b52ee8` (fix, includes RED log, tests, CHANGELOG)
3. **Task 3: MPV_KIT_REQUIRE_HWDEC guard** - `e7f32bf` (test); evidence `c7e395a` (docs)

**Plan metadata:** the SUMMARY/STATE commit follows this file.

## Deviations from Plan

**1. [Drift adaptation, planned by orchestrator] Build and golden facts.** The plan predates the FIFO ready queue; none of its tasks touch the native renderer, so ring/present-timeout facts did not matter. `golden-freeze-17.sha256` was not touched (`git diff` empty for `native/tests`).

**2. [Rule 3 - blocking, local tooling] Unit tests with libmpv on this Windows host.** `MPV_KIT_LIBMPV_PATH` in MSYS form is not loadable by the Dart VM (it needs backslashes), and dependency DLLs must sit in `packages/mpv_kit_video/build/native_assets/windows` (copied from the already-downloaded dev.2 bundle in `.dart_tool`, untracked build output). The plan's verify command (`$LIB/libmpv-2.dll` under the dev.3 bundle) names an empty directory on this host. Used the dev.2 bundle DLLs for the local run; CI runs the same tests against the staged libmpv and passed.

**3. [Observation] Local unavailable-mode check.** On this RTX 4060 laptop `MPV_KIT_VIDEO_API=d3d11 MPV_KIT_EXPECT_BACKEND=unavailable` correctly failed (the cell is expected to render here), and with `MPV_KIT_D3D11_INJECT=create-fail` it passed and printed a reason with the injected trails, so both sides of the unavailable assertion were exercised locally before CI.

**4. [Test-design choice] `D3D11-INJECT` `softwareFallback` assertion.** Asserted only when software won (hosted WARP); `null` in the report when Vulkan won (this laptop), as the plan specified. Local run on the RTX 4060 therefore printed `"softwareFallback":null`; the real software case is proven by run 40984192997.

Otherwise the plan was executed as written. No auto-fixed product bugs beyond the planned softwareFallback fix.

## Authentication gates

None.

## Known Stubs

None.

## Threat Flags

None. Test code, one workflow step, two scripts and a private-state change; no new endpoint, auth path or schema.

## Issues Encountered

- Local formatter: the installed `dart format` rewrites unrelated lines in `video_controller.dart` and `controller_channel_test.dart`; only the newly added group was spliced in formatted, all other lines are untouched.
- A scratch test (`zz_scratch_load_test.dart`) and a scratch evidence copy used to debug the Windows path issue were removed before commit.

## Next Phase Readiness

17-03 (soak harness, ubuntu opengl soak) can start; it appends a linux step to `native-verify.yml` after the new `Backend matrix` step. 17-04 (RTX 4060) reuses `tools/require_hwdec_negative.sh windows software d3d11va` for the real-GPU negative leg and runs the positive `MPV_KIT_REQUIRE_HWDEC=d3d11va` case plus the real-GPU Vulkan and d3d11 matrix cells. VER-01 stays partial (SC1 wording approval in 17-05).

## Self-Check: PASSED

- Files exist: `tools/backend_matrix.sh`, `tools/require_hwdec_negative.sh`, `evidence/matrix.txt` (8 cells), `evidence/red-local-17-02-fallback-event.log`: FOUND.
- Commits 02af05a, 5b52ee8, e7f32bf, 50be7f0, c7e395a are ancestors of HEAD and on origin/feat/mpv-master-upgrade.
- Plan verification: `check_matrix.py` ok; `git diff` for `packages/mpv_kit/lib`, `api_freeze_test.dart`, `mpv_kit_video.dart` empty since the grant head; enum line count 1; `flutter analyze --fatal-infos` clean for example and mpv_kit_video; `flutter test` mpv_kit_video 29 passed; `hwdec_probe_test` 40 passed.
