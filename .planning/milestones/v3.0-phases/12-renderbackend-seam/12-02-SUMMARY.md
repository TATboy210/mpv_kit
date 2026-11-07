---
phase: 12-renderbackend-seam
plan: 02
subsystem: testing
tags: [integration-test, impeller, soak-harness, pixel-probe, vulkan, flutter-3.47.8]

requires: []
provides:
  - "Probe-control diag (MPV_KIT_SMOKE_DIAG=probe) and evidence: texture-visible, stable, after-first-frame with Impeller on and off"
  - "Explanation of 10-05's 1266x683 probe surface (production 1280x720 boundary clamped by a 1265.33x682.67 logical view at dpr 1.5)"
  - "probe_decision: readiness-gate; part 2 reads pixels only after presented frames, pass rule unchanged"
  - "MPV_KIT_SMOKE_MODE=cycles baseline segment (stage:cycles BENCH line)"
  - "MPV_KIT_SMOKE_DIAG=resize-front reproducer for the keep_front reallocation shape"
  - "uhd_endurance_test MPV_KIT_BENCH_RENDER=1 rendered variant (BENCH uhd \"rendered\" field)"
affects: [12-04, 12-07, 12-08, 12-12]

actuals:
  tokens: 12635
  tasks: 2
  commits: 2
plan_head_before: 92e5927f67fec79a8999aa6df8ee6917ecad7a73
plan_head_after: fa11735a28de7d944b530aba6af15f19a5868235

tech-stack:
  added: []
  patterns:
    - "Evidence modes live in a `part of` file as `extension _SmokeModes on _SmokeHarness`, so they share harness state without growing the measured file"
    - "Probe control: green background + red patch + texture region through the same toImage channel; the texture is judged only when both controls read correctly"

key-files:
  created:
    - example/integration_test/impeller_smoke_modes.dart
    - .planning/phases/12-renderbackend-seam/evidence/probe-control-on.log
    - .planning/phases/12-renderbackend-seam/evidence/probe-control-off.log
    - .planning/phases/12-renderbackend-seam/evidence/probe-control.txt
  modified:
    - example/integration_test/impeller_smoke_test.dart
    - example/integration_test/uhd_endurance_test.dart

key-decisions:
  - "probe_decision: readiness-gate. RepaintBoundary.toImage does see the external texture with Impeller on and off, so _probePixels, _minNonBlackRatio = 0.01 and _classify stay as they were in 3a5f450. Part 2 now runs the same first-frame gate before probing. A black part-2 read now means a black composed frame."
  - "The rendered UHD variant's source runs 30 s longer than the timed window, because a window that reaches EOF counts the undisplayed tail as VO drops (8 drops in 20 s vs 0)"
  - "Unknown non-empty MPV_KIT_SMOKE_DIAG / MPV_KIT_SMOKE_MODE values now throw instead of silently running the measured D-05 workload"
  - "RBE-01 is not marked complete: this plan fixes the harness only; the baseline itself is 12-04"

patterns-established:
  - "New harness modes: put them in impeller_smoke_modes.dart, dispatch after the identity gate, never call _classify, never emit stage:complete"

requirements-completed: []

duration: 21min
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 02: Soak Harness Probe Control and Baseline Modes Summary

**The part-2 pixel probe does see the external texture. The new three-region control read the texture region as fully non-black, stable across two reads and after the first presented frame, with Impeller both on and off. 10-05's 1266x683 surface is the production 1280x720 boundary clamped by a 1265.33x682.67 view at dpr 1.5. With the probe confirmed, part 2 now waits for a first-frame readiness gate before it reads, and the pass rule is byte-identical. The harness also gained a 100-cycle create/dispose segment, a `resize-front` reproducer and a rendered variant of the UHD 4K gate.**

## Performance

- **Duration:** about 21 min
- **Started:** 2026-10-26T06:17:23Z
- **Completed:** 2026-10-26T06:38:08Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- **Probe control (WR-03 closed):** both switches gave the same readings.
  - Control patch `nonBlackRatio` 1.0; background `greenFraction` 1.0.
  - Texture region `nonBlackRatio` 1.0 with `greenFraction` about 0.157. That green share comes from the testsrc2 pattern; it is well below the 0.5 that would mean the background shows through.
  - Each run: 30 fps and a `time-pos` advance of 0.37 to 0.4 s before the first read.
  - Result: `probe_visibility_on/off: texture-visible`.
- **Surface explained:** the window client area is 1265.33x682.67 logical pixels at dpr 1.5. `Center` clamps the production `SizedBox(1280, 720)` to that size, and `toImage(pixelRatio: 1.0)` rounds it to 1266x683. The 640x360 control boundary is not clamped (`probe_surface_matches_boundary: true`).
- **Part 2 probe:** part 2 now runs `_firstFrameGate` before `_probePixels`. `probeTiming`, `fpsAtProbe` and `timePosDelta` are added to the `pixelProbe` map. `_classify` never reads them.
- **`MPV_KIT_SMOKE_MODE=cycles`:** the 3-round self-check printed `{"stage":"cycles","cycles":3,"completed":3,"failures":0,"rssStart":267427840,"rssEnd":296882176,...}`.
- **`MPV_KIT_SMOKE_DIAG=resize-front`:** each round runs mount, 1280x720 front, a 500 ms hold, setSize(640, 360) while the texture is still mounted, a 500 ms hold, then unmount and dispose. A flushed trace marker brackets every await.
- **`MPV_KIT_BENCH_RENDER=1`:** the 20 s 1080p self-check printed `"rendered":true` and passed every fixed gate (0 drops, 0 render errors).

## Task Commits

1. **Task 1 (tracer): probe-control diag, run with Impeller on and off.** `3ab4000` (test). Tracer gate: automated verify re-run passed, so expansion continued.
2. **Task 2: probe decision, cycles, resize-front and rendered UHD variant.** `fa11735` (test).

## Files Created/Modified
- `example/integration_test/impeller_smoke_modes.dart`: new `part of` file holding the probe tree, region stats, readiness gate, `_runProbe`, `_runCycles`, `_runResizeFront` and the moved `_runDiag` (672 lines).
- `example/integration_test/impeller_smoke_test.dart`: `part` directive, probe-tree selection before `pumpWidget`, mode dispatch, and the part-2 readiness gate (793 lines).
- `example/integration_test/uhd_endurance_test.dart`: guarded `MPV_KIT_BENCH_RENDER` branch, `rendered` field, and a header note that the Phase 4 gate never rendered.
- `.planning/phases/12-renderbackend-seam/evidence/probe-control{-on.log,-off.log,.txt}`: raw logs (exit 0 for both) and the key-per-line results.

## Decisions Made
See `key-decisions` in the frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Moved `_runDiag` into the modes file**
- **Found during:** Task 1
- **Issue:** `impeller_smoke_test.dart` was already 859 lines, so the plan's limit of 800 lines per file could not be met by adding code alone.
- **Fix:** Moved the 10-07 soak reproducer `_runDiag` into the `_SmokeModes` extension with its body unchanged. The only edit inside it is `var controller` becoming `final`.
- **Files modified:** `impeller_smoke_test.dart`, `impeller_smoke_modes.dart`
- **Commit:** `3ab4000`

**2. [Rule 2 - Missing critical] Unknown mode values fail loudly**
- **Found during:** Task 1
- **Issue:** A mistyped `MPV_KIT_SMOKE_DIAG` used to fall through to the measured D-05 workload and emit a `stage:complete` classification. That is the T-12-03 repudiation risk.
- **Fix:** Unknown non-empty `MPV_KIT_SMOKE_DIAG` and `MPV_KIT_SMOKE_MODE` values now throw a `StateError`.
- **Commit:** `3ab4000` / `fa11735`

**3. [Rule 1 - Bug] The rendered UHD variant counted EOF drops**
- **Found during:** Task 2 self-check
- **Issue:** The rendered variant starts timing only after the resize event, so its window ran past the end of the source. The 20 s 1080p run reported `frame-drop-count: 8` and failed the fixed gate. The unrendered run had 0 drops. A rendered run whose source outlasted the window, a temporary experiment that was reverted, also had 0.
- **Fix:** When `render` is set, the source is `seconds + 30` long, matching the 30 s bound on the resize wait. The unrendered source string is unchanged, and the gates are not relaxed.
- **Files modified:** `uhd_endurance_test.dart`
- **Commit:** `fa11735`

**4. [Formatting] `dart format` reflowed unrelated lines**
- The installed formatter changed three existing constructs in the main file. I restored them by hand so the diff only contains plan changes. CI does not gate on format.

## Observation for 12-04 / 12-07 (not evidence; self-check only)
A 2-round `resize-front` self-check (`--no-enable-impeller`, trace in a temp file, not in the evidence directory) **lost the process in round 1**. The last trace lines were:
```
t=1294 round=1 step=second-resize-wait-done ... resizeEvents=2
t=1296 round=1 step=hold-resized-begin ...
```
So the abort came within 500 ms of `setSize(640, 360)` on a controller with a published front frame. That matches the keep_front / `AllocateRing` double-destroy candidate. flutter test exited with code 79 (listener cleanup error after the device process vanished). 12-04 must record this formally as the pre-fix baseline. The fix is 12-07's job.

The default D-05 path was not run here, because it is 12-04's baseline. Its soak round 1 reaches the same shape.

## Issues Encountered
- `flutter test` does not forward the engine's "Using the Impeller rendering backend" line. probe-control.txt therefore records `engine_renderer: unresolved-by-harness`, and the on/off switch is the command-line flag only, as in 10-05.

## User Setup Required
None.

## Next Phase Readiness
- 12-04 can collect the D-05 baseline, `MPV_KIT_SMOKE_MODE=cycles` (100) and `MPV_KIT_SMOKE_DIAG=resize-front` from one harness. Pixel reads are trustworthy (probe_decision: readiness-gate).
- 12-08 and 12-12 can run `MPV_KIT_BENCH_RENDER=1` for a 4K comparison that really renders, next to the unchanged Phase 4 command.
- Commits are not pushed. Under `push-green-only` the orchestrator may push them; they touch only `example/integration_test` and evidence files.

## Self-Check: PASSED
