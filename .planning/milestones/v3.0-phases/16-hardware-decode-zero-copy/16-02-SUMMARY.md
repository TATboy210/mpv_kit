---
phase: 16-hardware-decode-zero-copy
plan: 02
subsystem: player
tags: [hwdec, zero-copy, defaults, adr, behavior-change]

requires:
  - phase: 16-hardware-decode-zero-copy
    provides: 16-01 hosted probes (HWDEC / ROUTE-HWDEC lines) and ci_gate.sh
provides:
  - "Player default hwdec is a per-platform zero-copy-first list (library-internal hwdec_defaults.dart, not exported)"
  - "ADR 0006, README/diagrams/CHANGELOG behavior-change docs"
affects: [16-03, 16-06]

status: complete
actuals:
  tokens: 40000
  tasks: 3
  commits: 2
plan_head_before: f304821f7b13eb049fd73cea18f1cc049a58cadd
plan_head_after: f23777f0efa66558799e5227408d9f6d922ec992

key-files:
  created:
    - packages/mpv_kit/lib/src/player/hwdec_defaults.dart
    - packages/mpv_kit/test/hwdec_defaults_test.dart
    - docs/adr/0006-hwdec-defaults.md
    - .planning/phases/16-hardware-decode-zero-copy/evidence/decisions.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/ci-runs-16-02.txt
  modified:
    - packages/mpv_kit/lib/src/player/player.dart
    - packages/mpv_kit/test/player_test.dart
    - example/lib/main.dart
    - README.md
    - docs/ARCHITECTURE-diagrams.md
    - packages/mpv_kit/CHANGELOG.md

key-decisions:
  - "User chose `adopt`: windows=vulkan,d3d11va,d3d11va-copy,auto-safe linux=vulkan,vaapi,auto-safe macos=videotoolbox,auto-safe other=auto-safe; d3d11va-zero-copy stays at mpv default."
  - "Platform switch is library-internal; public API unchanged (api_freeze_test passes)."

requirements-completed: []
requirements-partial: [HWD-01]
---

# Phase 16 Plan 02: Per-platform Player hwdec defaults Summary

`Player()` now defaults `hwdec` to a per-platform, zero-copy-first list (Windows `vulkan,d3d11va,d3d11va-copy,auto-safe`, Linux `vulkan,vaapi,auto-safe`, macOS `videotoolbox,auto-safe`, other `auto-safe`), documented as a behavior change in ADR 0006; user `hwdec` options still win.

## Tasks

1. Task 1 (checkpoint:decision): answered `adopt` by the user (2026-10-28); recorded in `evidence/decisions.txt`.
2. Task 2 (tracer) - commit `8bf1efb`: `hwdec_defaults.dart`, Player wiring (`...options` stays last), pure-Dart ordering test, two real-libmpv `hwdec default` tests, example uses the default.
3. Task 3 - commit `f23777f`: README table and pixelformat guidance, diagrams (3 spots), ADR 0006, CHANGELOG entry.

`defaultHwdecFor` branches match decisions.txt verbatim (checked by the exact-value test and the CI gate).

## CI gate (live, no reruns)

Pushed `8bf1efb`; native-verify 40715501196, flutter-plugin 40715501232, macos-route 40715501421: all success, `CI-GATE ok`. Gate assertions held: ubuntu opengl HWDEC `requested=vulkan,vaapi,auto-safe`; windows d3d11 `requested=vulkan,d3d11va,d3d11va-copy,auto-safe`; route-probe default row `requestedHwdec=videotoolbox,auto-safe`; no `unexpected` outcomes. Records in `evidence/ci-runs-16-02.txt`. Task 3 is docs only, no new gate.

## Local checks

dart analyze --fatal-infos (mpv_kit), flutter analyze (example) clean; hwdec_defaults_test, api_freeze_test, and the two `hwdec default` player tests pass; golden-freeze sha256 check OK; barrel has no new export.

## Deviations from Plan

None. The pre-existing local `player_test` failure ("default hwdec-codecs ... without ffv1", pinned v0.1.0-dev.3 bundle default list contains `apv`) was not touched; hosted CI Dart tests passed.

## Open items

- HWD-01 not ticked: 16-06 still lists it (RTX 4060 no/yes zero-copy comparison, hardware data).
- Unverified, recorded in ADR 0006: `vaapi` on real hardware, mpv#13304 (VRR with `d3d11va` direct), mpv#14934 (amdvlk Vulkan hwdec), hybrid-GPU `d3d11va-copy` adapter. The Windows benefit applies to the D3D11 backend only.

## Known Stubs

None.

## Self-Check: PASSED

Files exist, commits `8bf1efb` and `f23777f` are ancestors of HEAD.
