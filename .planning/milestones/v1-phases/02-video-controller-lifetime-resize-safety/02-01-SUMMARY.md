---
phase: 02-video-controller-lifetime-resize-safety
plan: 01
subsystem: video-rendering
tags: [lifecycle, platform-channel, rollback]
requires:
  - phase: none
    provides: "Existing MpvVideoController.create with mock-channel test seam and real libmpv FFI layer"
provides:
  - "Strict create-response validation: malformed or newer plugin responses raise PlatformException(code: render_init), never TypeError, and never silently downgrade a garbage backend to software"
  - "Best-effort native release of the render context when a response carrying an int textureId fails validation"
  - "Reverse-order rollback of _live entry, player dispose hook and native context for any failure after native creation, with the original error rethrown"
affects: [02-02, phase-3-error-surfacing]
actuals:
  tokens: 31000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Validate-then-construct: read response fields into raw locals, one explicit disjunction throws before any state mutation"
    - "_release/_rollback helpers: best-effort channel dispose with a swallowed-on-purpose catch that cannot mask the original error"
key-files:
  created: []
  modified:
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - packages/mpv_kit_video/test/controller_channel_test.dart
key-decisions:
  - "backend must be exactly 'vulkan' or 'software' — a same-repo plugin/Dart pair makes any other value a protocol break, which STAB-04 requires to surface instead of silently degrading to CPU rendering"
  - "A response without a usable textureId cannot release the native context (no handle to name it); the context then lives until process exit — documented as an accepted protocol-break edge instead of inventing a new wire call"
patterns-established:
  - "Rollback on later-step create failure: remove route entry, remove dispose hook, release native, rethrow original error unchanged"
requirements-completed: [STAB-04]
coverage:
  - id: D1
    description: "Every malformed response shape (missing/non-int textureId, unknown backend, non-String reason) raises PlatformException(code: render_init); garbage backend no longer resolves to software"
    requirement: STAB-04
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#malformed create result throws PlatformException and releases the texture"
        status: pass
    human_judgment: false
  - id: D2
    description: "A malformed response with an int textureId triggers exactly one dispose channel call with that id; a response without one cannot, and player disposal adds no further dispose calls"
    requirement: STAB-04
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#malformed create result throws PlatformException and releases the texture + #malformed create result without textureId cannot release native resources"
        status: pass
    human_judgment: false
  - id: D3
    description: "A failure after native creation (player disposed mid-create, refresh-rate sync StateError) rolls back route entry, hook and native context, rethrows the original error, and a retry on a live player succeeds"
    requirement: STAB-04
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#create rolls back when the player dies mid-create, retry succeeds"
        status: pass
    human_judgment: false
duration: 14 min
completed: 2026-10-24
status: complete
plan_head_before: 4bf65d8
plan_head_after: d72deaf
commits: 1
---

# Phase 02 Plan 01: Atomic MpvVideoController.create Summary

**`create` is now atomic: malformed platform responses surface as `PlatformException` with the native context released whenever a textureId exists, and any later-step failure rolls back route entry, hook and native context before rethrowing.**

## Performance

- Duration: 14 min (RED → GREEN → full suite → commit)
- Started: 2026-10-24; Completed: 2026-10-24
- Tasks: 2/2; Commits: 1 (RED and GREEN evidence collected in-session, landed atomically in `d72deaf`)
- Token estimate 46000 vs realized ~31000

## Accomplishments

- Replaced `result['textureId']! as int` trust-the-map parsing with explicit field validation (`textureId is int`, `backend` exactly `vulkan|software`, `reason` String-or-absent) before any construction or registration.
- Added `_release(textureId)` (best-effort `dispose` channel call, catch swallowed by design so rollback never masks the original error) and `MpvVideoController._rollback()` (route entry → hook → native context).
- Post-validation steps (construction, `_live` registration, `addDisposeHook`, `_syncInitialRefreshRate`, software-fallback emission) wrapped in `try/on Object { await _rollback(); rethrow; }`.
- 3 regression tests: 4 malformed shapes × PlatformException + release counting, missing-textureId edge with no-registration proof, mid-create player-dispose race with rollback + retry.

## Task Commits

1. `d72deaf` — fix(video): atomic MpvVideoController.create — strict response validation and rollback (STAB-04)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Strict create-response validation | `Expected: throws <Instance of 'PlatformException'> / Which: threw _TypeError:<Null check operator used on a null value> … video_controller.dart 179` | `00:00 +2: All tests passed!` |
| Rollback when a later create step fails | `Expected: throws satisfies function / Which: emitted <Instance of 'MpvVideoController'>` (probe error swallowed, create succeeded) | `00:00 +1: All tests passed!` |

## Files Created/Modified

- Modified: `packages/mpv_kit_video/lib/src/video_controller.dart` — validation, `_release`, `_rollback`, atomic create.
- Modified: `packages/mpv_kit_video/test/controller_channel_test.dart` — 3 new tests (+ `dart:async` import).

## Decisions Made

- Strict backend validation over lenient downgrade (rationale above).
- Rollback rethrows the original error unchanged (Phase 1 decision: error identity preserved).
- The missing-textureId native leak is accepted and documented in-code rather than adding a rollback-by-handle wire call (API freeze; protocol-break only).

## Deviations from Plan

1. `[Rule 1 - Test binding]` Found during: task 2 RED run. Issue: the plan injected a raw `StateError` through the mocked `getDisplayRefreshRate` handler, but flutter_test's mock messenger converts non-`PlatformException` handler errors into `PlatformException(code: 'error')`, which `_syncInitialRefreshRate`'s `on PlatformException` swallows by design — create succeeded instead of failing. Fix: replaced the injection with the realistic race (mock `create` response gated on a Completer; `player.dispose()` while create is in flight; `syncDisplayRefreshRate` then hits a disposed mpv and throws a genuine `StateError`). Files modified: `controller_channel_test.dart`. Verification: `create rolls back when the player dies mid-create, retry succeeds` passes. Committed in: `d72deaf`.
2. `[Rule 1 - flutter test CLI]` Found during: task 1 verify. Issue: `flutter test` has no `-n` flag (dart's `--plain-name`/`--name` differ). Fix: verify commands use `--plain-name`. Committed in: plan text corrected at execution, no code change.

## Issues Encountered

- None beyond the deviations above.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-02-01/02/03 mitigated as planned; T-02-SC not triggered (no installs).

## Verification Results

- `flutter test test/controller_channel_test.dart --plain-name "malformed create result"` → 2 passed.
- `flutter test test/controller_channel_test.dart --plain-name "create rolls back"` → 1 passed.
- `flutter test` (full package) → 16 passed, 0 failed (before 02-02 added more).
- `flutter analyze --fatal-infos` → No issues found.

## Next Phase Readiness

- 02-02 builds directly on this file: dispose try/finally and the interleave soak reuse `_release`'s swallow-on-rollback convention and the mock-gate test pattern introduced here.

## Self-Check: PASSED

- Both artifacts exist and compile; commit `d72deaf` is an ancestor of HEAD; commit count measured (1).
