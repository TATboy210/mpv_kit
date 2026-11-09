---
phase: 02-video-controller-lifetime-resize-safety
plan: 03
subsystem: ci
tags: [coverage, gates, artifacts]
requires:
  - phase: 02-01, 02-02
    provides: "Mock-channel plus libmpv-backed controller tests whose execution the gate depends on"
provides:
  - "80% line-coverage gate for mpv_kit_libs in the native-verify Linux Dart step"
  - "flutter-video-coverage job: mpv_kit_video tests run against the linux job's libmpv artifact and fail below 80% line coverage"
  - "Single libmpv build provenance: the coverage job consumes the artifact, it never rebuilds"
affects: [phase-5-build-provenance, phase-6-cross-platform-verification]
actuals:
  tokens: 18000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Artifact-fed sibling job: needs: [linux] + upload/download-artifact keeps one build and isolates gate failures from native failures"
key-files:
  created: []
  modified:
    - .github/workflows/native-verify.yml
key-decisions:
  - "The artifact carries prefix/lib AND deps/lib: libmpv.so.2 dlopens the deps.sh-built libplacebo/dav1d from deps/lib at load time, so the coverage job's LD_LIBRARY_PATH needs both"
  - "The coverage job installs the same distro -dev library list the linux job builds against instead of staging a traced dependency closure — one copy-paste block, version-resolved by apt, and a missing library fails the dlopen loudly rather than skipping tests"
  - "flutter-plugin.yml stays the fast analyze/test matrix without coverage; the gate lives next to the libmpv build it depends on"
patterns-established:
  - "LF/LH awk gate with a ::notice summary, now applied to all three Dart packages"
requirements-completed: [VERIFY-04]
coverage:
  - id: D9
    description: "mpv_kit_libs runs under coverage:test_with_coverage with the same 80% awk gate as mpv_kit"
    requirement: VERIFY-04
    verification:
      - kind: automated
        ref: "Local recipe validation: dart pub global run coverage:test_with_coverage → 82.0% (123/150), gate passed; wiring greps + YAML parse"
        status: pass
    human_judgment: false
  - id: D10
    description: "flutter-video-coverage downloads libmpv-verify-linux-ubuntu-24.04, runs the channel tests with libmpv present (not skipped), and fails below 80%"
    requirement: VERIFY-04
    verification:
      - kind: automated
        ref: "Static verification: job/artifact/coverage markers present (yml:114,121,139,153), no continue-on-error, YAML parses; live validation on next push"
        status: pass
    human_judgment: true
duration: 9 min
completed: 2026-10-24
status: complete
plan_head_before: c677389
plan_head_after: 39b7213
commits: 1
---

# Phase 02 Plan 03: Coverage Gates for mpv_kit_video and mpv_kit_libs Summary

**All three Dart packages are now under 80% line-coverage gates, and mpv_kit_video's skip-guarded channel tests run in CI against a real libmpv built exactly once.**

## Performance

- Duration: 9 min
- Started: 2026-10-24; Completed: 2026-10-24
- Tasks: 2/2; Commits: 1
- Token estimate 34000 vs realized ~18000

## Accomplishments

- mpv_kit_libs: `coverage:test_with_coverage` + LF/LH awk gate (80%) appended to the Linux Dart step; recipe validated locally (82.0%, gate passed).
- Linux job stages `prefix/lib` + `deps/lib` and uploads `libmpv-verify-linux-${{ matrix.runner }}` (both matrix runners, retention 14 days).
- New `flutter-video-coverage` job (`needs: [linux]`, ubuntu-24.04): apt runtime ABI, artifact download, subosito/flutter-action, `flutter test --coverage` with `MPV_KIT_LIBMPV_PATH` + `LD_LIBRARY_PATH`, `flutter analyze --fatal-infos`, 80% gate. No `continue-on-error`.

## Task Commits

1. `39b7213` — ci: coverage gates for mpv_kit_libs and mpv_kit_video (VERIFY-04)

## TDD Gate Compliance

- N/A (workflow change; no unit tests). Mechanical verification below.

## Files Created/Modified

- Modified: `.github/workflows/native-verify.yml` — mpv_kit_libs coverage gate, artifact stage/upload, new job.

## Decisions Made

- Artifact carries the deps.sh closure (libplacebo/dav1d are dlopened from `deps/lib`).
- apt -dev runtime libraries in the coverage job instead of a traced closure: consistent with the build job's ABI, and a missing library fails loudly.
- Single libmpv build (BUILD-01 direction); no rebuild in the coverage job.

## Deviations from Plan

- None. (The plan's fallback — rebuilding libmpv in the coverage job — was not needed.)

## Issues Encountered

- None.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-02-09/10/11 mitigated as planned; T-02-SC not triggered (only actions already used in the repo: actions/checkout, actions/upload-artifact, actions/download-artifact, plus subosito/flutter-action — pinned, first-party-ecosystem action).

## Verification Results

- YAML parses (`yaml.safe_load`).
- Markers present: `flutter-video-coverage` (yml:121), `libmpv-verify-linux-*` (yml:114/139), `flutter test --coverage` (yml:153); `continue-on-error` count in the new job: 0.
- Local recipe validation: `dart pub global run coverage:test_with_coverage` in mpv_kit_libs → 16 tests passed, awk gate printed `82.0% (123/150)` and passed.
- **CI itself cannot run locally; live validation of the new job happens on the next push.** Recorded as `human_judgment: true` on D10.

## Next Phase Readiness

- Phase 5 (BUILD) can build on the artifact/stage pattern; Phase 6 (VERIFY-01/02) owns real-plugin integration tests and the full six-target matrix, for which this job is the template.

## Self-Check: PASSED

- Artifact exists and parses; commit `39b7213` is an ancestor of HEAD; commit count measured (1).
