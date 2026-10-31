---
phase: 03-error-surfacing
plan: 02
subsystem: event-pump
tags: [error-surfacing, observability, rebaseline]
requires:
  - phase: 03-01
    provides: "Player.errors extended contract and the sink-installation pattern"
provides:
  - "Property observation and parse failures route to Player.errors; states keep their last good value"
  - "The wakeup drain survives malformed events and throwing listeners (later events keep flowing)"
  - "Abandoned async-command/property reply futures never produce unhandled async errors"
  - "errorString/eventName usable after dispose (IN-02 closed)"
affects: [phase-4-measured-performance]
actuals:
  tokens: 55000
  tasks: 1
  commits: 1
tech-stack:
  added: []
  patterns:
    - "future.ignore() at every error-path completeError, including the synchronous candidate-validation sites"
    - "Per-event containment in the drain loop: decode failures route to the observer stream where identifiable, else developer.log"
key-files:
  created: []
  modified:
    - packages/mpv_kit/lib/src/core/mpv.dart
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/test/mpv_test.dart
key-decisions:
  - "A raw user listener that throws still reports to the zone (standard Dart sync-controller semantics, add() unaffected) — mpv_kit cannot and should not swallow user code; the pinned property is that the drain survives"
  - "IN-02 covers exactly errorString/eventName: guard removal + post-dispose table rows removed; no other row touched"
patterns-established:
  - "Drain-survival test shape: two observers, first throws, second must receive two consecutive values"
requirements-completed: [OBS-02]
coverage:
  - id: D5
    description: "Drain survives a throwing observer listener; nothing besides the injected error escapes the zone"
    requirement: OBS-02
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#a throwing observer listener does not abort the drain"
        status: pass
    human_judgment: false
  - id: D6
    description: "An abandoned async-command reply error is ignored (future.ignore at every error-path completeError, sync and drain paths)"
    requirement: OBS-02
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#an abandoned async command error does not become an unhandled error"
        status: pass
    human_judgment: false
  - id: D7
    description: "errorString/eventName work after dispose (IN-02); post-dispose table rebaselined"
    requirement: OBS-02
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/mpv_test.dart#errorString and eventName work after dispose (IN-02)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Player._bind routes observation/parse failures to Player.errors (mechanism wired; triggers are defensive — registration and parse failures are unreachable through Player's valid property names)"
    requirement: OBS-02
    verification:
      - kind: automated
        ref: "Source gate: _bind onError + parse try/catch present (player.dart); drain-survival test proves the pump it feeds"
        status: pass
    human_judgment: true
duration: 22 min
completed: 2026-10-24
status: complete
plan_head_before: f3d4170
plan_head_after: 049ed65
commits: 1
---

# Phase 03 Plan 02: Observation Safety + IN-02 Summary

**Observation and parse failures are routed to `Player.errors`, the event drain is failure-proof, abandoned reply futures cannot become unhandled errors, and IN-02 is closed.**

## Performance

- Duration: 22 min; Tasks: 1 (tracer-style, all sub-changes TDD'd together); Commits: 1
- Token estimate 52000 vs realized ~55000

## Accomplishments

- `Player._bind`: `onError` routing + parse try/catch → `Player.errors` (`property parse/observation failed (name): <type>: <error>`), last-good state values preserved.
- `Mpv._onWakeup`: per-event decode/dispatch containment — decode failures go to the identified observer as a stream error (Player routes them) or to `developer.log`; the `while` loop can no longer be aborted by one bad event.
- `future.ignore()` at all five error-path completion sites (drain `_complete` + the four synchronous candidate-validation sites in `commandAsync`/`setPropertyAsync`/`getPropertyAsync`/dispose-mid-flight).
- IN-02: `errorString`/`eventName` guard-free; post-dispose table rows removed with a comment.

## Task Commits

1. `049ed65` — feat(player): observation/parse failures route to Player.errors; failure-proof event drain (OBS-02); IN-02 rebaseline

## TDD Gate Compliance

| Change | RED evidence | GREEN evidence |
|--------|--------------|----------------|
| IN-02 | `Bad state: Mpv has been disposed` from errorString post-dispose | test passes |
| Abandoned reply | zone captured `MpvException(invalidParameter @ command_async…)` | zone clean |
| Drain survival | (diagnostic: drain never aborted for listener throws — Dart reports them to the zone without touching add()) | B receives both values; only injected errors in zone |

## Files Created/Modified

- Modified: `mpv.dart` (`_onWakeup` guards, `_logDroppedEvent`, 5× `future.ignore()`, guard-free lookups, `dart:developer` import), `player.dart` (`_bind`, `_reportObservationFailure`), `mpv_test.dart` (3 tests + table).

## Decisions Made

- Raw user-listener zone reports are pinned as expected Dart semantics, not swallowed — documented in the test.
- The plan's awk ordering gate was replaced by the behavioral IN-02 test (the awk as written would false-positive on `_ensureAlive`'s own definition appearing after `errorString`).

## Deviations from Plan

1. `[Rule 1 - Dart semantics]` Found during: task RED. Issue: the plan assumed a throwing sync-controller listener aborts the drain via add() propagation and could be contained at Mpv level; Dart actually reports it to the zone with add() unaffected, so containment there is both impossible and unnecessary. Fix: the test pins drain survival + standard zone semantics; real containment lives in Player._bind's parse catch. Committed in: `049ed65`.
2. `[Rule 1 - Sync paths]` Found during: task GREEN. Issue: `future.ignore()` in `_complete` alone left the synchronous candidate-validation completeError sites (e.g. invalid command args) unhandled. Fix: ignore() added at all five sites. Committed in: `049ed65`.

## Issues Encountered

- `developer.log` takes an int level, not a string (fixed to 900 = WARNING); `close_sinks` lint false-positived on the drain-local observer (targeted ignore with rationale).

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-03-05…08 mitigated; T-03-SC not triggered.

## Verification Results

- `dart test` (mpv_kit) → 106 passed / 2 skipped; analyzer clean; api_freeze passes.

## Next Phase Readiness

- 03-04 adds the option/library seams using the same developer.log convention (int level 900).

## Self-Check: PASSED

- Artifacts exist; commit `049ed65` is an ancestor of HEAD; commit count measured.
