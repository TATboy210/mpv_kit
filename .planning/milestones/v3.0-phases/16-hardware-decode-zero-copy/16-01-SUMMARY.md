---
phase: 16-hardware-decode-zero-copy
plan: 01
subsystem: testing
tags: [hwdec, zero-copy, integration-test, ci, spike, videotoolbox, d3d11, opengl]

requires:
  - phase: 15-linux-opengl-backend
    provides: forced-opengl Linux leg, evidence/ci_gate conventions
provides:
  - "example/integration_test/hwdec_probe.dart: zero-copy / copy-back / software / unexpected classifier, HWDEC hwdec-1 line, bounded awaitHwdecReport (pure Dart)"
  - "hwdec_zero_copy_test.dart: hwdec=no reference + default-list run per real sample with VO screenshot checks, Flutter texture channel, play-to-end, HWDEC-RUN line"
  - "tools/make_hwdec_samples.sh + native-verify hwdec-samples job (hwdec-samples, hwdec-samples-uhd artifacts)"
  - "ci_gate.sh copy with CI_GATE_EVIDENCE, push authorization, evidence/hwdec-spike.txt, evidence/ci-runs.txt"
  - "macos_route_test default row reads the Player list at session creation and prints requestedHwdec"
affects: [16-02, 16-03, 16-04, 16-05, 16-06]

actuals:
  tokens: 36000
  tasks: 3
  commits: 3
plan_head_before: 42996d3d2ae6d887e268468637dbc97a2bbae2b6
plan_head_after: 57d0efe237a71080105a257e8b2e606f0c60e21c

key-files:
  created:
    - example/integration_test/hwdec_probe.dart
    - example/integration_test/hwdec_zero_copy_test.dart
    - example/test/hwdec_probe_test.dart
    - tools/make_hwdec_samples.sh
    - .planning/phases/16-hardware-decode-zero-copy/tools/ci_gate.sh
    - .planning/phases/16-hardware-decode-zero-copy/evidence/push-authorization.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/ci-runs.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/hwdec-spike.txt
  modified:
    - .github/workflows/native-verify.yml
    - example/integration_test/macos_route_test.dart
    - .gitignore

key-decisions:
  - "Zero-copy is never claimed from hwdec-current alone: needs the method's hardware pixelformat plus a non-empty hw-pixelformat."
  - "Push authorization push-green-only+dispatch with ci_mode=live (user answer, 2026-10-28)."

requirements-completed: []
requirements-partial: [HWD-05, HWD-01]

ci-gate: passed - task 2 on c6fe676 (native-verify 40700564165, flutter-plugin 40700564237), task 3 on 1cad32b (native-verify 40704367040, flutter-plugin 40704363157, macos-route 40704363148); no reruns
status: complete
completed: 2026-10-28
---

# Phase 16 Plan 01: hwdec probe tooling and hosted spike Summary

**CI can now say zero-copy / copy-back / software on real H.264 and HEVC samples (ubuntu forced opengl, windows forced d3d11 on WARP, macOS route probe), and the hosted spike shows the macOS default list does select VideoToolbox zero-copy once the probe stops feeding `List.toString()` back as the option.**

## Accomplishments

- **Task 1 (checkpoint):** user answered `push-green-only+dispatch`; written to `evidence/push-authorization.txt` with `ci_mode=live`, committed in c6fe676 before the first push.
- **Task 2 (c6fe676, tracer):** classifier + 26 unit tests, sample script, `hwdec-samples` job, linux opengl leg; CI gate ok, ubuntu prints the hwdec=no software lines and the default-list lines, no `unexpected`.
- **Task 3 (1cad32b):** three exact-seek screenshot checks, Flutter texture channel, play-to-end with per-second hwdec sampling, extended `HWDEC-RUN`, windows d3d11 leg, macOS default-list fix, `.gitignore`. CI gate ok on all three workflows. Spike recorded in `evidence/hwdec-spike.txt`.

## Spike facts (hosted, no hardware decoder anywhere)

- linux opengl / llvmpipe and windows d3d11 / WARP: the current default list ends in software for all samples (`hwdecSeen=no`); windows `d3d11vaZeroCopy=false`. Whether d3d11va was tried first is not visible (no verbose decoder log on that leg).
- macOS corrected default row (h264-8bit): `hwdecCurrent=videotoolbox`, interop `videotoolbox,vulkan`, pixelformat `videotoolbox`, hw `nv12`, outcome zero-copy, screenshot match. mpv log: vulkan tried first (unsupported), `d3d11va-copy` unsupported, then videotoolbox via `auto-safe`. `requestedHwdec` = `vulkan,d3d11va-copy,auto-safe`, same entries as ROUTE-IDENTITY `defaultHwdec`; no bracketed hwdec value left in the log.
- ASSUMED (A2): `d3d11`, `vulkan`, `drm_prime` hardware format names could not be observed on hosted runners; 16-06 records the real strings on the RTX 4060. Seen: `videotoolbox`/`nv12`, `videotoolbox`/`p010`.

## Deviations from Plan

None - plan executed as written. Unit tests ran locally (26 + macOS route probe tests pass); `hwdec_zero_copy_test` itself can only run on hosted CI (no local libmpv samples).

## Notes for 16-02

- Default list today: `vulkan,d3d11va-copy,auto-safe`. On macOS it already reaches VideoToolbox zero-copy through `auto-safe`; on WARP and llvmpipe it is software. Windows RTX 4060 behaviour of the list is still unmeasured (16-06).
- `requirements-partial`: HWD-01 (default list change lands in 16-02) and HWD-05 (wired into the other tests in 16-05) stay unticked.
- 14-09 / 14-10 / 14-11 remain pending user hardware sessions (recorded in STATE.md).

## Self-Check: PASSED

Files exist, commits c6fe676 and 1cad32b on origin, gate output `CI-GATE ok` for both shas, golden-freeze sha256 check OK.
