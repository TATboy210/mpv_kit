---
phase: 04-measured-performance-uhd-endurance
plan: 02
subsystem: hot-path
tags: [performance, single-decode, allocations]
requires:
  - phase: 04-01
    provides: "The committed BEFORE baseline (decode ns/op + reproduction commands)"
provides:
  - "Single mpv_node decode per property event (counter-proven, PERF-01)"
  - "Allocation-free time-pos throttle path (monotonic Stopwatch + integer microseconds; Duration only on emit, PERF-04)"
  - "After-record vs baseline: decode-double −38%, decode-map −49%"
affects: [04-03, phase-5-build-provenance]
actuals:
  tokens: 34000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Counter-seam single-decode proof: @visibleForTesting static incremented in _prop, snapshot/delta in the test (freeze-exempt)"
    - "Integer-microseconds throttle with a captured monotonic Stopwatch"
key-files:
  created:
    - docs/perf/2026-10-24-single-decode.md
  modified:
    - packages/mpv_kit/lib/src/core/events.dart
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/test/models_test.dart
key-decisions:
  - "decode restructured from a switch expression to a statement — the two property arms need a single _prop call with destructuring, impossible inside expression arms"
  - "Unavailable time-pos (idle) still resolves to position zero through the same throttle (old behavior); NaN/Inf normalize to zero instead of throwing the old round() — consistent with Phase 3's parse containment"
  - "The time-pos subscription stays on MPV_FORMAT_NODE — a DOUBLE-format fast path would fork observeProperty's shared code (potential follow-up, out of scope)"
patterns-established: []
requirements-completed: [PERF-01, PERF-04]
coverage:
  - id: D4
    description: "One propertyChange decode increments propDecodesForTesting by exactly 1"
    requirement: PERF-01
    verification:
      - kind: unit
        ref: "packages/mpv_kit/test/models_test.dart#a property event decodes its node exactly once (PERF-01)"
        status: pass
    human_judgment: false
  - id: D5
    description: "decode-double 169-175 → 102-113 ns/op (−38%), decode-map 1768-1960 → 927-950 ns/op (−49%) vs the committed baseline"
    requirement: PERF-04
    verification:
      - kind: automated
        ref: "docs/perf/2026-10-24-single-decode.md (two consecutive after-runs recorded)"
        status: pass
    human_judgment: false
  - id: D6
    description: "The time-pos throttle path allocates nothing on dropped events (3 Durations + DateTime eliminated); Duration only on emit"
    requirement: PERF-04
    verification:
      - kind: automated
        ref: "Source gate: integer comparisons + Stopwatch field in player.dart; behavior pinned by the existing position/seek tests (all green)"
        status: pass
    human_judgment: true
  - id: D7
    description: "Public API diff empty; behavior unchanged (unavailable property → zero through the throttle, preserved)"
    requirement: PERF-04
    verification:
      - kind: automated
        ref: "api_freeze_test passes; full suite 112 passed / 2 skipped"
        status: pass
    human_judgment: false
duration: 16 min
completed: 2026-10-24
status: complete
plan_head_before: eebf406
plan_head_after: 2785bd5
commits: 1
---

# Phase 04 Plan 02: Single Decode + Hot-Path Slimming Summary

**PERF-01 and the listener half of PERF-04 are delivered with counter proof and measured before/after data.**

## Performance

- Duration: 16 min; Tasks: 2/2; Commits: 1
- Token estimate 44000 vs realized ~34000

## Accomplishments

- `events.dart`: decode converted to a switch statement; both property arms call `_prop` once (`final (name, value) = …`); `@visibleForTesting propDecodesForTesting` counts calls.
- `player.dart`: the `time-pos` throttle compares integer microseconds against a captured `Stopwatch`; `Duration` is built only on emit; unavailable/NaN values normalize to zero exactly like the old code path.
- `docs/perf/2026-10-24-single-decode.md`: after-numbers vs baseline (double −38%, map −49%) plus the source-level listener allocation statement.

## Task Commits

1. `2785bd5` — perf(player): single mpv_node decode per property event; allocation-free time-pos throttle (PERF-01/PERF-04)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Single decode | compile failure (counter missing) → with counter, delta would be 2 pre-fix | 30/30 models tests, delta == 1 |
| Throttle integerization | N/A (behavior pinned by existing tests) | 112 passed / 2 skipped incl. all position tests |

## Files Created/Modified

- Modified: `events.dart`, `player.dart`, `models_test.dart`. Created: `docs/perf/2026-10-24-single-decode.md`.

## Decisions Made

- See key-decisions (statement switch; zero-on-unavailable preserved; node format unchanged).

## Deviations from Plan

- None. (The plan's own verify lines ran as written; the after-record documents the listener change as source-level, as planned.)

## Issues Encountered

- None.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-04-03/04 mitigated; T-04-SC not triggered.

## Verification Results

- mpv_kit suite 112 passed / 2 skipped; analyzer clean; api_freeze passes; after-bench recorded.

## Next Phase Readiness

- 04-03's UHD runs execute on the optimized hot path.

## Self-Check: PASSED

- Artifacts exist; commit `2785bd5` is an ancestor of HEAD; baseline commit `eebf406` precedes it; commit count measured.
