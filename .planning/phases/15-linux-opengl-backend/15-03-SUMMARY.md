---
phase: 15-linux-opengl-backend
plan: 03
subsystem: infra
tags: [linux, opengl, egl, spike, texture-probe, flutter-embedder]

requires:
  - phase: 15-01
    provides: GL/EGL Linux bundle, ci_gate.sh
provides:
  - "example/integration_test/texture_probe_test.dart: report-only PROBE {json} of the mounted texture (nonBlackRatio, orientation, before/after resize)"
  - "native-verify.yml Texture probe (linux) step (prints FLUTTER-VERSION)"
  - "GlInterop::ProbeGl failure diagnosis: failing EGL call, error name+code, calling-thread EGL/GDK state, fresh-thread retry (diagnostic only)"
  - "spike-flutter-linux.txt: D-FLUTTER-* from Flutter 3.47.8 source with file:line; CI-dependent decisions deferred"
affects: [15-05, 15-06]

actuals:
  tokens: 9000
  tasks: 2
  commits: 2
plan_head_before: c24df0c01d1d67487140590881d2190c65359839
plan_head_after: 06c433e

key-files:
  created:
    - example/integration_test/texture_probe_test.dart
    - .planning/phases/15-linux-opengl-backend/evidence/spike-flutter-linux.txt
    - .planning/phases/15-linux-opengl-backend/evidence/ci-runs-15-03.txt
  modified:
    - .github/workflows/native-verify.yml
    - packages/mpv_kit_video/linux/gl_interop.h
    - packages/mpv_kit_video/linux/gl_interop.cc

key-decisions:
  - "D-PROBE, D-ORIENT, D-THREAD, D-LOG and IMPLICATION are deferred placeholders: they are functions of CI log lines that do not exist yet (hosted CI deferred). 15-05/15-06 must not read them until replaced."

requirements-completed: []
requirements-partial: [GLX-03]

ci-gate: FAILED 2026-10-28 (expected PROBE api=vulkan, observed api=software; see deferred_ci_gates notes and evidence/ci-runs-15-03.txt)
deferred_ci_gates:  # ran, not passed: see notes
  - "RAN 2026-10-28, UNMET (run native-verify 40627862148, sha 091228abd70b22fbe2f425fdd1efb75eb8cfcb54): jobs-success, FLUTTER-VERSION and INTEGRATION vulkan(gpu-next) on llvmpipe held, but `--log ^integration-test \\(ubuntu PROBE \\{\"api\":\"vulkan\"` did not: the Texture probe ran on the software backend (ProbeGl failed on the platform thread, EGL_BAD_ACCESS). Original text: Task 1 (after pushing HEAD at milestone end): `CI_GATE_EVIDENCE=.planning/phases/15-linux-opengl-backend/evidence/ci-runs-15-03.txt bash .planning/phases/15-linux-opengl-backend/tools/ci_gate.sh --jobs-success '^integration-test' --jobs-success '^build \\(' --jobs-success '^flutter-video-coverage' --log '^integration-test \\(ubuntu' 'PROBE \\{\"api\":\"vulkan\"' --log '^integration-test \\(ubuntu' 'FLUTTER-VERSION Flutter ' --log '^integration-test \\(ubuntu' '\"reason\":\"vulkan \\(gpu-next\\) on llvmpipe'`; then append the raw lines to ci-runs-15-03.txt as `probe platform=linux api=<api> line=<raw>` and `flutter_version line=<raw>` (the verify greps expect those exact prefixes)."
  - "RAN 2026-10-28, UNMET with the same single expectation (PROBE api vulkan); the spike values were derived from the real lines instead (D-THREAD, IMPLICATION=helper-thread; D-PROBE, D-ORIENT, D-LOG unknown with reasons, see spike-flutter-linux.txt). Original text: Task 2 (same run): same ci_gate.sh without the FLUTTER-VERSION --log; confirms gl_interop.cc compiles on Linux and the default INTEGRATION reason is still vulkan gpu-next on llvmpipe. Then from the ubuntu integration-test log collect: deduplicated counts of the soak-loop `mpv_kit_video: <backend> (<reason>)` lines, one full `cannot create a probe EGL context: ...` diagnosis, the PROBE line, and whether any native `mpv_kit:` line appears; write D-PROBE, D-ORIENT, D-THREAD, D-LOG, IMPLICATION into spike-flutter-linux.txt (each with run id and raw fragment); IMPLICATION=blocked must be escalated, not continued."

duration: about 20 min (no hosted CI waits)
completed: 2026-10-28
status: complete
---

# Phase 15 Plan 03: Flutter Linux embedder spike Summary

**The mounted-texture probe, the full ProbeGl failure diagnosis and the Flutter 3.47.8 embedder facts are in place; every decision that needs a CI log line is a deferred placeholder.**

## Accomplishments

- **texture_probe_test.dart (Task 1):** real plugin, one `testWidgets`, texture in a `RepaintBoundary`, red-over-blue 640x360 lavfi source, presentation gate as in `_firstFrameGate`, reads before and after a resize to 320x180 and prints `PROBE {json}` with the planned key order. Asserts only params, presentation within 30 s and no deviceLost; no claim about pixels or orientation. `native-verify.yml` gains the linux-only `Texture probe (linux)` step after the existing steps (prints `FLUTTER-VERSION`; `MPV_KIT_VIDEO_API` unset).
- **ProbeGl diagnosis (Task 2):** `gl_reason_` is now a `std::string`; the `cannot create a probe EGL context` reason adds the failing call (`eglChooseConfig`/`eglCreateContext`/`eglMakeCurrent`), `EGL_*` name and hex code, the calling thread's EGL context and bound API, GDK GL context, and a `fresh thread: ok|<call> failed (<error>)` retry on a new `std::thread`, run only on failure. One line, comma-separated, no semicolons. `gl_ok_` assignment is unchanged (fresh-thread result is diagnostic only).
- **Flutter source facts:** `spike-flutter-linux.txt` records D-FLUTTER-RASTER=separate (fl_engine.cc:802-811), D-FLUTTER-CONTEXT=egl (fl_opengl_manager.cc:47-89, render/resource/platform EGL contexts, no GdkGLContext), D-FLUTTER-POPULATE (fl_engine.cc:434-466, raster thread with render_context; thread by inference), D-FLUTTER-ORIGIN=top-left (embedder_external_texture_gl.cc:113, Skia path only).

## Task Commits

1. Task 1 texture probe, workflow step, ci-runs placeholders - `ddb35a1`
2. Task 2 ProbeGl diagnosis and spike-flutter-linux.txt - `06c433e`

Nothing pushed; no workflow dispatched.

## Local verification

`flutter analyze --fatal-infos` on texture_probe_test.dart clean, `dart format` clean; `tools/check_matrix.py` ok (workflow YAML parses); `tools/check_consistency.dart` ok; golden-freeze-14 manifest all OK; the three plan grep gates for gl_interop (`fresh thread`, `gdk_gl_context_get_current`, `std::string gl_reason_`) pass; no CR bytes; no semicolons in the diagnostic text. Not possible locally: compiling gl_interop.cc (no Linux/epoxy/GDK toolchain), running the probe test.

## Deviations from Plan

None in behavior. Task 1's `tracer` feedback gate (re-run `<verify>`) cannot run without CI; it is part of the deferred gate. The Task 2 verify for spike-flutter-linux.txt (D-PROBE/D-ORIENT/D-THREAD/D-LOG/IMPLICATION regexes) does not pass until the deferred lines are replaced.

## Flagged assumptions

- The D-FLUTTER-POPULATE thread (raster thread) is inferred from the task-runner setup, not shown by a single file:line; Impeller's external-texture origin was not read.
- The unused-import fix (`dart:async`) was applied to the probe test; gl_interop.cc was reviewed by eye for the first Linux compile.

## Known Stubs

None (the deferred evidence lines are intentional deferral records).

## Threat Flags

None.

## Self-Check: PASSED

## CI backfill (2026-10-28)

The probe expectation did not hold: both default controllers of the Texture probe test fell back to software (`PROBE {"api":"software",...}`), because `ProbeGl` fails on the platform thread with `eglMakeCurrent failed (EGL_BAD_ACCESS 0x3002), calling thread EGL context: none (api OPENGL_ES), GDK GL context: current, fresh thread: ok`. In the ubuntu integration-test job 11 of 12 controllers got software (1 distinct reason text) and only the INTEGRATION controller got `vulkan (gpu-next) on llvmpipe`. This is the D-THREAD finding, so `IMPLICATION=helper-thread` (15-06 Task 2 moves the probe to a new thread). D-PROBE, D-ORIENT and D-LOG are written as `unknown` with reasons because the Vulkan control for the Texture probe never ran; re-run the probe after the 15-06 fix. No requirement changes.
Evidence: `evidence/ci-runs-15-03.txt, spike-flutter-linux.txt`. The gates were evaluated by this phase's unmodified `tools/ci_gate.sh` / `tools/release_gate.sh` against completed runs (PR runs at feat HEAD 091228a: native-verify 40627862148, flutter-plugin 40627862039; release.yml dispatch 40618740386 at b40cdff, valid for the linux bundle because b40cdff..091228a only touched the native-verify windows integration step, d3d11_backend.cpp WaitQuery flags, integration tests and notes). A gh shim served the cached logs; nothing was dispatched, rerun or pushed.
