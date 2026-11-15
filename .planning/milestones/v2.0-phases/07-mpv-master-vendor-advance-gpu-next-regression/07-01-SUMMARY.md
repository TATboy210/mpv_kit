---
phase: 07-mpv-master-vendor-advance-gpu-next-regression
plan: 01
subsystem: vendor
tags: [rebase, provenance]
requires:
  - phase: 05-01
    provides: "check_patches.sh drift gate + Phase 5 patch-regeneration procedure"
provides:
  - "Vendor advanced to mpv 0.41.0-1115 (gb2c255c13e8e) with exact provenance: snapshot identified by blob-hash walk + FULL-TREE diff=0"
  - "Patch set replayed onto the new base (0001..0007 zero rejects; 0008 regenerated as the version stamp alone); PATCH-DRIFT OK at the new base"
affects: [07-02, 08-*]
actuals:
  tokens: 46000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Zip-snapshot identification: multi-file blob-hash attribution + backwards 12-file full-match walk + full-tree diff verification"
key-files:
  modified:
    - native/mpv/**
    - native/patches/0008-vendor-integration-fixes.patch
    - native/patches/UPSTREAM.md
    - README.md
    - docs/ARCHITECTURE.md
key-decisions:
  - "The advance is a PROVENANCE CORRECTION, not a functional change: the v1 vendor had already absorbed the two commits separating the bases (io.c 0666 + wayland refactor) via misattributed 0008 deltas; the new base label now tells the truth and 0008 shrinks to the version stamp"
  - "Snapshot identified as exactly b2c255c13e8e (2026-10-09): 5-probe forward walk found accb7b28 (newest probe match); the 7 differing files attributed to OLDER commits revealed the snapshot predates accb7b28; backwards 11-file walk pinned b2c255c; full-tree diff = 0"
patterns-established:
  - "UPSTREAM.md per-rebase section (id evidence, superseded deltas, fuzz stats)"
requirements-completed: [REBASE-01]
coverage:
  - id: D1
    description: "Snapshot's exact upstream commit identified and recorded in MPV_VERSION (v0.41.0-1115-gb2c255c13)"
    requirement: REBASE-01
    verification:
      - kind: automated
        ref: "blob attribution logs + full-tree diff COUNT=0 (excl. .git/.code-review-graph)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Patches replay/regenerate: PATCH-DRIFT OK at the new base, 7 patches"
    requirement: REBASE-01
    verification:
      - kind: automated
        ref: "bash tools/check_patches.sh — PATCH-DRIFT OK base=b2c255c13e8e patches=7"
        status: pass
    human_judgment: false
  - id: D3
    description: "CONSISTENCY green with README/ARCHITECTURE updated; UPSTREAM.md records the rebase"
    requirement: REBASE-01
    verification:
      - kind: automated
        ref: "dart run tools/check_consistency.dart — all invariants hold"
        status: pass
    human_judgment: false
duration: 40 min
completed: 2026-10-24
status: complete
plan_head_before: 19642cf
plan_head_after: 9590dca
commits: 1
---

# Phase 07 Plan 01: Vendor Advance Summary

**Vendor provenance made exact at mpv 0.41.0-1115 (gb2c255c13e8e); the advance doubles as a correction of v1's misattributed 0008 deltas.**

## Performance

- Duration: 40 min; Tasks: 2/2; Commits: 1
- Token estimate 60000 vs realized ~46000

## Accomplishments

- Snapshot identification: 5-probe forward walk → accb7b28 (newest probe match); 7-file older-commit attribution revealed the snapshot predates it; backwards 11-file walk → **b2c255c13e8e**; full-tree diff **0** (excluding .code-review-graph junk).
- Vendor replaced (tar transfer, LF-preserved); MPV_VERSION = v0.41.0-1115-gb2c255c13.
- Patch replay in a staged git tree: 0001..0007 zero rejects (fuzz: 0001×3, 0002×1, 0006×2, 0007×3); 0008 regenerated as the version-stamp-only diff; porting-completeness check vs old vendor: **0 other diffs**.
- UPSTREAM.md rebase section (id evidence, superseded deltas, fuzz stats); README/ARCHITECTURE consistency sync.

## Task Commits

1. `9590dca` — build(native): advance vendor to mpv 0.41.0-1115 (gb2c255c13) — provenance made exact (REBASE-01)

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| (planned) MPV_VERSION-first gate run | In the event, the identity finding (vendor ≡ old vendor except MPV_VERSION) made the RED step moot; the gate was proven fresh against the new base post-replay |

## Deviations from Plan

1. `[Rule 1 - reality]` Found during: task 1. Issue: the plan anticipated a 380-line hand-port of 0004; the 380 lines turned out to be OUR patches (snapshot was unpatched) and the true upstream delta between bases is just 2 commits — both already absorbed by the v1 vendor via 0008's misattributed deltas. Fix: replay was mechanical; 0008 shrank to the version stamp; decision documented in UPSTREAM.md and the commit. Committed in: `9590dca`.

## Verification Results

- PATCH-DRIFT OK base=b2c255c13e8e patches=7; CONSISTENCY all hold; full gates green (PINS/MATRIX).

## Self-Check: PASSED

- Commit `9590dca` is an ancestor of HEAD; vendor contains no .code-review-graph.
