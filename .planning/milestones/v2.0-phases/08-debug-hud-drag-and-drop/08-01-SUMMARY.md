---
phase: 08-debug-hud-drag-and-drop
plan: 01
subsystem: example
tags: [hud, drag-and-drop, debuggability]
requires:
  - phase: 07-01
    provides: "The advanced vendor the example runs against"
provides:
  - "example/lib/hud.dart: HudSnapshot (1 Hz capture; fabricated for tests), HudEventLog (bounded 8-ring, error styling), DebugHud panel (five groups + event overlay + notice slot), isVideoPlayable allowlist"
  - "main.dart: F9/H HUD toggle, DropTarget wiring (first playable file opens; non-video -> 3 s notice; hover border), CI debugPrint summary kept"
  - "desktop_drop ^0.7.1 dependency (workspace lock committed)"
affects: [09-*, 11-*]
actuals:
  tokens: 30000
  tasks: 2
  commits: 3
tech-stack:
  added:
    - desktop_drop ^0.7.1 (example-only)
  patterns:
    - "Data/widget split: HudSnapshot.capture is the only mpv-touching seam; tests fabricate snapshots"
    - "Transient HUD notice slot with a 3 s auto-clear timer (no snackbars on top of video)"
key-files:
  created:
    - example/lib/hud.dart
    - example/test/hud_test.dart
  modified:
    - example/lib/main.dart
    - example/pubspec.yaml
    - pubspec.lock
key-decisions:
  - "HUD toggle lives in main.dart state (CallbackShortcuts F9/H); DebugHud itself is a stateless layout widget fed snapshot+events — trivially testable"
  - "compositor line is static 'ANGLE (DxgiSharedHandle)' until Phase 11 wires the live path (HUD-02's Phase-11 clause)"
  - "Polling stays at the pre-existing 1 s Timer pattern; debugPrint one-liner kept for CI logs"
patterns-established:
  - "isVideoPlayable allowlist (extensions + av://http(s):// passthrough) as the drop gate"
requirements-completed: [HUD-01, HUD-02, DND-01]
coverage:
  - id: D1
    description: "Five groups render, hidden-hint mode, error styling, ring bound 8 — widget tests"
    requirement: HUD-01
    verification:
      - kind: unit
        ref: "example/test/hud_test.dart (6/6 green)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Composition path visible (backend/reason live; compositor static until Phase 11)"
    requirement: HUD-02
    verification:
      - kind: unit
        ref: "find.textContaining('compositor=ANGLE') in hud_test; smoke log shows backend line"
        status: pass
    human_judgment: false
  - id: D3
    description: "isVideoPlayable matrix (extensions case-insensitive; av://http(s):// true; txt/jpg/bare/empty false)"
    requirement: DND-01
    verification:
      - kind: unit
        ref: "hud_test.dart isVideoPlayable group"
        status: pass
    human_judgment: false
  - id: D4
    description: "Local smoke: real mp4 + lavfi play through the rewired app on the Vulkan path; HUD/debugPrint evidence captured"
    requirement: HUD-01
    verification:
      - kind: automated_ui
        ref: "Smoke run: 'vulkan (gpu-next) on RTX 4060' backend line, per-second dropped/avdiff logs, screenshot hud_smoke.png; drag interaction itself needs human hands (manual UAT)"
        status: pass
    human_judgment: true
duration: 35 min
completed: 2026-10-25
status: complete
plan_head_before: 5e5d114
plan_head_after: 8a34297
commits: 3
---

# Phase 08 Plan 01: Debug HUD & Drag-and-Drop Summary

**The example is now a debugging cockpit: five-group HUD + live event overlay (F9), drag-and-drop playback with a non-video notice — all example-side, production untouched.**

## Performance

- Duration: 35 min; Tasks: 2/2; Commits: 3 (feature, analyzer-fix)
- Token estimate 44000 vs realized ~30000

## Accomplishments

- hud.dart (data/widget split), main.dart rewiring, desktop_drop 0.7.1, 6 widget tests, analyzer clean, Windows debug build compiles, local smoke on real mp4 + lavfi.

## Task Commits

1. `65cd129` — feat(example): debug HUD + drag-and-drop
2. `8a34297` — fix(example): unused imports

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| const-fabricated compile errors in const MaterialApp context | top-level final + non-const pumpWidget; 6/6 |

## Deviations from Plan

1. `[Rule 1 - analyzer]` unused imports caught post-commit; fixed in the follow-up commit (fatal-infos gate held).
2. `[Rule 1 - smoke scope]` OS-level drag interaction can't be simulated from bash: predicate + wiring compile + runtime playback are evidenced; the physical drag gesture is flagged as manual UAT (30-second human check: drop an mp4, drop a .txt).

## Verification Results

- flutter test 6/6; analyze clean; build √; smoke logs (backend line, dropped/avdiff ticks); screenshot captured (hud_smoke.png).

## Self-Check: PASSED

- Commits ancestors of HEAD; artifacts in repo.
