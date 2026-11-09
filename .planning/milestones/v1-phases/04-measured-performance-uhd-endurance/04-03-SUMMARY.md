---
phase: 04-measured-performance-uhd-endurance
plan: 03
subsystem: uhd-endurance
tags: [performance, endurance, 4k, 8k]
requires:
  - phase: 04-01
    provides: "The integration-test vehicle and bench libmpv selection"
  - phase: 04-02
    provides: "The optimized hot path the runs execute on"
provides:
  - "Parameterized UHD endurance test with fixed gates (example/integration_test/uhd_endurance_test.dart)"
  - "4K 30-minute endurance evidence: all gates green (drops 0/0, total-avsync-change −0.033 s bounded, avsync 4.7e-05, delayed 0, fps 30)"
  - "8K finding: reproducible process death from commit-memory exhaustion (RADAR_PRE_LEAK_64), recorded as failed data — PERF-03's 8K clause stays open"
affects: [phase-5-build-provenance, 8k-stability-insertion]
actuals:
  tokens: 46000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Endurance gates are fixed in code; a failure is recorded data, never a relaxed threshold"
key-files:
  created:
    - example/integration_test/uhd_endurance_test.dart
    - docs/perf/2026-10-24-uhd-endurance.md
  modified: []
key-decisions:
  - "The 8K crash is a stability finding, not an environment flake: reproducible three times (≤ 40 s), WER event 1001 RADAR_PRE_LEAK_64 names commit-memory exhaustion — a stability insertion owns the fix; the endurance gates were not touched"
patterns-established: []
requirements-completed: []
requirements-partial: [PERF-03]
coverage:
  - id: D8
    description: "Endurance harness runs end-to-end (10 s smoke, all gates) and the 4K 30-minute run passes every gate"
    requirement: PERF-03
    verification:
      - kind: automated
        ref: "Smoke: 640x360 x 10 s pass; 4K: 1800 s, drops 0/0, total-avsync-change −0.0333 s, avsyncPeak 4.7e-05, delayed 0, fps 30 (docs/perf/2026-10-24-uhd-endurance.md)"
        status: pass
    human_judgment: false
  - id: D9
    description: "8K endurance fails: reproducible process death from commit-memory exhaustion ≤ 40 s into playback (3 attempts, WER RADAR_PRE_LEAK_64 evidence)"
    requirement: PERF-03
    verification:
      - kind: automated
        ref: "docs/perf/2026-10-24-uhd-endurance.md 8K section (attempts 1-3 + WER event)"
        status: fail
    human_judgment: false
duration: 95 min
completed: 2026-10-24
status: complete
plan_head_before: 2785bd5
plan_head_after: 6c621ea
commits: 1
---

# Phase 04 Plan 03: 4K/8K UHD Endurance Summary

**4K 30-minute endurance passes every gate; 8K reproducibly dies of commit-memory exhaustion ≤ 40 s into playback — recorded as failed data with WER evidence, gates untouched.**

## Performance

- Duration: 95 min (two 30-min runs + probes and investigation)
- Tasks: 2/2; Commits: 1 (results doc; the harness itself landed with the plan)

## Accomplishments

- `example/integration_test/uhd_endurance_test.dart`: env-parameterized (size/seconds/label), resolution-arrival wait, 10 s metric sampling, fixed gates (drops == 0, |total-avsync-change| < 1.0 s, avg vo-delayed < 1, no deviceLost, no renderError storm).
- **4K 1800 s: PASS** — 0/0 drops, total-avsync-change −0.0333 s (bounded, constant after minute one), avsync peak 4.7e-05 s, vo-delayed 0, 30 fps, RSS 826 MB.
- **8K: FAIL** — process death ≤ 40 s into playback, reproducible 3×; WER `RADAR_PRE_LEAK_64` names commit-memory exhaustion (P1 mpv_kit_example.exe). Per-frame arithmetic: 8K YUV420P ≈ 124 MiB/frame in system queues + the 633 MiB shared-memory ring. Follow-up candidates recorded (queue scaling, commit sampling, graceful pressure event).

## Task Commits

1. Results doc commit (this plan's only artifact besides the harness).

## TDD Gate Compliance

- Gates verified by the 10 s smoke before the long runs; the 4K run passed them; the 8K runs failed them by dying — recorded as data.

## Files Created/Modified

- Created: `example/integration_test/uhd_endurance_test.dart`, `docs/perf/2026-10-24-uhd-endurance.md`.

## Decisions Made

- The 8K failure is a product stability finding → new CONCERNS entry + deferred item; gates never relaxed.

## Deviations from Plan

1. `[Rule 1 - reproducibility]` Found during: task 2. Issue: the first 8K run died; the plan's environment-interruption clause didn't cover product crashes. Fix: two more attempts (full + 120 s probe) to establish reproducibility, then recorded as a stability finding. Committed in: the results-doc commit.

## Issues Encountered

- The first 8K launch raced the 4K app's teardown; the probe approach removed any doubt.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-04-05 (relaxed gates): held — gates untouched. T-04-06/07: visibility + fps recorded. T-04-SC not triggered.

## Verification Results

- Smoke: pass. 4K: pass. 8K: fail (crash) — recorded.

## Next Phase Readiness

- Phase 5 (BUILD) unaffected; the 8K stability insertion is the recommended next work before/alongside it.

## Self-Check: PASSED

- Artifacts exist; results committed; gate verdicts match the recorded data.
