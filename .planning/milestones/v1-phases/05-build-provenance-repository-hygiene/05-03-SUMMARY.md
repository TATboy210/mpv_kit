---
phase: 05-build-provenance-repository-hygiene
plan: 03
subsystem: consistency
tags: [versions, pins, release]
requires:
  - phase: 05-01
    provides: "The patch-drift gate (checker style precedent)"
  - phase: 05-02
    provides: "The committed lock and README structure the checker validates"
provides:
  - "tools/check_consistency.dart: 8 mechanical invariants (mpv version mentions, macOS target, sdk constraints, README floor, FFmpeg version, provenance date), tamper-proven"
  - "All discovered drift fixed to the truth sources (podspec 12.0, sdk ^3.10.0 ×5, README exact version, ADR gap section, rev-eng date)"
  - "tools/pin_bundles.dart --check: bundles.dart pins verified against the live release's SHA256SUMS (PINS OK tag=v0.1.0-dev.3 targets=6), wired into native-verify"
  - "release.yml publish job self-verifies SHA256SUMS ↔ tar ↔ MANIFEST before creating the release"
affects: [phase-6-cross-platform-verification]
actuals:
  tokens: 58000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Exact-shape anchoring: each invariant checks a specific file/line form, so drift is detectable and fixes are unambiguous"
    - "Caret/-dev-aware version scanning (package versions vs libmpv stamps)"
key-files:
  created:
    - tools/check_consistency.dart
  modified:
    - tools/pin_bundles.dart
    - .github/workflows/native-verify.yml
    - .github/workflows/release.yml
    - README.md
    - docs/adr/0002-use-vendored-mpv-with-vulkan-render-backend.md
    - docs/reverse-engineering/01-libmpv-render-pipeline.md
    - packages/mpv_kit_video/macos/mpv_kit_video.podspec
    - pubspec.yaml
    - packages/mpv_kit/pubspec.yaml
    - example/pubspec.yaml
key-decisions:
  - "ADR-0002's stale 'Known gaps' (Homebrew bottles / macOS 15) was superseded by the from-source release tier; the section now records that and points at the patch-drift gate instead of being deleted"
patterns-established: []
requirements-completed: [BUILD-03]
coverage:
  - id: D12
    description: "Checker green on the fixed tree; tamper-proven (sdk edit -> exit 1 with FAILs, restore -> green)"
    requirement: BUILD-03
    verification:
      - kind: automated
        ref: "dart run tools/check_consistency.dart — all invariants hold; tamper run had 2 FAILs"
        status: pass
    human_judgment: false
  - id: D13
    description: "Drift fixed: podspec 12.0, sdk ^3.10.0 ×5, README exact vendor version, ADR-0002 rewritten, rev-eng date corrected"
    requirement: BUILD-03
    verification:
      - kind: automated
        ref: "checker invariants + git diff"
        status: pass
    human_judgment: false
  - id: D14
    description: "pin_bundles --check green against the live release (PINS OK tag=v0.1.0-dev.3 targets=6) and wired into native-verify"
    requirement: BUILD-02
    verification:
      - kind: automated
        ref: "dart run tools/pin_bundles.dart --check"
        status: pass
    human_judgment: false
  - id: D15
    description: "release.yml publish self-verifies SHA256SUMS ↔ tar ↔ MANIFEST before gh release create"
    requirement: BUILD-02
    verification:
      - kind: automated
        ref: "Static verification (inline bash in the publish job; YAML valid) — dynamic proof at the next tag"
        status: pass
    human_judgment: true
duration: 42 min
completed: 2026-10-24
status: complete
plan_head_before: 3666086
plan_head_after: eca8666
commits: 1
---

# Phase 05 Plan 03: Consistency Checks + Release Provenance Summary

**Version/deployment/SDK drift is fixed and mechanically guarded; release provenance self-verifies and the bundle pins are CI-checked against the live release.**

## Performance

- Duration: 42 min; Tasks: 2/2; Commits: 1
- Token estimate 52000 vs realized ~58000

## Accomplishments

- `tools/check_consistency.dart`: 8 invariants, each anchored on exact file/line shapes; header-scoped caret/-dev-aware version scanning.
- Drift fixed: podspec 10.15 → 12.0; sdk ^3.8.0 → ^3.10.0 in root/mpv_kit/example (unifying with mpv_kit_video/libs); README names `v0.41.0-1113-gfd9265a905`; ADR-0002's stale gaps section rewritten; rev-eng date corrected.
- `tools/pin_bundles.dart --check` (PINS OK against the live v0.1.0-dev.3 SHA256SUMS) wired into native-verify's Linux Dart step.
- release.yml publish: SHA256SUMS membership check + MANIFEST.txt verification of each extracted tar, before `gh release create`.

## Task Commits

1. `eca8666` — build: consistency checker with drift fixes; pin freshness + release self-verification (BUILD-03/BUILD-02)

## TDD Gate Compliance

| Task | RED evidence | GREEN evidence |
|------|--------------|----------------|
| Checker | first run: 6 FAILs on the real drift (README version, podspec, sdk split, rev-eng date) | all invariants hold |
| Tamper | sdk edit → exit 1 (2 FAILs) | restore → all hold |
| Pins | N/A (pins already fresh — the check exists for the next release) | PINS OK |

## Files Created/Modified

- Created: `tools/check_consistency.dart`. Modified: `tools/pin_bundles.dart`, both workflows, README, ADR-0002, rev-eng doc, podspec, three pubspecs.

## Decisions Made

- ADR-0002: rewrite the gap section in place (superseded-by note) rather than delete — it's the record of how each patch relates to master.
- sdk floor: ^3.10.0 everywhere (the transitive truth), README's "Dart 3.10" claim now accurate.

## Deviations from Plan

1. `[Rule 1 - caret scoping]` Found during: task 1 GREEN. Issue: the foreign-version scan flagged mpv_kit's own `^0.1.0-dev.3` package versions in README. Fix: header-scoped + skip caret-preceded matches + skip `-dev.`-continuation matches (mpv stamps never use that scheme). Committed in: `eca8666`.
2. `[Rule 1 - heredoc escaping]` Found during: task 1. Issue: a Python heredoc mangled a Dart string literal (`'\n'` became a real newline mid-expression). Fix: repaired via `String.fromCharCode(10)`. Committed in: `eca8666`.
3. `[Rule 1 - restore-from-HEAD]` Found during: task 1 tamper test. Issue: `git checkout --` restored the pre-fix constraint (the fix was uncommitted), making the restored run fail. Fix: re-applied the fix; the tamper conclusion (detection works) stands. Committed in: `eca8666`.

## Issues Encountered

- None beyond the deviations.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-05-05/06/07 mitigated; T-05-SC not triggered.

## Verification Results

- `dart run tools/check_consistency.dart` → all invariants hold; tamper exit 1.
- `dart run tools/pin_bundles.dart --check` → PINS OK tag=v0.1.0-dev.3 targets=6.
- Both workflows YAML-valid; PATCH-DRIFT OK; mpv_kit suite 112 passed / 2 skipped.

## Next Phase Readiness

- Phase 6 (cross-platform verification) inherits a fully provenanced tree.

## Self-Check: PASSED

- Artifacts exist; commit `eca8666` is an ancestor of HEAD; commit count measured.
