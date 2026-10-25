---
phase: 10-composition-spike
plan: 07
subsystem: testing
tags: [flutter, impeller, windows, soak, trace, diagnosis, not-reproduced, halted]

requires:
  - phase: 10-composition-spike
    provides: the 10-04 fixed harness (print channel, satisfiable part-1 gate, offset/length pixel probe) and the 10-05 abort shape (soak-start then process gone, exit 79)
provides:
  - A synchronously flushed step trace and an env-gated diag branch that replays the measured prelude and runs the shared soak body without reaching _classify
  - Two bounded diag runs plus a 25-round retry, all completing with exit 0 and `DIAG soak complete`
  - An honest `diagnosis: not-reproduced` record: the 10-05 soak abort did not recur, so no abort_step exists and no speculative fix was applied
affects: [phase-10-plan-08, phase-10-plan-09, phase-11]

actuals:
  tokens: 51334
  tasks: 1
  commits: 1
  plan_head_before: 65f409974f9422a7cd7a2d8706a1099a8e9ed134
  plan_head_after: e198d528b842bfa0e3eee0e24ec464fd64925995

tech-stack:
  added: []
  patterns:
    - "Evidence for an abrupt process stop must be written with writeAsStringSync(flush: true) before the next await; a print line is only a secondary channel"
    - "A diag branch that returns before the measured parts can never be read as a classification source: no _classify, no stage: complete, no classification file"
    - "A non-reproducing run is recorded as not-reproduced and fails the task; it is never promoted to a diagnosis and never licenses a speculative fix"

key-files:
  created:
    - .planning/phases/10-composition-spike/evidence/soak-abort.trace
    - .planning/phases/10-composition-spike/evidence/soak-abort-loop.trace
    - .planning/phases/10-composition-spike/evidence/soak-abort-diag-after4k.log
    - .planning/phases/10-composition-spike/evidence/soak-abort-diag-loop.log
    - .planning/phases/10-composition-spike/evidence/soak-abort-diag-retry25.log
    - .planning/phases/10-composition-spike/evidence/soak-abort-diagnosis.txt
  modified:
    - example/integration_test/impeller_smoke_test.dart

key-decisions:
  - "diagnosis is not-reproduced: soak-after-4k (5/5 rounds), soak (5/5) and the bounded soak-after-4k retry (25/25) all ended with `DIAG soak complete` and exit 0, so there is no abort to locate"
  - "Task 1 is FAILED and Task 2 is NOT executed: Task 2's precondition requires `diagnosis: complete` plus `reproducer: reproduced`, and no fix branch (F1..F6) may be applied without a diagnosed step"
  - "The trace channel is proven independently of the abort: both trace files end with round-end on their last requested round and contain 25/25 and 5/5 round pairs"
  - "The diag branch was verified not to overreach: `\"stage\":\"complete\"` count is 0 in all three diag logs, and _classify / the classification evidence file are never reached"
  - "The measured soak still runs through the same shared `_runSoakRounds(100, emitDiag: false)`, and the 100-round / 30-second / all-parts-ok / 0.01 conditions are unchanged"

requirements-completed: []

coverage:
  - id: D1
    description: "Env-gated synchronous trace plus a shared `_runSoakRounds` body and a diag branch that replays the part-1 lifecycle before the mode prelude"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "grep gate on example/integration_test/impeller_smoke_test.dart (MPV_KIT_SMOKE_TRACE, MPV_KIT_SMOKE_DIAG, writeAsStringSync, flush: true, _runSoakRounds x3, DIAG soak complete) -> PASS"
        status: pass
      - kind: other
        ref: "cd example && D:/flutter/bin/dart analyze --fatal-infos -> No issues found!"
        status: pass
    human_judgment: false
  - id: D2
    description: "Soak abort reproduced and located to one step and one in-flight await (`abort_step` / `abort_await` / `abort_precondition`)"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: "evidence/soak-abort-diagnosis.txt: diagnosis=not-reproduced, reproducer=not-reproduced, abort_step=none (3/3 runs completed, exit 0)"
        status: fail
    human_judgment: false
  - id: D3
    description: "Single-point fix chosen from the diagnosed step, proven by a 10-round diag rerun"
    requirement: COMP-01
    verification: []
    human_judgment: true
    rationale: "Task 2 was not executed because its precondition (Task 1 diagnosis: complete AND reproducer: reproduced) is false. Applying any fix without a diagnosed step is explicitly prohibited by the plan."

duration: ~10 min
completed: 2026-10-25
status: halted
---

# Phase 10 Plan 07: Soak-Abort Diagnosis Summary

**A synchronous-flush trace and a diag-only reproducer were added and run three times, but the 10-05 soak abort did not recur (5, 5 and 25 rounds all completed with exit 0), so the honest outcome is `diagnosis: not-reproduced`, Task 1 fails, and no fix is applied.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-10-25T05:06Z
- **Completed:** 2026-10-25T05:15Z
- **Tasks:** 1 of 2 attempted (Task 1 FAILED by the plan's own gate; Task 2 NOT executed)
- **Files changed:** 7 (6 evidence artifacts + the harness)

## Outcome

**This is a halted plan, not a closure.** The plan's Task 1 is a tracer whose
`<verify>` requires `diagnosis: complete` and `reproducer: reproduced`. Neither
holds:

| Run | Mode | Rounds | Result | Exit |
|-----|------|--------|--------|------|
| 1 | `soak-after-4k` | 5 | `DIAG soak complete` | 0 |
| 2 | `soak` | 5 | `DIAG soak complete` | 0 |
| 3 (bounded retry) | `soak-after-4k` | 25 | `DIAG soak complete` | 0 |

Plan step 7 is explicit: if both modes complete their 5 rounds, retry once with
25 rounds; if that also completes, write `diagnosis: not-reproduced` and let the
task fail. That is exactly what happened, so:

- `evidence/soak-abort-diagnosis.txt` records `diagnosis: not-reproduced`,
  `reproducer: not-reproduced`, `abort_step: none`, `abort_await: none`,
  `abort_precondition: none`, and every run/trace/exit-code field.
- **Task 2 is not entered**: its `<precondition>` is unsatisfied, and the plan
  forbids a speculative fix. No F1–F6 branch was applied.
- No file under `packages/` was touched; `dart analyze --fatal-infos` is clean.

The trace channel itself is proven: `soak-abort.trace` has 25 `round-start` /
25 `round-end` markers (last line `round=25 step=round-end`), and
`soak-abort-loop.trace` has 5 / 5 (last line `round=5 step=round-end`). Both
write through `writeAsStringSync(..., flush: true)`.

## Flagged Assumption (preserved verbatim from the plan objective)

**Flagged assumption（COMP-01 edge probe）：** 本阶段没有 `-SPEC.md`，确定性 edge probe 对 COMP-01 返回 `unclassified / unresolved`（`applicable: 1, resolved: 0`）。本计划不据此发明边界覆盖结论：未回答的边界保持 unresolved，**不得**用「backstop」自动标记为已覆盖。该假设在 SUMMARY 中原样保留。

The practical consequence this round: the soak boundary is now *executed*
(25 consecutive rounds without an abort in the replayed prelude shape), but the
10-05 abort remains **unexplained**, so the boundary is not closed by this plan.

## Accomplishments

- Added `_Trace`, a marker writer that appends `t/round/step/rss/resizeEvents/
  idleSoak/renderErrors/deviceLost/controllers` tokens with synchronous flush,
  plus a `DIAG soak` print as a secondary channel.
- Added `MPV_KIT_SMOKE_DIAG`, `MPV_KIT_SMOKE_ROUNDS` and
  `MPV_KIT_SMOKE_TRACE`, and a diag branch placed after the identity gate and
  before any measured part. Both modes replay the part-1 lifecycle
  (`part1_replay: yes`); `soak-after-4k` then applies the 4K prelude.
- Extracted the soak loop into one shared `_runSoakRounds(count, {emitDiag})`
  used by the measured part 3 (`100`, `emitDiag: false`) and both diag modes.
  Classification inputs (`rounds`, `_soakSeconds()`, `_parts`) are unchanged.
- Verified the diag branch cannot be mistaken for a measurement: 0
  `"stage":"complete"` occurrences in all three diag logs, no `_classify` call,
  no write to `evidence/impeller-bench.txt`.
- Ran the bounded retry the plan mandates and recorded the negative result
  instead of promoting it to a diagnosis.

## Task Commits

1. **Task 1: sync trace + bounded soak reproducer (FAILED: not reproduced)** — `e198d52` (test)
2. **Task 2: single-point fix + 10-round proof** — NOT EXECUTED (precondition false)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `example/integration_test/impeller_smoke_test.dart` — `_lavfiSource` const,
  `_Trace`, `_controllersCreated` / `_soakRoundsDone` counters, `_traceSnapshot`,
  `_runSoakRounds`, `_remountCycle`, `_runDiag`; the measured part 3 loop now
  calls the shared body.
- `.planning/phases/10-composition-spike/evidence/soak-abort.trace` — after-4k
  trace; overwritten by the 25-round retry (25 round pairs).
- `.planning/phases/10-composition-spike/evidence/soak-abort-loop.trace` —
  loop-only trace (5 round pairs).
- `.planning/phases/10-composition-spike/evidence/soak-abort-diag-after4k.log` —
  5-round after-4k console (`DIAG soak complete`, exit 0).
- `.planning/phases/10-composition-spike/evidence/soak-abort-diag-loop.log` —
  5-round loop console (`DIAG soak complete`, exit 0).
- `.planning/phases/10-composition-spike/evidence/soak-abort-diag-retry25.log` —
  the plan-mandated bounded retry console (25 rounds, `DIAG soak complete`,
  exit 0).
- `.planning/phases/10-composition-spike/evidence/soak-abort-diagnosis.txt` —
  the not-reproduced record with every required key and the run matrix.

## Decisions Made

- **`diagnosis: not-reproduced` is the result, not a failure to diagnose.** Three
  runs across both prelude shapes, including a 25-round run — five times the
  diagnosed window — completed without the process disappearing and without any
  WER dump, Application Error or resource-exhaustion event.
- **Task 2 is not executed and no fix branch is selected.** With `abort_step:
  none` there is no single point to fix; the plan's prohibition against a
  speculative fix is the governing rule.
- **`sibling_diff` records the differences that exist but are not causal.** The
  harness does not explicitly cancel its per-round event subscription (both
  siblings do) and defers `expect` to the end; with no abort observed in 25
  rounds neither can be tied to an `abort_step`.
- **COMP-01 is not marked complete.** The smoke half it depends on is still
  unestablished, and the abort explanation this plan was meant to supply is
  missing.

## Deviations from Plan

None - the trace/diag implementation followed the plan's action items. The
Task 1 gate failure is the plan's explicitly specified `not-reproduced`
outcome (step 7), not an unplanned deviation, and step 5's "do not enter Task 2"
was honored.

## Issues Encountered

- **The 10-05 abort did not reproduce.** It remains unexplained. RSS stayed
  bounded (≈286 MB at the first marker, ≈503 MB at round 25 of the retry, with a
  drop after each dispose); no `renderError`, `deviceLost` or `idleSoak` event
  was counted in any run. Because the abort was recorded in 10-05 as
  switch-independent and left no forensics, there is nothing further this
  harness can attribute.
- **The plan's Task 1 acceptance criteria therefore cannot all pass.** The
  diagnosis gate (`diagnosis: complete` / `reproducer: reproduced` /
  `abort_step` enum) fails by design; the static harness gates, the trace gates,
  the diag no-complete-line gate, `dart analyze --fatal-infos` and the
  `packages/` clean gate all pass.

## Threat Surface

No new runtime surface. The plan's mitigations were applied: T-10-19 (the
location would come only from the last synchronous marker; when nothing stops,
none is invented), T-10-20 (diag never calls `_classify`, never emits
`"stage":"complete"`, never writes the classification file — verified by count
0 in all three logs, and the 100 / 30 s / 0.01 / all-parts-ok conditions are
untouched). T-10-SC: no package was installed.

## Next Phase Readiness

- **10-08 and 10-09 both declare `depends_on: [10-07]` and this plan is
  halted**, so neither should run as if the abort were explained. 10-08 (probe
  surface) does not itself need the abort fix, but it does need the harness,
  which now has an additional env-gated diag branch that must not be left active
  in a measured run.
- **10-09 must not assume the soak window is fixed.** The strongest statement
  this plan supports is: in this environment, on 2026-10-25, the replayed
  prelude plus 25 soak rounds completed three times. The 10-05 abort (both
  switches, exit 79, no WER) is still unexplained.
- The harness now has one verified diagnostic advantage for any future rerun: if
  a run does stop, the last `step=` marker in `MPV_KIT_SMOKE_TRACE` names the
  step and the in-flight await without reading a stack.

## Self-Check: PASSED

- `example/integration_test/impeller_smoke_test.dart` and all six evidence
  artifacts exist on disk.
- Commit `e198d52` is an ancestor of HEAD; `git status --porcelain --
  packages/` is empty.
- Task 1's diagnosis gate was re-run and fails with `diagnosis:
  not-reproduced`, which is the plan's specified outcome; Task 2 was not
  started.
