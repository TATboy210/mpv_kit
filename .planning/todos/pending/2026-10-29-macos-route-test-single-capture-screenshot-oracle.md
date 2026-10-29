---
created: 2026-10-29T00:00:00.000Z
title: Harden the macos_route_test.dart single-capture screenshot oracle (macos-route.yml)
area: testing
severity: minor
files:
  - example/integration_test/macos_route_test.dart
  - example/integration_test/macos_route_probe.dart
  - .github/workflows/macos-route.yml
  - .planning/phases/14-windows-native-d3d11-backend/debug/macos-fifo-black-reference.md
---

## Problem

`macos_route_test.dart` (workflow `macos-route.yml`) judges each sample by ONE
`player.screenshot()` (`_runSample`, the `screenshot-raw` call around line 602).
On the hosted macos-15 runner (Apple Paravirtual device behind MoltenVK) that
single capture is intermittently black or only partly drawn while the Flutter
texture channel still matches the reference. `hwdec_zero_copy_test.dart` had the
same oracle and failed the same way (debug session
`macos-fifo-black-reference`, fixed by commit 196cedc).

Evidence for the route test (older tree, before Phase 16 and the FIFO queue):

- macos-route run on 2026-10-28 06:55: `ROUTE-HWDEC-REF {"sample":"hevc-8bit",
  "hwdecCurrent":"no","screenshotPath":"vo","nonBlackRatio":0.0,"valid":false,
  "textureVisibility":"texture-visible"}`, then the videotoolbox leg
  `"screenshot":"mismatch","screenshotDiff":125.9009 ... "flutterFrame":"match"`.
- Same run family as native-verify: bad captures are isolated per capture and
  vary continuously (nonBlack 0 / 0.00003 / 0.007; diff 10 / 54 / 129).

## Constraint

`macos_route_probe.dart` documents that the thresholds (`routeMinNonBlackRatio`,
`routeFrameMaxMeanAbsDiff`) are not relaxed without a user decision. The fix
below keeps every threshold and only raises the evidence quality.

## Solution

1. In `_runSample`, take the frame through `routeStableCapture` (already in
   `macos_route_probe.dart`, with its unit tests in
   `example/test/macos_route_probe_test.dart`) instead of a single
   `player.screenshot()`, and print `ROUTE-NOTE screenshot: ...` for every
   discarded capture, as `hwdec_zero_copy_test.dart` does with `HWDEC-NOTE`.
2. Keep the `bgr0` format check and the `_screenshotTimeout` per capture; the
   helper treats a null capture as "unavailable".
3. Verify with several macos-route runs on one SHA (the pre-hardening failure
   rate of the sibling check was about 2 of 3), and look for `ROUTE-NOTE`
   lines in green runs as proof that a flake was absorbed.
4. Do not combine with a change of the thresholds or of the golden files.
