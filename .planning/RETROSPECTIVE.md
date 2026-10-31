# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.0 — GPU-Next Optimization & Full-Rate UHD

**Closed:** 2026-10-25 (`override_closeout`, user decision)
**Phases:** 5 in scope (2 complete, 1 partial, 2 not delivered) | **Plans:** 14 (10 summaries)

### What Was Built

- Vendor provenance made exact at mpv 0.41.0-1115 (gb2c255c13e8e), and the
  advance corrected v1's misattributed `0008` deltas.
- gpu-next regression on the new base: seek-recovery test, full suites and
  benchmarks green (the 4K 30-minute re-run was blocked by a full host disk,
  recorded as environment, not as a pass).
- The example became a debugging cockpit: five-group HUD, live event overlay,
  drag-and-drop playback.
- Frame-size-derived demuxer queue budgets with runtime auto-tune (UHD-01):
  1080p/4K/8K formula matrix in tests; 8K survived 60 s with all v1 gates green.
- A per-path static reverse-engineering of Flutter 3.47.8's external-texture
  consumption (report 03) and ADR 0003: both surface types bind through ANGLE,
  no fence or keyed mutex, Impeller only removes Ganesh's per-resolve work.

### What Worked

- Evidence-first composition work: the REA corrected a wrong premise ("enable
  Impeller" = "no ANGLE") before any production code was written.
- Identity gating on smoke runs: a run whose engine identity is unproven can
  never become a renderer verdict. This turned a would-be false pass/fail into
  an honest `inconclusive`.
- The harness defect was found, fixed and re-run rather than blamed on the
  renderer; the second abort was recorded as an evidence gap, not as a crash.

### What Was Inefficient

- The 10-05 soak abort consumed a full gap-closure cycle and never reproduced
  (5/5, 5/5, 25/25, all exit 0). Three runs produced no diagnosis.
- Phase 10's verification loop kept expanding (9 plans for a spike) while the
  actual decision (settle D-05) stayed blocked behind its own harness.
- Phase 9's second plan (30-minute 8K endurance) never started, leaving UHD-02
  in a state where 60 s passed but the requirement was not met.

### Patterns Established

- Requirement verdicts must match evidence strength: `inconclusive` is not
  `failed`, and neither may be written as "infeasible".
- Static evidence and runtime smoke answer different questions and are never
  interchangeable.
- Close-out may be an override, but it must be recorded as such: known gaps,
  deferred requirements and the override count go into MILESTONES.md rather
  than being smoothed away.

### Key Lessons

1. A spike whose acceptance gate depends on a harness defect will fail
   indefinitely; fix or replace the gate before scheduling more reruns.
2. When the user says "simple close-out", stop the verification loop and record
   the gap — do not manufacture a pass.
3. Before/after performance claims need the renderer identity recorded on both
   sides; v2.0's historical 4K baseline did not record it and cannot be reused
   as a Skia baseline.

### Cost Observations

- Model mix: not recorded for this milestone.
- Sessions: multiple; Phase 10 plan 01 alone took ~2 h 10 m (Ghidra decompile).
- Notable: the two most expensive activities were REA decompilation and
  repeated smoke reruns; both produced evidence, but the reruns produced no
  diagnosis.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | — | 6 | Failure-injection + soak invariants; five CI gates |
| v2.0 | — | 5 | Evidence-first composition spike; override close-out with recorded gaps |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | see v1 archives | 80% gate (mpv_kit) | — |
| v2.0 | +seek recovery, +formula matrix, +smoke harness | unchanged gates | 0 new runtime deps |

### Top Lessons (Verified Across Milestones)

1. Verification conclusions must separate "measured and passed" from "not run
   because of the environment" (v1 Phase 1; re-confirmed by v2.0's 4K re-run).
2. Plans that grow a gap-closure tail are a signal that the acceptance gate is
   wrong, not that more plans are needed (v2.0 Phase 10).
