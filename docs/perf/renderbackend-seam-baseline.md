# RenderBackend Seam Baseline — BEFORE Phase 12 (pre-RenderBackend, pre-fix)

**Machine:** Windows 11 (MINGW64_NT-10.0-26300), x64, NVIDIA GeForce RTX 4060 Laptop GPU, driver 617.42
**Date:** 2026-10-26 (runs 10:16:36Z – 10:29:10Z, strictly serial)
**Flutter:** 3.47.8 stable, framework 737ba8f885, engine cf636b1dfb (hash dfd2e6cb7d), Dart 3.13.7
**libmpv:** mpv_kit_libs hook build v0.1.0-dev.3 windows-x64 (`libmpv-2.dll` sha256 `a21d4797891aa164fbc3477d6ceb8abfac9496818a849b5c67afa80236a6376c`), Vulkan gpu-next on the RTX 4060 in every run
**Code state:** `baseline_sha` = `5de4f8f5c3cb6901c048924ef9dd50060802b3d9`. At this SHA, `packages/mpv_kit_video/src` and `packages/mpv_kit_video/windows` are byte-identical to `3a5f450`, which is the native render path before the refactor and before the 12-07 fix. The paths were still unchanged after the last run (`native_unchanged_during_runs=yes`).
**Machine-readable record:** `.planning/phases/12-renderbackend-seam/evidence/baseline-runs.txt`. Raw logs and traces are in the same directory under `baseline-*.log` and `baseline-*.trace`.

**Status (2026-10-26T10:47:53Z): attempt 2 incomplete, 3 of 6 groups recorded.** At the Task 3 checkpoint the user invalidated all six `attempt=1` runs as `run-conditions-unverified`. Nobody had watched the example window during the runs, and the desktop probe ran only before and after each run, with the foreground window being TaskBarHero rather than the example. The attempt-1 lines stay in `baseline-runs.txt` unchanged, each followed by an appended `invalid run=… attempt=1` line. Their rows are kept under [Invalidated attempts](#invalidated-attempts-attempt-1). Attempt 2 runs the same commands at HEAD `dcdbc5cd8f15cca1408e6186fe4770cad48b99da`, where the native render path is still byte-identical to `3a5f450`. Its files carry an `-a2` suffix. During each run, a background PowerShell sampler records every 2 s the foreground window's owning process and title, plus whether the `mpv_kit_example` main window is visible, iconic, or foreground (`baseline-*-a2.fg.txt`). The sampler only observes and never moves, resizes or focuses a window. Attempt 2 halted after `cycles-on`: `cs2.exe` (Counter-Strike 2) started at 10:47:02Z, during that run, and was still running afterwards. That breaks the "no other GPU program" condition, so `cycles-off`, `resize-front-on` and `resize-front-off` were not started.

Attempt 1 (invalidated): every group ran once. Each run was started only after the previous flutter process had exited. Before and after every run, the count of stray `mpv_kit_example.exe` processes was 0 and the desktop probe read `unlocked`: no LogonUI in the session, a non-zero foreground window, an openable input desktop, and no Modern Standby entry after the 10:00:59Z exit. The probe cannot show whether the example window was visible and uncovered.

## Reproduce

Run from `example/`, with the example window kept visible:

```sh
LIB=D:/mpv_kit/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.3/windows-x64/lib
E=D:/mpv_kit/.planning/phases/12-renderbackend-seam/evidence
F=D:/flutter/bin/flutter
cd D:/mpv_kit/example

# engine renderer identity (flutter test does not forward the engine log)
MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" timeout 75 $F run -d windows --enable-impeller    | tee "$E/baseline-identity-on.log"
MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" timeout 75 $F run -d windows --no-enable-impeller | tee "$E/baseline-identity-off.log"

# d05: part 1 -> part 2 (4K) -> 100 resize/dispose rounds, >= 30 s
MPV_KIT_SMOKE_TRACE="$E/baseline-d05-on.trace"  MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --enable-impeller    | tee "$E/baseline-d05-on.log"
MPV_KIT_SMOKE_TRACE="$E/baseline-d05-off.trace" MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller | tee "$E/baseline-d05-off.log"

# cycles: 100 create/dispose (MPV_KIT_SMOKE_ROUNDS default 100)
MPV_KIT_SMOKE_MODE=cycles MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --enable-impeller    | tee "$E/baseline-cycles-on.log"
MPV_KIT_SMOKE_MODE=cycles MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller | tee "$E/baseline-cycles-off.log"

# resize-front: setSize on a controller with a published front (default 5 rounds)
MPV_KIT_SMOKE_DIAG=resize-front MPV_KIT_SMOKE_TRACE="$E/baseline-resize-front-on.trace"  MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --enable-impeller    | tee "$E/baseline-resize-front-on.log"
MPV_KIT_SMOKE_DIAG=resize-front MPV_KIT_SMOKE_TRACE="$E/baseline-resize-front-off.trace" MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller | tee "$E/baseline-resize-front-off.log"
```

The exit code is the flutter `PIPESTATUS[0]`. Every trace file is truncated when its run's first marker is written. Attempt 2 runs the same commands, with `-a2` inserted before the extension in every log and trace path (`baseline-d05-on-a2.log` and so on). Its foreground samples go to `baseline-<group>-<switch>-a2.fg.txt`.

## Engine renderer identity

| Switch | Command | rc | `Using the Impeller rendering backend` lines | Note |
|--------|---------|----|---------------------------------------------|------|
| on  | `flutter run -d windows --enable-impeller`    | 124 (timeout end, normal) | **1** | `embedder_surface_gl_impeller.cc(126)] Using the Impeller rendering backend (OpenGLESSDF).` |
| off | `flutter run -d windows --no-enable-impeller` | 124 (timeout end, normal) | **0** | the app ran (56 `mpv_kit_example:` stats lines, `mpv_kit_video: vulkan (gpu-next)`), so 0 is not a launch failure |

`flutter test` does not forward this engine line. For the six harness runs, the switch is therefore established by the command-line flag, and the identity table above shows that the flag takes effect. Attempt 2 reuses these attempt-1 identity runs (`attempt2_identity` in `baseline-runs.txt`). The plan requires an identity per switch, not per attempt, and the engine log line does not depend on whether the window is visible.

## Results (attempt 2, measured record)

| group | switch | engine renderer lines | exit | result | key values | fg_during (2 s samples) | example window |
|-------|--------|-----------------------|------|--------|------------|-------------------------|----------------|
| d05 | on  | 1 | 79 | aborted | parts oneFrame=ok, uhd4k=ok; soak round 1 started, 0 rounds done; pixelProbe nonBlackRatio 0.0 (**872x385**, before-first-frame, fpsAtProbe null, timePosDelta 0.0); renderErrors 0, deviceLost 0; last_marker `t=32939 round=1 step=dispose-begin`; forensics none | TaskBarHero:17, mpv_kit_example:13, steamwebhelper:1 | visible and not iconic in 16/16 samples with a window; foreground 13/18 running samples, continuously from 10:43:22Z to 10:43:46Z (end of run) |
| d05 | off | 0 | 79 | aborted | parts oneFrame=ok, uhd4k=ok; soak round 1 started, 0 rounds done; pixelProbe nonBlackRatio 0.0 (1266x683, before-first-frame, fpsAtProbe null, timePosDelta 0.0); renderErrors 0, deviceLost 0; last_marker `t=33036 round=1 step=dispose-begin`; forensics none | WindowsTerminal:20, msedge:9, mpv_kit_example:3 | visible and not iconic in 17/17; foreground only 10:45:36Z–10:45:40Z (3/17), WindowsTerminal foreground from 10:45:42Z to the end |
| cycles | on  | 1 | 0 | complete (**GPU condition not met**) | completed 100/100, failures 0, controllers 101, renderErrors 0, deviceLost false; RSS 286420992 → 343982080 (+57561088 B, +54.9 MiB); `cs2.exe` started 10:47:02Z during the run | TaskBarHero:20, cs2:3, steamwebhelper:1, explorer:1 | visible and not iconic in 10/10 with a window; never foreground (0/12); cs2 foreground from 10:47:23Z |
| cycles | off | 0 | — | not run | halted: `cs2.exe` running (precondition unmet) | — | — |
| resize-front | on  | 1 | — | not run | halted: `cs2.exe` running (precondition unmet) | — | — |
| resize-front | off | 0 | — | not run | halted: `cs2.exe` running (precondition unmet) | — | — |

"foreground" is `GetForegroundWindow` equal to the example's `MainWindowHandle`. A window that is not in the foreground can still be uncovered, and the sampler cannot tell whether another window overlaps it. The user, who watched the window, confirms that. In d05-on, the part-2 pixel probe read an 872x385 surface where every other d05 run read 1266x683. The record does not establish why.

Attempt 2 compared with attempt 1, for the groups recorded so far: d05 aborted again under both switches, with the same shape and the same last marker (`round=1 step=dispose-begin`, 18 ms (on) and 24 ms (off) after `round-start`), exit 79 and no crash forensics. cycles-on again completed 100/100 with 0 failures (+54.9 MiB, against +60.2 MiB in attempt 1). That run had a concurrent GPU program, though.

## Invalidated attempts (attempt 1)

All six rows are `invalid … reason=run-conditions-unverified`, and none is a measured record. They are kept because the protocol never deletes an attempt.

| group | switch | engine renderer lines | exit | result | key values |
|-------|--------|-----------------------|------|--------|------------|
| d05 | on  | 1 | 79 | aborted | parts oneFrame=ok, uhd4k=ok; soak round 1 started, 0 rounds done; seconds: n/a (no complete line); pixelProbe nonBlackRatio 0.0 (1266x683, probeTiming before-first-frame, fpsAtProbe null, timePosDelta 0.0); renderErrors 0, deviceLost 0 at last marker; last_marker `round=1 step=dispose-begin` |
| d05 | off | 0 | 79 | aborted | parts oneFrame=ok, uhd4k=ok; soak round 1 started, 0 rounds done; seconds: n/a; pixelProbe nonBlackRatio 0.0 (1266x683, probeTiming before-first-frame, fpsAtProbe null, timePosDelta 0.0); renderErrors 0, deviceLost 0 at last marker; last_marker `round=1 step=dispose-begin` |
| cycles | on  | 1 | 0 | complete | completed 100/100, failures 0, controllers 101, renderErrors 0, deviceLost false; RSS 288616448 → 351690752 (+63074304 B, +60.2 MiB) |
| cycles | off | 0 | 0 | complete | completed 100/100, failures 0, controllers 101, renderErrors 0, deviceLost false; RSS 269660160 → 353546240 (+83886080 B, +80.0 MiB) |
| resize-front | on  | 1 | 79 | aborted | 0 of 5 rounds complete; no `DIAG resize-front complete` line; last_marker `round=1 step=set-size-640-done` (resizeEvents=1) |
| resize-front | off | 0 | 79 | aborted | 0 of 5 rounds complete; no `DIAG resize-front complete` line; last_marker `round=1 step=set-size-640-done` (resizeEvents=1) |

"engine renderer lines" is the identity count for that switch, taken from the `flutter run` logs. cycles mode has no pass rule (it never calls `_classify`), so a run that reports every cycle is classified `complete` rather than `pass`. The cycles RSS growth is the in-process `ProcessInfo.currentRss` difference across 100 cycles. It is not comparable to the 50-cycle, 5-warm-up figure in `2026-10-24-baseline.md`.

### Raw BENCH / DIAG lines (attempt 1, invalidated)

The `dart` field of the preflight line is the same in every run: `3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "windows_x64"`. Each preflight line names `mpvKitPath` = the bundle above, and the log prints `mpv_kit_video: vulkan (vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU)`.

- d05 on: `BENCH impeller {"stage":"soak-start","parts":{"oneFrame":"ok","uhd4k":"ok","soak":"inconclusive"},"rssBytes":465575936,"pixelProbe":{"supported":true,"nonBlackRatio":0.0,"width":1266,"height":683,"probeTiming":"before-first-frame","fpsAtProbe":null,"timePosDelta":0.0}}`
- d05 off: `BENCH impeller {"stage":"soak-start","parts":{"oneFrame":"ok","uhd4k":"ok","soak":"inconclusive"},"rssBytes":449216512,"pixelProbe":{"supported":true,"nonBlackRatio":0.0,"width":1266,"height":683,"probeTiming":"before-first-frame","fpsAtProbe":null,"timePosDelta":0.0}}`
- cycles on: `BENCH impeller {"stage":"cycles","cycles":100,"completed":100,"failures":0,"rssStart":288616448,"rssEnd":351690752,"controllers":101,"renderErrors":0,"deviceLost":false}`
- cycles off: `BENCH impeller {"stage":"cycles","cycles":100,"completed":100,"failures":0,"rssStart":269660160,"rssEnd":353546240,"controllers":101,"renderErrors":0,"deviceLost":false}`
- resize-front on/off: preflight only; no DIAG complete line.

All four aborted runs end the same way in the log: `did not complete [E]`, `Some tests failed.`, `No tests were found.`, then a listener-cleanup `PathNotFoundException`.

## Soak abort

The analysis below was written from attempt 1, which is now invalidated. In attempt 2, both d05 runs reproduced the same shape and the same last marker (see the attempt-2 table), and resize-front was not yet re-run.

**Reproduced: yes, under both switches, with the same shape.**

- **d05.** Parts 1 and 2 completed. `soak-start` was printed at about t=32.8 s, which is part 2 plus a 30 s readiness gate that timed out (see Pixel probe). The trace shows soak round 1 running in `_remountCycle` order: `round-start` → `unmount-begin/done` → `frame-after-unmount-begin/done` → `set-size-begin` → `set-size-done` → `dispose-begin`. Round 1's `nextSize` is 1280x720, applied to the part-2 4K controller after its texture was unmounted. No marker after `dispose-begin` was written. The process was gone about 18 ms (on) or 16 ms (off) after `round-start`. The trace and the console agree.
  - on: `t=32862 round=1 step=dispose-begin rss=467562496 resizeEvents=2 idleSoak=0 renderErrors=0 deviceLost=0 controllers=2`
  - off: `t=32952 round=1 step=dispose-begin rss=446255104 resizeEvents=2 idleSoak=0 renderErrors=0 deviceLost=0 controllers=2`
- **resize-front.** Round 1 created a controller, opened the source, applied `setSize(1280, 720)`, received the first resize event and held the mounted front for 500 ms. It then called `setSize(640, 360)` while the texture was still mounted. `set-size-640-done` is the last marker. `second-resize-wait-done` was never written, so the process vanished before a second resize event arrived.
  - on: `t=1254 round=1 step=set-size-640-done rss=453357568 resizeEvents=1 idleSoak=0 renderErrors=0 deviceLost=0 controllers=2`
  - off: `t=1247 round=1 step=set-size-640-done rss=432340992 resizeEvents=1 idleSoak=0 renderErrors=0 deviceLost=0 controllers=2`
  - Compared with the 12-02 self-check (2 rounds, `--no-enable-impeller`, not evidence): that run got one step further, to `second-resize-wait-done` and `hold-resized-begin`, before it vanished. Both runs lost the process in round 1, within 500 ms of `setSize(640, 360)` on a controller with a published front.
- **Exit code.** Every aborted run exited 79. This is package:test `noTests` (the log prints `No tests were found.`), the same code 10-05 recorded. It is not a native crash code.
- **Forensics** (for every aborted run, checked right after it ended):
  - `%LOCALAPPDATA%/CrashDumps` has no new dump. The newest entry is `TaskBarHero.exe.15664.dmp` from 2026-10-18.
  - The Application log has no Id 1000/1001 event in the preceding 20 minutes.
  - Nothing names `mpv_kit_example.exe` or `flutter_windows.dll`.
  - Recorded as `forensics=none`.
- **Comparison with 10-05.** 10-05 recorded the process vanishing after `soak-start`, exit 79 and no WER. That matches here, and the trace now pins the last completed step: `dispose-begin` in round 1 for d05, and `set-size-640-done` in round 1 for resize-front.
- **Attribution: unexplained.** No crash evidence names any module, so this baseline does not attribute the abort to Impeller, Skia, the renderer or any other component. The abort shape is the same with Impeller on and off.

## Pixel probe

`probe-control.txt` (12-02) records `probe_decision: readiness-gate`. `RepaintBoundary.toImage` does see the external texture with Impeller on and off (`probe_visibility_on/off: texture-visible`, stable, after-first-frame). Part 2 therefore reads pixels only after `_firstFrameGate`: `estimated-vf-fps > 0` and `time-pos` advancing by at least 0.2 s, within 30 s. The pass rule is unchanged (`_minNonBlackRatio = 0.01`, whole-image sampling).

In both d05 runs, the gate did **not** observe presented frames. It returned `probeTiming: before-first-frame` with `fpsAtProbe: null` and `timePosDelta: 0.0` after its 30 s deadline, and the probe that followed read `nonBlackRatio: 0.0` on the 1266x683 surface. Under the readiness-gate decision, that probe channel is known to see the texture. The 0.0 reading is therefore recorded together with the fact that no frame presentation was observed in part 2 (`estimated-vf-fps` unavailable for 30 s, `time-pos` not advancing after the 4K controller was created). This baseline does not establish why playback produced no measurable frames in part 2. `_classify` was never reached, because both runs aborted before `stage:complete`. Had it been reached, this probe would not have met the `nonBlack` condition.

## Candidate cause (unverified here)

This is the planning-time code-reading conclusion from the 12-02 objective, restated as written there. It was **not verified in this plan. 12-07 decides it with golden tests.**

> 10-05's measured path calls `setSize(1280, 720)` in soak round 1 on part 2's 4K controller, which has already published frames. That triggers the `keep_front` reallocation in `RenderOnce`. `VulkanContext::AllocateRing` keeps the old front with `retired_.push_back(std::move(*keep_retired))`. But `SharedImage` is an aggregate, so the move is a copy and the source slot stays non-empty. `DestroyAll(ring_)` then destroys it immediately, and `FreeRetired` or the destructor destroys it a second time (a double destroy). If the compositor picks up `retired_front_` in the meantime, `RetainFrame` also retains a platform object that has already been released. Neither 10-07 diag mode reached this shape. `soak-after-4k`'s preceding `_remountCycle(round: 0)` passes no size, and every later round is the first allocation of a fresh controller that has never been sized. That is consistent with those modes not reproducing it. (Source: `video_renderer.cc:478-509` keep_front path, `vulkan_backend.cc:363-384` `AllocateRing`.)

This baseline only records where each run's last trace marker sits relative to that path. No crash evidence ties the abort to it.
