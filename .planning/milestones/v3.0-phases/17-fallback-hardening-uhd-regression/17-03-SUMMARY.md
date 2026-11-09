---
phase: 17-fallback-hardening-uhd-regression
plan: 03
subsystem: testing
tags: [soak, memory-plateau, rss, vram, rtx-session-tools, opengl, ci-gate, uhd-endurance]

requires:
  - phase: 17-fallback-hardening-uhd-regression
    provides: 17-01 push authorization and ci_gate.sh, 17-02 forced backend matrix, MPV_KIT_REQUIRE_HWDEC guard
  - phase: 16-hardware-decode-zero-copy
    provides: release run 40812562348 (libmpv-windows-x64 bundle), hwdec_probe.dart, hwdec-samples artifacts
provides:
  - "soak_memory.dart: pre-registered memory-plateau rule (soakMemoryVerdict) with unit tests, committed before any measured run"
  - "backend_soak_test.dart: platform-independent 100-round resize/dispose soak per forced backend (SOAK-CHECKPOINT and SOAK lines, RSS plateau assertion)"
  - "native-verify: Backend soak (linux, opengl) step, green on hosted ubuntu with rssVerdict flat"
  - "RTX session tools: rtx_run.sh (gate, timestamped never-overwrite runs, ledger, forensics, --dry-run), vram_sample.ps1, vram_verdict.dart"
  - "rtx-prep.txt: traceable session inputs (reused Phase 16 bundle, samples, expected reasons)"
  - "uhd_endurance_test.dart MPV_KIT_BENCH_SOURCE file-source mode for the hevc d3d11 session"
affects: [17-04, 17-05]

# Not ticked in REQUIREMENTS.md: VER-04 also needs the RTX 4060 session (17-04): three-backend soak with a VRAM curve
# and the two 4K 1800 s runs. This plan delivers the tooling, the registered rule and the hosted opengl part.
requirements-completed: []
requirements-partial: [VER-04]

actuals:
  tokens: 18600
  tasks: 3
  commits: 5
plan_head_before: ad4b8b185e40d31109e6129f11aa9351dedbbef9
plan_head_after: cbdab03f254b1c0a702c70cb200b5ac9ba9f5262

tech-stack:
  added: []
  patterns:
    - "Pass/fail rule written and unit-tested before the first measurement; one implementation shared by the RSS soak and the VRAM verdict tool"
    - "Navigator push/pop mount cycle for texture lifetime soaks (zero transition time keeps the D-05 cadence)"
    - "Hardware-session wrapper: gate before every run, never overwrite a log, UTC-stamped lines, ledger line, standby and crash forensics"

key-files:
  created:
    - example/integration_test/soak_memory.dart
    - example/test/soak_memory_test.dart
    - example/integration_test/backend_soak_test.dart
    - .planning/phases/17-fallback-hardening-uhd-regression/tools/rtx_run.sh
    - .planning/phases/17-fallback-hardening-uhd-regression/tools/vram_sample.ps1
    - .planning/phases/17-fallback-hardening-uhd-regression/tools/vram_verdict.dart
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/rtx-prep.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/dryrun.txt
  modified:
    - .github/workflows/native-verify.yml
    - example/integration_test/uhd_endurance_test.dart
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/ci-runs.txt
    - .planning/phases/17-fallback-hardening-uhd-regression/evidence/flake-timing.txt

key-decisions:
  - "Memory rule: 11 checkpoints (round 0 and every 10th), late = c10 - c6, growth iff late > 32 MiB or (last four steps each >= 1 MiB and late > 8 MiB); fewer than 11 checkpoints is insufficient and never flat; with more, the last 11 are judged."
  - "The 32 MiB limit is justified next to the constant: 40 rounds each leaking one 640x360 BGRA image (0.88 MiB) is 35 MiB."
  - "Hosted opengl soak asserts the RSS plateau as a hard failure (MPV_KIT_SOAK_MEMORY=rss); real Linux GPU memory stays unverified."
  - "Reuse the Phase 16 release bundle (no release.yml dispatch): git diff of native/mpv, native/patches, native/build and release.yml between 15f61ff and HEAD is empty."

patterns-established:
  - "VER-04 prohibition honoured: rule and tests landed in 2296c9a, before any measured run; 17-04 can only apply it."

coverage:
  - id: D1
    description: "Pre-registered memory-plateau rule with unit tests (flat, warm-up, 1 MiB and 0.5 MiB per-round leaks, +-10 MiB noise, small drift, insufficient, boundary values, constants)"
    requirement: "VER-04"
    verification:
      - kind: unit
        ref: "example/test/soak_memory_test.dart (13 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Same 100-round soak on a forced backend; opengl on hosted ubuntu passes with a flat RSS curve, HWDEC software on the lavfi source"
    requirement: "VER-04"
    verification:
      - kind: integration
        ref: "native-verify run 40989693698 and 40991964430: SOAK api=opengl rounds=100 deviceLost=0 idleSoak=0 rssVerdict=flat; ci_gate.sh CI-GATE ok on 2296c9a and cbdab03"
        status: pass
      - kind: integration
        ref: "local RTX 4060 self-check, MPV_KIT_VIDEO_API=vulkan MPV_KIT_SOAK_MEMORY=rss: SOAK line with 11 checkpoints, rssVerdict flat (not evidence)"
        status: pass
    human_judgment: false
  - id: D3
    description: "RTX session tools gate, record, sample and judge each run; dry run recorded as is"
    requirement: "VER-04"
    verification:
      - kind: other
        ref: "bash tools/rtx_run.sh --dry-run (evidence/dryrun.txt: gate FAIL on this host as it should, ledger line exit=0, csv_rows=3, adapter column numeric); vram_verdict.dart --self-test ok"
        status: pass
    human_judgment: false
  - id: D4
    description: "Session inputs are traceable: bundle run id and MANIFEST check, sample run id and sha256, expected reasons per forced api, product sha"
    requirement: "VER-04"
    verification:
      - kind: other
        ref: "evidence/rtx-prep.txt; sha256sum -c MANIFEST.txt 0 failures; rtx_run.sh gate native_equal=yes"
        status: pass
    human_judgment: false
  - id: D5
    description: "Three-backend soak on the RTX 4060 with a dedicated-VRAM curve, and the two 4K 1800 s runs"
    requirement: "VER-04"
    verification: []
    human_judgment: true
    rationale: "Needs the RTX 4060 session with the user present (17-04); hosted runners have no real GPU memory curve."

duration: ~55min
completed: 2026-10-30
status: complete
---

# Phase 17 Plan 03: VER-04 soak tooling, memory rule and RTX session preparation Summary

**A pre-registered memory-plateau rule (committed with its unit tests before any measurement), one 100-round soak that runs on every forced backend and passes flat on hosted ubuntu opengl in CI, plus a gated, timestamped, never-overwriting RTX session wrapper with a CIM VRAM sampler and verdict tool, and fully traceable session inputs.**

## Performance

- **Duration:** about 55 min of work (start 2026-10-30T01:54:57Z), plus two CI gates of about 17 min each that ran while the tooling was written
- **Completed:** 2026-10-30T02:50Z
- **Tasks:** 3 (1 tracer, 2 auto)
- **Files:** 10 outside `.planning/`-evidence (see key-files)

## Accomplishments

- **Task 1 (tracer): rule, soak, CI step.** `soak_memory.dart` (dart: imports only) holds the constants and `soakMemoryVerdict`; 13 unit tests cover every behavior line of the plan plus boundary values (32 MiB exact is flat, 32.5 is growth; steady tail 8.0 flat, 8.5 growth; more than 11 values judges the last 11). `backend_soak_test.dart` runs the D-05 part 3 rounds against one Player on a forced backend, prints `SOAK-CHECKPOINT` (rounds 0, 10 ... 100) and `SOAK`, asserts rounds == 100, seconds >= 30, deviceLost == 0, renderErrors < 10, idleSoak == 0, apiMismatches == 0, a printed software HWDEC outcome, and (with `MPV_KIT_SOAK_MEMORY=rss`) a flat RSS curve. The new native-verify step `Backend soak (linux, MPV_KIT_VIDEO_API=opengl, VER-04)` has no continue-on-error. CI gate ok on 2296c9a (native-verify 40989693698, flutter-plugin 40989693687) and again on cbdab03 (native-verify 40991964430, flutter-plugin 40991964230).
- **Task 2: RTX session tools.** `rtx_run.sh gate|run|--dry-run`, `vram_sample.ps1` (CIM `GPUProcessMemory` and `GPUAdapterMemory`, 1 s, language independent), `vram_verdict.dart` (joins SOAK-CHECKPOINT utc to the CSV and applies the shared rule; `--self-test` prints `VRAM-VERDICT self-test ok`).
- **Task 3: session inputs and file-source mode.** `uhd_endurance_test.dart` got `MPV_KIT_BENCH_SOURCE` (decision uhd=lavfi+hevc-d3d11) in commit 9ae347f, which is the product sha recorded in `rtx-prep.txt`. The Phase 16 bundle is reused (run 40812562348, MANIFEST 0 failures, same libmpv-2.dll sha256 as before), the four mp4 samples match the artifacts of native-verify run 40989693698 byte for byte, and expected reasons follow the actual Windows chain order (vulkan, d3d11).

### D-05 part 3 versus the new soak

| Step | impeller_smoke_test (D-05 part 3) | backend_soak_test | Same? |
|---|---|---|---|
| rounds loop | `_runSoakRounds(100)` | `_runRounds`, `_soakRounds = 100` constant | yes |
| gap between rounds | 250 ms | `_roundGap` 250 ms | yes |
| sizes | alternate 1280x720 / 640x360 (even index large) | same | yes |
| cycle | `_remountCycle`: unmount, `_nextFrame`, setSize on the outgoing controller, dispose, create, mount, `_nextFrame` | same order; the new controller is not sized, as in D-05 | yes |
| bounded frame wait | `_nextFrame` (endOfFrame or 100 ms) | same | yes |
| >= 30 s | pad with a delay if the rounds took less | same padding | yes |
| idle accounting | `_classifyIdle`: idle after >= 500 ms continuous mount inside the soak | `_onEvent`, same rule | yes |
| verdict | `_classify`: rounds, seconds, deviceLost, renderErrors < 10, idleSoak | same asserts plus apiMismatches | yes |
| Player and source | `hwdec: auto-safe`, 1920x1080 testsrc2 + sine | identical | yes |
| mount/unmount | ValueNotifier subtree swap | Navigator route push/pop, zero transition | the one intentional difference |
| every-round frame wait | none | none (open finding stays out of the verdict) | yes |

### Hosted ubuntu opengl soak (llvmpipe, RSS in MiB at rounds 0, 10, ... 100)

| Run | Checkpoints | late | Verdict |
|---|---|---|---|
| 40989693698 on 2296c9a | 657.6, 954.7, 1124.8, 1186.7, 1184.6, 1198.0, 1203.7, 1202.9, 1214.5, 1213.3, 1210.5 | 6.8 MiB | flat |
| 40991964430 on cbdab03 | 657.3, 944.4, 1161.5, 1229.1, 1235.3, 1235.6, 1234.7, 1240.3, 1243.2, 1242.3, 1242.6 | 8.0 MiB | flat |

Both runs: rounds 100, seconds 31.2 / 32.5 (padding to the 30 s floor), renderErrors 0, deviceLost 0, idleSoak 0, apiMismatches 0, HWDEC `outcome=software` on the lavfi source. `lastControllerFrame` is `not-presented` in both, which is the registered second-controller finding (todo 2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front); it is only recorded. Warm-up in the first four checkpoints is large (about +500 MiB) and is why the rule ignores checkpoints 0 to 5. For background only (not thresholds): Phase 12 D-05 grew +233 / +235 MiB and cycles +63.6 / +46.9 MiB over a whole run.

Local self-check on the RTX 4060 (forced vulkan, Phase 16 bundle, not evidence): `SOAK` line with 11 checkpoints 426.7 ... 521.2 MiB, late -4.1 MiB, flat, 47.8 s, deviceLost 0. Local file-source check (hevc-10bit.mp4, 640x360, 20 s, rendered): BENCH `"source":"hevc-10bit.mp4"`, `loopsSeen` 5, `hwdecCurrentFinal` vulkan, HWDEC zero-copy; lavfi mode (15 s) unchanged and green.

### Dry run of the session tool (evidence/dryrun.txt)

The gate printed `result=FAIL` on this host and that is recorded as is: `desktop=unlocked`, `ac=yes`, `stray_example=0` were true; `disk_free_repo_mib=5518` (below the 5632 MiB minimum) and `heavy_gpu=Deskrawl:12` (a foreground app above 10 % GPU engine) were not. A later gate probe after the product sha was recorded printed `native_equal=yes`, `disk_free_repo_mib=6536` and still `heavy_gpu=Deskrawl:13`. The wrapped `sleep 5` ran with `exit=0`, `standby_during=none`, `forensics=none`, and the CSV has 3 rows with a numeric adapter column. These are the conditions the user must clear before 17-04 (close the GPU-using app, keep at least 5.5 GB free on D:); nothing was weakened to get a pass.

## Task Commits

1. **Task 1: rule, soak, ubuntu opengl step** - `2296c9a` (test); evidence `b1d2b85` (docs)
2. **Task 2: RTX session tools and dry run** - `3fb6e11` (chore)
3. **Task 3: file-source mode** - `9ae347f` (test, product sha of the session); provenance `cbdab03` (docs)

**Plan metadata:** the SUMMARY/STATE commit follows this file.

## Deviations from Plan

**1. [Rule 3 - blocking, local tooling] Bundle for the local soak self-check.** The plan names the local hook bundle v0.1.0-dev.3, whose lib directory is empty on this host, and the dev.2 libmpv answers `mpv_render_context_create: operation not implemented` for Vulkan. The Phase 16 bundle `build/phase16/libmpv-rtx/lib` was also empty (DLLs cleaned). Task 3 step 1 downloads that exact bundle anyway, so it was fetched earlier than listed, into `build/phase17/libmpv-rtx` (git-ignored), and used for the local runs. Windows needs a backslash `MPV_KIT_LIBMPV_PATH` and the bundle `lib` dir on PATH.

**2. [Design choice] `lastControllerFrame` check.** The plan asks for a bounded presented check on the last controller. That controller is created unsized (as in D-05), and an unsized controller never renders, so the check would be vacuous. The soak therefore calls `setSize(1280, 720)` on it first and then waits (still bounded to 30 s and record-only). It reads `not-presented` on CI and locally, consistent with the open second-controller finding.

**3. [Plan item not needed] release dispatch and files.** No `release.yml` dispatch (build-relevant paths unchanged since 15f61ff), so `tools/release_gate.sh` and `evidence/release-runs.txt` were not created; the third Task 3 check takes its `reused_from=phase16` branch.

**4. [Process] Plan order and formatting.** Task 3 step 4 (product test code) was committed before the provenance record as the plan requires. `dart format` was applied to the three new Dart files in `example/`; `uhd_endurance_test.dart` was edited by hand only, not run through the newer formatter, so unrelated lines stay untouched.

**5. [Drift adaptation, planned by orchestrator]** The plan predates the FIFO ready queue; none of its tasks touch the native renderer, so ring and present-timeout facts did not matter and `golden-freeze-17.sha256` was not touched.

## Observations for 17-04

- `Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory` summed over every instance of a pid gave 9517.6 MiB for `dwm` on this hybrid laptop while the adapter sum is 2994.6 MiB. The instance semantics (several luid/phys instances per pid, possibly counting both GPUs) are not validated for the example process; the first `--vram` run of 17-04 shows it, and `vram_verdict.dart` only compares a run against itself, so a constant offset does not change the verdict.
- `adapter_dedicated_mib` is the sum over both adapters (iGPU and RTX), as the plan specifies.
- The soak's RSS curve on Windows/RTX is not the memory record there (dedicated VRAM is); the SOAK line still prints it.

## Known Stubs

None.

## Threat Flags

None. `rtx_run.sh` and `vram_sample.ps1` read process names, GPU counters and event logs only; the foreground process name lands in evidence files (T-17-10, accepted in the plan).

## Self-Check: PASSED

- Files exist: `soak_memory.dart`, `soak_memory_test.dart`, `backend_soak_test.dart`, `rtx_run.sh`, `vram_sample.ps1`, `vram_verdict.dart`, `rtx-prep.txt`, `dryrun.txt`: FOUND.
- Commits 2296c9a, b1d2b85, 3fb6e11, 9ae347f, cbdab03 are ancestors of HEAD and of origin/feat/mpv-master-upgrade: FOUND.
- Rule and tests (2296c9a) precede any measured run and every 17-04 artifact in git log order.
