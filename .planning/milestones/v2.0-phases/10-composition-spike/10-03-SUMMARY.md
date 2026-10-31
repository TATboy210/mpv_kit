---
phase: 10-composition-spike
plan: 03
subsystem: rendering
tags: [flutter, impeller, angle, windows, smoke, adr, identity, d05]

requires:
  - phase: 10-composition-spike
    provides: 10-01 REA (three-path ANGLE/device/fence conclusions) and 10-02 harness
  - phase: 09-8k-full-rate
    provides: the pinned local Flutter 3.47.8 SDK/engine artifact

provides:
  - Impeller-on and --no-enable-impeller run pair on the pinned 3.47.8 SDK
  - Renderer identity proven from the engine's own log (flutter-run fallback)
  - Four-bucket classification with identity recorded separately (inconclusive)
  - RGBA8 cliff scan, non-black-probe status and crash forensics as data
  - ADR 0003 with the Phase 11 route, fallback contract, quarantine hypothesis and Q1-Q5 mapping

affects: [phase-11]

actuals:
  tokens: 11633
  tasks: 2
  commits: 2
  plan_head_before: 9ad1ed19f2a237e3cd2a4c782e162327999c2473
  plan_head_after: 6f3656e8e76a1f088935043f43c9d4b582071be1

tech-stack:
  added: []
  patterns:
    - "Renderer identity from the engine log only; flutter-run fallback when flutter test drops engine output"
    - "Classification and identity are independent fields; an inconclusive run is never rewritten as failed or a crash"
    - "Evidence logs may carry a labelled fallback section with its source and command"

key-files:
  created:
    - .planning/phases/10-composition-spike/evidence/impeller-on.log
    - .planning/phases/10-composition-spike/evidence/impeller-off.log
    - .planning/phases/10-composition-spike/evidence/impeller-run-on.log
    - .planning/phases/10-composition-spike/evidence/impeller-run-off.log
    - .planning/phases/10-composition-spike/evidence/impeller-bench.txt
    - docs/adr/0003-windows-composition-path.md
  modified:
    - .planning/phases/10-composition-spike/evidence/disk-gate.txt

key-decisions:
  - "Classification is inconclusive, not failed: both runs abort in the 10-02 harness part-1 readiness gate (resizeEvents=0), which is an unsatisfiable predicate because no setSize precedes part 1; attributing that to the renderer would violate T-10-09"
  - "Identity is proven: the engine logged 'Using the Impeller rendering backend (OpenGLESSDF)' under --enable-impeller in the flutter-run fallback and never under --no-enable-impeller"
  - "flutter test -d windows does not forward the app process's engine log (Open Question 1 answered: no); the documented flutter-run fallback was used and labelled"
  - "D-05 was neither confirmed nor refuted; Phase 11's first task is to fix the harness gate and settle D-05 before any composition change"
  - "Phase 11 primary route: upstream the requirement/repro, with the upgrade bypass as its delivery vehicle and self-modified ANGLE as fallback; 'no ANGLE' on 3.47.8 is rejected as unverifiable"

requirements-completed: [COMP-01]

coverage:
  - id: D1
    description: "Both smoke runs executed on the pinned 3.47.8 debug SDK with a visible window; commands, switch values, exit codes and times recorded"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 1 gates 1 and 3 (log presence + disk-gate status/run-gate) — passed; commands in impeller-bench.txt"
        status: pass
    human_judgment: false
  - id: D2
    description: "Renderer identity proven from the engine's own log line, with the control run as negative evidence"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 1 gate 1 (impeller-on.log has the line + OpenGLESSDF; impeller-off.log does not) — passed"
        status: pass
    human_judgment: false
  - id: D3
    description: "Four-bucket classification with identity, RGBA8 scan, non-black-probe status and crash forensics recorded"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 1 gate 2 (classification/identity/reason/switch/nonBlackRatio/rgba8 counts) — passed"
        status: pass
    human_judgment: true
    rationale: "The gates prove the fields exist; whether 'inconclusive' is the correct bucket for an unsatisfiable harness gate (rather than failed) is a judgment recorded in ADR 0003 and must be reviewed."
  - id: D4
    description: "ADR 0003 answers shorter/cheaper, records what Impeller does not remove, guards identity, maps Q1-Q5, and sets the Phase 11 route with measurable indicators"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gates 1-3 (section/verdict/identity-guard/hash/log paths/Q-count/ADR number) — passed"
        status: pass
    human_judgment: true
    rationale: "Automated gates prove structure and required strings; the route choice, evidence separation and honesty of the inconclusive verdict require review."

duration: 14 min
completed: 2026-10-25
status: complete
---

# Phase 10 Plan 03: Impeller Smoke Pair and Composition ADR Summary

**Both D-05 runs on the pinned 3.47.8 SDK abort in the 10-02 harness's own unsatisfiable part-1 gate (inconclusive, identity proven from the engine log), and ADR 0003 records that Impeller is still GLES-over-ANGLE, sets Phase 11's route, and makes settling D-05 its first task.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-10-24T17:38:47Z
- **Completed:** 2026-10-24T17:53Z
- **Tasks:** 2 of 2
- **Files changed:** 11 (10 created, 1 modified)
- **Commits:** 2 task commits (+1 metadata commit)

## Accomplishments

- Ran the harness pair exactly as 10-02 defined it: `--enable-impeller` then
  `--no-enable-impeller`, both on the local 3.47.8 debug build (framework
  `737ba8f885`, engine `cf636b1dfb`), one external texture, visible window,
  the `mpv_kit_libs` dev.3 libmpv. Full commands, switch values, exit codes and
  times are in `evidence/impeller-bench.txt` and the `*.meta` files.
- Both runs stopped at the same harness gate after 30 s:
  `part 1 readiness timeout ... resizeEvents=0`. `VideoRenderer::SetSize` is the
  only writer of the render size and `resize` fires only when it differs from
  the ring; the harness never calls `setSize` before part 1. Recorded as a
  **harness defect**, never as a renderer failure.
- Proved the engine renderer from its own line:
  `Using the Impeller rendering backend (OpenGLESSDF)` under
  `--enable-impeller`, absent under `--no-enable-impeller`. `flutter test -d
  windows` does not forward the engine log, so the documented `flutter-run`
  fallback was used and its source labelled in the logs.
- Scanned both logs for `Only support GL_RGBA8 format now`: 0 hits each. The
  pixel probe was never reached, so `nonBlackRatio: unsupported` and `pass` is
  impossible — process-alive is not a pass.
- Crash forensics are negative: exit code 1 (test-framework timeout, not a
  native exception), no `mpv_kit_example` WER dump, no `Application Error`
  event naming `flutter_windows.dll`; the 3.47.0 offset `0x2c55f7` was not used.
- Wrote `docs/adr/0003-windows-composition-path.md`: `verdict: inconclusive`,
  `engine-renderer:` and `identity: proven` at the top, the identity guard,
  separate REA / smoke / premise-correction evidence, the Phase 11 route and
  measurable closing indicators, the fallback contract, the quarantine
  hypothesis, D-06 conditions and provenance.

## Task Commits

1. **Task 1: run the Impeller/control pair and classify with identity** — `0b53190` (test)
2. **Task 2: write ADR 0003** — `6f3656e` (docs)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `.planning/phases/10-composition-spike/evidence/impeller-on.log` — full
  console of the primary run, plus a labelled `flutter-run` identity section.
- `.planning/phases/10-composition-spike/evidence/impeller-off.log` — full
  console of the control run, plus a labelled negative-identity note.
- `.planning/phases/10-composition-spike/evidence/impeller-run-on.log` /
  `impeller-run-off.log` — the identity fallback captures.
- `.planning/phases/10-composition-spike/evidence/impeller-bench.txt` — the
  classification: `inconclusive` / `proven`, reason, switch, `nonBlackRatio:
  unsupported`, `rgba8_on: 0`, `rgba8_off: 0`, per-run exit codes/commands,
  crash forensics and the libmpv/backend identity record.
- `.planning/phases/10-composition-spike/evidence/disk-gate.txt` — appended
  `run-gate: avail_bytes=8,183,009,280 ... status=ok`.
- `docs/adr/0003-windows-composition-path.md` — the decision record.

## Plan-Level Verification

- Identity line + `OpenGLESSDF` in the primary log, absent in the control —
  **PASS**.
- `MpvLibrary.resolvedPath` and `mpvBackend == vulkan` asserted before
  measurement (the preflight gate passed) and recorded — **PASS**.
- Classification file carries classification + identity, RGBA8 counts and the
  non-black-probe status — **PASS**.
- ADR 0003 verdict matches the classification, honors the identity guard,
  answers shorter/cheaper and maps five Open Questions — **PASS**.
- BENCH `soak-start` / `complete` stage lines — **NOT PRODUCED**: both runs
  aborted before the workload. This is the recorded blocking reason for the
  `inconclusive` classification, not an unhandled failure.

## Decisions Made

- **Inconclusive is the correct bucket.** The abort happens in harness code
  before any renderer workload; calling it `failed` would attribute a harness
  defect to Impeller (T-10-09). `renderer-crash` is contradicted by the exit
  code and the absence of WER/event-log entries.
- **Identity stands on the engine's own log only.** The `mpv_kit_video: vulkan`
  line proves mpv's backend, not the engine renderer; the HUD field remains a
  placeholder. The fallback provenance (`flutter-run`) is recorded next to the
  line.
- **D-05 is unsettled, and the ADR says so.** Phase 11's first task is to fix
  the harness gate (call `setSize` before the part-1 gate, or gate on a first
  rendered frame) and re-run; no composition change is approved on "Impeller
  works".
- **Phase 11 route.** Primary: upstream the requirement and repro (executable
  now, and the only route that can produce a non-ANGLE consumption backend).
  Upgrade bypass is its delivery vehicle once such an engine exists;
  self-modified ANGLE is the fallback. Measured indicators: per-resolve CPU µs,
  presence/absence of flush/submit/reset, 4K cost before/after, D-05, 4K
  endurance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Evidence integrity] Reconciled the Step-4 identity fallback with the Task-1 gate**
- **Found during:** Task 1, after both runs
- **Issue:** `flutter test -d windows` forwards no engine log, so neither test
  log contains the identity line; the plan's Step 4 permits a `flutter-run`
  fallback, but the Task-1 automated gate greps the run logs.
- **Fix:** Appended a clearly delimited section to each run log carrying the
  fallback capture (positive) or the negative-match note (control), labelled
  with its source, SDK, env and full-log path. No line was invented; the
  original console output is untouched above the banner.
- **Files modified:** `evidence/impeller-on.log`, `evidence/impeller-off.log`
- **Verification:** Task-1 gate 1 passes; `impeller-bench.txt` records
  `identity-source: flutter-run`.
- **Committed in:** `0b53190`

### Blocking Issue Recorded Instead of Fixed (by instruction)

**2. [Rule 3 - Blocking] The 10-02 harness part-1 gate is unsatisfiable**
- **Found during:** Task 1, both runs
- **Issue:** The gate waits for a `resize` event, but the renderer emits
  `resize` only after `SetSize` changes the render size, and the harness never
  calls `setSize` before part 1. It timed out identically with the switch on
  and off.
- **Why not fixed:** The dispatch explicitly says the harness was already built
  and must be run, not rewritten; the plan's own failure path says to record
  `inconclusive` with the exact blocking reason.
- **Result:** classification `inconclusive`, reason recorded; the defect and
  the required fix are recorded in ADR 0003 and are the first Phase 11 task.

---

**Total deviations:** 1 auto-fixed (evidence reconciliation), 1 blocking issue
recorded by instruction.
**Impact on plan:** D-05 was not exercised. The classification is honest and
the ADR refuses to turn the harness defect into a renderer verdict; the cost is
that Phase 11 must first repair and re-run the harness before any route work.

## Issues Encountered

- No `BENCH impeller` line reached the captured console in either run, so the
  workload, soak and pixel probe did not execute; the probe status is
  `unsupported` by construction.
- `flutter test -d windows` does not forward the engine's log (Open Question 1
  answered: no). The fallback required a second, short `flutter run` pair.
- The first `flutter run` fallback was terminated by `timeout` (exit 124) after
  capturing the line; the example window was force-closed between runs. This is
  expected for a capture-only run, not a failure.

## User Setup Required

None - no external service configuration required.

## Threat Surface

No new runtime or code surface. The plan added evidence files and one ADR; no
package was installed and `packages/` was not modified. Mitigations recorded:
T-10-09 (non-black proof required for pass; RGBA8 scan in both logs),
T-10-10 (identity and classification are separate fields; the ADR's guard
forces `inconclusive` on unproven identity), T-10-11 (commands, switches, exit
codes and times are in the evidence).

## Next Phase Readiness

- Phase 11 can decide with ADR 0003 + report 03 + the log pair, without new
  research.
- First Phase 11 task: repair the part-1 gate in
  `example/integration_test/impeller_smoke_test.dart` and re-run the pair to
  settle D-05.
- The historical 4K baseline's renderer is unrecorded; any before/after
  comparison must capture the engine line on both sides.
- Quarantine stays at 4 (ring 7) until Phase 11 measures compositor latency
  under the selected path.

## Self-Check: PASSED

- `docs/adr/0003-windows-composition-path.md`, `evidence/impeller-bench.txt`,
  `evidence/impeller-on.log`, `evidence/impeller-off.log` and the fallback
  logs/metas exist.
- Commits `0b53190` and `6f3656e` are ancestors of HEAD; no file deletions.
- All Task-1 and Task-2 automated gates were re-run after the commits and pass;
  the only unmet plan-verification sub-clause is the BENCH stage lines, which
  is the documented blocking reason for `inconclusive`.
