# RenderBackend Seam Regression — AFTER Phase 12 (RenderBackend seam)

**Machine:** Windows 11 (MINGW64_NT-10.0-26300), x64, NVIDIA GeForce RTX 4060 Laptop GPU, driver 617.42
**Date:** 2026-10-27, strictly serial, from 00:33:00Z to 01:51:47Z.
**Flutter:** 3.47.8 stable, engine cf636b1dfb (hash dfd2e6cb7d), Dart 3.13.7
**libmpv:** mpv_kit_libs hook build v0.1.0-dev.3 windows-x64 (`libmpv-2.dll` sha256 `a21d4797891aa164fbc3477d6ceb8abfac9496818a849b5c67afa80236a6376c`). Every harness log prints `mpv_kit_video: vulkan (vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU)`.
**Machine, toolchain and bundle** are identical to the pre-move reference (`postfix-runs.txt` header).
**Machine-readable record:** `.planning/phases/12-renderbackend-seam/evidence/final-runs.txt`. Raw files are `final-*.log`, `final-*.trace` and `final-*.fg.txt` in the same directory.

## Code state

- `final_sha` = `d04ab9625a35dd948da18768d1080773e17efdbd`, the Phase 12 final HEAD. Its code tree (`packages`, `example`, `native`) is identical to `c3edb9e`.
- The hosted CI full gate passed for `a3dc4c2`: native-verify `40421971121` and flutter-plugin `40421971099`. `d04ab96` changes only docs after it. The seven close-out audits are all `ok` (`evidence/final-audit.txt`).
- The native render path differs from the pre-move reference (`postfix_sha` `59281b3`) in `render_backend.h`, `video_renderer.cc`, `video_renderer.h`, `vulkan_backend.cc` and `windows/mpv_kit_video_plugin.cpp`. These are the 12-09 move, the 12-10 forced switch and the 12-11 move of swap reporting to the render thread.
- Runs were started at HEADs `c4214c0` through `53bdf8c`. Each of them differs from `final_sha` only in `.planning/` evidence files.
- Every run was preceded by a passing gate with `native_equal_to_final=yes`. After the last run, `native_unchanged_during_runs=yes`.
- golden freeze: 5/5 OK in Task 1 and again after the last run (01:52:20Z).

## Method

The commands are the 12-04/12-08 commands, verbatim (`renderbackend-seam-baseline.md` Reproduce), with `final-` in place of `baseline-` in every output path. Every trace path is absolute. Each group ran attempt 1, except d05-on (see "Invalidated attempt").

**Gate before every run:**

- the desktop is unlocked, and the foreground is not LockApp or LogonUI
- no cs2, dota2 or csgo, and no new executable under `steamapps\common`
- no non-dwm process at 10% or more GPU engine
- 0 stray example processes
- the native path equals `final_sha`
- the 12-12 precondition: at least 5.5 GB (5632 MiB) free on the repo filesystem D:

During each run, sampler v2 recorded the foreground every 2 s. After each run, read-only forensics checked for crash dumps and Application 1000/1001 events, and `standby.ps1` checked for Kernel-Power 506/507 events. TaskBarHero and `UnityCrashHandler64` are known background processes, which the user accepted in 12-04. TaskBarHero exited at about 01:00:12Z, and every sample after that shows `games=none`.

**Interruptions** (all recorded as `halt=` and `resume=` lines):

1. **00:27:28Z:** the uhd4k gate failed with D: at 975 MiB free. The user replied "只删 flutter_build 缓存" (delete only the flutter_build cache). The orchestrator deleted `example/.dart_tool/flutter_build`, leaving 5865 MiB free.
2. **01:29:42Z:** the d05-off gate failed with D: at 5630 MiB free, 2 MiB below the minimum. The user replied "continue" after freeing space, and D: had 8003 MiB free.

No run was launched under a failed gate. The executor deleted nothing.

## Reproduce

Run from `example/`, with the example window kept visible:

```sh
LIB=D:/mpv_kit/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.3/windows-x64/lib
E=D:/mpv_kit/.planning/phases/12-renderbackend-seam/evidence
F=D:/flutter/bin/flutter
cd D:/mpv_kit/example

# 4K 30 minutes (Phase 4 command; never calls setSize, so it does not render)
MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 MPV_KIT_BENCH_LABEL=4k \
  MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/uhd_endurance_test.dart -d windows | tee "$E/final-uhd-4k.log"

# rendered 4K, 600 s (12-08 command)
MPV_KIT_BENCH_RENDER=1 MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=600 MPV_KIT_BENCH_LABEL=4k-rendered \
  MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/uhd_endurance_test.dart -d windows | tee "$E/final-uhd4k-rendered.log"

# engine renderer identity
MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" timeout 75 $F run -d windows --enable-impeller    | tee "$E/final-identity-on.log"
MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" timeout 75 $F run -d windows --no-enable-impeller | tee "$E/final-identity-off.log"

# d05, cycles, resize-front (d05-on ran as attempt 2: -a2 before every extension)
MPV_KIT_SMOKE_TRACE="$E/final-d05-on-a2.trace" MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --enable-impeller    | tee "$E/final-d05-on-a2.log"
MPV_KIT_SMOKE_TRACE="$E/final-d05-off.trace"   MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller | tee "$E/final-d05-off.log"
MPV_KIT_SMOKE_MODE=cycles MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --enable-impeller    | tee "$E/final-cycles-on.log"
MPV_KIT_SMOKE_MODE=cycles MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller | tee "$E/final-cycles-off.log"
MPV_KIT_SMOKE_DIAG=resize-front MPV_KIT_SMOKE_TRACE="$E/final-resize-front-on.trace"  MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --enable-impeller    | tee "$E/final-resize-front-on.log"
MPV_KIT_SMOKE_DIAG=resize-front MPV_KIT_SMOKE_TRACE="$E/final-resize-front-off.trace" MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" PATH="$PATH:$LIB" $F test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller | tee "$E/final-resize-front-off.log"
```

The exit code is the flutter `PIPESTATUS[0]`. The run script refuses to start if any target file already exists.

## 4K, 30 minutes — compared with Phase 4

The reference is `docs/perf/2026-10-24-uhd-endurance.md`. **This command does not render:** it never calls `setSize`, so no frame reaches a shared image. It shows decode and A/V timing parity only. The rendered check is the next section.

Attempt 1 ran from 00:33:00Z to 01:03:43Z: the full 1800 s, exit 0, `All tests passed!`.

| Gate / metric | Phase 4 | Phase 12 final | Verdict |
|---------------|---------|----------------|---------|
| frame-drop-count (final) | 0 | 0 | same |
| decoder-frame-drop-count (final) | 0 | 0 | same |
| vo-delayed-frame-count (avg / max) | 0 / 0 | 0.0 / 0 | same |
| avsync (peak abs) | 4.74e-05 s | 4.45e-05 s | same (microsecond-scale) |
| total-avsync-change (final) | -0.0333 s | -0.0333 s | same (bounded, one frame) |
| estimated-vf-fps (final) | 30.0 | 30.0 | same |
| renderErrors / deviceLost | 0 / false | 0 / false | same |
| display-sync-active | false | false | same |
| RSS (end), not a gate | 826 MB | 834 MB (833777664 B) | differs (+8 MB) |
| run conditions | not recorded | **interrupted by Modern Standby twice** | differs |

All 30 per-minute samples (t=11 … 1751 s) show frame-drop 0, decoder-drop 0, vo-delayed 0 and estimated-vf-fps 30.0.

**Run conditions:**

- **Modern Standby, twice:**
  - Kernel-Power 506 at 00:35:45.407Z, then 507 at 00:36:43.544Z (58 s).
  - 506 at 00:40:14.547Z, then 507 at 00:40:33.586Z (19 s).
  - The sampler shows `fg=none` over the same intervals.
  - The samples at t=131 s (inside the first interval) and t=431 s (just after the second) still read drops 0, vo-delayed 0 and vf-fps 30.0.
  - The cause was not established. The machine was on AC, and the display idle timeout read after the run was 3600 s.
- **Window:** visible and not iconic in 794 of 795 running samples, never iconic, and in the foreground in 343/795. The other foreground owners were TaskBarHero (368), WindowsTerminal (34), none (33, the standby intervals), a Settings window "设置" (30, 01:00:41Z–01:01:52Z) and explorer (3).
- **Rect:** `1280x720@10,10` in every sample (1 distinct).
- **Pointer tap:** the log has one `No widgets found at Offset(646.0, 419.3).` line, which `LiveTestWidgetsFlutterBinding` prints for a pointer tap in the test window.
- **Forensics:** none.

Plan action 6 applies: the user decides at Task 3 whether to repeat the full 1800 s run because of the standby intervals.

## Rendered 4K, 600 s — compared with 12-08

The reference is the `### Rendered 4K reference (600 s)` table in `renderbackend-seam-baseline.md`, from the same command under default switches. This is the phase's real-hardware timing check of the refactor, including 12-11's move of swap reporting to the render thread.

Attempt 1 ran from 01:07:36Z to 01:18:24Z: exit 0, `All tests passed!`, `"rendered":true`.

| Item | 12-08 reference | Phase 12 final | Verdict |
|------|-----------------|----------------|---------|
| frameDropCountFinal | 0 | 0 | same |
| decoderFrameDropCountFinal | 0 | 0 | same |
| voDelayedFrameCount avg / max | 0.0 / 0 | 0.0 / 0 | same |
| avsyncPeakAbs | 1.34e-05 s | 1.62e-05 s | **worse** (+2.8 µs) |
| totalAvsyncChangeFinal | -0.0333 s | -0.0333 s | same |
| estimatedVfFpsFinal | 30.0 | 30.0 | same |
| renderErrors | 0 | 0 | same |
| deviceLost | false | false | same |
| rssBytes, not a gate | 829779968 | 816308224 | better (-13.5 MB) |

All 10 per-minute samples show frame-drop 0, decoder-drop 0, vo-delayed 0 and estimated-vf-fps 30.0.

**About the `worse` marking:** the plan defines no threshold for `avsyncPeakAbs`, so any increase is marked worse. Both values are microsecond-scale, and one frame at 30 fps is 33.3 ms. The marking goes to the user at Task 3.

**Run conditions:** these are cleaner than the reference.

- No standby events and `games=none` in all 288 samples.
- Window visible and not iconic in 268 of 270 running samples, never iconic, and in the foreground in 268/270.
- Rect `1280x720@10,10` in every sample, with no pointer-tap lines.
- In the 12-08 reference, the window was resized and moved by hand, and TaskBarHero held the foreground from 19:50:45Z. The user accepted those conditions.
- Forensics: none.

## Engine renderer identity

| Switch | rc | `Using the Impeller rendering backend` lines | Note |
|--------|----|---------------------------------------------|------|
| on  | 124 (timeout end, normal) | **1** | `embedder_surface_gl_impeller.cc(126)] Using the Impeller rendering backend (OpenGLESSDF).`; 40 stats lines (12-08: 55; the 75 s timeout includes the build) |
| off | 124 (timeout end, normal) | **0** | the app ran (54 `mpv_kit_example:` stats lines, `mpv_kit_video: vulkan (gpu-next)`), so 0 is not a launch failure |

Both match the pre-move reference.

## Harness groups — compared with the pre-move reference (after fix)

The reference is `## pre-move reference (after fix)` in `renderbackend-seam-baseline.md` and the `run=` lines in `postfix-runs.txt`. The pre-fix section is not used.

**Verdict rules (from the plan):**

- the result class must not get worse (pass < inconclusive < failed < aborted)
- cycles failures must not increase
- a resize-front group that was complete in the reference must still be complete
- cycles RSS growth above 2× the reference is flagged

| group | switch | attempt | exit | pre-move reference (after fix) | Phase 12 final | verdict |
|-------|--------|---------|------|--------------------------------|----------------|---------|
| d05 | on  | 2 | 0 | failed, pixel probe only; 100/100 rounds in 41.898 s; RSS +206.7 MiB | failed, pixel probe only (nonBlackRatio 0.0, 1266x683, before-first-frame, fpsAtProbe null, timePosDelta 0.0); **100/100 rounds in 43.728 s**; parts oneFrame/uhd4k/soak ok; renderErrors 0, gpuTimeouts 0, deviceLost false; RSS 288911360 → 533655552 (+233.4 MiB, 1.13×); last_marker `t=76554 round=100 step=round-end … controllers=102` | no-new-failure |
| d05 | off | 1 | 0 | failed, pixel probe only; 100/100 rounds in 41.873 s; RSS +191.7 MiB | failed, pixel probe only (same reading); **100/100 rounds in 43.768 s**; parts ok; renderErrors 0, gpuTimeouts 0, deviceLost false; RSS 271040512 → 518078464 (+235.6 MiB, 1.23×); last_marker `t=76505 round=100 step=round-end … controllers=102` | no-new-failure |
| cycles | on  | 1 | 0 | complete 100/100, 0 failures, +66.8 MiB | complete 100/100, **0 failures**, controllers 101, renderErrors 0, deviceLost false; RSS 288231424 → 354942976 (+63.6 MiB, 0.95×) | no-new-failure |
| cycles | off | 1 | 0 | complete 100/100, 0 failures, +80.8 MiB | complete 100/100, **0 failures**, controllers 101, renderErrors 0, deviceLost false; RSS 271532032 → 320700416 (+46.9 MiB, 0.58×) | no-new-failure |
| resize-front | on  | 1 | 1 | inconclusive, 1 of 5 rounds, round-2 StateError after the 30 s wait | inconclusive, **1 of 5 rounds**; round 1 through `dispose-done` (t=2001); round 2 `set-size-1280-done` t=2118, then `first-resize-wait-done` t=32126 and `StateError: resize-front: no 1280x720 resize in round 2`; process did not vanish | no-new-failure |
| resize-front | off | 1 | 1 | inconclusive, same ending | inconclusive, **1 of 5 rounds**; round 1 through `dispose-done` (t=2271); round 2 `set-size-1280-done` t=2384, then `first-resize-wait-done` t=32473 and the same StateError; process did not vanish | no-new-failure |

Neither resize-front reference was complete, so the "still complete" rule does not apply. Both runs keep the same class and the same ending. No cycles RSS growth reaches the 2× flag; both values are at or below the reference.

d05 RSS growth is 1.13× and 1.23× the reference. The plan's 2× flag rule covers cycles only, and these d05 values are recorded without a verdict.

### Run conditions per harness run (sampler v2, 2 s)

Every run passed its gate. Each had `games=none` in every sample, no standby, rect `1280x720@10,10` in every sample (1 distinct), 0 stray example processes before and after, and forensics `none`.

| run | fg_during | example window: running samples / visible and not iconic / iconic / foreground | foreground first – last (UTC) |
|-----|-----------|-------------------------------------------------------------------------------|-------------------------------|
| d05-on a2 | mpv_kit_example:35, explorer:15 | 36 / 35 / 0 / 35 | 01:27:32Z – 01:28:48Z |
| d05-off a1 | mpv_kit_example:35, WindowsTerminal:14 | 35 / 35 / 0 / 35 | 01:41:55Z – 01:43:10Z |
| cycles-on a1 | WindowsTerminal:15, mpv_kit_example:9 | 10 / 9 / 0 / 9 | 01:45:14Z – 01:45:32Z |
| cycles-off a1 | WindowsTerminal:15, mpv_kit_example:9 | 9 / 9 / 0 / 9 | 01:46:58Z – 01:47:16Z |
| resize-front-on a1 | WindowsTerminal:16, mpv_kit_example:14 | 16 / 14 / 0 / 14 | 01:49:03Z – 01:49:31Z |
| resize-front-off a1 | mpv_kit_example:15, WindowsTerminal:14 | 16 / 15 / 0 / 15 | 01:51:14Z – 01:51:46Z |

The sampler cannot tell whether another window covered the example window.

### Invalidated attempt

**d05-on attempt 1** (01:24:43Z–01:25:53Z, exit 1) is invalid. The executor passed `MPV_KIT_SMOKE_TRACE` as a repo-relative path. `flutter test` runs in `example/`, so the path did not resolve, and the harness threw `PathNotFoundException` before any soak round. It measured nothing about d05.

Its files stay as `final-d05-on.log` and `final-d05-on.fg.txt`. No trace was written, so `final-d05-on.trace` does not exist. Attempt 2 used the absolute path under the same gate. The executor made this invalidation, and the user confirms it at Task 3.

## Open findings (re-tested, observations only)

- **resize-front round 2 (12-08):** reproduced unchanged after the move under both switches.
  - Round 1 completes. Round 2, on a fresh controller, times out 30 s after `set-size-1280-done` with `resizeEvents=3` at the marker.
  - The likely unmet part of the wait is still `estimated-vf-fps > 0`.
  - The cause is still not established.
- **d05 part-2 pixel probe (12-08 candidate link):** unchanged. Both valid d05 runs read nonBlackRatio 0.0, before-first-frame, fpsAtProbe null, and `longestMountMs` was 32153 (on) and 32128 (off), against 32154 and 32193 in the reference. These runs neither confirm nor rule out the link to resize-front round 2: a second controller in the process may never receive presented frames.
- **nvidia-smi 42% at a 12-08 gate:** not repeated. This session's gates read 30% and 19% while TaskBarHero ran, then 0–2% for every later gate.
- **Modern Standby during the 4K 30-minute run:** new to this phase's records. See the 4K section. The user decides at Task 3 whether to repeat that run.

## Verification tiers

- **Hosted CI (proves the render path only):** the final-HEAD full gate passed on all native-verify jobs and all flutter-plugin build jobs.
  - Covered: golden_sw, golden_vk, api_test and affinity_test on linux x64, windows x64, macos arm64 and sanitizers; render_vk_smoke and render_vk_smoke_gpu; INTEGRATION and INTEGRATION-SOAK lines on all three integration-test platforms.
  - Those runners use the software path on WARP (Windows), xvfb plus lavapipe (Linux) and MoltenVK on an Apple Silicon VM (macOS). All of them render with hwdec=no.
  - Hosted CI does not prove real-GPU timing, hardware decode or long-run stability.
- **RTX 4060 (Windows 11, NVIDIA driver 617.42), real hardware:** this is the only tier where the conclusions above are real-hardware conclusions.
  - It covers the 4K 30-minute parity with Phase 4, the rendered 4K 600 s comparison with 12-08, engine renderer identity, and the six harness groups compared with the pre-move reference.
- **Unverified (未验证):**
  - Linux real GPU drivers (NVIDIA, AMD, Intel): not run in this phase.
  - macOS real hardware (Apple GPU through MoltenVK outside a VM): not run in this phase.
  - No result in this document applies to them.
