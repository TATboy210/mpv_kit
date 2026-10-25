---
phase: 10-composition-spike
plan: 05
subsystem: testing
tags: [flutter, impeller, windows, smoke, bench, evidence, d05, failed, evidence-gap]

requires:
  - phase: 10-composition-spike
    provides: the 10-04 fixed harness (print channel, satisfiable part-1 gate, offset/length pixel probe)
provides:
  - Two fresh reruns on the 10-04 harness (both switches) with a fresh disk-gate anchor
  - BENCH preflight and soak-start lines in the captured console (channel confirmed again)
  - Re-verified renderer identity (flutter-run fallback, on=1 / off=0) recorded separately from classification
  - An honest evidence-gap record showing that neither (A) nor (B) holds, so D-05 is NOT settled
affects: [phase-10-plan-06, phase-11]

actuals:
  tokens: 7129
  tasks: 2
  commits: 2
  plan_head_before: 2f8a3940882e4506c48e053e4234ffe7d2634146
  plan_head_after: ff60222f96d2457910ba790e212d5b0a3af1da67

tech-stack:
  added: []
  patterns:
    - "A rerun that produces preflight/soak-start but no complete line is an evidence gap, never a classification"
    - "An exit code must be interpreted before it is classified: 79 is package:test noTests, not a crash code"
    - "Switch-independent abort shape forbids attributing the stop to Impeller or to its absence"

key-files:
  created: []
  modified:
    - .planning/phases/10-composition-spike/evidence/impeller-on.log
    - .planning/phases/10-composition-spike/evidence/impeller-on.meta
    - .planning/phases/10-composition-spike/evidence/impeller-off.log
    - .planning/phases/10-composition-spike/evidence/impeller-off.meta
    - .planning/phases/10-composition-spike/evidence/impeller-bench.txt
    - .planning/phases/10-composition-spike/evidence/disk-gate.txt

key-decisions:
  - "Task 2 is FAILED, not closed: (A) fails because complete_on=0 and (B) fails because there is no WER dump and no Application Error event naming flutter_windows.dll, so the abort cannot be attributed to the renderer"
  - "The classification file records classification: inconclusive + evidence_gap: complete-line-missing ONLY as an evidence-gap record, with task_status: failed and closure: refused, so 10-06 cannot read it as a verdict source"
  - "Exit code 79 is package:test's noTests code (the log prints 'No tests were found.'), not a native crash code; it does not satisfy the 'neither 0 nor 1' half of (B) as crash evidence"
  - "The abort is switch-independent (identical shape with --enable-impeller and --no-enable-impeller), so it is recorded as an unexplained abort, never as 'Impeller failed' or 'Skia failed'"
  - "The pixel probe did run in part 2 and reported supported:true / nonBlackRatio 0.0; recorded as an unresolved black-frame signal that would be failed/black-frame only if the workload had completed"
  - "COMP-01 is NOT marked complete: the smoke half it depends on remains unestablished"

requirements-completed: []

coverage:
  - id: D1
    description: "Main run on the 10-04 harness produced a fresh preflight BENCH line and reached part 2 (oneFrame=ok, uhd4k=ok)"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: ".planning/phases/10-composition-spike/evidence/impeller-on.log#benches_on=2 preflight_on=1 soakstart_on=1"
        status: pass
    human_judgment: false
  - id: D2
    description: "Control run on the 10-04 harness produced a fresh preflight BENCH line and the same part-1/part-2 shape"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: ".planning/phases/10-composition-spike/evidence/impeller-off.log#benches_off=2 preflight_off=1 soakstart_off=1"
        status: pass
    human_judgment: false
  - id: D3
    description: "Independent four-bucket classification derived from the gates rather than the harness self-report"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gates G1, G2, G5, G6 pass; gate G4 (A)/(B) fails with A=0 C=0"
        status: fail
    human_judgment: false
  - id: D4
    description: "Renderer identity re-verified from the engine's own log line via the labelled flutter-run fallback (on=1 / off=0)"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gate G7 (identity_on_matches=1, identity_off_matches=0, new logs 0 engine lines above the label)"
        status: pass
    human_judgment: false
  - id: D5
    description: "D-05 settled from the rerun evidence"
    requirement: COMP-01
    verification: []
    human_judgment: true
    rationale: "D-05 was not settled: neither workload proof (A) nor renderer-abort proof (B) holds. This is the plan's specified failure outcome, not a bucket that needs a human verdict."

duration: 7 min
completed: 2026-10-25
status: halted
---

# Phase 10 Plan 05: Impeller Rerun and D-05 Classification Summary

**The fixed harness ran both switches end to end but aborted inside the soak window in both; with no complete line and no crash forensics, neither workload proof (A) nor renderer-abort proof (B) holds, so the plan FAILS rather than closing D-05.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-10-25T04:09:21Z
- **Completed:** 2026-10-25T04:17:08Z
- **Tasks:** 2 of 2 executed (Task 1 passed; Task 2's (A)/(B) gate failed by design)
- **Files changed:** 6 (all evidence artifacts)

## Outcome

**This is a FAILED plan, not a closure.** The only honest reading of the evidence is:

| Gate | Requirement | Actual | Result |
|------|-------------|--------|--------|
| (A) workload executed | `complete_on >= 1`, parts all ok, `rounds == 100`, `seconds >= 30`, `pixelProbeSupported: true`, numeric `nonBlackRatio` | `complete_on: 0` (both runs); last payload is `soak-start` with `parts.oneFrame=ok, parts.uhd4k=ok, parts.soak=inconclusive` | **FAIL** |
| (B) renderer-side abort | exit neither 0 nor 1, real `.dmp` (or positive `Application Error` naming `flutter_windows.dll`), `crash.last_stage`, `classification: renderer-crash` | exit 79 (package:test `noTests`), no `.dmp`, no `Application Error`/WER event, no TDR; `crash.last_stage: soak` | **FAIL** |

Both reruns behaved identically with only the switch changed:

- preflight BENCH line reached the console (the 10-04 channel fix works);
- part 1 and part 2 executed (`oneFrame=ok`, `uhd4k=ok`) — the 10-04 part-1 gate fix works;
- the pixel probe ran in part 2 and returned `supported: true, nonBlackRatio: 0.0` (a black frame);
- the process then stopped inside the soak window, before any `soak-progress` or `complete` line.

`classification: inconclusive` + `evidence_gap: complete-line-missing` is written in
`evidence/impeller-bench.txt` **only as an evidence-gap record**, together with
`task_status: failed` and `closure: refused`. 10-06 must not write an ADR verdict
from it.

## Flagged Assumption (preserved verbatim from the plan objective)

**Flagged assumption（COMP-01 edge probe）：** 本阶段没有 `-SPEC.md`，确定性 edge probe 对 COMP-01 返回 `unclassified / unresolved`（`applicable: 1, resolved: 0`）。本计划不据此发明边界覆盖结论：冒烟的边界行为就是 D-04 工作负载实际执行到的那部分；未回答的边界保持 unresolved，**不得**用「backstop」自动标记为已覆盖。该假设在 SUMMARY 中原样保留。

The practical consequence this round: the only exercised edge is
"part 1 (create → composed frame → dispose) and one 4K render target execute";
the soak boundary and the 30 s + 100-round boundary remain **unresolved**.

## Accomplishments

- Appended a fresh disk gate (`run_start_epoch=1792901401`, `avail_bytes=7818346496`,
  `status=ok`) before any run; the rerun freshness gate passes
  (`start_epoch=1792901417 >= 1792901401`).
- Ran the main switch on the 10-04 harness: 2 BENCH lines (`preflight`,
  `soak-start`), `rgba8_on=0`, no renderer anomaly signals
  (`shared-image allocation failed`, `device lost`, RGBA8 cliff).
- Ran the control switch: the same 2 BENCH lines and the same abort shape,
  `rgba8_off=0`, no anomaly signals.
- Re-verified identity without another `flutter run`: 1 match in
  `impeller-run-on.log`, 0 in `impeller-run-off.log`; the new logs carry 0 engine
  lines above the labelled fallback section, so `flutter test -d windows` still
  does not forward the engine log (Q1 stays answered: no).
- Derived the classification independently from the gates (not from the
  harness's self-reported `result`), and refused to promote it to a settled
  bucket.

## Task Commits

1. **Task 1: main run (`--enable-impeller`) + disk gate** — `f479a1c` (test)
2. **Task 2: control run + independent classification (FAILED gate)** — `ff60222` (test)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `evidence/impeller-on.log` — full console of the main rerun (2 BENCH lines),
  plus a labelled `flutter-run` identity section appended below the raw output.
- `evidence/impeller-on.meta` — overwritten with the fresh run: start
  `2026-10-25T04:10:16Z` / `start_epoch: 1792901417`, `exit_code: 79`,
  end `2026-10-25T04:11:05Z`.
- `evidence/impeller-off.log` — control rerun console, plus the labelled
  negative-identity note.
- `evidence/impeller-off.meta` — `switch: --no-enable-impeller`,
  `start_epoch: 1792901621`, `exit_code: 79`.
- `evidence/impeller-bench.txt` — rewritten machine-readable evidence-gap record:
  classification/identity/reason/switch/probe/RGBA8/BENCH counts/parts/rounds/
  seconds/identity matches/resolvedLibmpv/mpvBackend/renderer-refs, plus
  `evidence_gap`, `task_status: failed`, `closure: refused`, the full
  `run-on.*`/`run-off.*` matrix and crash forensics.
- `evidence/disk-gate.txt` — appended `run-gate: avail_bytes=7818346496
  threshold_bytes=5905580032 run_start_epoch=1792901401 status=ok` plus raw
  `df`; the 10-03 lines were left untouched.

## Decisions Made

- **Task 2 is FAILED.** The plan's own (A)/(B) gate is the arbiter: A=0, C=0.
  No closure, no "phase closed" language.
- **Exit 79 was interpreted, not classified.** It is package:test's `noTests`
  code (the log prints `No tests were found.`), which means the app process
  stopped reporting; it is neither a native crash code nor evidence for (B).
- **No attribution.** The abort shape is identical with Impeller on and off, so
  it cannot be blamed on Impeller or on Skia. It is recorded as an unexplained
  abort (the plan's prohibition against attributing a harness-side abort to the
  renderer).
- **The black frame is recorded but not promoted.** The probe reached part 2 and
  returned `supported: true, nonBlackRatio: 0.0`. Had the workload completed,
  this alone would be `failed` with reason `black-frame`; while (A)/(B) fail it
  stays an unresolved signal (WR-03: no independent black control, so a real
  black frame cannot be distinguished from a texture the probe could not see).
- **COMP-01 is not marked complete.** Its smoke half is still unestablished.

## Deviations from Plan

None - plan executed exactly as written. The (A)/(B) gate failing is the
plan's explicitly specified failure outcome, not an unplanned deviation.

## Issues Encountered

- **Both reruns abort inside the soak window.** At `00:03`–`00:04` the test
  reports `did not complete [E]` after the `soak-start` line; the process is
  gone before any `soak-progress` or `complete` line. This is the blocking
  reason the plan fails.
- **No crash forensics exist.** `%LOCALAPPDATA%/CrashDumps` has no
  `mpv_kit_example` dump in the last 60 minutes; the Application log has no
  `Application Error` (Id 1000/1001) event naming `flutter_windows.dll` or
  `mpv_kit_example`; the System log has no display-driver/TDR event. Application
  logging itself was verified live (other providers logged in the same window),
  so the absence is meaningful, not a logging failure.
- **`flutter test` finalization error.** Both runs end with a
  `PathNotFoundException` on the temp `flutter_test_listener.*` directory while
  finalizing the test process. This is a consequence of the abrupt stop, not an
  additional verdict signal.

## Threat Surface

No new runtime surface. The plan's mitigations were applied:
T-10-15 (classification derived independently from the gates; BENCH counts and
each gate basis are on disk; harness self-report ignored), T-10-16 (identity only
from the engine log line, matches recorded, `mpv_kit_video: vulkan` explicitly
not used as engine identity). No package was installed; `packages/` has zero
working-tree changes.

## Next Phase Readiness

- **10-06 must not write an ADR verdict from `evidence/impeller-bench.txt`.**
  The file is an evidence-gap record (`task_status: failed`, `closure: refused`).
- Phase 11's first task now has two concrete items: (1) find the cause of the
  soak-window abort that reproduces with both switches, and (2) investigate the
  black frame the probe observed in part 2 (`nonBlackRatio 0.0` at 1266x683).
- The harness fixes from 10-04 are confirmed working: the report channel and the
  part-1 gate both produced the expected evidence before the abort.

## Self-Check: PASSED

- `.planning/phases/10-composition-spike/evidence/impeller-on.log`,
  `impeller-off.log`, both `.meta` files, `impeller-bench.txt` and
  `disk-gate.txt` exist with the required lines.
- The plan's (A)/(B) gate fails with A=0, C=0; the SUMMARY records that as a
  FAILED plan and does not claim closure.
- Commits `f479a1c` and `ff60222` are ancestors of HEAD; no file deletions.
- `git status --porcelain -- packages/` is empty.
