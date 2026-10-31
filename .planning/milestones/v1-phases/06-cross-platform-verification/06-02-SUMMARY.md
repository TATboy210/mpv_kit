---
phase: 06-cross-platform-verification
plan: 02
subsystem: ci
tags: [integration, ci, fail-loud]
requires:
  - phase: 06-01
    provides: "The integration test artifact"
provides:
  - "native-verify integration-test matrix job: real Flutter runners on Linux (xvfb)/Windows/macOS against the verify tier's libmpv artifacts"
  - "macOS artifact upload (libmpv-verify-macos-<runner>)"
  - "MPV_KIT_REQUIRE_LIBMPV: libmpv/bridge skip guards fail loud when CI demands a library"
  - "flutter-plugin.yml runs the channel tests against the hook bundle on all three runners (no silent skips)"
affects: [phase-close]
actuals:
  tokens: 30000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Artifact-fed integration matrix: needs [linux, windows, macos] + per-OS download; libmpv never rebuilt"
key-files:
  created: []
  modified:
    - .github/workflows/native-verify.yml
    - .github/workflows/flutter-plugin.yml
    - packages/mpv_kit_video/test/controller_channel_test.dart
    - packages/mpv_kit/test/failure_injection_test.dart
key-decisions:
  - "The REQUIRE guard fails (not skips) at guard-evaluation time in main(), so every affected test fails with one clear message instead of N skips"
  - "flutter-plugin locates the hook bundle by find (no hardcoded per-OS paths); dir goes to GITHUB_PATH (Windows dependency resolution) and MPV_KIT_LIBMPV_PATH uses forward slashes (loadable on every OS)"
patterns-established:
  - "MPV_KIT_REQUIRE_LIBMPV convention for CI-must-have-library suites"
requirements-completed: [VERIFY-01]
coverage:
  - id: D3
    description: "integration-test job exists (linux/windows/macos entries, needs all three build tiers, zero continue-on-error); macOS uploads libmpv-verify-macos"
    requirement: VERIFY-01
    verification:
      - kind: automated
        ref: "YAML parse + python assertion (3 targets, no continue-on-error); dynamic proof at next push"
        status: pass
    human_judgment: true
  - id: D4
    description: "REQUIRE mode: channel tests run with 0 libmpv skips locally (17/17); guard fails loud when the library is absent"
    requirement: VERIFY-01
    verification:
      - kind: unit
        ref: "MPV_KIT_REQUIRE_LIBMPV=1 flutter test test/controller_channel_test.dart → +17 All tests passed (no skips)"
        status: pass
    human_judgment: false
  - id: D5
    description: "flutter-plugin locates the hook bundle and sets REQUIRE + PATH; channel tests run for real on all three runners"
    requirement: VERIFY-01
    verification:
      - kind: automated
        ref: "YAML valid; wiring greps; dynamic proof at next push"
        status: pass
    human_judgment: true
duration: 35 min
completed: 2026-10-24
status: complete
plan_head_before: a87e197
plan_head_after: df25c74
commits: 1
---

# Phase 06 Plan 02: CI Wiring + Fail-Loud Skips Summary

**The real-plugin test now has a three-OS CI home, and silent libmpv skips are gone wherever CI provides a library.**

## Performance

- Duration: 35 min; Tasks: 2/2; Commits: 1
- Token estimate 42000 vs realized ~30000

## Accomplishments

- REQUIRE guards in both suites (channel tests: main()-time fail; failure-injection: bridge guard fails).
- flutter-plugin: find-based hook-bundle location → GITHUB_PATH/GITHUB_ENV; analyze step consumes them.
- native-verify: macos stage+upload; integration-test matrix job (ubuntu/xvfb, windows/PATH, macos/DYLD) — artifacts only, no continue-on-error.

## Task Commits

1. `df25c74` — ci: real-plugin integration test on Linux/Windows/macOS runners; libmpv skips fail loud (VERIFY-01, criterion 3)

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| Guards absent (skips silent on CI) | REQUIRE mode: 17/17 channel tests run, 0 skipped; integration test green with the flag |
| (python heredoc mangling broke two attempts at the job YAML) | Edit-tool application; YAML assertions pass |

## Deviations from Plan

1. `[Rule 1 - heredoc escaping]` Found during: task 2. Issue: Python heredocs mangled backslash-continuations and `${...}` in YAML. Fix: applied the workflow edits with the Edit tool directly. Committed in: `df25c74`.
2. `[Rule 1 - step shape]` Found during: task 1. Issue: the first locate-step draft mixed per-OS cygpath logic (fragile). Fix: simplified to one find + forward-slash path + GITHUB_PATH. Committed in: `df25c74`.

## Verification Results

- YAML valid; python assertions (3 targets, needs, no continue-on-error); local REQUIRE run 17/17; integration test green with flag set.

## Self-Check: PASSED

- Artifacts exist; commit `df25c74` is an ancestor of HEAD.
