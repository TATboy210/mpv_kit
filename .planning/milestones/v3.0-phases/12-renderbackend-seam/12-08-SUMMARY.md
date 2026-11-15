---
phase: 12-renderbackend-seam
plan: 08
subsystem: video-output
tags: [baseline, post-fix, soak, d05, impeller, vulkan, rtx-4060, integration-test, windows, uhd-4k]

requires:
  - phase: 12-04
    provides: "pre-refactor, pre-fix RTX 4060 baseline (baseline-runs.txt, renderbackend-seam-baseline.md) and the run protocol (commands, gate, sampler, forensics)"
  - phase: 12-07
    provides: "publish gate (f77378f), AllocateRing retired-slot fix (e3ef12b), 8K ring fallback after resize (de9dcc5), golden freeze; postfix CI gate ok on de9dcc5"
provides:
  - "docs/perf/renderbackend-seam-baseline.md section '## pre-move reference (after fix)': identity, six-group results table, rendered 4K table, before/after comparison, cycles RSS comparison, soak abort verdict"
  - "evidence/postfix-runs.txt: append-only post-fix ledger (header, gates, halt/resume, seven run= lines, compare lines, forensics, native_unchanged_during_runs, golden_freeze pre/post, task3_verify)"
  - "evidence/postfix-*.log / *.trace / *.fg.txt: raw output, traces and 2 s foreground samples for every run"
  - "First rendered 4K reference on Phase 12 (uhd_endurance_test, 3840x2160, 600 s, rendered=true): drops 0/0, vo-delayed 0, renderErrors 0"
  - "D-05 soak abort verdict resolved-by-fix (across the 12-06+12-07 change set)"
affects: [12-09, 12-12]

actuals:
  tokens: 269700
  tasks: 3
  commits: 4
plan_head_before: 59281b332a5ff0158be95b4083b0099df38c1600
plan_head_after: 42df617c7a8ed028eca44481ca593db3cf3649d1

tech-stack:
  added: []
  patterns:
    - "Post-fix reference reuses the pre-fix protocol verbatim (same commands, SDK, bundle, gate, sampler), so 12-12 can compare same-named run= lines one by one"
    - "A failed pre-run gate halts the remaining runs and appends halt= / resume= lines with the user's verbatim reply; nothing already measured is re-run"

key-files:
  created:
    - .planning/phases/12-renderbackend-seam/evidence/postfix-runs.txt
    - .planning/phases/12-renderbackend-seam/evidence/postfix-identity-on.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-identity-off.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-d05-on.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-d05-on.trace
    - .planning/phases/12-renderbackend-seam/evidence/postfix-d05-off.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-d05-off.trace
    - .planning/phases/12-renderbackend-seam/evidence/postfix-cycles-on.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-cycles-off.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-resize-front-on.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-resize-front-on.trace
    - .planning/phases/12-renderbackend-seam/evidence/postfix-resize-front-off.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-resize-front-off.trace
    - .planning/phases/12-renderbackend-seam/evidence/postfix-uhd4k-rendered.log
    - .planning/phases/12-renderbackend-seam/evidence/postfix-*.fg.txt (7 sampler files)
  modified:
    - docs/perf/renderbackend-seam-baseline.md (new section appended; pre-fix section unchanged)

key-decisions:
  - "D-05 soak abort verdict is resolved-by-fix: the same d05 command aborted in round 1 in all three pre-fix attempts under both switches (exit 79) and completed 100/100 rounds post-fix under both switches (exit 0, forensics none). Attributed to the whole 12-06+12-07 change set, not isolated to one change"
  - "resize-front is NOT counted as resolved-by-fix: the pre-fix shape (process vanishing after set-size-640) is gone, but the run ends inconclusive in round 2 (1 of 5 rounds). The user accepted this as the pre-move reference for both switches; if 12-12 ends the same way it is not a new failure"
  - "The rendered 4K run stays the reference even though the user resized/moved/tapped the window by hand 19:48:05Z-19:49:07Z and TaskBarHero held the foreground from 19:50:45Z (user accepted at Task 3)"
  - "Cycles RSS growth (+66.8 MiB on, +80.8 MiB off over 100 cycles; 0.67-0.81 MiB/cycle) is accepted as comparable to Phase 4 (0.90 MiB/cycle), no amplification"
  - "Go decision: proceed to the move (12-09)"
  - "No requirement completes here: RBE-01 is shared with 12-12 (post-move comparison against this section), RBE-06 is owned by 12-09/12-11/12-12"

patterns-established:
  - "The pre-move reference contains only known, deliberate behavior changes (12-06, 12-07); any 12-12 difference is attributable to the move (Pitfall 11)"

requirements-completed: []

coverage:
  - id: D1
    description: "Six post-fix groups (d05, cycles, resize-front x Impeller on/off) recorded in postfix-runs.txt with compare lines against the 12-04 measured record; native diff vs baseline limited to video_renderer.cc/.h and vulkan_backend.cc; native path unchanged during the runs"
    requirement: RBE-01
    verification:
      - kind: other
        ref: "12-08-PLAN Task 1 verify #2 (postfix_sha, run=d05-on, compare d05-on, native_diff_vs_baseline allow-list)"
        status: pass
      - kind: other
        ref: "12-08-PLAN Task 2 verify #1 (six run=/compare lines, identity_off_matches=0, native_unchanged_during_runs=yes, run=uhd4k-rendered rendered=true)"
        status: pass
    human_judgment: true
    rationale: "Run-condition validity (window visible, desktop unlocked, no other GPU load) is only observable by the user; signed off at the blocking-human Task 3 checkpoint (reply \"approved\")"
  - id: D2
    description: "Baseline doc section '## pre-move reference (after fix)' with results, rendered 4K table, comparison, cycles RSS and soak abort verdict; pre-fix section byte-unchanged; golden freeze 5/5 OK before and after"
    requirement: RBE-01
    verification:
      - kind: other
        ref: "12-08-PLAN Task 2 verify #2 (section heading, verdict token, no deleted lines vs postfix_sha, sha256sum -c golden-freeze.sha256)"
        status: pass
    human_judgment: true
    rationale: "The verdict wording and the acceptance of the resize-front and 4K run conditions are user judgments (Task 3)"
  - id: D3
    description: "Rendered 4K 600 s reference (uhd_endurance_test, MPV_KIT_BENCH_RENDER=1, 3840x2160) for 12-12's same-command comparison"
    requirement: RBE-01
    verification:
      - kind: integration
        ref: "example/integration_test/uhd_endurance_test.dart (postfix-uhd4k-rendered.log, 'All tests passed!', \"rendered\":true)"
        status: pass
    human_judgment: true
    rationale: "Manual window interaction during the run had to be accepted by the user before the run could serve as the reference"

duration: 47min
completed: 2026-10-26
status: complete
---

# Phase 12 Plan 08: Post-fix, pre-move RTX 4060 reference Summary

**The same 12-04 commands, rerun after the 12-06/12-07 fixes, now complete the D-05 soak: 100/100 rounds under both Impeller switches, where every pre-fix attempt aborted in round 1. That gives the verdict `resolved-by-fix`. cycles is 100/100 with lower RSS growth. resize-front no longer loses the process but ends inconclusive in round 2. A first rendered 4K 600 s run passed with 0 drops. The user approved the data and the move to 12-09.**

## Performance

- **Duration:** about 47 min of wall time, including two checkpoint waits (the gate-failure halt and Task 3)
- **Started:** 2026-10-26T19:23:29Z (golden freeze before the runs)
- **Runs:** 19:24:05Z to 19:56:50Z, strictly serial, attempt 1 for every group
- **Completed:** 2026-10-26T20:10Z
- **Tasks:** 3 of 3 (Task 3 approved)
- **Files modified:** 22 (21 evidence files plus 1 doc)

## Accomplishments

- **Post-fix reference recorded.** The six groups ran on `postfix_sha` `59281b3`. Against the 12-04 baseline, the native diff is limited to `video_renderer.cc`, `video_renderer.h` and `vulkan_backend.cc`, which are the 12-06 and 12-07 changes. Every gate reported `native_equal_to_postfix=yes`, and the ledger records `native_unchanged_during_runs=yes`. The golden freeze checked 5/5 OK before and after the runs.
- **Engine identity.** With `--enable-impeller` the log has 1 `Using the Impeller rendering backend` line, and with `--no-enable-impeller` it has 0. In both cases the app ran on `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`.
- **D-05 settled as `resolved-by-fix`.** d05-on finished 100 rounds in 41.898 s and d05-off finished 100 rounds in 41.873 s, both with exit 0 and no crash forensics. Before the fix, both switches stopped at `round=1 step=dispose-begin` with exit 79. The post-fix `result=failed` comes only from the pixel probe (`nonBlackRatio` 0.0, before-first-frame), which read the same in every pre-fix run.
- **Rendered 4K reference.** This is the first rendered 4K run in Phase 12 (Phase 4's 4K gate never called `setSize`). It ran 600 s with `rendered=true`. Frame drops were 0 and decoder drops were 0. vo-delayed was 0.0 on average and 0 at most. Peak |avsync| was 1.34e-05 s, the total avsync change was -0.0333 s, and vf-fps held at 30.0. renderErrors was 0 and deviceLost was false. All 10 per-minute samples were clean.

## Results vs 12-04 (measured record)

| group | switch | before (12-04) | after (12-08) |
|-------|--------|----------------|---------------|
| d05 | on  | aborted, exit 79, 0 rounds, `round=1 step=dispose-begin` | failed (pixel probe only), exit 0, **100/100 rounds, 41.898 s**, RSS +206.7 MiB |
| d05 | off | aborted, exit 79, 0 rounds, `round=1 step=dispose-begin` | failed (pixel probe only), exit 0, **100/100 rounds, 41.873 s**, RSS +191.7 MiB |
| cycles | on  | complete 100/100, +81.8 MiB | complete 100/100, 0 failures, **+66.8 MiB** |
| cycles | off | complete 100/100, +100.6 MiB | complete 100/100, 0 failures, **+80.8 MiB** |
| resize-front | on  | aborted, exit 79, 0 of 5, process vanished after `set-size-640-done` | inconclusive, exit 1, **1 of 5**, round 2 `StateError: no 1280x720 resize` after 30 s, process alive |
| resize-front | off | same as on | inconclusive, exit 1, **1 of 5**, same shape as on |
| uhd4k-rendered | default | n/a (no rendered 4K before) | pass, 600 s, rendered=true, drops 0/0 |

All seven runs recorded `forensics=none`: no crash dumps and no Application event 1000 or 1001 entries.

## Task Commits

1. **Task 1: post-fix Impeller-on identity and D-05 (tracer)**: `cb16665` (test)
2. **Gate failure halt (Deskrawl.exe) before identity-off**: `c22efef` (test)
3. **Task 2: remaining five groups, rendered 4K, doc section "pre-move reference (after fix)"**: `cd28711` (test)
4. **Task 3: user approval recorded in the ledger (`task3_verify=`)**: `42df617` (docs)

**Plan metadata:** the final docs commit (SUMMARY, STATE, ROADMAP).

## Files Created/Modified

- `docs/perf/renderbackend-seam-baseline.md`: a new section `## pre-move reference (after fix)` at the end. The pre-fix section is untouched (verified with zero deleted lines against `postfix_sha`).
- `.planning/phases/12-renderbackend-seam/evidence/postfix-runs.txt`: the append-only machine-readable ledger that 12-12 compares against line by line.
- `.planning/phases/12-renderbackend-seam/evidence/postfix-*.log`, `*.trace`, `*.fg.txt`: raw evidence for each run.

## Decisions Made

See `key-decisions` in the frontmatter. In short:

- **Soak abort verdict.** It is `resolved-by-fix` for D-05, scoped to the 12-06+12-07 change set. The data does not isolate which single change fixed it.
- **resize-front.** It stays `inconclusive` and is accepted as the reference.
- **Rendered 4K run.** It stays the reference even though the window was touched by hand during the run.
- **Cycles RSS.** The growth is accepted as normal.
- **Go decision.** 12-09 proceeds.

## Task 3 approval (user reply verbatim: "approved")

The approval was given on the orchestrator's presentation. It is recorded in `postfix-runs.txt` as a `task3_verify=` line, appended without editing earlier lines.

1. **Table vs ledger:** the orchestrator checked that exit code, result, rounds and RSS in the doc tables match the `run=` lines, and that all seven runs have `forensics=none`.
2. **uhd4k-rendered:** the manual window resize, move and taps (19:48:05Z to 19:49:07Z, `window_interaction_observed=yes`) are accepted, as is the TaskBarHero foreground from 19:50:45Z. The run (pass, frameDrop 0) stays the reference.
3. **Soak abort:** `resolved-by-fix` for D-05 is confirmed. It is credited to the whole 12-06+12-07 change set, not to one isolated change.
4. **resize-front round 2:** the inconclusive ending is accepted as the pre-move reference and kept as an open finding (below).
5. **Cycles RSS:** the growth is comparable to Phase 4 (0.67 to 0.81 MiB per cycle vs 0.90), with no amplification.
6. **nvidia-smi:** the 42% reading at the resize-front-off gate stays recorded as unexplained.
7. **Go decision:** proceed to the move (12-09).

## Deviations from Plan

### Run-condition deviations (no auto-fixes; no code changed)

**1. Gate failure on Deskrawl.exe, then halt and resume**
- **Found during:** Task 2, at the gate before identity-off (19:29:33Z).
- **Issue:** `Deskrawl.exe` was running in the foreground at 9.4% GPU engine (nvidia-smi 34%/2913 MiB). It is a new executable under `steamapps\common`, so the precondition was not met.
- **Action:** the remaining runs were halted and the halt was committed (`c22efef`, `halt=` line). They resumed after the user replied "continue" (`resume=` line, 19:34:06Z). The gate before every later run was unchanged and passed.
- **Effect:** none on d05-on, which had ended at 19:27:42Z. All 47 of its samples showed only TaskBarHero+UnityCrashHandler64, and its post-run gate was ok.

**2. Manual window interaction during the rendered 4K run**
- **What happened:** the window was resized 9 times (19:48:05Z to 19:48:23Z) and moved 4 times (19:49:00Z to 19:49:07Z). The log also has 4 pointer-tap finder blocks. The harness and sampler never touch the window.
- **Resolution:** the user accepted it at Task 3, and the run stays the reference. The renderer's `setSize` is the source size (3840x2160), not the window size, and no gate tripped.

**3. resize-front ends in a new shape, not the one the plan expected**
- **Expected:** the plan's three verdicts assumed a post-fix run either completes or aborts.
- **Observed:** resize-front neither completes nor aborts. Round 1 now passes and is disposed. Round 2 throws a harness `StateError` after the 30 s wait, and the process stays alive.
- **How it was recorded:** it is not counted as `resolved-by-fix`, because the same command did not complete. The reference for 12-12 is `inconclusive`, 1 of 5 rounds, ending at `round=2 step=first-resize-wait-done`.

**4. Ledger SHA on later runs**
- Runs after d05-on were started at HEAD `c22efef`, which differs from `postfix_sha` only in `.planning/` evidence files. Every gate confirmed `native_equal_to_postfix=yes`.

**Total deviations:** 4 run-condition and data-shape deviations, all user-accepted. No auto-fixes, no product or code changes.

## Open Findings (routed, not fixed here)

- **resize-front round 2.** A fresh second controller never gets a 1280x720 resize within 30 s.
  - The wait needs `estimated-vf-fps > 0` **and** a resize event newer than the baseline count. `resizeEvents` was 3 against a baseline of 2, so the likely unmet part is `estimated-vf-fps > 0`.
  - **Candidate link:** in the d05 part 2, the pixel probe always reads "before-first-frame, fpsAtProbe null", both before and after the fix. A second controller in the same process may never receive presented frames.
  - **Routing:** to 12-12 or a separate diagnostic. Recorded in STATE.md Blockers/Concerns.
- **nvidia-smi 42% at the resize-front-off gate.** It is unexplained. The engine-level sampler showed only TaskBarHero at 1.7% and dwm at 0.7%.

## Note for 12-09 (plan text is stale)

12-09-PLAN Task action step 3 still says the publish gate becomes `render_backend_->pipelined() && pending_front_ >= 0` with `render_backend_->Wait(pending_front_)`. It also describes a deferred publish gate inside RenderOnce. 12-07 (`f77378f`) removed that mechanism. The Vulkan publish gate is now a synchronous wait right after the render call, and the pipeline depth is 1. `grep -rn pending_front_ packages/mpv_kit_video/src` returns nothing. 12-09 must move the current gate as it is, as a pure move, instead of rebuilding the `pending_front_` form.

## Issues Encountered

None beyond the deviations above.

## Known Stubs

None. This plan changed no code.

## User Setup Required

None.

## Next Phase Readiness

- 12-09 (the RenderBackend move) can start, with the stale-text note above.
- 12-12 compares its post-move runs against `## pre-move reference (after fix)` and the `run=` lines in `postfix-runs.txt`, never against the pre-fix section.

## Self-Check: PASSED

- FOUND: docs/perf/renderbackend-seam-baseline.md (contains `## pre-move reference (after fix)`, verdict `resolved-by-fix`)
- FOUND: .planning/phases/12-renderbackend-seam/evidence/postfix-runs.txt (postfix_sha, 7 run= lines, 6+1 compare lines, native_unchanged_during_runs=yes, task3_verify)
- FOUND: postfix-uhd4k-rendered.log with `"rendered":true`
- FOUND commits: cb16665, c22efef, cd28711, 42df617 (all ancestors of HEAD)
