---
phase: 06-cross-platform-verification
plan: 01
subsystem: integration-test
tags: [real-plugin, verify]
requires:
  - phase: 04-01
    provides: "The integration-test vehicle (example/integration_test, integration_test dep, lavfi graph shape)"
provides:
  - "example/integration_test/real_plugin_test.dart: the no-mocks create→render-a-frame→dispose test"
affects: [06-02]
actuals:
  tokens: 16000
  tasks: 1
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Readiness poll with deadline: videoParams (decoder) AND estimated-vf-fps (VO presenting frames) — the fps estimate exists only once the render loop presents"
key-files:
  created:
    - example/integration_test/real_plugin_test.dart
  modified: []
key-decisions:
  - "'Rendered a frame' is asserted via estimated-vf-fps != null: mpv only produces that estimate after the VO presents frames through the render context — a software-backend frame on GPU-less runners satisfies it by design"
patterns-established:
  - "INTEGRATION {json} report line (backend/reason/elapsed/fps/events)"
requirements-completed: []
coverage:
  - id: D1
    description: "Real plugin path (no mocks): create→open→params+frames→dispose-once, no deviceLost, <10 renderErrors"
    requirement: VERIFY-01
    verification:
      - kind: automated_ui
        ref: "Local Windows: vulkan (gpu-next) RTX 4060, ready 211 ms, fps 30, All tests passed"
        status: pass
    human_judgment: false
  - id: D2
    description: "Assertions are load-bearing: making the frame-wait vacuous fails the test"
    requirement: VERIFY-01
    verification:
      - kind: automated
        ref: "RED proof (if(false) variant): Some tests failed; restored: green"
        status: pass
    human_judgment: false
duration: 12 min
completed: 2026-10-24
status: complete
plan_head_before: a87e197^
plan_head_after: a87e197
commits: 1
---

# Phase 06 Plan 01: Real-Plugin Integration Test Summary

**The VERIFY-01 test artifact exists and passes against the real native plugin (Vulkan path locally, 211 ms to frames).**

## Performance

- Duration: 12 min; Tasks: 1/1; Commits: 1
- Token estimate 30000 vs realized ~16000

## Accomplishments

- `real_plugin_test.dart`: real channel (no mocks), multi-stream lavfi source, deadline-poll for videoParams + estimated-vf-fps, single dispose with done-delivery, idempotent re-dispose, deviceLost/renderError-storm guards, INTEGRATION json line.

## Task Commits

1. `a87e197` — test(video): real-plugin integration test — create, render a frame, dispose (VERIFY-01)

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| `if (false)` fps-wait variant → Some tests failed (waits are load-bearing) | vulkan/RTX 4060, 211 ms, fps 30, All tests passed |

## Files Created/Modified

- Created: `example/integration_test/real_plugin_test.dart`.

## Deviations from Plan

- None (an unused dart:io import caught by the analyzer before commit).

## Verification Results

- Windows local green; analyzer clean.

## Self-Check: PASSED

- Artifact exists; commit `a87e197` is an ancestor of HEAD.
