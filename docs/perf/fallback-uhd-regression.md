# Fallback Hardening and UHD Regression — Phase 17

**Scope:** VER-01 (fault injection), VER-02 (forced-backend matrix), VER-03 (`MPV_KIT_REQUIRE_HWDEC` guard), VER-04 (4K 1800 s runs and 100-round soaks per backend).
**Machine-readable record:** `.planning/phases/17-fallback-hardening-uhd-regression/evidence/` (`ci-runs.txt`, `matrix.txt`, `flake-timing.txt`, `rtx-prep.txt`, `rtx-session.txt`, `rtx-runs.txt`, `rtx-verdicts.txt`, `decisions.txt`, `unverified.txt`, `final-audit.txt`). Every number below can be found in one of those files or in the raw `rtx-*.log` / `rtx-*.vram.csv` next to them.
**Status words:** a result is called *proven* only for the tier that ran it (see `## Verification tiers`). Nothing in this document is a conclusion about hardware that did not run.

## Machine and code state

- **Product code:** `9ae347fd48aec7e6601b0448c8e2b04205291cef` is the sha every RTX 4060 run was gated against (`native_equal=yes` at every gate). Everything committed after it is evidence, docs, CI workflow and session-tool files; `git diff 9ae347f HEAD -- packages example/lib example/integration_test native` is empty.
- **Hardware:** Windows 11 (MINGW64_NT-10.0-26300), x64, NVIDIA GeForce RTX 4060 Laptop GPU, driver 617.42 (hybrid laptop, the iGPU adapter is also counted in the adapter VRAM column).
- **Flutter:** 3.47.8 stable. **libmpv:** the Phase 16 release bundle, `release_run=40812562348`, `libmpv-2.dll` sha256 `e63ccc2a6d89f431206654b81f125d69c28c656f66da319412e9b278b8ed9d3c`, `MANIFEST.txt` verified with 0 failures. No `release.yml` dispatch was needed (`git diff 15f61ff HEAD -- native/mpv native/patches native/build .github/workflows/release.yml` is empty).
- **Samples:** `h264-8bit`, `hevc-8bit`, `hevc-10bit`, `hevc-10bit-2160p` from native-verify run `40989693698` (`samples_run`), sha256 identical to the artifacts.
- **Windows chain order:** `vulkan, d3d11` (`kWindowsApiOrder`). The Phase 14 decision D3D-08 (14-11) was *keep*; Phase 17 did not revisit it.
- **Hosted CI:** native-verify, flutter-plugin and macos-route, every job `success` on the final gate (`ci-runs.txt`, `final-audit.txt` key `ci_final`).

## Decisions

Answered once by the user at the start of the phase (`decisions.txt`):

| Decision | Choice | Consequence |
|---|---|---|
| `ver01` | `create-chain` | The auto chain advances only when *creation* fails. Runtime faults give event-driven determinate states. A running controller never switches backend (RBE-F1). SC1 and VER-01 need new wording, proposed in `final-audit.txt`, pending user approval. |
| `vk-flake` | `measure-split` | The macOS `vk-gpu-timeout` golden judges the 1 s device wait and the 100 ms engine backoff separately. `golden_vk.cc` was re-frozen with the user's explicit consent (`golden-freeze-17.sha256`). |
| `uhd-source` | `lavfi+hevc-d3d11` | Besides the 3840x2160 lavfi 1800 s runs, one 4K HEVC Main10 1800 s run on forced d3d11 under `MPV_KIT_REQUIRE_HWDEC=d3d11va`. |

## Reproduce

Hosted pieces (also what CI runs):

```sh
# Fault-injection golden (meson test in native/tests): video_renderer_fault_test
# Forced backend matrix, one real-plugin texture probe per backend of the platform
bash tools/backend_matrix.sh linux     # opengl, vulkan, software
bash tools/backend_matrix.sh windows   # d3d11, software, vulkan (asserted unavailable on hosted)
bash tools/backend_matrix.sh macos     # vulkan, software
# Guard negative leg: the guard must fail loudly where the zero-copy decode does not exist
bash tools/require_hwdec_negative.sh windows software d3d11va h264-8bit.mp4
# 100-round soak on a forced backend, RSS plateau asserted (hosted ubuntu step)
cd example && MPV_KIT_VIDEO_API=opengl MPV_KIT_SOAK_MEMORY=rss MALLOC_ARENA_MAX=1 \
  xvfb-run -a flutter test integration_test/backend_soak_test.dart -d linux
```

New test environment variables of this phase:

- `MPV_KIT_REQUIRE_HWDEC=<method>`: `hwdec_zero_copy_test` fails (it never skips) when the first-frame or end report does not show the named zero-copy method as `hwdec-current`. Only the zero-copy methods are accepted; `-copy`, `no`, `auto*` and typos are errors, never "no requirement".
- `MPV_KIT_EXPECT_BACKEND=render|unavailable`: `texture_probe_test` asserts either a rendering backend with the forced api, or `render_init` with the forced api's own failure reason and every other candidate excluded.
- `MPV_KIT_SOAK_MEMORY=rss`: `backend_soak_test` asserts a flat RSS curve under the pre-registered rule.
- `MPV_KIT_BENCH_SOURCE=<file>`: `uhd_endurance_test` plays a file instead of lavfi (used for the HEVC run).

RTX 4060 session (Git Bash on Windows, repo root; every command goes through the gate and ledger wrapper, which refuses to start on a failed gate and never overwrites a log):

```sh
# temporary hooks user_defines in the root pubspec.yaml (never committed, restored afterwards):
#   hooks:
#     user_defines:
#       mpv_kit_libs:
#         libmpv_bundle: <cygpath -m build/phase17/libmpv-rtx>
export MPV_KIT_LIBMPV_PATH=<build/phase17/libmpv-rtx/lib/libmpv-2.dll, backslash form>
export MPV_KIT_REQUIRE_LIBMPV=1
R=.planning/phases/17-fallback-hardening-uhd-regression/tools/rtx_run.sh
cd example   # rtx_run.sh runs its command in example/

bash ../$R run matrix-rtx-d3d11   -- env MPV_KIT_VIDEO_API=d3d11 /d/flutter/bin/flutter test integration_test/texture_probe_test.dart -d windows
bash ../$R run hwdec-require-d3d11va -- env MPV_KIT_VIDEO_API=d3d11 MPV_KIT_REQUIRE_HWDEC=d3d11va \
  MPV_KIT_HWDEC_SAMPLES=h264-8bit.mp4,hevc-8bit.mp4,hevc-10bit.mp4,hevc-10bit-2160p.mp4 \
  /d/flutter/bin/flutter test integration_test/hwdec_zero_copy_test.dart -d windows
bash ../$R run soak-d3d11 --vram -- env MPV_KIT_VIDEO_API=d3d11 /d/flutter/bin/flutter test integration_test/backend_soak_test.dart -d windows
bash ../$R run uhd4k-1800-d3d11 --vram -- env MPV_KIT_VIDEO_API=d3d11 MPV_KIT_BENCH_RENDER=1 MPV_KIT_BENCH_SIZE=3840x2160 \
  MPV_KIT_BENCH_SECONDS=1800 MPV_KIT_BENCH_LABEL=4k-rendered-1800-d3d11 \
  /d/flutter/bin/flutter test integration_test/uhd_endurance_test.dart -d windows
bash ../$R run uhd4k-hevc-1800-d3d11 --vram -- env MPV_KIT_VIDEO_API=d3d11 MPV_KIT_REQUIRE_HWDEC=d3d11va \
  MPV_KIT_BENCH_SOURCE=<abs path of route_samples/hevc-10bit-2160p.mp4> MPV_KIT_BENCH_RENDER=1 \
  MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 MPV_KIT_BENCH_LABEL=4k-hevc-1800-d3d11 \
  /d/flutter/bin/flutter test integration_test/uhd_endurance_test.dart -d windows
```

The other runs repeat the same shape with `vulkan` or `software` as the forced api (`matrix-rtx-vulkan`, `matrix-rtx-software`, `soak-vulkan`, `soak-software`, `uhd4k-1800-vulkan`), `bash ../tools/require_hwdec_negative.sh windows software d3d11va h264-8bit.mp4` for the real-GPU negative, and `--attempt <n>` for a user-approved repeat. The per-run VRAM verdict is `dart .planning/phases/17-fallback-hardening-uhd-regression/tools/vram_verdict.dart <vram.csv> <log> <run>`.

## VER-01: fault injection

`native/tests/video_renderer_fault_test.cc` injects faults into fake d3d11 and vulkan backends behind `Interop::CreateBackend`, with `golden/fault.txt` as the pinned trace. Seven scenarios; the test passes on all six CI jobs (linux x64, linux arm64, macOS, windows x64, windows arm64, sanitizers): run `6500cfb` / native-verify `40928914091`, tracer subset on `468f509` / `40918922908`.

| Scenario | What it pins |
|---|---|
| `create-device-lost-next-api` | A failed d3d11 device leaves one `d3d11/gpu-next unavailable: <why>` trail; vulkan/gpu-next wins; no event. |
| `create-every-gpu-candidate-fails` | All four GPU candidates appear in chain order in the software `reason`; the Vulkan fallback notice carries the whole trail; software draws. |
| `runtime-device-lost-then-recreate` | Exactly one `device_lost`, later frames are skips, one context free; a re-created renderer while the device is still gone starts on the next candidate with the d3d11 trail. |
| `runtime-timeout-storm` | `gpu_timeout` on failures 1, 2, 4 only; retries no earlier than 100/200/400/800/1600/3200 ms, the 7th step is the 5000 ms cap; exactly one `recovered`; no `device_lost`. |
| `runtime-alloc-fails-then-backoff-recovers` | Ring 8 then fallback ring 5 both fail: one `render_error` with the ring-5 reason; the engine retries after 100 ms by itself and recovers. |
| `runtime-alloc-fails-resize-retries-at-once` | A pending 1600 ms backoff is cut short by `SetSize`. |
| `runtime-alloc-fails-persist-recreate-same-backend` | Allocation faults do not advance the chain: a re-created renderer starts on the same backend and fails the same way. |

A mutation check (local, not committed) replacing the 5 s backoff cap with 1000000 ms made the storm scenario fail with `backoffs measured 113,203,404,807,1601,3209,6400`.

**Real plugin, create-fail (hosted windows, native-verify `40984192997`):** `D3D11-INJECT {"mode":"create-fail",...,"backend":"software",...,"softwareFallback":"rendering in software: software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; d3d11/gpu-next unavailable: d3d11 device creation failed: 0x887A0004 (injected); vulkan/gpu unavailable: ...; d3d11/gpu unavailable: ..."}`.

**softwareFallback delivery defect, found and fixed in 17-02 (`5b52ee8`):** the event was added to an asynchronous broadcast stream inside `create`, before any listener could exist, so it was always lost. It is now held and handed to the first `events` listener. RED evidence (`red-local-17-02-fallback-event.log`) was taken before the fix. The public API is unchanged (`api_freeze` audit, `enum MpvVideoBackend { vulkan, software }` still present exactly once).

**Boundary of this result (`ver01=create-chain`):** the chain advances only during creation. A running controller does not switch backend when its device is lost or its allocations fail; it reaches a determinate state through events. ROADMAP SC1 as written ("渲染切到 auto 链的下一候选") therefore does not literally hold for runtime faults. The replacement wording is a proposal in `final-audit.txt` and is not applied.

## VER-02: platform x backend matrix

`tools/backend_matrix.sh` forces each backend of a platform with `MPV_KIT_VIDEO_API` and runs the real-plugin `texture_probe_test` (hwdec=no, non-black pixel probe before and after a resize, resize keeps the texture id, a second controller gets the same backend). Native-verify run `40982220052` (repeated green in `40984192997`); raw lines in `matrix.txt`.

| Platform | opengl | vulkan | d3d11 | software |
|---|---|---|---|---|
| linux x64 (ubuntu-24.04, llvmpipe) | ok, run 40982220052 | ok (`vulkan (gpu-next) on llvmpipe`), run 40982220052 | n/a | ok, run 40982220052 |
| windows x64 (windows-2025, WARP) | n/a | asserted-unavailable (`vulkan/gpu-next unavailable: vkCreateInstance failed`), run 40982220052 | ok (`d3d11 (gpu-next) on Microsoft Basic Render Driver`), run 40982220052 | ok, run 40982220052 |
| macos (macos-15, MoltenVK on an Apple Silicon VM) | n/a | ok (`vulkan (gpu-next) on Apple Paravirtual device via MoltenVK`), run 40982220052 | n/a | ok, run 40982220052 |
| windows real GPU (RTX 4060) | n/a | RTX: `matrix-rtx-vulkan` | RTX: `matrix-rtx-d3d11` | RTX: `matrix-rtx-software` |

Per-platform summary lines asserted by the final gate: `BACKEND-MATRIX-SUMMARY platform=linux cells=3 ok=3`, `platform=windows cells=3 ok=3`, `platform=macos cells=2 ok=2`.

RTX 4060, session of 2026-10-30 (`rtx-verdicts.txt`): each forced api's `reason` equals the registered expectation verbatim (`expect_match=yes`), `nonBlackRatio` 1.0 before and 1.0 after the resize, exit 0:

- `matrix-rtx-d3d11`: `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU; vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=d3d11`
- `matrix-rtx-vulkan`: `vulkan (gpu-next) on NVIDIA GeForce RTX 4060 Laptop GPU`
- `matrix-rtx-software`: `software (sw) on cpu; ...` with all four GPU candidates excluded

The Windows vulkan cell on hosted runners is an *asserted absence*, not a pass of the Vulkan backend: hosted Windows has only WARP. The real Vulkan cell is the RTX row. The D3D-02 ANGLE ban stays in the gate: `ANGLE-FREE example\build\windows\x64\plugins\mpv_kit_video\Debug\mpv_kit_video_plugin.dll` and `ANGLE-FREE prefix/bin/libmpv-2.dll (x64 and arm64)`.

## VER-03: hardware-decode guard

- **Hosted negative (windows-2025, WARP, native-verify `40984192997`):** `REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=d3d11 exit=1`, with `HWDEC-REQUIRE ... "hwdecCurrent":"no","outcome":"software","result":"fail"` at `first-frame` and at `end`. The guard fails loudly where no zero-copy decode exists. It says nothing about hardware decode itself.
- **RTX 4060 positive:** `hwdec-require-d3d11va` over four samples (including `hevc-10bit-2160p`, 3840x2160 HEVC Main10): 8 ok lines, 0 fail lines, exit 0. The 4K line reads `pixelformat=d3d11`, `hwPixelformat=p010`, the same as the Phase 16 `hwd02` row (`hwd02-consistency ... phase16=same`).
- **RTX 4060 negative:** the GPU forced onto the software backend: `REQUIRE-HWDEC-NEGATIVE ok required=d3d11va api=software exit=1`.

## VER-04: 4K 1800 s and soaks

### 4K, 1800 s, rendered, RTX 4060

`MPV_KIT_BENCH_RENDER=1`, 3840x2160, lavfi unless stated. "Example in front" is the fraction of 1 s sampler rows in which the foreground process was `mpv_kit_example`.

| Run | Backend | frameDropCountFinal | decoderDrops | voDelayedMax | avsyncPeakAbs (s) | renderErrors / deviceLost | Example in front | Result |
|---|---|---|---|---|---|---|---|---|
| `uhd4k-1800-d3d11` attempt 1 | d3d11 | **3** | 0 | 0 | 1.599e-05 | 0 / false | about 4 min of the run, then WindowsTerminal | FAIL (drops between t=191 s and 251 s) |
| `uhd4k-1800-d3d11` attempt 2 | d3d11 | **5** | 0 | 0 | 1.960e-05 | 0 / false | about 472 of 1775 rows (msedge, WindowsTerminal in front for most of the rest) | FAIL (3 drops between t=251 s and 311 s, 2 between t=1031 s and 1091 s) |
| `uhd4k-1800-d3d11` attempt 3 (supplementary, user-approved, hands-off) | d3d11 | 0 | 0 | 0 | 1.480e-05 | 0 / false | 1777 of 1779 rows | pass |
| `uhd4k-1800-vulkan` | vulkan | 0 | 0 | 0 | 1.980e-05 | 0 / false | 1773 of 1775 rows | pass |
| `uhd4k-hevc-1800-d3d11` (HEVC Main10, `MPV_KIT_REQUIRE_HWDEC=d3d11va`) | d3d11 | 0 | 0 | 0 | n/a (file source) | 0 / false | 1774 of 1775 rows | pass, `hwdecCurrentFinal=d3d11va`, 179 loops, 2 `HWDEC-REQUIRE` ok |

**What these rows do and do not show.**

- Attempts 1 and 2 are recorded failures of the zero-drop gate and are not relabeled. Neither had a decoder drop, a delayed frame, a render error, a device loss, a standby event or a crash.
- Attempt 3 repeated the same test, product sha and environment with the example window in front and the user hands-off, and read 0 drops. Together this is one pass with the window in front for 99.9 percent of the run against two fails with the window covered for most of the run. That points to window occlusion or focus changes, and it is **evidence, not proof**: occlusion was not toggled within a single run, the three runs are not blind, and the sample is one pass against two fails. The cause of the attempt 1 and 2 drops is attributed, not established.
- The stricter reading of the VER-04 clause "D3D11 and Vulkan 4K 30 minutes zero drops" is therefore *met under the condition that the example window is in front and the session is hands-off*, and *not met when the window is covered*. A wording proposal that says exactly this is in `final-audit.txt` and is not applied.
- Reference: Phase 12 `run=uhd4k-rendered` ran 600 s (Vulkan, before the FIFO ready queue of `0e792c8`, example in front in 268 of 270 samples), `run=uhd4k` 1800 s without rendering. The comparison below is not like-for-like (duration, FIFO and occlusion differ). `avsyncPeakAbs` has no threshold; as in Phase 12 any increase counts as worse, and the increases are microsecond scale (one frame is 33.3 ms).

Compare lines (`rtx-verdicts.txt`, Phase 12 `rendered600` / `1800` reference, now, verdict by the Phase 12 method):

| Item | Phase 12 rendered600 / 1800 | d3d11 a1 | d3d11 a2 | d3d11 a3 | vulkan |
|---|---|---|---|---|---|
| frameDropCountFinal | 0 / 0 | 3 worse | 5 worse | 0 same | 0 same |
| decoderFrameDropCountFinal | 0 / 0 | 0 same | 0 same | 0 (BENCH line) | 0 same |
| voDelayedFrameCountMax | 0 / 0 | 0 same | 0 same | 0 (BENCH line) | 0 same |
| avsyncPeakAbs (s) | 1.620e-05 / 4.449e-05 | 1.599e-05 better | 1.960e-05 worse | 1.480e-05 better | 1.980e-05 worse |
| renderErrors, deviceLost | 0, false | same | same | 0, false (BENCH line) | same |

Worse items remain worse: d3d11 attempts 1 and 2 (`frameDropCountFinal`), d3d11 attempt 2 and Vulkan (`avsyncPeakAbs`).

**Process VRAM during the long runs.** The `GPUProcessMemory.DedicatedUsage` counter is cumulative for a process that presents frames (about 1.96 GB/s at 4K 30 fps), so it is unusable for those runs; `process_local_mib` (`LocalUsage`) is used instead and `process_dedicated_mib` is marked unavailable. Vulkan: process local 7.8 (before the first frame) to 559.2 MiB max, adapter 1389.4 to 1887.3 MiB. d3d11 attempt 3: process local 7.8 to 464.5 MiB (last 419.8), adapter 1502 to 1902.8 MiB. HEVC d3d11: about 1123 MiB after the first minutes, max 1168.4, adapter 1399.4 to 2496.3 MiB (hardware decode surfaces). The long-run curves are recorded, not judged; the per-backend VRAM verdict is made on the soaks.

### 100-round soaks, RTX 4060

100 resize/dispose rounds on one player, forced backend, `renderErrors` 0, `deviceLost` 0, `idleSoak` 0, `apiMismatches` 0. The VRAM curve is `process dedicated MiB` at the 11 checkpoints (rounds 0, 10, ... 100); the sampler is the 1 s CIM sampler of `vram_sample.ps1`, joined to the checkpoint timestamps by `vram_verdict.dart`.

| Backend | Rounds / seconds | RSS curve (MiB) | RSS verdict (late) | Process VRAM curve (MiB) | VRAM verdict |
|---|---|---|---|---|---|
| d3d11 | 100 / 39.2 | 449.4, 435.2, 434.4, 431.9, 433.2, 432.3, 436.1, 439.3, 450.1, 447.5, 448.7 | flat (+12.6) | 182.3, 135.6, 135.9, 134.5, 135.9, 135.9, 126.8, 135.9, 134.6, 135.9, 126.8 | flat |
| vulkan | 100 / 38.4 | 426.1, 470.5, 484.4, 483.7, 492.9, 491.9, 496.7, 508.1, 513.0, 505.2, 510.1 | flat (+13.4) | 288.2, 174.0 (x8), 148.8, 174.0 | flat |
| software | 100 / 30.9 | 418.7, 399.2, 403.0, 398.0, 398.0, 395.7, 397.0, 401.3, 398.2, 401.1, 404.9 | flat (+7.9) | 111.3, 51.7 (x10) | flat |

The soaks did not present a frame per round (`lastControllerFrame=not-presented`), so the dedicated-memory counter did not accumulate there (curves are 51 to 290 MiB, plausible and flat); the cumulative-counter problem above applies only to the frame-presenting 4K runs.

### Pre-registered memory rule

Registered, with its unit tests, in `2296c9a` before any measured run (`example/integration_test/soak_memory.dart`, `example/test/soak_memory_test.dart`):

- 11 checkpoints (round 0 and every 10th round); with more, the last 11 are judged; fewer than 11 is `insufficient` and never flat.
- `late = c10 - c6`.
- **growth** iff `late > 32 MiB`, or the last four steps each rise by at least 1 MiB and `late > 8 MiB`; otherwise **flat**.
- The 32 MiB limit is justified next to the constant: 40 rounds each leaking one 640x360 BGRA image (0.88 MiB) is 35 MiB. Checkpoints 0 to 5 are ignored because warm-up is large (about +500 MiB on hosted llvmpipe).

The same rule judges RSS (`MPV_KIT_SOAK_MEMORY=rss`) and the process VRAM curve (`vram_verdict.dart`). No threshold was changed after any measurement.

### Hosted ubuntu opengl soak (llvmpipe) and the malloc-arena choice

The opengl backend's soak runs on the hosted ubuntu runner in native-verify with `MPV_KIT_VIDEO_API=opengl` and asserts a flat RSS. There is no Linux GPU, so a real VRAM curve is **unverified** (`unverified.txt`).

**What happened.** With the default glibc allocator the step was intermittently red on identical product code. Run `40993938470` attempt 1 on `aac870d` read `rssLateMiB` 219.8 (growth); attempt 2 of the same run read flat with late +28.1 (flat only because one step fell by 28 MiB). Of 16 default-allocator soaks measured in the investigation, 6 were red (37.5 percent); the earlier two green CI runs (`40989693698` late +6.8, `40991964430` late +8.0) were two of the passing ones.

**Cause (diagnosed, `debug/ubuntu-soak-late-rss-growth.md`).** glibc malloc arena retention, not a leak. A 4-vCPU runner lets glibc create 8 x 4 = 32 arenas; the process already has about 44 live threads, so every arena is attached and the free list is empty. Each controller's short-lived render threads are placed round-robin on the 32 arenas and each leaves about 29 MiB of freed llvmpipe/GL ring memory in the arena it landed on. glibc's in-use memory stayed flat at 465 to 520 MiB for all 100 rounds in every probed soak (a leak of the smallest frame would add 88 MiB), mapped memory, threads and open fds were flat, and all growth was free-but-retained chunks. With `MALLOC_ARENA_MAX=1` the same code, which changes no object lifetime, was flat.

**The choice, in `b34a402`.** `MALLOC_ARENA_MAX: '1'` on that CI step only. This is a *measurement-environment choice*: the RSS record is only meaningful with a single glibc arena on 4-vCPU runners. It changes no product code, no test, no rule and no threshold; the RTX session product sha `9ae347f` stays valid.

**Evidence for the choice.**

- With one arena, 32 of 32 soaks were flat (late -108.5 to +18.9 MiB, RSS at the last checkpoint 751 to 919 MiB) against 6 of 16 red with the default allocator (plateau 1121 to 1623 MiB).
- Sensitivity: with one arena plus a deliberate 0.9 MiB-per-round leak (the 0.88 MiB frame of the rule's own design) the unchanged rule reported growth in 3 of 4 soaks (+55.5, +72.7, +81.2) and flat in one (+22.0, within the rule's own 35 versus 32 MiB design margin); a larger leak is detected essentially always. So the rule is less sensitive than the nominal design for the smallest frame size, and it is not blind.
- With one arena, the CI runs after the change (`41042057042` on `8ec851b`, late +2.3, curve 654.4 to 867.8 MiB; `41052501831` on `db26707`, late +3.4, curve 664.9 to 823.8 MiB) are flat.
- Before the change, flat runs `40989693698` and `40991964430`: curves in `ci-runs.txt`.

This does not show that the opengl backend has no small leak below the rule's sensitivity, and it does not show anything about real Linux GPU memory.

## vk-gpu-timeout flake (`vk-flake=measure-split`)

The old golden asserted one combined retry window of 1100 ms plus slack; run `40679129407` on macos-15 measured a mixed `retry-ms` of 1396. The scenario is now judged as the 1 s device wait (accepted in [995, 1995] ms) and the 100 ms engine backoff (accepted in [95, 100 + 250] ms) separately, and every run prints `GOLDEN timing-info scenario=vk-gpu-timeout wait-ms=... backoff-ms=... retry-ms=...` (`flake-timing.txt`).

Observed on hosted runners (the macos-15 job; Windows jobs skip the Vulkan golden, exit status 77 because there is no Vulkan device):

- linux x64, linux arm64 and the sanitizer job: `wait-ms=1000 backoff-ms=100 retry-ms=1100` in every recorded run.
- macos-15, 10 recorded runs up to the final gate `41056455257`: wait 1000 to 1113 ms, backoff 103 to 169 ms, none outside the split bounds, 0 `vk-gpu-timeout` golden mismatches in any gated run (summary line in `final-audit.txt`).
- Local RTX 4060 (MSVC): wait 999 to 1000 ms, backoff 100 ms.

Runs without a mismatch do not prove the flake is gone. Run `40679129407` measured a mixed `retry-ms` of 1396, outside the old combined window; the split removes the coupling between a slow device wait and the backoff bound that made it fail, and observation continues.

## Open findings

1. **d3d11 4K lavfi, 3 and 5 VO drops with the example covered.** Recorded failures of attempts 1 and 2; cause attributed to occlusion or focus (attempt 3, 0 drops, window in front), not established. See VER-04.
2. **`lastControllerFrame=not-presented` in every soak.** The soak harness leaves the last controller unsized, and an unsized controller never renders (by design, as in Phase 12 D-05); the soak sizes it once before the bounded wait and it still reads `not-presented` on hosted ubuntu, locally and on the RTX 4060. Likely harness-by-design; it is recorded only and never asserted, and it is the registered second-controller finding (todo `2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front`). It is not a claim of a product defect, and it is not closed.
3. **Process VRAM counter.** `GPUProcessMemory.DedicatedUsage` accumulates for frame-presenting processes; use `LocalUsage`/`TotalCommitted`.
4. **`mpv_kit_libs` build hook, stale `$target.ok` stamp (found while preparing 17-03, not fixed here).** `packages/mpv_kit_libs/hook/build.dart:76` returns `sharedLibrariesIn(extracted)` when the stamp matches the pin, without checking that `extracted` still exists. If the extracted directory was cleaned and the stamp survived, the hook silently returns no libraries; the local `v0.1.0-dev.3` lib directory was empty for this reason. Recorded in `unverified.txt` and `deferred-items.md`; no code was changed in Phase 17.
5. **Windows local notes.** `MPV_KIT_LIBMPV_PATH` needs the backslash form for the Dart VM and the bundle `lib` directory on `PATH`; `powercfg /getactivescheme` prints garbage in Git Bash unless `MSYS_NO_PATHCONV=1` is set.

## Verification tiers

- **Hosted CI (proves the render path, the event contract and the guards only):** native-verify, flutter-plugin and macos-route all `success` on the final gate.
  - Fault-injection golden (7 scenarios, six jobs including sanitizers) and the split-timing golden.
  - Forced-backend matrix: linux (opengl, vulkan, software), windows (d3d11 on WARP, software, vulkan asserted unavailable), macOS (vulkan via MoltenVK, software).
  - Guard negative leg on WARP, the create-fail `softwareFallback` message on the real plugin, ANGLE-FREE and PATCH-DRIFT audits.
  - The 100-round opengl soak on **llvmpipe**: RSS flat, with `MALLOC_ARENA_MAX=1` as a documented measurement-environment choice.
  - llvmpipe, WARP and the MoltenVK VM are software or virtual devices. None of these results is a real-GPU conclusion.
- **RTX 4060 laptop (Windows 11, driver 617.42), real hardware:** the real plugin on forced d3d11, vulkan and software; the hwdec guard positive (8 ok) and negative; the three 100-round soaks with flat RSS and flat process VRAM; 4K 1800 s on vulkan (0 drops), on d3d11 HEVC hardware decode (0 drops), and on d3d11 lavfi: 3 and 5 drops with the example covered, 0 drops with the example in front (one pass against two fails). Nothing here applies to other GPUs.
- **Unverified (未验证):** see `.planning/phases/17-fallback-hardening-uhd-regression/evidence/unverified.txt`.
  - Real-driver device loss and TDR sequences (injection is at the HRESULT layer and in fake backends only); Linux GL device loss.
  - Real Linux GPU memory curves (only llvmpipe RSS exists).
  - macOS real hardware matrix cells and the macOS branch libmpv Vulkan path; arm64 real-plugin matrix on Windows and Linux.
  - AMD, Intel, other NVIDIA GPUs and the GTX 960 laptop for VER-04.
  - Vulkan-backend hardware-decode long runs, and every hardware-decode long run when the source is lavfi.
  - Runtime backend switching of a running controller (not implemented, RBE-F1 adjacent).
  - Deferred, not attempted: UHD-02 (8K 30 minutes) and COMP-03.
