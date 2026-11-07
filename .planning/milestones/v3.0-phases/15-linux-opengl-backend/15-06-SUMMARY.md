---
phase: 15-linux-opengl-backend
plan: 06
subsystem: native
tags: [linux, opengl, egl, probe, thread, auto-chain, vulkan-unavailable]

requires:
  - phase: 15-03
    provides: D-THREAD / IMPLICATION=helper-thread
  - phase: 15-05
    provides: OpenGLBackend and the Linux chain
provides:
  - "gl_interop.cc: ProbeGl on a short-lived thread (display from GDK on the platform thread, EGL work and context on the new thread, joined before members are written)"
  - "texture_probe_test.dart: SECOND-CONTROLLER assertion (same api for a second controller on the same player)"
  - "native-verify: Texture probe (linux, Vulkan unavailable) step, VK_DRIVER_FILES/VK_ICD_FILENAMES -> missing manifest"
affects: [15-07]

actuals:
  tokens: 9000
  tasks: 2
  commits: 3
plan_head_before: a99aa97
plan_head_after: fbcd55a4406d70dfcdfe6da32ebacaeb623bf027

key-files:
  modified:
    - packages/mpv_kit_video/linux/gl_interop.cc
    - packages/mpv_kit_video/linux/gl_interop.h
    - example/integration_test/texture_probe_test.dart
    - packages/mpv_kit_video/test/controller_channel_test.dart
    - .github/workflows/native-verify.yml

key-decisions:
  - "Probe thread, not platform thread: D-THREAD showed eglMakeCurrent EGL_BAD_ACCESS on the platform thread (11 of 12 controllers) and ok on a fresh thread. EglCurrentGuard and the fresh-thread diagnostics were deleted; the failure text keeps the failing call and EGL error."
  - "D-PROBE=supported, D-ORIENT=upright (vulkan and opengl), D-LOG=unknown (no native line was due in any run) written from real lines."

requirements-completed: []
requirements-partial: [GLX-03, GLX-04]  # not ticked: 15-07 lists both (docs, unverified list, final audit)

ci-gate: passed 2026-10-28 on sha fbcd55a (native-verify 40653685694, flutter-plugin 40653685682); same code on 45275ac also green (native-verify 40651979314, flutter-plugin 40651979441)
status: complete
completed: 2026-10-28
---

# Phase 15 Plan 06: Vulkan-unavailable auto proof and probe on a fresh thread Summary

**`GlInterop::ProbeGl` now runs on its own short-lived thread, so every controller gets the same backend as the first; with Vulkan made unavailable (`vkCreateInstance failed`) the auto chain lands on `opengl (gpu)` with the Vulkan reason in the trail, proven on the real plugin.**

## Accomplishments

- **Fix (Task 2):** the platform thread fails `eglMakeCurrent` (EGL_BAD_ACCESS) for most controllers; a fresh thread does not. The probe moved to a `std::thread` (display from GDK on the platform thread, `eglInitialize`/context/UUID query/destroy/`eglReleaseThread` on the thread, always joined, members written after the join). Same principle as `OpenGLBackend::RunBound`.
- **SECOND-CONTROLLER assertion:** after the first controller is disposed (player alive), a second one is created; its api must equal the first's. Committed together with the fix (push-green-only).
- **Vulkan-unavailable run (Task 1):** new linux-only step with both loader variables pointing at a missing manifest, `MPV_KIT_VIDEO_API` unset. Result: `PROBE api=opengl ... reason "opengl (gpu) on llvmpipe (...); vulkan/gpu-next unavailable: vkCreateInstance failed"`, hard assertions pass (supported, nonBlackRatio 1.0, upright before and after resize, renderErrors 0), SECOND-CONTROLLER opengl/opengl.

## Evidence (run 40653685694, sha fbcd55a; raw lines in evidence/backend-runs.txt)

- Default: `PROBE api=vulkan` (`vulkan (gpu-next) on llvmpipe`), upright, `SECOND-CONTROLLER vulkan/vulkan`. Forced opengl: opengl/opengl. Vulkan unavailable: opengl/opengl.
- Soak (default run): 13x `vulkan (gpu-next)` lines, none software or opengl. **Before the fix (15-05, run 40647806493): 1 vulkan, 11 opengl** (probe failure).
- Whole log: `opengl (gpu-next)` 0, `cannot create a probe EGL context` 0, `opengl (gpu)` 21. Native `mpv_kit:` lines: 0.
- Carried-over gates now green: 15-03 (`PROBE {"api":"vulkan"`, FLUTTER-VERSION, vulkan gpu-next INTEGRATION reason, soak counts) and 15-05's `PROBE vulkan` expectation; moved to `ci_gates_passed` in both SUMMARYs. D-PROBE=supported, D-ORIENT=upright, D-LOG=unknown (nothing was due to be logged: only a failed `mpv_render_context_create` logs natively) in spike-flutter-linux.txt.

## Deviations from Plan

1. **[Rule 3 - order] Task 2 committed before Task 1's gate.** Task 1's gate expects a default `PROBE api=vulkan`, which only exists after the probe fix, and Task 2's precondition expects Task 1's gate; both were pushed together and gated on one SHA. Commits stay per-task (f778d5a fix, 45275ac CI step).
2. **[Rule 1 - gate scope] mocked `opengl (gpu-next) on test`.** The plan's whole-log negative grep matched a mocked reason in `controller_channel_test.dart` (flutter-video-coverage job, run 40651979314), not plugin output. Made the mock realistic (`opengl (gpu)`), commit fbcd55a, re-gated: 0 matches.
3. **Transient infra:** the first gate invocation died on a GitHub API `EOF` while waiting (no test failure, nothing rerun); the gate was started again.
4. **SC2 note:** D-PROBE is `supported`, so the pixel and orientation assertions are on in all three runs (no "partial, compositor layer unverified" fallback needed). llvmpipe only.

## Known limits

llvmpipe only (software GL and Vulkan): real GPU drivers, Wayland EGL and Mesa Xe2 stay unverified (15-07 lists them). GLX-03 and GLX-04 are not ticked because 15-07 still carries both.

## Known Stubs

None.

## Self-Check: PASSED

f778d5a, 45275ac, fbcd55a are on origin/feat/mpv-master-upgrade; golden-freeze-14 manifest all OK; no CR bytes in touched files.
