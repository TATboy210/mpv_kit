---
phase: 02-video-controller-lifetime-resize-safety
plan: 02
subsystem: video-rendering
tags: [lifecycle, concurrency, soak, dispose-safety]
requires:
  - phase: 02-01
    provides: "Atomic create with rollback; mock-gate test pattern; real libmpv FFI test precondition"
provides:
  - "Exception-safe MpvVideoController.dispose: events stream always closes (listeners observe done) even when the native dispose call throws; the channel error still propagates"
  - "Post-dispose in-flight setSize/setIccProfile failures dropped; live-controller failures rethrown"
  - "100-round resize/dispose interleave soak (incl. re-entrant dispose from listeners) and 100-cycle create/dispose leak soak, both in the default CI-runnable suite"
  - "Single-flight Player.dispose (IN-05): racing callers share one teardown future and the same outcome, including the same error object; late idempotent calls succeed"
affects: [phase-3-error-surfacing, phase-6-cross-platform-verification]
actuals:
  tokens: 48000
  tasks: 3
  commits: 3
tech-stack:
  added: []
  patterns:
    - "dispose try/finally with a _closeIfOpen-style close helper (one microtask retry) so stream closure never depends on channel success"
    - "dispose-won-the-race swallow: on Object catch rechecks _disposed and only then rethrows"
    - "Shared-teardown-future dispatcher: in-flight callers share the future, post-completion callers get success, re-entrants must not await"
key-files:
  created: []
  modified:
    - packages/mpv_kit_video/lib/src/video_controller.dart
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit_video/test/controller_channel_test.dart
    - packages/mpv_kit/test/player_test.dart
key-decisions:
  - "Re-entrant dispose cannot be distinguished from a concurrent caller at dispatch time, so teardown-in-flight callers all share the future; the Phase 1 pinned unawaited re-entrant pattern is unaffected, and awaiting dispose() from inside a dispose hook is documented as a deadlock to avoid — the alternative (immediate future for everyone during teardown) would leave IN-05's observable issue unfixed"
  - "Post-dispose resize/ICC failures are dropped only when _disposed is already true; the paired live-controller propagation guard test pins the asymmetry so a future refactor cannot over-swallow"
  - "The controller soak runs in the default suite (no dart_test.yaml tag): the mock channel makes 100 rounds fast, and the 02-03 coverage job runs it in CI"
patterns-established:
  - "Interleave-soak pattern: per-round gate Completer holds every setSize in flight through dispose; every 10th round disposes re-entrantly from the events listener"
  - "Hook-leak proof: after N explicit create/dispose cycles, player disposal must add zero controller teardown calls"
requirements-completed: [STAB-05, STAB-01]
coverage:
  - id: D4
    description: "dispose() closes the events stream even when the native call throws; the error surfaces; a second dispose is harmless"
    requirement: STAB-05
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#dispose closes events even when the native call throws"
        status: pass
    human_judgment: false
  - id: D5
    description: "A resize in flight during dispose produces no uncaught zone error; the identical failure on a live controller still throws"
    requirement: STAB-05
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#resize during dispose does not surface an uncaught error + #resize failure on a live controller still throws"
        status: pass
    human_judgment: false
  - id: D6
    description: "100 resize/dispose interleave rounds complete without uncaught errors or stuck size state; recreated controllers route events; 100 create/dispose cycles leave zero residual hooks"
    requirement: STAB-05
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#resize and dispose interleave 100 rounds without sticking + #create/dispose cycles do not accumulate hooks"
        status: pass
    human_judgment: false
  - id: D7
    description: "Racing Player.dispose callers run the teardown once and share the outcome, including the same error object; re-entrant hook calls do not deadlock; api_freeze_test passes"
    requirement: STAB-05
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/player_test.dart#concurrent dispose runs teardown once and shares the outcome + #concurrent dispose surfaces the same error to both callers + #reentrant dispose from a hook does not deadlock"
        status: pass
    human_judgment: false
  - id: D8
    description: "Dart-side bookkeeping for repeated controller create/dispose leaks nothing (STAB-01 deferred clause); native-side leak evidence is local UAT + Phase 6 real-plugin tests"
    requirement: STAB-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit_video/test/controller_channel_test.dart#create/dispose cycles do not accumulate hooks"
        status: pass
    human_judgment: false
duration: 24 min
completed: 2026-10-24
status: complete
plan_head_before: d72deaf
plan_head_after: c677389
commits: 3
---

# Phase 02 Plan 02: Dispose/Resize Concurrency Safety + IN-05 Summary

**Controller dispose can no longer leak an open event stream, resize/dispose interleaving is proven race-safe at 100 rounds, repeated create/dispose leaks no bookkeeping, and concurrent `Player.dispose()` calls share one teardown and its outcome.**

## Performance

- Duration: 24 min across 3 tasks (RED → GREEN per task, atomic commits)
- Started: 2026-10-24; Completed: 2026-10-24
- Tasks: 3/3; Commits: 3
- Token estimate 54000 vs realized ~48000

## Accomplishments

- `MpvVideoController.dispose` wraps the native call in try/finally; `_closeEvents()` replicates Mpv's `_closeIfOpen` (isClosed guard + one microtask retry).
- `setSize`/`setIccProfile` drop only dispose-won-the-race failures (`if (_disposed) return;` inside the catch), with the asymmetry documented in-code and pinned by a paired propagation test.
- Two soak tests: 100-round interleave (gated in-flight setSize per round, re-entrant listener dispose every 10th round, fresh-controller routing and sizing checks per round) and 100-cycle create/dispose leak soak (zero residual hooks, streams closed per round, create still works).
- `Player.dispose` restructured into a single-flight dispatcher (`_disposeFuture` / `_disposeDone`): racing callers share the future and the same error; late calls succeed; the re-entrant contract is documented (never await the shared future from inside a hook).

## Task Commits

1. `03e3f5f` — fix(video): exception-safe controller dispose; drop post-dispose in-flight resize/ICC errors (STAB-05)
2. `d03d329` — test(video): 100-round resize/dispose interleave and create/dispose cycle soak (STAB-05, STAB-01 clause)
3. `c677389` — fix(player): concurrent Player.dispose shares one teardown future (IN-05, STAB-05)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Exception-safe dispose + resize race | `dispose closes events … [E]` (done never delivered); `resize during dispose … [E] PlatformException(no_texture, gone)` (uncaught zone error) | `+19: All tests passed!` |
| Interleave + cycle soak | `TimeoutException after 0:00:30` (gated final setSize never released) and `Bad state: Mpv has been disposed` (final create after player disposal) — both test-logic defects, fixed in-session | `+1: All tests passed!` × 2 |
| IN-05 shared dispose future | `Failing tests: concurrent dispose runs teardown once…; concurrent dispose surfaces the same error…` (second caller returned early) | `+21: All tests passed!`, api_freeze passed |

## Files Created/Modified

- Modified: `packages/mpv_kit_video/lib/src/video_controller.dart` — try/finally dispose, `_closeEvents`, resize/ICC race handling.
- Modified: `packages/mpv_kit/lib/src/player/player.dart` — single-flight dispose dispatcher.
- Modified: `packages/mpv_kit_video/test/controller_channel_test.dart` — 3 dispose/resize tests + 2 soak tests.
- Modified: `packages/mpv_kit/test/player_test.dart` — 3 concurrent/re-entrant dispose tests.

## Decisions Made

- Share the teardown future with all in-flight callers rather than special-casing re-entrants: the two caller classes are indistinguishable at dispatch time, the Phase 1 pinned re-entrant pattern (`unawaited`) is unaffected by sharing, and the only deadlock pattern (awaiting dispose inside a hook) is documented as forbidden — preserving Phase 1's post-completion "second dispose harmless" contract via `_disposeDone`.
- Soak tests run untagged in the default suite so the 02-03 CI coverage job exercises them; native-side leak evidence remains local UAT + Phase 6 (recorded in the plan's scope note).

## Deviations from Plan

1. `[Rule 1 - Semantics]` Found during: task 3 GREEN run. Issue: the plan's `_disposing`-guard dispatcher returned an immediate future to every call made while teardown ran, which silently un-shares concurrent callers (the IN-05 tests failed) and replaying the raw cached future broke Phase 1's "second dispose completes normally" test. Fix: share the in-flight future with every caller and gate post-completion calls on `_disposeDone`; the re-entrancy rule becomes "never await the shared future from inside a hook" (documented). Verification: all 21 player tests + api_freeze pass. Committed in: `c677389`.
2. `[Rule 1 - Test logic]` Found during: task 2 RED run. Issue: the first soak draft created a controller after `player.dispose()` (FFI error) and released the interleave gates only before the final gated `setSize` (30 s timeout). Fix: reorder the final-create check before player disposal and restore an ungated mock for the final sizing assertions. Committed in: `d03d329`.

## Issues Encountered

- None beyond the deviations above.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-02-04…08 mitigated as planned; T-02-SC not triggered.

## Verification Results

- `flutter test` (mpv_kit_video) → 21 passed, 0 failed.
- `dart test` (mpv_kit, real libmpv) → 101 passed, 2 skipped, 0 failed.
- `dart test test/api_freeze_test.dart` → passed (public API unchanged).
- `flutter analyze --fatal-infos` / `dart analyze --fatal-infos` → clean.

## Next Phase Readiness

- 02-03's coverage job runs this suite with libmpv present; the swallow conventions here are the boundary Phase 3 (OBS-01/02) will convert into explicit error surfacing.

## Self-Check: PASSED

- All four artifacts exist and compile; commits `03e3f5f`/`d03d329`/`c677389` are ancestors of HEAD; commit count measured (3).
