---
phase: 05-build-provenance-repository-hygiene
plan: 01
subsystem: build-provenance
tags: [patches, ci, provenance]
requires:
  - phase: none
    provides: "Existing native/patches set and native-verify.yml"
provides:
  - "tools/check_patches.sh: mechanical proof that base(MPV_VERSION) + patches == native/mpv, tamper-proven"
  - "Regenerated patch set: 0004+0005 merged, new 0008 vendor-integration patch — base+patches is now byte-identical to the vendor tree"
  - "native-verify.yml patch-drift job (cheapest first job)"
affects: [05-03]
actuals:
  tokens: 66000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "LF-pinned temp clone: git -c core.autocrlf=false at clone AND config core.autocrlf false in the new repo (the -c form does not persist; the later checkout would CRLF-convert everything)"
    - "GNU patch --no-backup-if-mismatch + .orig/.rej cleanup before diffing"
key-files:
  created:
    - tools/check_patches.sh
  modified:
    - native/patches/UPSTREAM.md
    - native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch
    - native/patches/0008-vendor-integration-fixes.patch
    - .github/workflows/native-verify.yml
key-decisions:
  - "The patch set was REGENERATED from the vendored tree rather than accepting a soft semantic gate: the old 0004 carried 5 hand-rebase hunks that exist only in the vendored tree, so verbatim application could never equal vendor"
  - "0004+0005 merged (overlapping files render_vk.h/vo_libmpv.c); 0005 removed; 0006/0007 keep historical numbers"
  - "New 0008 carries the no-owner deltas (io.c mode 0600->0666, wayland_common.c pre-refactor snapshot, MPV_VERSION stamp) — explicit and documented instead of silently excluded"
  - "The gate deletes the stray local native/mpv/.code-review-graph directory (tool artifact, untracked)"
patterns-established:
  - "PATCH-DRIFT OK/FAIL one-line verdict format"
requirements-completed: [BUILD-01]
coverage:
  - id: D1
    description: "Clean run: PATCH-DRIFT OK base=fd9265a905... patches=7"
    requirement: BUILD-01
    verification:
      - kind: automated
        ref: "bash tools/check_patches.sh — exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Tamper: one-line vendor edit -> exit 1; restore -> OK"
    requirement: BUILD-01
    verification:
      - kind: automated
        ref: "Tamper test on native/mpv/MPV_VERSION (exit 1 / restore OK)"
        status: pass
    human_judgment: false
  - id: D3
    description: "patch-drift is the first job in native-verify.yml; YAML valid"
    requirement: BUILD-01
    verification:
      - kind: automated
        ref: "grep + yaml.safe_load"
        status: pass
    human_judgment: false
duration: 75 min
completed: 2026-10-24
status: complete
plan_head_before: 2d4e2c9
plan_head_after: d3fd648
commits: 1
---

# Phase 05 Plan 01: Patch Drift Gate Summary

**base(MPV_VERSION) + patches == native/mpv is now mechanically proven, CI-gated, and tamper-tested — the patch set was regenerated from the vendored tree to make it true.**

## Performance

- Duration: 75 min; Tasks: 2/2; Commits: 1
- Token estimate 40000 vs realized ~66000 (the vendor-tree drift investigation)

## Accomplishments

- `tools/check_patches.sh`: blobless clone (LF-pinned), patch -p1 application, `diff -r` against `native/mpv`, `PATCH-DRIFT OK/FAIL` verdict.
- Patch set regenerated: 0004+0005 merged (579-line patch), 0008 added (84-line integration patch); old 0004/0005 removed; UPSTREAM.md documents the new set and the gate.
- native-verify.yml: `patch-drift` first job.

## Task Commits

1. `d3fd648` — build: patch-drift gate — regenerated patch set proves base+patches == vendor (BUILD-01)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Drift script | first run: 0004 rejects 5/13 hunks (hand-rebase only in vendor); then 575k-line CRLF diff exposed the autocrlf leak | PATCH-DRIFT OK |
| Tamper | exit 1 on a vendor edit | OK after restore |

## Files Created/Modified

- Created: `tools/check_patches.sh`. Modified: `native/patches/UPSTREAM.md`, patch 0004 (regenerated), patch 0008 (new), 0005 (removed), `native-verify.yml`.

## Decisions Made

- See key-decisions. The regeneration over the plan's original "explicit exclusion list" idea: reality showed the vendor tree carries hand-rebase + no-owner deltas that must live IN the patches for the gate to be honest.

## Deviations from Plan

1. `[Rule 1 - vendor reality]` Found during: task 1 RED run. Issue: the vendor tree is NOT base+old-patches (0004's 5 hand-rebase hunks; io.c mode change; stale wayland snapshot; version stamp) — the planned exclusion-list approach would have papered over real drift. Fix: regenerated the patch set (0004+0005 merged, 0008 added) so base+patches == vendor byte-for-byte; UPSTREAM.md documents it; ROADMAP's 0001..0007 wording updated. Committed in: `d3fd648`.
2. `[Rule 1 - autocrlf]` Found during: task 1 GREEN attempts. Issue: `git -c core.autocrlf=false clone` does not persist into the new repo; the later `checkout --detach` CRLF-converted the tree (575k-line phantom diff). Fix: `git config core.autocrlf false` inside the clone before checkout. Committed in: `d3fd648`.
3. `[Rule 1 - patch artifacts]` Found during: task 1. Issue: GNU patch leaves .orig/.rej files that pollute the diff. Fix: `--no-backup-if-mismatch` + post-apply cleanup. Committed in: `d3fd648`.

## Issues Encountered

- Short shas are invalid fetch refs (blobless clone): fetch master first, resolve locally, fall back to all-refs.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-05-01/02 mitigated; T-05-SC not triggered.

## Verification Results

- `bash tools/check_patches.sh` → PATCH-DRIFT OK; tamper test exit 1/OK; YAML OK.

## Next Phase Readiness

- 05-02 (hygiene) and 05-03 (consistency) are independent of this gate.

## Self-Check: PASSED

- Artifacts exist; commit `d3fd648` is an ancestor of HEAD; commit count measured.
