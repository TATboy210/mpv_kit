---
phase: 06-cross-platform-verification
plan: 03
subsystem: ci-hygiene
tags: [matrix, honesty]
requires:
  - phase: 06-02
    provides: "The integration-test job the matrix guard must not flag"
provides:
  - "All Intel-VM continue-on-error steps converted to explicit if-skips with documented environment reasons (native-verify 1 + release.yml 2)"
  - "tools/check_matrix.py: six-target matrix completeness + continue-on-error audit (two documented exceptions), wired into the first CI job, tamper-proven"
affects: [phase-close]
actuals:
  tokens: 18000
  tasks: 1
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Explicit if-skip over continue-on-error: the skip is visible in the run record; capable runners stay strict"
key-files:
  created:
    - tools/check_matrix.py
  modified:
    - .github/workflows/native-verify.yml
    - .github/workflows/release.yml
key-decisions:
  - "Two continue-on-error exceptions are codified in the audit: the msys2 setup retry (immediate second attempt; double failure fails the job) and the informational vulkaninfo tail"
patterns-established: []
requirements-completed: [VERIFY-02]
coverage:
  - id: D6
    description: "Six targets present in both tiers; no unauthorized continue-on-error; audit green and tamper-proven (windows-arm64 rename → exit 1)"
    requirement: VERIFY-02
    verification:
      - kind: automated
        ref: "python tools/check_matrix.py (green; tamper red/green recorded)"
        status: pass
    human_judgment: false
  - id: D7
    description: "Intel-VM steps are explicit if-skips with comments; release.yml has zero continue-on-error"
    requirement: VERIFY-02
    verification:
      - kind: automated
        ref: "grep: release.yml continue-on-error = 0; native-verify actual uses = 2 (both allowed by the audit)"
        status: pass
    human_judgment: false
duration: 20 min
completed: 2026-10-24
status: complete
plan_head_before: df25c74
plan_head_after: 2522d26
commits: 1
---

# Phase 06 Plan 03: Six-Target Matrix Hygiene Summary

**The matrix is complete, honest, and guarded; continue-on-error survives only as two documented patterns.**

## Performance

- Duration: 20 min; Tasks: 1/1; Commits: 1
- Token estimate 28000 vs realized ~18000

## Accomplishments

- Three Intel-VM steps → `if: matrix.runner != 'macos-15-intel'` with environment-limitation comments (native-verify render smoke; release render smoke + packaged-bundle test).
- msys2 retry + vulkaninfo documented in place and codified as the only allowed continue-on-error uses.
- `tools/check_matrix.py` (matrix completeness for both tiers + continue-on-error audit) wired into the patch-drift job; tamper-proven.

## Task Commits

1. `2522d26` — ci: six-target matrix audit; Intel-VM skips made explicit (VERIFY-02)

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| First tamper attempt didn't match the YAML indentation (no-op) | corrected tamper (windows-arm64→arm99): exit 1 with drift message; restored: green |

## Deviations from Plan

- None.

## Verification Results

- check_matrix green; tamper red/green; both workflows YAML-valid; release.yml continue-on-error count 0.

## Self-Check: PASSED

- Artifacts exist; commit `2522d26` is an ancestor of HEAD.
