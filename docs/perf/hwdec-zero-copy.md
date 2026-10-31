# Hardware decode zero-copy — Phase 16 (RTX 4060, forced D3D11 backend)

This document records what Phase 16 proved about hardware decoding and zero-copy, how to reproduce it, and which parts are still unverified. Every number comes from a raw log kept next to the ledger `.planning/phases/16-hardware-decode-zero-copy/evidence/rtx4060-hwdec-runs.txt`.

## Machine and code state

- **Machine:** Windows 11 (MINGW64_NT-10.0-26300), x64, NVIDIA GeForce RTX 4060 Laptop GPU, driver 617.42, AC power.
- **Toolchain:** Flutter 3.47.8 stable, engine `dfd2e6cb7d31` (cf636b1dfb), Dart 3.13.7.
- **Product code:** `ad5c54b5dc8bfa69500d4dada6c59e8cb9ef0c72`. HEAD at release time was `15f61ff`, which is docs-only over it (decision `release-basis` choice B).
- **Test source:** `f644220`. Its only change makes `_openAndWaitForFrame` in `example/integration_test/hwdec_zero_copy_test.dart` wait for any non-zero video-params size instead of 640x360. It is test-only and not part of the libmpv bundle.
- **libmpv bundle:** artifact `libmpv-windows-x64` of release run `40812562348` (`release.yml` on `feat/mpv-master-upgrade`, publish skipped), `sha256sum -c MANIFEST.txt` all OK. `libmpv-2.dll` sha256 `e63ccc2a6d89f431206654b81f125d69c28c656f66da319412e9b278b8ed9d3c`.
- **Samples:** artifacts `hwdec-samples` and `hwdec-samples-uhd` of native-verify run `40798831729` (`samples_run`): `h264-8bit`, `hevc-8bit`, `hevc-10bit` (640x360) and `hevc-10bit-2160p` (3840x2160 HEVC Main10).
- **Backend:** forced with `MPV_KIT_VIDEO_API=d3d11` (decision `hwd02-acceptance` = `forced-d3d11`, shared session with 14-09). The auto chain still prefers Vulkan before 14-11.

## Reproduce

```sh
# once: point the example's native-assets hook at the downloaded bundle (temporary; never commit)
printf '\nhooks:\n  user_defines:\n    mpv_kit_libs:\n      libmpv_bundle: %s\n' "$(cygpath -m "$PWD/build/phase16/libmpv-rtx")" >> pubspec.yaml
gh run download 40812562348 -n libmpv-windows-x64 -D build/phase16/libmpv-rtx   # then: sha256sum -c MANIFEST.txt
gh run download 40798831729 -n hwdec-samples -D build/phase16/samples
gh run download 40798831729 -n hwdec-samples-uhd -D build/phase16/samples-uhd
mkdir -p example/integration_test/route_samples
cp build/phase16/samples/*.mp4 build/phase16/samples-uhd/*.mp4 example/integration_test/route_samples/
export LIB="$PWD/build/phase16/libmpv-rtx/lib" MPV_KIT_LIBMPV_PATH="$LIB/libmpv-2.dll" MPV_KIT_REQUIRE_LIBMPV=1
export PATH="$LIB:$PATH" FLUTTER=/d/flutter/bin/flutter
cd example
S=h264-8bit.mp4,hevc-8bit.mp4,hevc-10bit.mp4,hevc-10bit-2160p.mp4
# (a) forced d3d11 (HWD-02 evidence)
MPV_KIT_VIDEO_API=d3d11 MPV_KIT_HWDEC_SAMPLES=$S $FLUTTER test integration_test/hwdec_zero_copy_test.dart -d windows
# (b) comparison: d3d11va-zero-copy=yes
MPV_KIT_VIDEO_API=d3d11 MPV_KIT_HWDEC_ZERO_COPY=yes MPV_KIT_HWDEC_SAMPLES=$S $FLUTTER test integration_test/hwdec_zero_copy_test.dart -d windows
# (c) information: auto chain (Vulkan first before 14-11)
MPV_KIT_HWDEC_SAMPLES=$S $FLUTTER test integration_test/hwdec_zero_copy_test.dart -d windows
# afterwards: git checkout -- pubspec.yaml
```

Conditions that mattered: desktop unlocked, the example window visible and untouched for the whole run, no other GPU workload, at least 5632 MiB free on `D:`. The hooks `user_defines` keeps the pinned `v0.1.0-dev.3` bundle's same-name DLLs from shadowing the artifact's DLL closure.

## Default lists

The per-platform lists and the reasons for the order are in [ADR 0006](../adr/0006-hwdec-defaults.md). Windows is `vulkan,d3d11va,d3d11va-copy,auto-safe`; `d3d11va-zero-copy` stays at mpv's default (`no`) because the comparison below shows no measurable difference worth a behavior change.

## RTX 4060 results (forced d3d11)

Log: `evidence/rtx-hwdec-d3d11-a2.log` (attempt 2). Attempt 1 (`rtx-hwdec-d3d11.log`) stopped at the 4K software-reference leg because the test's ready condition was hard-coded to 640x360; that is a test defect, fixed in `f644220`, and the log is kept.

| Sample | `hwdec-current` | `pixelformat` | `hw-pixelformat` | outcome | screenshots (3 seeks) | drops / decoder / vo-delayed |
|---|---|---|---|---|---|---|
| hevc-10bit-2160p | `d3d11va` | `d3d11` | `p010` | zero-copy (first frame and end) | match, match, match; flutter frame match | 0 / 0 / 0 |
| hevc-10bit (640x360) | `d3d11va` | `d3d11` | `p010` | zero-copy | match x3 | 0 / 0 / 0 |
| hevc-8bit (640x360) | `d3d11va` | `d3d11` | `nv12` | zero-copy | match x3 | 0 / 0 / 0 |
| h264-8bit (640x360) | `d3d11va` | `d3d11` | `nv12` | zero-copy | match x3 | 0 / 0 / 0 |

All four played to the end, `hwdecStable=true` (hwdec never changed mid-play), `deviceLost=0`, `renderErrors=0`. `d3d11vaZeroCopy=false` in this run (mpv default). The `hwdec=no` software reference of each sample reported `software` and produced the reference screenshots the hardware frames were compared against. The 4K software reference dropped one frame (`frameDrops=1`); that leg is not the subject of the measurement.

## `d3d11va-zero-copy` no vs yes (data only, default unchanged)

Log: `evidence/rtx-hwdec-d3d11-zero-copy-yes.log`.

| Item (4K sample) | `no` (default) | `yes` |
|---|---|---|
| `hwdec-current`, `hw-pixelformat` | `d3d11va`, `p010` | `d3d11va`, `p010` |
| `d3d11vaZeroCopy` | false | true |
| frame drops / decoder drops / vo-delayed | 0 / 0 / 0 | 0 / 0 / 0 |
| screenshot diffs (3 seeks) | 0.0, 0.0, 0.0 (match) | 0.0089, 0.0089, 0.009 (match) |
| first frame | 154 ms | 113 ms |

The three 640x360 samples also show 0 / 0 / 0 and three matches in both modes. The conclusion is limited to these short clips: no difference in drops or correctness, a single first-frame timing sample (not a benchmark). It is not a decision; the default stays `no`.

## Auto chain (information only)

Log: `evidence/rtx-hwdec-auto.log`, `MPV_KIT_VIDEO_API` unset. Before 14-11 the auto chain selects the Vulkan backend on this machine. The 4K sample reported `api=vulkan`, `hwdec-current=vulkan`, `pixelformat=vulkan`, `hw-pixelformat=p010`, outcome zero-copy, three screenshot matches. This does not count towards HWD-02.

## Hosted matrix

Run `40798831729` on `ad5c54b` (all jobs green, no unexpected outcome). `hwdec=no` is software everywhere; the default list differs only on macOS:

| Backend | Platform | `hwdec=no` | default list |
|---|---|---|---|
| opengl | ubuntu (llvmpipe) | software | software |
| vulkan | ubuntu (lavapipe) | software | software |
| software | ubuntu | software | software |
| d3d11 | windows (WARP) | software | software |
| software | windows | software | software |
| vulkan | macos-15 (MoltenVK) | software | zero-copy (videotoolbox) |
| software | macos-15 | software | copy-back (videotoolbox-copy) |

On `15f61ff` and `f644220` the macOS videotoolbox screenshot check is flaky in hosted CI (the failing seek point differs between runs); it is handed to a separate debug session and does not affect Windows.

## Linux VA-API

Proved on hosted runners: `DRM_DISPLAY_V2` parameter content and lifetime (fake libmpv + `/dev/null`), path allow-list and device lookup, both `drm` variants (GL `vo_gpu` and Vulkan gpu-next register the native resource), and a safe fall back to software without `/dev/dri`. Not proved: any real VA-API decode into a dma-buf texture (see `evidence/unverified.txt`). The release bundle links `libva.so.2` and `libva-drm.so.2` as host libraries (README).

## How to tell zero-copy

Read `hwdec-current`, `video-params/pixelformat` and `hw-pixelformat` together. `hwdec-current=d3d11va` is the same for both `d3d11va-zero-copy` modes, so a hardware pixelformat (`d3d11`) and a hardware `hw-pixelformat` (`p010`/`nv12`) are required as well. With the default `no`, `d3d11va` includes one GPU-memory copy per frame and zero CPU round trips; `d3d11va-copy` instead copies frames back to system memory.

## Verification tiers

- **Hosted CI (fallback, software decode, assertion wiring, DRM parameter passing):** proves that every backend decodes in software with `hwdec=no`, that the HWDEC assertions are wired into every integration and soak test, and that the DRM parameters are passed and closed correctly. It does not prove hardware decode or real GPU behavior; WARP, llvmpipe and lavapipe results are not hardware evidence.
- **RTX 4060 Laptop GPU (d3d11va zero-copy, forced d3d11, before 14-11):** proves `d3d11va` + `d3d11` pixelformat + `p010` zero-copy for 4K HEVC Main10 with correct screenshots against the software reference and no mid-play fallback.
- **Unverified / not applicable:**
  - Real VA-API zero-copy on Linux (no GPU hardware).
  - AMD, Intel and other NVIDIA GPUs (including Intel HEVC driver blacklist paths).
  - The GTX 960 + integrated-GPU laptop (14-10) and hybrid-GPU adapter selection for `d3d11va-copy`.
  - Windows arm64 hardware decode.
  - 8K (UHD-02).
  - Apple real hardware.
  - The default path after 14-11 switches the auto chain to D3D11.
  - Long-running `d3d11va-zero-copy=yes` and padding edge cases.
  - Vulkan Video (`hwdec=vulkan`) beyond the single information run above.
