---
created: 2026-10-27T02:00:25.298Z
title: Diagnose second-controller first-frame stall in resize-front and d05
area: testing
severity: major
files:
  - example/integration_test/impeller_smoke_modes.dart:324-342
  - example/integration_test/impeller_smoke_modes.dart:620-640
  - packages/mpv_kit_video/src/video_renderer.cc
  - .planning/phases/12-renderbackend-seam/evidence/final-runs.txt
  - .planning/phases/12-renderbackend-seam/evidence/postfix-runs.txt
  - docs/perf/renderbackend-seam-regression.md
---

## Problem

Carried forward from Phase 12 (12-12 Task 3, user-approved close: "approved"). Phase 12 did not fix it. These are observations only. The cause has not been found.

Two RTX 4060 harness readings have stayed the same pre-fix (12-04), post-fix (12-08) and post-move (12-12), under Impeller on and off:

1. **resize-front round 2 timeout.** Round 1 completes through `dispose-done`. Round 2 runs on a fresh second controller in the same process, and it times out 30 s after `set-size-1280-done` with `StateError: resize-front: no 1280x720 resize in round 2` (thrown at `impeller_smoke_modes.dart:635`). At the marker `resizeEvents=3`, so the new resize event arrived. The unmet part of the wait is most likely `estimated-vf-fps > 0`. The process stays alive, and the result is `inconclusive` 1 of 5 rounds.
   - 12-12 on: set-size-1280-done t=2118 -> first-resize-wait-done t=32126. 12-12 off: t=2384 -> t=32473.
   - 12-08 on: t=2244 -> t=32290. 12-08 off: t=2016 -> t=32107.
2. **d05 part-2 pixel probe.** Every valid d05 run reads `nonBlackRatio 0.0`, `1266x683`, `probeTiming before-first-frame`, `fpsAtProbe null`, `timePosDelta 0.0`, with `longestMountMs` of about 32.1 s (12-12: 32153 on, 32128 off; 12-08: 32154, 32193). d05 therefore classifies as `failed (pixel probe only)` even though its 100/100 soak rounds complete.

Candidate link (neither confirmed nor ruled out): a second controller created in the same process may never receive presented frames, or `estimated-vf-fps` may stay unavailable for it.

Also recorded as unexplained during the 12-12 runs, with no action taken:
- Two Modern Standby intervals (Kernel-Power 506/507) during the 4K 30-minute run: 00:35:45Z-00:36:43Z and 00:40:14Z-00:40:33Z on 2026-10-27. The in-interval samples still read 0 drops and 30 fps.
- Free space on the temp filesystem dropped from 6523 to 4141 MiB during the runs. This filesystem is not gated.

Severity `major` was suggested by the executor and has not been confirmed by the user.

## Solution

TBD. Start with diagnosis only, under the Phase 12 harness rules: record every attempt and do not re-run until green.
- Trace whether the second controller's render thread renders and publishes any frame after `set-size-1280-done`: render calls, the publish gate, `FrameReady`, and swap reports on the render thread (12-11).
- Separate the two halves of the harness wait. Log `estimated-vf-fps` and the presented-frame count at each poll, so the result shows whether only the fps read is missing or no frames are presented.
- Check whether d05 part 2 hits the same condition. Its probe also runs on a controller created after an earlier one.
- Decide from the evidence whether the harness is wrong (e.g. `estimated-vf-fps` is the wrong readiness signal) or the product is.
