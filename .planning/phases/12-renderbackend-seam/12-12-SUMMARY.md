---
phase: 12-renderbackend-seam
plan: 12
subsystem: video-output
tags: [phase-close-out, ci-gate, audit, golden-freeze, rtx-4060, uhd-4k, endurance, impeller, soak-harness, regression, verification-tiers]

requires:
  - phase: 12-04
    provides: "pre-refactor RTX 4060 baseline and the verbatim harness commands/attempt rules"
  - phase: 12-08
    provides: "pre-move reference (after fix): postfix-runs.txt and the rendered 4K 600 s reference"
  - phase: 12-09
    provides: "RenderBackend move of the Vulkan and software backends"
  - phase: 12-10
    provides: "wire names and MPV_KIT_VIDEO_API; deferred CI gates eec251c / 598d287"
  - phase: 12-11
    provides: "swap reporting and render_context_free on the render thread; deferred CI gates c4019dc / c3edb9e"
provides:
  - "Final-HEAD hosted CI full gate CI-GATE-ok on a3dc4c2 (native-verify 40421971121, flutter-plugin 40421971099; all 15 jobs success)"
  - "The four deferred gates closed CI-GATE-ok: 12-10 eec251c and 598d287, 12-11 c4019dc and c3edb9e"
  - "evidence/final-audit.txt: golden_freeze, constants, api_freeze, enum_line, dart_surface, build_files, docs_env, all ok"
  - "RTX 4060 post-move record (evidence/final-runs.txt + final-*.log/.trace/.fg.txt): 4K 30 min parity with Phase 4, rendered 4K 600 s vs 12-08, identity on/off, six harness groups no-new-failure"
  - "docs/perf/renderbackend-seam-regression.md with ## Verification tiers (Linux real GPU and macOS real hardware 未验证)"
  - "User approval of the Phase 12 close (task3_verify line) and a pending todo for the second-controller first-frame finding"
affects: [13, 14, 15, 16, 17]

actuals:
  tokens: 17517      # chars/4 over the hand-written files (final-runs.txt, final-audit.txt, ci-runs.txt, regression doc, todo); raw run logs/traces/fg samples add ~293300 more (310823 total over the whole diff)
  tasks: 3
  commits: 11        # git rev-list --count f8d8715..cf09349 (excludes this SUMMARY and the state commit)
plan_head_before: f8d87150559546fb83606a9e331ad0d0bc4e22e7
plan_head_after: cf093492f15ddac9b04ee9dd8868c751010da47f

tech-stack:
  added: []
  patterns:
    - "Phase close-out = one full CI gate on the final HEAD (--jobs-success '.') plus re-runnable one-line-per-item audits"
    - "Every real-hardware run passes a recorded gate first (desktop, GPU contention, stray processes, native path == final_sha, free disk). A failed gate halts, and the user decides what happens next. The executor deletes nothing."
    - "Ledger lines are append-only. Text lost to the ASCII filter is restored in a separate *_fix line, never by editing in place."

key-files:
  created:
    - .planning/phases/12-renderbackend-seam/evidence/final-audit.txt
    - .planning/phases/12-renderbackend-seam/evidence/final-runs.txt
    - .planning/phases/12-renderbackend-seam/evidence/final-uhd-4k.log
    - .planning/phases/12-renderbackend-seam/evidence/final-uhd4k-rendered.log
    - .planning/phases/12-renderbackend-seam/evidence/final-identity-on.log
    - .planning/phases/12-renderbackend-seam/evidence/final-identity-off.log
    - .planning/phases/12-renderbackend-seam/evidence/final-d05-on.log
    - .planning/phases/12-renderbackend-seam/evidence/final-d05-on-a2.log
    - .planning/phases/12-renderbackend-seam/evidence/final-d05-on-a2.trace
    - .planning/phases/12-renderbackend-seam/evidence/final-d05-off.log
    - .planning/phases/12-renderbackend-seam/evidence/final-d05-off.trace
    - .planning/phases/12-renderbackend-seam/evidence/final-cycles-on.log
    - .planning/phases/12-renderbackend-seam/evidence/final-cycles-off.log
    - .planning/phases/12-renderbackend-seam/evidence/final-resize-front-on.log
    - .planning/phases/12-renderbackend-seam/evidence/final-resize-front-on.trace
    - .planning/phases/12-renderbackend-seam/evidence/final-resize-front-off.log
    - .planning/phases/12-renderbackend-seam/evidence/final-resize-front-off.trace
    - docs/perf/renderbackend-seam-regression.md
    - .planning/todos/pending/2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md
  modified:
    - .planning/phases/12-renderbackend-seam/evidence/ci-runs.txt

key-decisions:
  - "Task 3: user reply \"approved\". Phase 12 closes on the recorded data."
  - "4K 30 min is not repeated despite two Modern Standby intervals (00:35:45Z-00:36:43Z, 00:40:14Z-00:40:33Z). The in-interval samples show 0 drops and 30 fps, and every gate item matches Phase 4."
  - "d05-on attempt 1 is invalid: it passed a repo-relative trace path and measured nothing. Attempt 2 is the record."
  - "Rendered 4K avsyncPeakAbs is marked worse (1.34e-05 -> 1.62e-05 s, +2.8 us; the plan sets no threshold). The user accepted it as negligible."
  - "The open finding (resize-front round-2 timeout on a fresh second controller; d05 part-2 pixel probe before-first-frame / fpsAtProbe null) is carried forward as a todo. Phase 12 does not fix it."
  - "windows-2025 golden_vk, golden_vk_fallback and golden_vk_retire_twice are gated OK-or-SKIP (12-07 user decision 2 = a; the hosted runner has no Vulkan ICD and observed SKIP exit 77)"

patterns-established:
  - "A failed disk precondition halts every remaining run. Only the user (or the orchestrator on the user's word) frees space."

requirements-completed: [RBE-01, RBE-04, RBE-05, RBE-06]

coverage:
  - id: D1
    description: "Final-HEAD hosted CI full gate: every native-verify and flutter-plugin job success; native tests OK on linux/macos/sanitizers (windows-2025 golden_vk family OK-or-SKIP); INTEGRATION and INTEGRATION-SOAK lines on ubuntu, windows and macos"
    requirement: RBE-04
    verification:
      - kind: integration
        ref: "ci_gate.sh --jobs-success '.' ... on a3dc4c2 (native-verify 40421971121, flutter-plugin 40421971099): CI-GATE-ok gate_rc=0 (evidence/ci-runs.txt)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Deferred gates closed: 12-10 eec251c / 598d287 and 12-11 c4019dc / c3edb9e"
    requirement: RBE-05
    verification:
      - kind: integration
        ref: "evidence/ci-runs.txt gate lines plan=12-10 task=1/2 and plan=12-11 task=1/2: CI-GATE-ok gate_rc=0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Seven close-out audits ok and re-runnable (golden freeze 5/5, CONSTANTS ok, API frozen vs 3a5f450, enum line, Dart surface, build files, docs/env)"
    requirement: RBE-04
    verification:
      - kind: other
        ref: "evidence/final-audit.txt; sha256sum -c evidence/golden-freeze.sha256 && tools/constants_audit.sh && git diff --quiet 3a5f450 HEAD -- packages/mpv_kit/lib packages/mpv_kit/test/api_freeze_test.dart"
        status: pass
    human_judgment: false
  - id: D4
    description: "RTX 4060 4K 30 min (non-rendering Phase 4 command) at parity with Phase 4 on every gate item"
    requirement: RBE-04
    verification:
      - kind: manual_procedural
        ref: "evidence/final-runs.txt run=uhd4k attempt=1 and compare uhd4k lines; final-uhd-4k.log"
        status: pass
    human_judgment: true
    rationale: "Two Modern Standby intervals occurred during the run. Only a human could judge whether the run stays valid. The user approved it at Task 3."
  - id: D5
    description: "RTX 4060 rendered 4K 600 s vs the 12-08 reference: drops 0/0, vo-delayed 0, renderErrors 0, deviceLost false; avsyncPeakAbs +2.8 us"
    requirement: RBE-05
    verification:
      - kind: manual_procedural
        ref: "evidence/final-runs.txt run=uhd4k-rendered attempt=1 and compare uhd4k-rendered lines; final-uhd4k-rendered.log (\"rendered\":true)"
        status: pass
    human_judgment: true
    rationale: "One item is marked worse and the plan sets no threshold for it. The user accepted it as negligible at Task 3."
  - id: D6
    description: "Six harness groups (d05 / cycles / resize-front x Impeller on/off) vs the pre-move reference (after fix): all no-new-failure, no RSS flag"
    requirement: RBE-01
    verification:
      - kind: manual_procedural
        ref: "evidence/final-runs.txt compare d05-on/d05-off/cycles-on/cycles-off/resize-front-on/resize-front-off verdict=no-new-failure"
        status: pass
    human_judgment: true
    rationale: "Real-hardware runs on the single RTX 4060, judged against a reference that is itself inconclusive (resize-front) or failed (d05, pixel probe only). The user approved the verdicts at Task 3."
  - id: D7
    description: "Verification tiers stated honestly: hosted CI = render path only; RTX 4060 = only real-hardware tier; Linux real GPU and macOS real hardware 未验证"
    requirement: RBE-04
    verification:
      - kind: other
        ref: "docs/perf/renderbackend-seam-regression.md ## Verification tiers"
        status: pass
    human_judgment: true
    rationale: "Whether a claim is honest is a human judgment. The orchestrator checked the section, and the user approved it."

duration: 2h 20m
completed: 2026-10-27
status: complete
---

# Phase 12 Plan 12: Phase Close-out (CI full gate, audit, RTX 4060 regression) Summary

**The final Phase 12 HEAD passes the full hosted CI gate (15/15 jobs) and seven re-runnable audits. On the RTX 4060, 4K 30 min matches Phase 4 on every gate item, rendered 4K 600 s keeps 0 drops and 0 vo-delayed frames against 12-08, and all six harness groups show no new failure. The user approved the Phase 12 close.**

## Performance

- **Duration:** about 2h 20m (most of it real-hardware runs and two disk halts)
- **Started:** 2026-10-26T23:45:14Z (Task 1 audit)
- **Completed:** 2026-10-27T02:05Z
- **Tasks:** 3 of 3 (Task 3 approved by the user)
- **Files modified:** 29 (all evidence, docs or todo; no code)

## Accomplishments

- **Task 1, CI and audit:**
  - The final-HEAD full gate on `a3dc4c2` is CI-GATE-ok: native-verify `40421971121` and flutter-plugin `40421971099`, all 15 jobs success. The code tree is identical to `c3edb9e`.
  - The integration reasons on that run were:
    - ubuntu: `vulkan (gpu-next) on llvmpipe`
    - windows: `software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; vulkan/gpu unavailable: vkCreateInstance failed`
    - macos: `vulkan (gpu-next) on Apple Paravirtual device`
    - INTEGRATION-SOAK on all three platforms: `{"resizeEvents":30,"cycles":10,"renderErrors":0,"deviceLost":0}`
  - mpv_kit_video coverage is 91.4%.
  - The four deferred gates are now closed CI-GATE-ok: 12-10 `eec251c` and `598d287`, and 12-11 `c4019dc` and `c3edb9e`.
  - All seven audits are ok: `golden_freeze`, `constants`, `api_freeze`, `enum_line`, `dart_surface`, `build_files` and `docs_env`.
- **Task 2, RTX 4060 runs.** All ran on `final_sha` `d04ab96`, with the native path equal to it before every run and unchanged afterwards. Golden freeze was 5/5 OK after the runs.
  - **4K 30 min** (Phase 4 command, non-rendering): full 1800 s, exit 0.
    - frame-drop 0, decoder-drop 0, vo-delayed 0/0.
    - avsync peak 4.45e-05 s (Phase 4: 4.74e-05 s); total-avsync-change -0.0333 s; estimated-vf-fps 30.0.
    - renderErrors 0, deviceLost false.
    - All gate items are `same`. RSS was +8 MB (not a gate item). The run conditions differ because of two Modern Standby intervals.
  - **Rendered 4K 600 s** (`"rendered":true`): drops 0/0, vo-delayed 0/0, renderErrors 0, deviceLost false and vf-fps 30.0, all `same`. avsyncPeakAbs is `worse` (1.34e-05 to 1.62e-05 s). RSS is -13.5 MB, which is better.
  - **Identity:** Impeller on prints 1 `Using the Impeller rendering backend` line, and off prints 0. Both match the reference.
  - **Harness groups:** all six are `no-new-failure`.
    - d05 on (attempt 2) and off: `failed` on the pixel probe only, 100/100 rounds. RSS is 1.13x and 1.23x the reference.
    - cycles on and off: complete 100/100 with 0 failures. RSS is 0.95x and 0.58x the reference, under the 2x flag.
    - resize-front on and off: `inconclusive` 1 of 5 rounds, with the same round-2 StateError as the reference.
  - Forensics found nothing after all 9 recorded runs.
  - `docs/perf/renderbackend-seam-regression.md` is written, including `## Verification tiers`.
- **Task 3, approval:** the user replied "approved". The decisions are recorded in the `task3_verify=` ledger line and below.

## Task Commits

1. **Task 1: Final-HEAD CI full gate and phase audit:** `a3dc4c2` (audit), `d04ab96` (deferred gates and full gate green)
2. **Task 2: RTX 4060 runs and regression document:** `c4214c0` (disk halt), `7007447` (uhd4k), `3a19587` (uhd4k-rendered), `4d46d70` (identity, d05-on, second disk halt), `b1e3cd2` (d05-off), `53bdf8c` (cycles), `86f44f6` (resize-front and post-run checks), `3b9ba73` (regression report)
3. **Task 3: Human verification (approved):** `cf09349` (task3_verify line and carried-forward todo)

**Plan metadata:** this SUMMARY commit, then the STATE/ROADMAP/REQUIREMENTS commit.

## Files Created/Modified

- `.planning/phases/12-renderbackend-seam/evidence/final-audit.txt`: seven audit items, one line each.
- `.planning/phases/12-renderbackend-seam/evidence/ci-runs.txt`: the four deferred gate lines, the final-HEAD gate, the integration lines and coverage.
- `.planning/phases/12-renderbackend-seam/evidence/final-runs.txt`: the gate, run, forensics and compare lines for every attempt; the halt and resume lines; the observations; and `task3_verify`.
- `.planning/phases/12-renderbackend-seam/evidence/final-*.log`, `final-*.trace` and `final-*.fg.txt`: raw run output, smoke traces and 2 s foreground samples.
- `docs/perf/renderbackend-seam-regression.md`: the post-move regression report and the verification tiers.
- `.planning/todos/pending/2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md`: the open finding, carried forward.

## Decisions Made

All decisions below were given by the user at Task 3 ("approved"), against the orchestrator's presentation.

**What the orchestrator checked:**
- The ledger `run=` lines match the report (results, RSS, rounds).
- Forensics found nothing in all 9 recorded runs.
- Golden freeze is 5/5.
- Verification tiers marks Linux real GPU and macOS real hardware as 未验证.

**What the user confirmed:** the 4K 30-min run conditions (window visible, desktop unlocked, no other GPU load).

**Decisions:**
1. **Do not repeat uhd4k.** Two Modern Standby intervals occurred (Kernel-Power 506/507: 00:35:45Z-00:36:43Z, 58 s; 00:40:14Z-00:40:33Z, 19 s). The in-interval samples still show 0 drops and 30 fps, and every gate item matches Phase 4.
2. **d05-on attempt 1 is invalid.** It passed a relative trace path and measured nothing. Attempt 2 is the record.
3. **avsyncPeakAbs `worse` is accepted.** The change is 1.34e-05 to 1.62e-05 s, +2.8 µs, and the plan sets no threshold. The user judged it negligible.

**Harness:** all six groups are `no-new-failure`, with no flags.

**Phase conclusion:** approved. Close Phase 12.

**Carried forward, not fixed here** (todo `2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md`, also in the STATE.md concerns):
- The resize-front round-2 timeout on a fresh second controller (`resizeEvents=3`, 30 s wait).
- The d05 part-2 pixel probe reads `before-first-frame`, `fpsAtProbe null`.
- Both appear pre-fix (12-04), post-fix (12-08) and post-move (12-12).

**Recorded as unexplained:**
- The Modern Standby intervals during uhd4k.
- Free space on the temp filesystem fell from 6523 to 4141 MiB during the runs. This filesystem is not gated, and the cause is unknown.

## Deviations from Plan

### Halts and user actions

**1. Disk precondition halt before the first run (Task 2)**
- **Found during:** Task 2, gate `run=uhd4k attempt=1` at 00:27:28Z.
- **Issue:** D: had 975 MiB free, below the plan minimum of 5.5 GB (5632 MiB). Every other gate item passed.
- **Action:** halted with no run started. The user replied "只删 flutter_build 缓存" (delete only the flutter_build cache). The orchestrator deleted the git-ignored `example/.dart_tool/flutter_build` (about 4.8 GB), leaving 5865 MiB free. The executor deleted nothing. Runs resumed at uhd4k attempt 1.
- **Committed in:** `c4214c0` (halt), `7007447` (resume line)

**2. Second disk halt at d05-off (Task 2)**
- **Found during:** Task 2, gate `run=d05-off attempt=1` at 01:29:42Z.
- **Issue:** D: had 5630 MiB free, 2 MiB below the minimum. Each launch had used about 39 MiB, as each run configuration rebuilt its `flutter_build` cache.
- **Action:** halted with the remaining five runs not started. The user freed space and replied "continue". D: then had 8003 MiB free, and `build/golden-local` was gone. The executor deleted nothing.
- **Committed in:** `4d46d70` (halt), `b1e3cd2` (resume)

### Invalidated attempt

**3. d05-on attempt 1 used a relative trace path (executor error)**
- **Found during:** Task 2, d05-on.
- **Issue:** `MPV_KIT_SMOKE_TRACE` was passed as a repo-relative path. `flutter test` runs in `example/`, so the harness threw `PathNotFoundException` before any soak round, and the run exited 1.
- **Fix:** recorded the attempt as `invalid run=d05-on attempt=1 reason=command-not-verbatim`, then ran attempt 2 with the absolute path under the same gate. The attempt-1 files are kept. The user confirmed the invalidation at Task 3.
- **Committed in:** `4d46d70`

### Gate text adjustment

**4. Windows golden_vk gate is OK-or-SKIP, not OK**
- **Found during:** Task 1.
- **Issue:** the plan's `<automated>` gate requires `video_renderer_golden_vk +OK` on `windows (windows-2025`. Since 12-07 (user decision 2 = a), the windows-2025 expectation for the golden_vk family is OK or SKIP, because the hosted runner has no Vulkan ICD.
- **Fix:** the final gate checked golden_sw, golden_sw_retire_twice, api_test and affinity_test as OK on windows-2025. It checked golden_vk, golden_vk_fallback and golden_vk_retire_twice as OK-or-SKIP, and SKIP (exit 77) was observed. Every other expectation was as written.
- **Committed in:** `d04ab96`

### Ledger text repairs

**5. UTF-8 text lost by the ledger ASCII filter**
- **Issue:** the ledger writer filtered with `LC_ALL=C tr` and mapped non-ASCII bytes to `?` in two places: the user's quote on the resume line and a Settings window title.
- **Fix:** appended `resume_quote_fix=` and `run_text_fix=` lines with the original text. No line was edited in place. The `task3_verify=` line was written UTF-8-safe; it contains 未验证 and was checked.

---

**Total deviations:** 2 disk halts resolved by the user, 1 invalid attempt (executor error, user-confirmed), 1 gate-text adjustment from an earlier user decision, and 2 ledger text repairs.
**Impact on plan:** none on the conclusions. Every recorded run passed its gate. No run was shortened. No group was dropped or re-run to green.

## Issues Encountered

- **Modern Standby** during the 4K 30-minute run, twice. The cause was not established: the machine was on AC, and the display idle timeout was 3600 s. The user decided not to repeat the run.
- **Open finding** (unchanged across 12-04, 12-08 and 12-12, under both switches):
  - resize-front round 2 on a fresh controller times out 30 s after `set-size-1280-done`.
  - d05 part 2 always probes before the first frame.
  - Both are carried forward as a todo.

## User Setup Required

None. No external service configuration is required.

## Next Phase Readiness

- Phase 12 is closed: RBE-01 through RBE-08 have their evidence in. The RenderBackend seam stands on a baseline that CI and the RTX 4060 show is unchanged in behavior.
- Later phases (14 D3D11, 15 OpenGL) add candidates to `DefaultCandidates` / `Interop::BackendCandidates`, and must keep the golden freeze, `CONSTANTS ok` and API freeze green.
- The second-controller first-frame finding is pending as a todo. A later phase should take it up before relying on the d05 part-2 or resize-front classifications.
- Linux real GPU and macOS real hardware remain unverified.

## Self-Check: PASSED

- FOUND: .planning/phases/12-renderbackend-seam/evidence/final-audit.txt
- FOUND: .planning/phases/12-renderbackend-seam/evidence/final-runs.txt (task3_verify line present)
- FOUND: docs/perf/renderbackend-seam-regression.md
- FOUND: .planning/todos/pending/2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front.md
- FOUND commits on HEAD: a3dc4c2, d04ab96, c4214c0, 7007447, 3a19587, 4d46d70, b1e3cd2, 53bdf8c, 86f44f6, 3b9ba73, cf09349
- Plan verify re-run at close: the Task 1 audit loop and the Task 2 ledger/doc greps pass (see below)

---
*Phase: 12-renderbackend-seam*
*Completed: 2026-10-27*
