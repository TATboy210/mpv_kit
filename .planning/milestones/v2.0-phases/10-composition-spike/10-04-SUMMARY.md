---
phase: 10-composition-spike
plan: 04
subsystem: testing
tags: [flutter, integration-test, impeller, angle, windows, bench, harness, d05]

requires:
  - phase: 10-composition-spike
    provides: the 10-02 smoke harness and the 10-03 run classification that isolated the two harness defects (CR-01, CR-02)
provides:
  - A report channel proven end-to-end to reach the captured console (print + the one sanctioned ignore)
  - A satisfiable part-1 readiness gate that keeps resize (ring allocation) as positive render evidence
  - An offset/length-safe pixel probe that refuses a short buffer instead of scanning unrelated memory
  - Failure reporting at both preflight stages (preflight emit and pumpWidget)
  - Descriptive soak-end fields (fpsAtSoakEnd, timePosAtSoakEnd, longestMountMs) for the 10-05 rerun
affects: [phase-10-plan-05, phase-10-plan-06, phase-11]

actuals:
  tokens: 3975
  tasks: 2
  commits: 2
  plan_head_before: 9942e5de298765f4bc4d9b2ba4a6555f3a82365d
  plan_head_after: 7874734d8a66220b95324fceb86a18d4791be978

tech-stack:
  added: []
  patterns:
    - "BENCH report channel is print(); stdout.writeln is not forwarded by flutter test -d windows"
    - "Readiness gates require decoder params plus a positive renderer signal (resize), never fps alone"
    - "ByteData views use offsetInBytes/lengthInBytes; a short buffer is an evidence gap, not a pass"

key-files:
  created:
    - .planning/phases/10-composition-spike/evidence/impeller-channel-probe.log
  modified:
    - example/integration_test/impeller_smoke_test.dart

key-decisions:
  - "The report channel is print('BENCH impeller ...') with exactly one // ignore_for_file: avoid_print, matching the three sibling harnesses; this explicitly supersedes 10-02's must-have that the new file carry no analyzer suppression comments"
  - "This single ignore is a recorded, explicit exception to the CLAUDE.md rule that hand-written code carries no analyzer suppression directives; the three sibling harnesses are the precedent and CLAUDE.md itself is not modified in this phase"
  - "The part-1 gate keeps resize as a required signal (fps>0 AND _resizeEvents > baseline): resize is emitted only after a successful ring allocation, whereas the pre-fix logs showed fps=30 with resizeEvents=0"
  - "The probe run is a channel proof only: exit 1 at the not-yet-fixed part-1 gate is the expected shape, and no smoke classification is derived from it (10-05 owns the rerun)"
  - "WR-04/WR-05 fields are descriptive and never enter _classify; no new pass condition was added"

patterns-established:
  - "Prove a report channel with a real run before any workload depends on it"
  - "An unsatisfiable readiness gate is fixed by supplying the missing native trigger, not by dropping the proof it carries"

requirements-completed: [COMP-01]

coverage:
  - id: D1
    description: "BENCH lines reach the captured console under the real run command (preflight proven end-to-end)"
    requirement: COMP-01
    verification:
      - kind: integration
        ref: ".planning/phases/10-composition-spike/evidence/impeller-channel-probe.log#benches=2 preflight=1 exit=1"
        status: pass
    human_judgment: false
  - id: D2
    description: "The part-1 readiness gate is satisfiable without weakening it (params wait, resize baseline before setSize, resize growth required)"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gate 1 (params -> baseline -> setSize order) and gate D (fps>0 && resize>baseline) — passed"
        status: pass
    human_judgment: true
    rationale: "The gates prove the code shape; that the gate actually turns green at runtime is proven by the 10-05 rerun, not by this plan"
  - id: D3
    description: "Pixel probe reads the ByteData view and reports a short buffer as supported:false"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gate 2 (no bare asUint8List(), offsetInBytes present once, short-buffer verdict) — passed"
        status: pass
    human_judgment: false
  - id: D4
    description: "Both preflight stages (emit and pumpWidget) report result:inconclusive before rethrow"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gate 3 (pumpWidget -> catch -> _emitBench -> inconclusive, before runAsync) — passed"
        status: pass
    human_judgment: false
  - id: D5
    description: "Complete line carries fpsAtSoakEnd/timePosAtSoakEnd/longestMountMs as descriptive-only evidence"
    requirement: COMP-01
    verification:
      - kind: other
        ref: "plan Task 2 gate 4 (three fields present) and gate 5 (dart analyze --fatal-infos) — passed"
        status: pass
    human_judgment: false

duration: 5 min
completed: 2026-10-25
status: complete
---

# Phase 10 Plan 04: Harness Channel, Readiness Gate and Evidence Paths Summary

**The smoke harness now reports through `print()` with a run-proven BENCH preflight line, gates part 1 on decoder params plus a real `setSize`-driven resize, slices the pixel buffer by offset/length, and reports harness failures at both preflight stages — CR-01, CR-02, WR-02 and IN-06 closed without weakening any verdict rule.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-10-25T03:59:32Z
- **Completed:** 2026-10-25T04:04:48Z
- **Tasks:** 2 of 2
- **Files changed:** 2 (1 created, 1 modified)

## Accomplishments

- Replaced the unreachable `stdout.writeln` report channel with
  `print('BENCH impeller ...')` and added exactly one
  `// ignore_for_file: avoid_print`, the same convention as
  `playback_bench_test.dart`, `uhd_endurance_test.dart` and
  `real_plugin_test.dart`.
- Proved the channel with a real run on the pinned 3.47.8 SDK:
  `evidence/impeller-channel-probe.log` contains 2 `BENCH impeller` lines
  including the `"stage":"preflight"` line, plus a `# channel-probe:` block with
  counts, exit code, command and time. Exit 1 at the (still unfixed) part-1 gate
  is the expected shape for this task and was not classified.
- Moved the preflight emit inside `tester.runAsync`'s `try`, so it sits under
  the failure-reporting catch and uses the forwarding channel the sibling
  harnesses rely on.
- Made the part-1 gate satisfiable in the only order that preserves the proof:
  wait for `videoParams == 1920x1080`, take `_resizeEvents` as the baseline,
  then `controller.setSize(1920, 1080)`, then require `fps > 0` **and**
  `_resizeEvents > baseline`. The comment block records the native basis
  (`SetSize` is the only writer of `width_`/`height_`,
  `video_renderer.cc:166-176`; `resize` is emitted after a successful ring
  allocation, `:500-541`).
- Hardened the pixel probe: `bytes.buffer.asUint8List(offsetInBytes,
  lengthInBytes)` and a `short pixel buffer` verdict returning
  `supported:false` when `data.length < width*height*4`. The WR-03 limitation
  (no independent black control) is documented on `_probePixels`.
- Added failure coverage: a `pumpWidget` failure now emits
  `{'stage':'preflight','result':'inconclusive',...}` and rethrows; the existing
  `_execute` catch stays unchanged, giving two `result: inconclusive` sites.
- Added `fpsAtSoakEnd`, `timePosAtSoakEnd` and `longestMountMs` to the
  `complete` payload with an explicit comment above `_classify` that they do not
  participate in the pass decision and that `idleSoak == 0` can be trivially
  true (normal mount windows are ~250-350 ms, below the 500 ms idle window).

## Task Commits

1. **Task 1: report channel end-to-end proof (`print` + preflight log)** - `ef56647` (test)
2. **Task 2: part-1 gate, pixel slice, failure coverage, descriptive fields** - `7874734` (fix)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `example/integration_test/impeller_smoke_test.dart` — `_emitBench` now prints;
  preflight emit moved into `runAsync`; `pumpWidget` wrapped in a reporting
  catch; part 1 split into params wait → baseline → `setSize` → resize+fps gate;
  pixel probe slices by offset/length with a short-buffer verdict; `complete`
  line gains the three descriptive soak-end fields; `longestMountMs` tracked in
  `_setTexture`.
- `.planning/phases/10-composition-spike/evidence/impeller-channel-probe.log` —
  raw console output of the channel-probe run plus the `# channel-probe:` block
  (benches=2, preflight=1, exit=1, command, start/end times). The raw output was
  not rewritten.

## Decisions Made

- **The `avoid_print` ignore supersedes 10-02's no-suppression must-have.** The
  plan records this explicitly: `print` is the only channel measured to reach
  the captured console under `flutter test -d windows`, and `example/` uses
  `package:flutter_lints/flutter.yaml`, so `--fatal-infos` fails without the
  ignore. Three sibling harnesses carry the same line. This is a recorded
  exception to the CLAUDE.md "hand-written code has no ignore directives" rule;
  CLAUDE.md itself is not modified in this phase.
- **The channel proof is deliberately separate from a smoke conclusion.** The
  probe run exited 1 in the not-yet-fixed part-1 gate; that is the success shape
  for Task 1. No classification was derived from it.
- **The gate keeps resize as required evidence.** fps-only would have turned
  green in the pre-fix runs (`fps=30`, `resizeEvents=0`) without rendering.
- **No new pass condition.** WR-04/WR-05 fields are descriptive; `_classify`
  is unchanged.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- None. The probe run behaved exactly as predicted: build succeeded, the
  preflight BENCH line was forwarded, part 1 timed out at the still-unfixed
  gate with `resizeEvents=0`, and the run exited 1.

## Threat Surface

No new runtime surface. Mitigations from the plan's threat register are now in
the code: T-10-12 (report channel proven by a real run before any workload),
T-10-13 (params → resize baseline → `setSize` → `fps>0 && resize>baseline`,
with the native basis recorded), T-10-14 (offset/length view + short-buffer
verdict). No package was installed; `packages/` has zero working-tree changes.

## Next Phase Readiness

- 10-05 can rerun the exact same command on both switch values: the channel is
  proven, the part-1 gate is now satisfiable, and the complete line carries the
  descriptive soak-end fields.
- The known-limitation follow-ups named by the plan but out of scope here
  (IN-01 tautological `expect`, IN-04 500 ms constant sync, IN-05 720p probe
  resolution, WR-03 black-control ambiguity) are to be written into 10-06's
  known-limitations section.
- `packages/` and the public API are untouched; `dart analyze --fatal-infos` in
  `example/` reports `No issues found!`.

## Self-Check: PASSED

- `.planning/phases/10-composition-spike/evidence/impeller-channel-probe.log`
  exists, has 2 `BENCH impeller` lines, 1 `"stage":"preflight"` line and the
  `# channel-probe:` block.
- `example/integration_test/impeller_smoke_test.dart` exists with exactly one
  `ignore_for_file: avoid_print`, no `stdout.writeln`, and a `print('BENCH
  impeller ...` call.
- Commits `ef56647` and `7874734` are ancestors of HEAD; no file deletions.
- All plan-level verification gates were re-run after the commits:
  channel log, part-1 order, resize+fps gate, pixel slice, inconclusive
  coverage, WR-04/05 fields, `dart analyze --fatal-infos` (No issues found!)
  and `git status --porcelain -- packages/` (empty) all pass.
