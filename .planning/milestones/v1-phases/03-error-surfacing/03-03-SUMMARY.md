---
phase: 03-error-surfacing
plan: 03
subsystem: video-native
tags: [fallback-reasons, interop, obs-03]
requires:
  - phase: 02-01
    provides: "Create-response validation the reason strings flow through"
provides:
  - "Honest create-time fallback reasons: D3D11 device-creation failures carry the HRESULT, Metal absence is named, adapter-probe failures are specific"
  - "CreateImage null-device guard (CONCERNS 212-219 closed)"
affects: [phase-6-cross-platform-verification]
actuals:
  tokens: 30000
  tasks: 1
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Interop::interopReason() virtual hook: platforms answer why zero-copy sharing is unavailable"
key-files:
  created: []
  modified:
    - packages/mpv_kit_video/windows/d3d11_interop.h
    - packages/mpv_kit_video/windows/d3d11_interop.cpp
    - packages/mpv_kit_video/macos/Classes/metal_interop.h
    - packages/mpv_kit_video/macos/Classes/metal_interop.mm
    - packages/mpv_kit_video/src/video_renderer.h
    - packages/mpv_kit_video/src/video_renderer.cc
key-decisions:
  - "interopReason() is a virtual on the Interop base (default null) rather than a per-platform string plumbed through constructors — the renderer reads it at Start time"
  - "Reason strings only: backend selection and vulkan() gating are untouched"
patterns-established: []
requirements-completed: [OBS-03]
coverage:
  - id: D9
    description: "Windows fallback reasons name their cause (HRESULT / no adapter / desc failure); CreateImage null-safe"
    requirement: OBS-03
    verification:
      - kind: automated
        ref: "flutter build windows --debug compiled clean; marker greps (interopReason ×5 files, CreateImage guard)"
        status: pass
    human_judgment: false
  - id: D10
    description: "macOS no-Metal reason flows; Linux probe reasons already flowed via gl_reason_ (verified, no change needed)"
    requirement: OBS-03
    verification:
      - kind: automated
        ref: "Code review: metal_interop.mm reason capture; gl_interop.cc gl_reason_ plumbing confirmed"
        status: pass
    human_judgment: true
duration: 12 min
completed: 2026-10-24
status: complete
plan_head_before: 0b934f6
plan_head_after: f3d4170
commits: 1
---

# Phase 03 Plan 03: Honest Interop Fallback Reasons Summary

**Fallback reasons now name their true cause on every platform; the misleading "platform has no Vulkan interop" for a failed D3D11 device creation is gone.**

## Performance

- Duration: 12 min; Tasks: 1; Commits: 1
- Token estimate 38000 vs realized ~30000

## Accomplishments

- `Interop::interopReason()` virtual hook (video_renderer.h) + `VideoRenderer::Start` else-branch preferring it over the generic string.
- Windows: `D3D11CreateDevice` HRESULT captured (`d3d11 device creation failed: 0x…`), plus specific reasons for `no DXGI adapter` and `failed to read the DXGI adapter desc`; `CreateImage` entry guard `if (!device_) return false;`.
- macOS: `no Metal device` reason; `interopReason()` override.
- Vulkan shared-instance failures: verified already flowing into `backend_reason_` via the Init error out-params — no change needed.
- Dart side untouched: the create response `reason` → `controller.reason` → synthetic `softwareFallback` event message carries the honest text (Phase 2 verified channel).

## Task Commits

1. `f3d4170` — feat(video): honest interop fallback reasons — D3D11 HRESULT, Metal probe, null-device guard (OBS-03)

## TDD Gate Compliance

- N/A (native C++; no unit-test harness for device failures). Mechanical verification: marker greps + Windows native compile + Dart suite regression.

## Files Created/Modified

- Modified: `video_renderer.{h,cc}`, `d3d11_interop.{h,cpp}`, `metal_interop.{h,mm}`.

## Decisions Made

- Virtual hook on the base class; per-platform strings stay private to each interop.

## Deviations from Plan

1. `[Rule 1 - Compile]` Found during: verify. Issue: first implementation defined `interopReason()` both inline (header) and out-of-line (cpp/mm) → C2084 duplicate body on the Windows build. Fix: kept the inline header definitions, removed the cpp/mm ones. Committed in: `f3d4170`.

## Issues Encountered

- None beyond the deviation.

## User Setup Required

- None.

## Known Stubs

- None.

## Threat Flags

- T-03-09/10 mitigated; T-03-SC not triggered.

## Verification Results

- `flutter build windows --debug` → built `mpv_kit_example.exe`.
- `flutter test` (mpv_kit_video) → 21 passed.
- Real device-failure behavior: local UAT (Windows RTX 4060) + Phase 6 real-plugin tests — CI cannot force `D3D11CreateDevice` to fail (recorded in 03-VERIFICATION).

## Next Phase Readiness

- None required; this plan is independent of the Dart-side plans.

## Self-Check: PASSED

- Artifacts exist; commit `f3d4170` is an ancestor of HEAD; commit count measured.
