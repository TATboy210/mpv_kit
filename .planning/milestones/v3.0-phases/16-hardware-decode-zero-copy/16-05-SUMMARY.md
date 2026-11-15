---
phase: 16-hardware-decode-zero-copy
plan: 05
subsystem: testing
tags: [hwdec, integration-test, ci, hwd-05]

requires:
  - phase: 16-hardware-decode-zero-copy
    provides: 16-01 hwdec_probe.dart and hwdec_zero_copy_test; 16-03 verify-tier libmpv
provides:
  - "All eight lavfi integration/soak tests print an HWDEC line at the first frame and assert software / zeroCopy=false"
  - "native-verify runs hwdec_zero_copy_test forced on every backend: linux opengl/vulkan/software, windows d3d11/software, macOS vulkan (bundle) and software (branch libmpv)"
affects: [16-06, 17]

status: complete
actuals:
  tokens: 18000
  tasks: 3
  commits: 2
plan_head_before: 9f0a18b111d764da4004eaa676803e7cc00bdd7b
plan_head_after: ad5c54b5dc8bfa69500d4dada6c59e8cb9ef0c72

key-files:
  modified:
    - example/integration_test/real_plugin_test.dart
    - example/integration_test/texture_probe_test.dart
    - example/integration_test/d3d11_backend_test.dart
    - example/integration_test/d3d11_device_lost_test.dart
    - example/integration_test/uhd_endurance_test.dart
    - example/integration_test/playback_bench_test.dart
    - example/integration_test/impeller_smoke_test.dart
    - example/integration_test/seek_recovery_test.dart
    - .github/workflows/native-verify.yml
    - .planning/phases/16-hardware-decode-zero-copy/evidence/decisions.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/ci-runs-16-05.txt

key-decisions:
  - "HWD-05 scope on lavfi soaks: option A (user, 2026-10-29). lavfi tests print and assert software; real hardware decode is proven by hwdec_zero_copy_test on real samples; long hwdec stability goes to Phase 17's 4K HEVC 1800 s loop."

requirements-completed: []
requirements-partial: [HWD-05]
---

# Phase 16 Plan 05: HWDEC line and assertion on every soak/integration test Summary

Every integration/soak test now prints `HWDEC {hwdec-1 json}` at its first frame and asserts `outcome=software`, `zeroCopy=false`; `hwdec=no` software decode passes on every backend in CI. HWD-05 is not ticked: 16-06 (RTX 4060 d3d11va zero-copy) still owns the hardware half.

## Tasks

1. Task 1 (decision): user chose A; recorded in `evidence/decisions.txt`.
2. Task 2 (tracer) - `5cd411e`: real_plugin, texture_probe, d3d11_backend, d3d11_device_lost. In device_lost the report runs in both modes before the injected loss is awaited.
3. Task 3 - `ad5c54b`: uhd_endurance, playback_bench, impeller_smoke (preflight part 1 only), seek_recovery, plus the workflow legs.

Only imports and 3-5 added lines per file; no source, duration, threshold or verdict changed.

## Verification

- Local (RTX 4060, bundle libmpv): `flutter analyze --fatal-infos` clean, `check_matrix.py` ok; real_plugin, uhd_endurance (20 s 1080p render) and seek_recovery pass with `api=vulkan outcome=software zeroCopy=false`.
- CI Task 2, sha 5cd411e: native-verify 40797106875, flutter-plugin 40797107003 (`^build \(` jobs success), `CI-GATE ok`, no reruns. Ten per-leg HWDEC lines recorded as `hwdec-wired` in `evidence/ci-runs-16-05.txt`.
- CI Task 3, sha ad5c54b: native-verify 40798831729, flutter-plugin 40798831636, `CI-GATE ok`, no reruns, no `unexpected`, no `playedToEnd=false`/device loss.

## hwdec=no matrix (hevc-10bit end row; other samples identical; run 40798831729)

| Backend | Platform | `hwdec=no` | default list |
|---|---|---|---|
| opengl | ubuntu (llvmpipe) | software | software |
| vulkan | ubuntu (lavapipe) | software | software |
| software | ubuntu | software | software |
| d3d11 | windows (WARP) | software | software |
| software | windows | software | software |
| vulkan | macos-15 (MoltenVK) | software | zero-copy (videotoolbox) |
| software | macos-15 | software | copy-back (videotoolbox-copy) |

Windows has no lavapipe, so Vulkan there is covered by linux and macOS. macOS identity (HWDEC-IDENTITY): the vulkan cell used the pinned bundle `@rpath/mpv.2.framework/mpv.2` (v0.1.0-dev.3); the software cell used the branch build `stage/libmpv.2.dylib`.

## Deviations from Plan

- No rule-1..4 deviations. One scope note: `seek_recovery_test` with `MPV_KIT_SEEK_MEDIA` (manual real-media runs) asserts only "not unexpected", since a real file may legitimately decode in hardware; the lavfi default asserts software. Still unconditional for CI.
- The first background gate invocation exited empty (nohup shell); it was rerun in the foreground, so `ci-runs-16-05.txt` had duplicate result lines, which were deduplicated (identical content).
- `packages/mpv_kit` Dart tests (`vo=null`) are not covered: no render backend, so zero-copy is undefined (plan option A).

## Known Stubs

None.

## Self-Check: PASSED
