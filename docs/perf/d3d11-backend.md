# D3D11 backend on RTX 4060 — Phase 14 (14-09)

Real-hardware measurements of the D3D11 render backend, forced with `MPV_KIT_VIDEO_API=d3d11`, compared with the Phase 12 Vulkan references in `docs/perf/renderbackend-seam-regression.md`. The machine-readable record is `.planning/phases/14-windows-native-d3d11-backend/evidence/rtx4060-runs.txt`; raw logs (`rtx-*.log`), traces and foreground samplers (`rtx-*.fg.txt`) sit next to it. Hosted results (WARP) are not hardware evidence and are not used here.

## Machine and code state

- **Machine:** Windows 11 (MINGW64_NT-10.0-26300), x64, NVIDIA GeForce RTX 4060 Laptop GPU, driver 617.42, AC power.
- **Toolchain:** Flutter 3.47.8 stable, engine `dfd2e6cb7d31` (cf636b1dfb), Dart 3.13.7.
- **Code:** product `ad5c54b5dc8bfa69500d4dada6c59e8cb9ef0c72` (HEAD `15f61ff` is docs-only over it); example test source `f644220` (test-only change for 16-06).
- **libmpv bundle:** artifact `libmpv-windows-x64` of release run `40812562348` (`manifest=ok`), `libmpv-2.dll` sha256 `e63ccc2a6d89f431206654b81f125d69c28c656f66da319412e9b278b8ed9d3c`. The same bundle and session as 16-06; used through a temporary hooks `user_defines` in the root `pubspec.yaml` (reverted afterwards), which is a deviation from the plan's PATH-only text.
- **Backend identity:** every log prints `mpv_kit_video: vulkan (d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11)`. The leading `vulkan` is a label issue (see Follow-ups); the reason and the `HWDEC` lines (`api=d3d11`) identify the D3D11 backend.

## Reproduce

```sh
# temporary: bundle through hooks user_defines (never commit)
printf '\nhooks:\n  user_defines:\n    mpv_kit_libs:\n      libmpv_bundle: %s\n' "$(cygpath -m "$PWD/build/phase16/libmpv-rtx")" >> pubspec.yaml
export LIB="$PWD/build/phase16/libmpv-rtx/lib" MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" MPV_KIT_REQUIRE_LIBMPV=1
export PATH="$LIB:$PATH" FLUTTER=/d/flutter/bin/flutter R="$PWD"
E=.planning/phases/14-windows-native-d3d11-backend/evidence
cd example
# functional: fence (default) and query paths
MPV_KIT_VIDEO_API=d3d11 $FLUTTER test integration_test/d3d11_backend_test.dart -d windows
MPV_KIT_VIDEO_API=d3d11 MPV_KIT_D3D11_SYNC=query $FLUTTER test integration_test/d3d11_backend_test.dart -d windows
# rendered 4K, 600 s, default Impeller switch (run in the background)
MPV_KIT_VIDEO_API=d3d11 MPV_KIT_BENCH_RENDER=1 MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=600 MPV_KIT_BENCH_LABEL=4k-rendered-d3d11 \
  $FLUTTER test integration_test/uhd_endurance_test.dart -d windows
# D-05 harness, absolute trace paths
MPV_KIT_VIDEO_API=d3d11 MPV_KIT_SMOKE_TRACE="$R/$E/rtx-d05-d3d11-on.trace"  $FLUTTER test integration_test/impeller_smoke_test.dart -d windows --enable-impeller
MPV_KIT_VIDEO_API=d3d11 MPV_KIT_SMOKE_TRACE="$R/$E/rtx-d05-d3d11-off.trace" $FLUTTER test integration_test/impeller_smoke_test.dart -d windows --no-enable-impeller
# pickup latency: 150 s timeout, 140 s 4K60 lavfi source, window visible
MPV_KIT_VIDEO_API=d3d11 timeout 150 $FLUTTER run -d windows --enable-impeller    --dart-entrypoint-args 'av://lavfi:testsrc2=size=3840x2160:rate=60:duration=140[out0]'
MPV_KIT_VIDEO_API=d3d11 timeout 150 $FLUTTER run -d windows --no-enable-impeller --dart-entrypoint-args 'av://lavfi:testsrc2=size=3840x2160:rate=60:duration=140[out0]'
# afterwards: git checkout -- pubspec.yaml
```

Run conditions: unlocked desktop, window visible and untouched, no other GPU load, `steam`/`steamwebhelper` not running for the rerun of the 4K run, at least 5632 MiB free on `D:`. Every run had a gate line (desktop, foreground, GPU engine users, disk, stray processes) in the ledger, and a 2 s foreground sampler.

## Functional runs (D3D11 backend)

| Run | Result | Reason header | Probes | Events |
|---|---|---|---|---|
| fence (default) | pass | `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU` | red top 1.0, blue bottom 1.0, non-black 1.0; resize 640x360 and 320x180 all 1.0 | active, idle, resize |
| query (`MPV_KIT_D3D11_SYNC=query`) | pass | same; `"syncEnv":"query"` | same | same |

No `device_lost`, `render_error` or `gpu_timeout` events. Device-removal and creation-failure injection stay with hosted CI (14-08); the real-device "creation failure to Vulkan" path is verified after 14-11.

## Rendered 4K, 600 s, compared with Phase 12 Vulkan

Both attempts used `rendered:true` and the full 600 s.

**Attempt 1 failed its own gate and is kept in the ledger.** The test's fixed `drops==0` gate failed with `frameDropCountFinal=22` (all between t=191 and t=311, none after; decoder drops and vo-delayed 0 in every sample). The machine entered Modern Standby during that run (Kernel-Power 506@04:51:39Z to 507@04:52:14Z, 35 s), exactly the sampler's `fg=Idle` interval and the minute of the first 14 drops. The executor's first forensics query used the wrong time window and missed it; the correction is recorded in the ledger. Cause of the standby itself is not established.

**Attempt 2 (the record)**, after the user closed Steam and left the machine alone: exit 0, `All tests passed!`, no standby event, no crash dump, no TDR.

| Item | Phase 12 Vulkan (`uhd4k-rendered`) | D3D11 attempt 2 | Verdict |
|---|---|---|---|
| frameDropCountFinal | 0 | 0 | same |
| decoderFrameDropCountFinal | 0 | 0 | same |
| voDelayedFrameCountMax (avg) | 0 (0.0) | 0 (0.0) | same |
| avsyncPeakAbs | 1.62e-05 s | 2.01e-05 s | worse (+3.9 us; no threshold is defined, one frame at 30 fps is 33.3 ms) |
| renderErrors | 0 | 0 | same |
| deviceLost | false | false | same |
| estimatedVfFpsFinal | 30.0 | 30.0 | same |
| totalAvsyncChangeFinal | -0.0333 s | -0.0333 s | same |
| rssBytes (not a gate) | 816308224 | 820264960 | worse (+4 MB) |

All ten per-minute samples show frame-drop 0, decoder-drop 0, vo-delayed 0 and estimated-vf-fps 30.0. The window was visible, never iconic, never moved (1280x720 at 10,10); the foreground alternated between the example and WindowsTerminal in the sampler, and the log shows the same pointer finder lines as the Phase 12 run.

## D-05 harness (Impeller on / off), compared with Phase 12

Same harness and absolute trace paths as 12-04, `MPV_KIT_VIDEO_API=d3d11`. Result classes rank pass < inconclusive < failed < aborted.

| Switch | Phase 12 final (Vulkan) | D3D11 | Verdict |
|---|---|---|---|
| `--enable-impeller` | failed, 100 rounds, 43.7 s, pixel probe only (nonBlackRatio 0.0, 1266x683, before-first-frame, fpsAtProbe null), rss +233.4 MiB | failed, 100 rounds, 38.7 s, same pixel-probe signature, renderErrors 0, deviceLost false, rss +170.5 MiB | no-new-failure |
| `--no-enable-impeller` | failed, 100 rounds, 43.8 s, same signature, rss +235.6 MiB | failed, 100 rounds, 38.4 s, same signature, renderErrors 0, deviceLost false, rss +170.9 MiB | no-new-failure |

The failure class is the pre-existing pixel-probe finding (Phase 12 open finding `d05-part-2-pixel-probe`); D3D11 is not worse. Note the harness line prints `mpvBackend: vulkan` for the D3D11 run (same label issue as below).

## Consumer-side measurements (pickup, render waits)

Source: `flutter run` with the 4K60 lavfi source, 150 s timeout (exit 124 expected). Impeller identity: `Using the Impeller rendering backend` appears once in the on log and zero times in the off log, as the 12-04 rule requires.

| Impeller | pickup windows | pickup avg (median of windows) | pickup max | render waits prev (median) | render waits done (median) | max_done |
|---|---|---|---|---|---|---|
| on | 64 | 8.59 ms | 25.65 ms | 0.0059 ms | 3.56 ms | 5.32 ms |
| off | 65 | 8.55 ms | 40.58 ms | 0.0062 ms | 3.64 ms | 5.80 ms |

The isolation period stays 4 and no parameter was changed. Pickup latency measures how quickly the compositor takes a frame, not when ANGLE finishes reading it (the consumer side has no fence, ADR 0003 Q4); therefore it is not used to re-tune anything, and COMP-03 stays deferred.

## Hybrid-GPU laptops (14-10)

- **Machine:** GeForce GTX 960M + Intel HD 530, demo package 11b728a, user report 2026-10-29.
- **Observation:** Flutter/ANGLE stayed on the HD 530. The plugin binds to `GetGraphicsAdapter()` by design (shared textures cannot cross adapters), so d3d11va decode and d3d11 gpu-next rendering also ran on the HD 530: dropped 477-3310, dec-drop 0. The per-app "High performance" setting in Windows Settings did not move it; the cause is not established.
- **Opt-in:** the app picks its adapter before any plugin registers, so the plugin cannot do it. The app runner calls `project.set_gpu_preference(...)` (Flutter 3.41+, flutter/flutter#177653). The example runner is power-aware (D-04): `GetSystemPowerStatus` with AC online and battery saver off gives `HighPerformancePreference`, anything else (battery, saver, unknown, call failed) gives `NoPreference`, so Windows' per-app graphics setting decides. It decides once at startup and writes `mpv_kit_example: GPU preference high-performance (AC power, battery saver off)` or `mpv_kit_example: GPU preference none (<reason>); Windows graphics settings decide`. The snippet is in the mpv_kit_video README. Every `D3D11Interop` creation writes `mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>` to stderr and DebugView, so a redirected log shows the adapter in use.
- **Hint (D-03, log-only):** when Flutter's adapter looks integrated (non-Microsoft, under 512 MiB of dedicated video memory; Intel iGPUs report about 128 MiB) while another hardware, non-Microsoft adapter with at least 512 MiB exists (DXGI enumeration, software adapters excluded), the plugin writes one `mpv_kit: hybrid GPU hint: ...` line. It changes no renderer reason; AMD APUs with a 512 MiB or larger carve-out are not detected.
- **Optional low-cost config (D-02):** for weak or integrated GPUs an app can set `linear-downscaling=no`, `cscale=bilinear` and, with the D3D11 backend and d3d11va decoding, `d3d11va-zero-copy=yes` (caveat: the bottom and right picture edges may be sampled wrongly because of padding; driver bugs are possible). Nothing is applied by default; see the "Weak or integrated GPUs" paragraph of the mpv_kit_video README.
- **Status:** package2 (824a69e) moved Flutter to the GTX 960M, but drops remained (auto vulkan gpu-next 2.5-6%, forced d3d11 25-34%). The power-aware choice, the hint and the `superseded=` count ship in package3; the laptop result is pending (`.planning/phases/14-windows-native-d3d11-backend/evidence/laptop-package.txt`, sections `## package2` and `## package3`).

## Follow-ups

- **Backend label (for 14-11):** the `D3D11-BACKEND` line (fence and query runs), the startup line and the D-05 harness all print `"backend":"vulkan"` next to the d3d11 reason. It looks like a Dart-side label bug; nothing was changed here.

## Verification tiers

- **Hosted WARP (render path only, `hwdec=no`):** the 14-07/14-08 runs prove the render path, fallback behavior and failure injection; they are not hardware evidence.
- **RTX 4060 Laptop GPU (this document, real hardware):** functional runs on both sync paths, 4K rendered 600 s, D-05 on/off, pickup and render waits, all with the backend forced to d3d11.
- **GTX 960 laptop:** see "Hybrid-GPU laptops (14-10)" above; the preference result is pending.
- **Unverified / not applicable:** hardware decode zero-copy beyond what `docs/perf/hwdec-zero-copy.md` records (Phase 16), 8K (UHD-02), other GPU vendors, the auto chain default after 14-11, real-device creation failure falling back to Vulkan, Linux and macOS.
