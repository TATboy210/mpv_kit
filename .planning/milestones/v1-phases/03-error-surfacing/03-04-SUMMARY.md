---
phase: 03-error-surfacing
plan: 04
subsystem: ffi-options
tags: [error-surfacing, library-loader, options]
requires:
  - phase: 03-02
    provides: "developer.log convention (int level 900) and the visibleForTesting seam pattern"
provides:
  - "MpvLibrary.resolvedPath / lastOpenAttempts: library resolution is diagnosable from Dart (wrong-DLL incident class closed)"
  - "Ignored optionNotFound options recorded on Mpv.ignoredOptionsForTesting + developer.log; create still succeeds"
  - "gpu-shader-cache-dir tolerates propertyNotFound on reduced libmpv builds"
affects: [phase-4-measured-performance, phase-5-build-provenance]
actuals:
  tokens: 42000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Cold-isolate ordering: suite files own their process cache, so the fall-through test must run first in its file"
key-files:
  created:
    - packages/mpv_kit/test/library_test.dart
  modified:
    - packages/mpv_kit/lib/src/ffi/library.dart
    - packages/mpv_kit/lib/src/core/mpv.dart
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - packages/mpv_kit/test/mpv_test.dart
    - packages/mpv_kit/test/api_freeze_test.dart
key-decisions:
  - "resolvedPath/lastOpenAttempts are plain public statics (MpvLibrary is outside the api_freeze enumeration); ignoredOptionsForTesting is @visibleForTesting (auto-exempt seam)"
  - "On a cache hit lastOpenAttempts is not updated — no candidate ran; the fall-through test therefore owns the cold cache"
patterns-established:
  - "Tolerate-not-found only: property/option absence is compatible behavior, every other error stays loud"
requirements-completed: [OBS-04]
coverage:
  - id: D11
    description: "A failed explicit candidate is recorded when a later one succeeds; resolvedPath names the loaded library; cache identity unchanged"
    requirement: OBS-04
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/library_test.dart#a failed explicit candidate is recorded when a later one succeeds"
        status: pass
    human_judgment: false
  - id: D12
    description: "An explicit path ignored by the process cache leaves resolvedPath unchanged (developer.log warning wired)"
    requirement: OBS-04
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/library_test.dart#an explicit path ignored by the process cache does not change the resolved library"
        status: pass
    human_judgment: false
  - id: D13
    description: "Unknown options at create are recorded and logged; invalid values still throw"
    requirement: OBS-04
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#an unknown option at create is recorded, not silent (OBS-04) + #an invalid option value still fails create loudly"
        status: pass
    human_judgment: false
  - id: D14
    description: "Shader-cache setup tolerates propertyNotFound (reduced builds); other errors propagate"
    requirement: OBS-04
    verification:
      - kind: automated
        ref: "Source gate: try/catch on MpvException.propertyNotFound in _applyShaderCacheDir (video_controller.dart:306-309); unreachable without a reduced libmpv"
        status: pass
    human_judgment: true
duration: 18 min
completed: 2026-10-24
status: complete
plan_head_before: 049ed65
plan_head_after: 6c621ea
commits: 1
---

# Phase 03 Plan 04: Option and Library Visibility Summary

**Both remaining silent sites are closed: unknown options are recorded without breaking create, and library resolution fall-throughs are diagnosable from Dart.**

## Performance

- Duration: 18 min; Tasks: 2; Commits: 1
- Token estimate 46000 vs realized ~42000

## Accomplishments

- `MpvLibrary.resolvedPath`/`lastOpenAttempts` statics + `developer.log` warnings on candidate fall-through and cache-ignored explicit paths; existing resolution semantics byte-for-byte unchanged.
- `Mpv.ignoredOptionsForTesting` (`@visibleForTesting`, freeze-exempt) recorded at both `optionNotFound` swallow sites with `developer.log`; invalid values still throw.
- `_applyShaderCacheDir` tolerates `propertyNotFound` (reduced builds) via debugPrint; other errors propagate into Phase 2's rollback.
- New `library_test.dart` (3 tests) + 2 mpv option tests; freeze `_seams` updated.

## Task Commits

1. `6c621ea` — feat(player): option and library-resolution errors become observable (OBS-04)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Library statics | compile failure (missing members) | 3/3 library tests pass |
| Option recording | compile failure (missing seam) | recording + loud-invalid tests pass |

## Files Created/Modified

- Created: `library_test.dart`. Modified: `library.dart`, `mpv.dart`, `video_controller.dart`, `mpv_test.dart`, `api_freeze_test.dart`.

## Decisions Made

- See key-decisions: plain public statics outside the freeze enumeration; cache-hit attempts untouched.

## Deviations from Plan

1. `[Rule 1 - Cache ordering]` Found during: task 1 GREEN. Issue: the fall-through test initially ran after another open() had primed the process cache, so no candidate loop ran and lastOpenAttempts stayed empty. Fix: test order (fall-through owns the cold cache) + documented ordering constraint in the file header. Committed in: `6c621ea`.

## Issues Encountered

- String-interpolation typo in a log message caught by the analyzer before any test run.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-03-11…13 mitigated; T-03-SC not triggered.

## Verification Results

- `dart test` (mpv_kit) → 111 passed / 2 skipped; `flutter test` (mpv_kit_video) → 21 passed; analyzers clean; api_freeze passes.

## Next Phase Readiness

- Phase 4 (PERF) can benchmark against a now fully observable baseline; Phase 5 (BUILD) inherits the single-source resolution story.

## Self-Check: PASSED

- Artifacts exist; commit `6c621ea` is an ancestor of HEAD; commit count measured.
