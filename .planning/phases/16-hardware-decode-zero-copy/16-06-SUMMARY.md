---
phase: 16-hardware-decode-zero-copy
plan: 06
subsystem: testing
tags: [hwdec, d3d11va, rtx4060, zero-copy, audit]

requires:
  - phase: 16-hardware-decode-zero-copy
    provides: 16-01..16-05 hwdec defaults, probes, verify-tier libmpv and hosted matrix
provides:
  - "RTX 4060 d3d11va zero-copy proof for 4K HEVC Main10 with the D3D11 backend forced (HWD-02 evidence)"
  - "d3d11va-zero-copy no/yes comparison data and an auto-chain information run"
  - "docs/perf/hwdec-zero-copy.md, README libva requirement, 18-item unverified list, final-audit.txt"
affects: [14-11, 17]

status: awaiting-human-check
actuals:
  tokens: 45000
  tasks: 2
  commits: 7
plan_head_before: 77d4ba8
plan_head_after: e40ba3c

key-files:
  created:
    - docs/perf/hwdec-zero-copy.md
    - .planning/phases/16-hardware-decode-zero-copy/evidence/final-audit.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/rtx-hwdec-d3d11.log
    - .planning/phases/16-hardware-decode-zero-copy/evidence/rtx-hwdec-d3d11-a2.log
    - .planning/phases/16-hardware-decode-zero-copy/evidence/rtx-hwdec-d3d11-zero-copy-yes.log
    - .planning/phases/16-hardware-decode-zero-copy/evidence/rtx-hwdec-auto.log
  modified:
    - README.md
    - .planning/phases/16-hardware-decode-zero-copy/evidence/rtx4060-hwdec-runs.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/unverified.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/ci-runs.txt
    - example/integration_test/hwdec_zero_copy_test.dart

key-decisions:
  - "HWD-02 accepted on evidence from the forced d3d11 backend (decision=hwd02-acceptance forced-d3d11, shared session with 14-09)."
  - "ROADMAP.md and REQUIREMENTS.md left untouched; Task 3 human-check (phase16-close) is the user's."

requirements-completed: []

duration: 2 sessions (about 2 h wall including the test fix and rerun)
completed: 2026-10-29
---

# Phase 16 Plan 06: RTX 4060 d3d11va Zero-Copy Acceptance Summary

On the RTX 4060 with the D3D11 backend forced, 4K HEVC Main10 plays with `hwdec-current=d3d11va`, pixelformat `d3d11`, hw-pixelformat `p010`, zero-copy at first frame and end, three screenshot matches against the software reference, no mid-play fallback and no device loss. Plan stops before its Task 3 human-check.

## RTX runs (release run 40812562348 manifest=ok, samples run 40798831729, product ad5c54b, test source f644220)

| Run | Result | Key numbers |
|---|---|---|
| d3d11 attempt 1 | fail (kept) | 4K software-reference leg timed out: the test's ready condition was hard-coded to 640x360; the three 640x360 samples passed (d3d11va, d3d11, nv12/p010) |
| d3d11 attempt 2 | pass | 4K: d3d11va, `d3d11`, `p010`, zero-copy first and end, match x3, flutterFrame match, played to end, hwdec stable, 0/0/0 drops, deviceLost 0; 640x360 samples all zero-copy and match |
| d3d11-zero-copy-yes | pass | 4K: d3d11vaZeroCopy true, d3d11va, p010, match x3 (diff 0.009), 0/0/0; first frame 113 ms vs 154 ms |
| auto (information) | pass | Vulkan backend, hwdec-current vulkan, pixelformat vulkan, p010, match x3 |

A2 pixelformat strings observed: `d3d11` on all four samples (hw-pixelformat nv12 for h264/hevc-8bit, p010 for hevc-10bit and 4K); the classifier table was not edited.

## Deviations from Plan

**1. [Rule 1 - Bug, test] Attempt 1 failure.** `_openAndWaitForFrame` required 640x360. Not edited by the executor; the orchestrator committed f644220 after the user chose "fix the test and rerun", and the whole session was re-run from the start with new log names (`-a2`). Attempt-1 log and fail line are kept.

**2. [Rule 3] Bundle via hooks user_defines** (as the plan's step 4 requires); the same change was applied to 14-09 (deviation recorded in the 14 ledger).

**3. [Rule 1 - Executor bug] Forensics window** was queried with UTC against a local-time filter; corrected and re-queried for every run (ledger lines `correction=...`). No standby or crash in any 16-06 run.

**4. Plan-verify greps.** `rtx-hwdec-d3d11.log` is attempt 1 (fails the 4K check by design and is kept); attempt 2 is `rtx-hwdec-d3d11-a2.log`, which passes the same patterns. `grep '^run=.* result=fail '` also matches the preserved attempt-1 line, so Task 2's "no fail line" check, run literally on the whole ledger, does not pass; the pass lines are `run=d3d11 attempt=2`, `run=d3d11-zero-copy-yes`, `run=auto` (3).

**5. Machine entered Modern Standby between runs** (04:18Z, 04:27Z, 05:00Z-05:22Z); a keep-awake helper was used from then on. It did not prevent a standby during 14-09's first 4K attempt (see the 14-09 summary).

## Task 3 (automated part done, human-check pending)

- docs/perf/hwdec-zero-copy.md (Reproduce, results, no/yes comparison, hosted matrix, `## Verification tiers`), README (libva.so.2 and libva-drm.so.2 host requirement, link to the doc), 9 new unverified items (18 total with 状态=未验证), final-audit.txt with the three audit outputs (golden freeze 5 OK, CHECK-MATRIX ok, CONSTANTS ok) and the HWD/SC mapping. SC3 is 部分证明 with `proposal=SC3-wording ... status=pending-user-approval`.
- The human-check answer (`decision=phase16-close`) is not written; ROADMAP.md and REQUIREMENTS.md are untouched.

## Requirements

Not ticked here (the plan forbids executor edits to REQUIREMENTS.md and the human-check is pending). Evidence status in final-audit.txt: HWD-02 证明 (forced d3d11), HWD-01 证明, HWD-05 证明 (scope A, hosted matrix; macOS videotoolbox screenshot flake noted), HWD-03 部分证明 (vaapi real zero-copy 未验证).

## Self-Check: PASSED

- docs/perf/hwdec-zero-copy.md, final-audit.txt, the four RTX logs and the ledger exist; Task 3's two automated checks were run (doc/README/unverified count and the mapping/proposal patterns).
- Commits 822ef58, a19085b, 0a111b6, e40ba3c are ancestors of HEAD; nothing was pushed (origin at f644220).
