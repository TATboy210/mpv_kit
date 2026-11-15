---
phase: 05-build-provenance-repository-hygiene
plan: 02
subsystem: repo-hygiene
tags: [git, lockfile, docs]
requires:
  - phase: none
    provides: "Working tree with bt/ on disk and the hook bundle as the tested libmpv"
provides:
  - "bt/ untracked (22 DLLs, ~44 MB off the index) and gitignored; working-tree copy preserved"
  - "pubspec.lock committed with a documented policy (workspace lock, CI consumes)"
  - "README: dependency-locking policy + two supported local-libmpv workflows + Git Bash PATH-form note"
  - "No executable bt/ command references left in docs"
affects: [05-03]
actuals:
  tokens: 26000
  tasks: 1
  commits: 1
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - .gitignore
    - pubspec.lock
    - README.md
    - docs/ARCHITECTURE-diagrams.md
    - docs/perf/2026-10-24-baseline.md
    - docs/perf/2026-10-24-single-decode.md
key-decisions:
  - "pubspec.lock policy = committed: workspace + example app + BUILD-02 reproducibility make the lock a build artifact of record; CI resolves against it"
  - "The working-tree bt/ directory is kept (local convenience); only the index and future checkouts drop it"
patterns-established: []
requirements-completed: [BUILD-04]
coverage:
  - id: D9
    description: "bt/ untracked (git ls-files bt/ = 0), gitignored, working-tree copy kept"
    requirement: BUILD-04
    verification:
      - kind: automated
        ref: "git ls-files assertions + test -d bt"
        status: pass
    human_judgment: false
  - id: D10
    description: "pubspec.lock tracked; offline pub get succeeds against it; policy documented in README"
    requirement: BUILD-04
    verification:
      - kind: automated
        ref: "git ls-files pubspec.lock = 1; dart pub get --offline OK; grep .gitignore"
        status: pass
    human_judgment: false
  - id: D11
    description: "Zero remaining executable D:/mpv_kit/bt command references in docs; diagrams entry replaced with the retired note"
    requirement: BUILD-04
    verification:
      - kind: automated
        ref: "grep -rn 'D:/mpv_kit/bt' docs/ README.md = 0"
        status: pass
    human_judgment: false
duration: 18 min
completed: 2026-10-24
status: complete
plan_head_before: 2d4e2c9
plan_head_after: 3666086
commits: 1
---

# Phase 05 Plan 02: Repo Hygiene Summary

**bt/ is off the index (44 MB of stale binaries), the workspace lock is committed with a documented policy, and every doc command now uses the hook-cache libmpv.**

## Performance

- Duration: 18 min; Tasks: 1/1; Commits: 1
- Token estimate 34000 vs realized ~26000

## Accomplishments

- `git rm -r --cached bt/` (22 DLLs); `bt/` gitignored with a pointer to the replacement; working-tree copy preserved.
- `pubspec.lock` committed; `.gitignore` exclusion removed; README gains "Dependency locking" and "Local libmpv for tests" sections (hook bundle default; MPV_KIT_LIBMPV_PATH + PATH explicit; bt/ retirement rationale; Git Bash POSIX PATH-form note added during 05-03's debugging).
- `docs/ARCHITECTURE-diagrams.md` bt/ tree entry → retired note; both perf docs' command lines → hook-cache path.

## Task Commits

1. `3666086` — chore: repo hygiene — untrack stale bt/ DLLs, commit pubspec.lock with a documented policy (BUILD-04)

## TDD Gate Compliance

- Mechanical assertions only (git ls-files, offline pub get, doc greps) — all pass.

## Files Created/Modified

- Modified: `.gitignore`, `README.md`, `docs/ARCHITECTURE-diagrams.md`, two perf docs. Added: `pubspec.lock`.

## Decisions Made

- Lock committed; working-tree bt/ kept.

## Deviations from Plan

- None.

## Issues Encountered

- None.

## User Setup Required

- None. (Other clones: `git pull` removes bt/ from their index; local copies stay until deleted manually.)

## Known Stubs

- None.

## Threat Flags

- T-05-03/04 mitigated; T-05-SC not triggered.

## Verification Results

- All git assertions pass; `dart pub get --offline` OK; doc greps clean.

## Next Phase Readiness

- 05-03's docs edits layered on this cleanly.

## Self-Check: PASSED

- Artifacts exist; commit `3666086` is an ancestor of HEAD; commit count measured.
