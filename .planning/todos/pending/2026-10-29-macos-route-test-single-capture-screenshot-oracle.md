---
created: 2026-10-29T00:00:00.000Z
title: Harden the macos_route_test.dart single-capture screenshot oracle (macos-route.yml)
area: testing
severity: minor
resolved: 2026-10-30
resolved_by: quick 261030-5v4 (4285f2b)
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

## Resolution (quick 261030-5v4)

Resolved 2026-10-30 by quick 261030-5v4 (commit 4285f2b). `_runSample` now takes
the frame through `routeStableCapture` (two agreeing non-black captures of the
same paused frame, at most 5, 300 ms apart) and prints
`ROUTE-NOTE screenshot: capture <n>/<max> ...; taking another` for every
discarded capture. `_screenshot` keeps the `bgr0` check and the
`_screenshotTimeout` per capture; thresholds, golden files, product code and
public API are unchanged.

Trigger: macos-route runs 40937808507 (6f6631c), 40939860844 (127a348) and
40943562936 (c00e843) were red with the h264-8bit videotoolbox leg
`zero-copy-bad-frame`, `screenshot: mismatch`, `screenshotDiff 58.9165` while the
reference leg was valid (nonBlackRatio 1.0). The files macos-route.yml depends on
(packages/, native/, example/, the workflow, tools/macos_frame_probe.patch,
tools/check_route_probe.py, the pinned bundle) have an empty `git diff
0e149da c00e843`, so quick 261030-3pc did not cause it.

Evidence: macos-route 40947581802 on 4285f2b is green (all four HWDEC legs
`zero-copy`). It printed no `ROUTE-NOTE` line, so this sample does not itself
show an absorbed flake. Second sample 40949963643 on 8f06b0b: green, also no `ROUTE-NOTE`.
