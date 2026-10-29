---
created: 2026-10-27T00:00:00.000Z
title: Publish and pin a libmpv bundle that contains the D3D11 render backend
area: native
severity: minor
files:
  - packages/mpv_kit_libs/lib/src/bundles.dart
  - tools/pin_bundles.dart
  - .github/workflows/release.yml
---

## Problem

`mpv_kit_libs` still pins bundle `v0.1.0-dev.3` (`bundleTag` in `packages/mpv_kit_libs/lib/src/bundles.dart`). That bundle was built before patches 0010 (D3D11 render API) and the D3D11 branch of 0004, so its libmpv has no `mpv_render_context` D3D11 API.

An app that gets mpv_kit through pub and the pinned bundle therefore cannot use the Phase 14 D3D11 backend on Windows. The plugin still behaves correctly: it tries `d3d11/gpu-next` after Vulkan fails (or when forced with `MPV_KIT_VIDEO_API=d3d11`), gets `mpv_render_context_create: ...` from the old libmpv, and reports it as a trail in `MpvVideoController.reason` (`d3d11/... unavailable: mpv_render_context_create: ...`). Where Vulkan works nothing changes. Where Vulkan is rejected (no driver, hybrid-GPU laptop with Flutter on the integrated adapter) the app falls back to software instead of D3D11 until a newer bundle is pinned.

D3D-08 was decided as keep (Vulkan first, D3D11 second, 14-11), so the default chain does not depend on this todo; only the D3D11 fallback does.

## Solution

When the user decides to cut a release: push a `v*` tag so `release.yml` publishes the six-target bundles, run `dart run tools/pin_bundles.dart` to update `bundleTag` and the per-target sha256 values, and re-run the Windows integration tests against the pinned bundle. Release timing is the user's decision (PROJECT.md: no rush to release); Phase 14 does not publish.
