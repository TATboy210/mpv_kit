---
created: 2026-10-27T00:00:00.000Z
title: Publish and pin a libmpv bundle that contains the D3D11 and OpenGL render backends
area: native
severity: minor
files:
  - packages/mpv_kit_libs/lib/src/bundles.dart
  - tools/pin_bundles.dart
  - .github/workflows/release.yml
  - .github/workflows/flutter-plugin.yml
  - tools/pinned_bundle_identity.sh
---

## Problem

`mpv_kit_libs` still pins bundle `v0.1.0-dev.3` (`bundleTag` in `packages/mpv_kit_libs/lib/src/bundles.dart`). That bundle was built before patches 0010 (D3D11 render API) and the D3D11 branch of 0004, so its libmpv has no `mpv_render_context` D3D11 API.

An app that gets mpv_kit through pub and the pinned bundle therefore cannot use the Phase 14 D3D11 backend on Windows. The plugin still behaves correctly: it tries `d3d11/gpu-next` after Vulkan fails (or when forced with `MPV_KIT_VIDEO_API=d3d11`), gets `mpv_render_context_create: ...` from the old libmpv, and reports it as a trail in `MpvVideoController.reason` (`d3d11/... unavailable: mpv_render_context_create: ...`). Where Vulkan works nothing changes. Where Vulkan is rejected (no driver, hybrid-GPU laptop with Flutter on the integrated adapter) the app falls back to software instead of D3D11 until a newer bundle is pinned.

D3D-08 was decided as keep (Vulkan first, D3D11 second, 14-11), so the default chain does not depend on this todo; only the D3D11 fallback does.

Linux half (v3.0 audit INT-2): the `v0.1.0-dev.3` Linux libmpv was built before the GL/EGL build (5c2b060), so pub consumers on Linux had no opengl candidate either. Their auto chain fell from vulkan/gpu-next to vulkan/gpu and then to software, and `MPV_KIT_VIDEO_API=opengl` could not work from the pinned bundle. The Windows half is INT-1 in the same audit.

## Solution

When the user decides to cut a release: push a `v*` tag so `release.yml` publishes the six-target bundles, run `dart run tools/pin_bundles.dart` to update `bundleTag` and the per-target sha256 values, and re-run the Windows integration tests against the pinned bundle. Release timing is the user's decision (PROJECT.md: no rush to release); Phase 14 does not publish.

## Resolution (Phase 17.1, 2026-10-31)

All values below are copied from `.planning/phases/17.1-close-gap-int-1-int-2-release-and-pin-a-libmpv-bundle-with-t/evidence/` (E).

- **Tag and release:** `v0.1.0-dev.4` at `47cbbf21f603cffb0d0d472796f42f72ad768099` (contains quick 261030-umq, the render/Describe timing probe lines, log only). Tag run 41123644028 (attempt 1, no rerun) published the release (not draft, not prerelease) at 2026-10-30T20:55:34Z with seven assets: `libmpv-{linux-x64,linux-arm64,macos-arm64,macos-x64,windows-x64,windows-arm64}.tar.gz` and `SHA256SUMS`. All six archives re-hashed locally; SHA256SUMS = API digest for every target (E/release.txt, E/release-runs.txt). The tag was pushed with the user's explicit go (E/push-authorization.txt). Remote tags are exactly dev.1 to dev.4.
- **Pin:** commit `10f5bd1d51f44690e57ba3c98ee17ec7780a3fc9`: `bundleTag = 'v0.1.0-dev.4'` and six sha256 written by `tools/pin_bundles.dart`; `--check` printed `PINS OK tag=v0.1.0-dev.4 targets=6`; pin = SHA256SUMS = API digest for every target (E/pin.txt).
- **Pinned-only CI (pin gate at `95c2b6d10f33d2e9036508dc844cd3cbfe2df051`, first attempt, no rerun):** native-verify 41129271542, flutter-plugin 41129271358, macos-route 41129271190, all success (E/ci-runs.txt, `pin-gate ... result=ok`). windows-2025: forced d3d11 from the pinned bundle alone, `D3D11-BACKEND` reason `d3d11 (gpu-next) on Microsoft Basic Render Driver; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11`, probe nonBlack 1.0, `PINNED-IDENTITY ... libs=24 app_copy=same libmpv_env=unset`. ubuntu-24.04 under xvfb: forced opengl, `PROBE` reason `opengl (gpu) on llvmpipe`, nonBlackRatio 1.0, renderErrors 0, `PINNED-IDENTITY ... libs=17`. D-06: `ROUTE-PARITY ok` on macos-route (HEAD leg dev.4, pre12 leg dev.3).
- **RTX 4060 Laptop GPU (Plan 06, pinned dev.4 bundle only, E/rtx-verdicts.txt):** `pin-d3d11` reason `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11`, nonBlack 1.0/1.0 before and after resize, exit 0; `pin-auto` reason `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`, nonBlack 1.0/1.0, exit 0 (default chain unchanged). libmpv sha256 `1d66e561292f13df25bac2ed0c23bc92ff4679c8c8e5ff1761d0fa8ef90cba3e` before and after (E/rtx-identity.txt).
- **D-05 (flutter-plugin Windows leg):** commit `ca0c410`. The leg never loaded libmpv and its failing test did not fail the job (7 passed, 1 failed, job success in runs 40949963646, 40984192897, 41065294826). Hosted red proof, run 41092363822: 29 tests ran and the deliberate failure turned the Windows, Linux and macOS jobs red (E/d05-ci.txt).
- **D-07 (hook stale stamp):** commit `022f663` (`resolvePinnedBundle` in `packages/mpv_kit_libs/lib/src/bundle.dart`, called from `hook/build.dart`): a `{target}.ok` stamp is honoured only when the extracted `lib/` holds shared libraries, otherwise the hook reinstalls from the sha256-verified cached archive (or re-downloads), and an installed pinned bundle without shared libraries fails with `BundleIntegrityException`. RED at 7f858d3 in E/red-local-d07-stamp.log.
- **Scope of the closure (D-04):** pub.dev users get the D3D11 and OpenGL backends only after 0.1.0-dev.4 is published to pub.dev, which needs a separate user approval (D-04). INT-1 and INT-2 are closed for git/path consumers, hosted CI and the RTX 4060 only. Superseding D-04's "no pub.dev publication in this phase": the user later decided to publish `mpv_kit`, `mpv_kit_libs` and `mpv_kit_video` at 0.1.0-dev.4 after Plan 17.1-07, with a dry run shown first and a separate final confirmation before the real publish (E/push-authorization.txt, `pubdev_decision`, commit 9cbc1e9). That publication is decided and pending, not done.
