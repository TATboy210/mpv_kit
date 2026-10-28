# macOS Route Verification — Phase 13 (macOS Metal route decision)

**Date:** 2026-10-27 (document), hosted-VM readings backfilled 2026-10-28
**Status of the evidence:** complete for the hosted macos-15 tier. Every reading below is quoted from a completed hosted CI run of PR #1 and carries `run=<id> sha=<sha>`. The hosted gates were deferred on 2026-10-27 and evaluated on 2026-10-28 against the finished runs (nothing was re-run for this backfill).
**Machine-readable record:** `.planning/phases/13-macos-metal-route-decision/evidence/route-runs.txt` (all `ROUTE-*` lines) and `evidence/ci-runs.txt` (workflow conclusions and gate results).

Nothing in this document invents a run id, a `ROUTE-*` line or a measurement. Apple real hardware was never measured and is marked 未验证.

Runs used (all `success`):

- `final`: macos-route run `40627862041`, native-verify run `40627862148`, flutter-plugin run `40627862039`, sha `091228abd70b22fbe2f425fdd1efb75eb8cfcb54` (feat HEAD, PR #1).
- `earlier`: macos-route runs `40617697853` (sha `b40cdff9262e32f884f4c71b31d3306a4fa37e49`) and `40616234145` (sha `943f0be6f9a74c2150b1e1d8dde05b37c1bdce20`).

## Summary

- **SC1 decided (ADR 0005, `Status: proposed`):** MoltenVK to IOSurface is chosen over CGL plus IOSurface and an own Metal backend, with five re-evaluation triggers ([ADR 0005](../adr/0005-macos-metal-route.md)). The ADR becomes `accepted` only after the user decision in 13-06.
- **SC2 reason proven; SC2 像素部分已证明（通道：toImage）:** the `via MoltenVK` reason is proven on hosted macos-15, and the HEAD plugin and the pre-Phase-12 plugin (3a5f450) read the same frame through the `toImage` channel (`ROUTE-PARITY ok ... informative=yes`, `ROUTE-SC2 pixel=proven channel=toImage`, run `40627862041`). The same result holds in the two earlier runs.
- **SC3 zero-copy for all three samples on the hosted VM:** h264-8bit `zero-copy`, hevc-8bit `zero-copy`, hevc-10bit `zero-copy` with P010 (run `40627862041`; identical in runs `40617697853` and `40616234145`). Apple real hardware 未验证.

## Verification tiers

- **Hosted macos-15 runner (Apple Silicon VM, Metal device `Apple Paravirtual device`):** the only tier that can prove the render path, the reason and the VideoToolbox interop chain (CVPixelBuffer to MTLTexture to VkImage to libplacebo).
  - The libmpv under test is the `mpv_kit_libs` hook bundle `v0.1.0-dev.3` (FFmpeg 8.1.3 `--enable-videotoolbox`, mpv `-Dvideotoolbox-pl=enabled`, MoltenVK 1.4.2). It is not a build of the current vendored `native/mpv` tree. `ROUTE-IDENTITY` shows the loaded library: `@rpath/mpv.2.framework/mpv.2`.
  - Inside the VM, VideoToolbox may use Apple's hardware decoder or Apple's software decoder. The process cannot tell which. A `zero-copy` outcome proves the interop chain, not the Apple media engine.
  - Covered by real runs: the `reason` header (13-01 and again in run `40627862148`), pixel parity and the frame probe (13-03), HWD-04 (13-04).
- **RTX 4060 (Windows 11):** not involved in Phase 13.
- **Unverified (未验证):**
  - macOS real hardware (Apple GPU through MoltenVK outside a VM): not run. No result in this document applies to it.
  - Intel Macs and dual-GPU Macs: not run.
  - Local macOS: the project has no macOS host. The macOS plugin and the Dart integration tests of 13-03 and 13-04 ran only on the hosted macos-15 runner.

## MAC-02: reason

Real evidence, final run (gate 13-03 Task 1 and 13-05 Task 2 evaluated on these runs):

```
run=40627862148 sha=091228abd70b22fbe2f425fdd1efb75eb8cfcb54 workflow=native-verify.yml conclusion=success
run=40627862039 sha=091228abd70b22fbe2f425fdd1efb75eb8cfcb54 workflow=flutter-plugin.yml conclusion=success
run=40627862041 sha=091228abd70b22fbe2f425fdd1efb75eb8cfcb54 workflow=macos-route.yml conclusion=success
run=40627862148 integration-test (macos-15): INTEGRATION {"backend":"vulkan","reason":"vulkan (gpu-next) on Apple Paravirtual device via MoltenVK","elapsedMs":219,"fps":30.0,"events":[]}
run=40627862148 integration-test (macos-15): INTEGRATION-SOAK {"resizeEvents":30,"cycles":10,"renderErrors":0,"deviceLost":0}
run=40627862041 route-probe: ROUTE-IDENTITY {"tree":"head","libmpv":"@rpath/mpv.2.framework/mpv.2","attempts":{},"backend":"vulkan","reason":"vulkan (gpu-next) on Apple Paravirtual device via MoltenVK","defaultHwdec":["vulkan","d3d11va-copy","auto-safe"]}
run=40627862041 route-probe: ROUTE-IDENTITY {"tree":"pre12","libmpv":"@rpath/mpv.2.framework/mpv.2","attempts":{},"backend":"vulkan","reason":"vulkan (gpu-next) on Apple Paravirtual device","defaultHwdec":["vulkan","d3d11va-copy","auto-safe"]}
```

The HEAD tree says `via MoltenVK`; the pre-Phase-12 tree reports the same Vulkan gpu-next device without the carrier suffix, as expected. The 13-05 gate also asserted with `--log-absent` that no ubuntu or windows `integration-test` reason ends in ` via <carrier>`, so the Linux and Windows reasons are unchanged (Linux `vulkan (gpu-next) on llvmpipe`, no suffix). The earlier 13-01 gate on run `40465908724` (sha `8103bebfde1031b5a68ba000989448fce9407654`) read the same macOS reason.

## MAC-02: pixel parity

Same-runner comparison of the HEAD plugin and the pre-Phase-12 plugin (3a5f450), same libmpv bundle, run `40627862041` sha `091228abd70b22fbe2f425fdd1efb75eb8cfcb54`:

```
ROUTE-PARITY self-test ok cases=14
ROUTE-PIXEL {"tree":"head","read":3,"final":true,"visibility":"texture-visible","texture":{"nonBlackRatio":1.0,"greenFraction":0.0,"meanR":122.2648,"meanG":129.7299,"meanB":126.0352},"control":{...red...},"background":{...green...},"image":"640x360"}
ROUTE-PIXEL {"tree":"pre12","read":3,"final":true,"visibility":"texture-visible","texture":{"nonBlackRatio":1.0,"greenFraction":0.0,"meanR":122.2648,"meanG":129.7299,"meanB":126.0352},"control":{...red...},"background":{...green...},"image":"640x360"}
ROUTE-PARITY ok head=texture-visible pre12=texture-visible informative=yes dNonBlack=0.0000 dMeanMax=0.0000
ROUTE-FRAME {"tree":"head","supported":true,"captured":true,"format":"32BGRA","width":640,"height":360,"nonBlackRatio":1.0,"meanR":122.2631,"meanG":129.7294,"meanB":126.0409}
ROUTE-FRAME {"tree":"pre12","supported":true,"captured":true,"format":"32BGRA","width":640,"height":360,"nonBlackRatio":1.0,"meanR":122.2631,"meanG":129.7294,"meanB":126.0409}
ROUTE-FRAME-PARITY ok head=captured/1.0 pre12=captured/1.0 informative=yes dNonBlack=0.0000 dMeanMax=0.0000
ROUTE-SC2 pixel=proven channel=toImage
```

(The `control` and `background` regions are abbreviated here; the full lines are in `route-runs.txt`. Control reads pure red and background pure green, so the probe discriminates.)

Conclusion: **SC2 像素部分已证明（通道：toImage）**. The `toImage` channel is informative (`informative=yes`: the texture is visible, not composited black), and both trees produce the same readings to four decimals. The IOSurface frame channel agrees (`informative=yes`) but is not the deciding channel. Runs `40617697853` and `40616234145` give the identical `ROUTE-PIXEL`, `ROUTE-PARITY`, `ROUTE-FRAME-PARITY` and `ROUTE-SC2` lines. Thresholds (0.02 non-black, 4.0 mean for `toImage`; 0.01 and 0.5 robust bounds for IOSurface) were committed before any CI result and were not changed.

What this does not show: the readings are a paused first frame at 640x360 on the first controller (see Not verified).

## HWD-04: VideoToolbox on MoltenVK

Source: run `40627862041`, sha `091228abd70b22fbe2f425fdd1efb75eb8cfcb54`, `ROUTE-HWDEC` lines with `gate:true`. Samples generated by the workflow with `ROUTE-SAMPLES ffmpeg=ffmpeg version 9.0.1`: `h264-8bit.mp4 codec=h264 pix_fmt=yuv420p bytes=420212`, `hevc-8bit.mp4 codec=hevc pix_fmt=yuv420p bytes=288395`, `hevc-10bit.mp4 codec=hevc pix_fmt=yuv420p10le bytes=286766`. Each sample has a valid software reference (`ROUTE-HWDEC-REF ... "valid":true`, `textureVisibility":"texture-visible"`).

| Sample | Outcome | hwdec-current | pixelformat | hw-pixelformat | P010 | Screenshot | Flutter frame | Evidence |
|---|---|---|---|---|---|---|---|---|
| h264-8bit | zero-copy | videotoolbox | videotoolbox | nv12 | false | match (diff 1.3242, path vo) | match | 15 (failure 0) |
| hevc-8bit | zero-copy | videotoolbox | videotoolbox | nv12 | false | match (diff 1.3046, path vo) | match | 15 (failure 0) |
| hevc-10bit | zero-copy | videotoolbox | videotoolbox | p010 | true | match (diff 0.0, path vo) | match | 15 (failure 0) |

Raw lines (run `40627862041`):

```
ROUTE-HWDEC {"tree":"head","sample":"h264-8bit","hwdec":"videotoolbox","outcome":"zero-copy","gate":true,"hwdecCurrent":"videotoolbox","hwdecInterop":"videotoolbox,vulkan","pixelformat":"videotoolbox","hwPixelformat":"nv12","p010":false,"screenshot":"match","screenshotPath":"vo","screenshotDiff":1.3242,"failureEvidence":0,"evidence":15,"flutterFrame":"match"}
ROUTE-HWDEC {"tree":"head","sample":"hevc-8bit","hwdec":"videotoolbox","outcome":"zero-copy","gate":true,"hwdecCurrent":"videotoolbox","hwdecInterop":"videotoolbox,vulkan","pixelformat":"videotoolbox","hwPixelformat":"nv12","p010":false,"screenshot":"match","screenshotPath":"vo","screenshotDiff":1.3046,"failureEvidence":0,"evidence":15,"flutterFrame":"match"}
ROUTE-HWDEC {"tree":"head","sample":"hevc-10bit","hwdec":"videotoolbox","outcome":"zero-copy","gate":true,"hwdecCurrent":"videotoolbox","hwdecInterop":"videotoolbox,vulkan","pixelformat":"videotoolbox","hwPixelformat":"p010","p010":true,"screenshot":"match","screenshotPath":"vo","screenshotDiff":0.0,"failureEvidence":0,"evidence":15,"flutterFrame":"match"}
```

Per-sample conclusions:

- **h264-8bit:** zero-copy interop chain holds on the hosted VM; Apple hardware 未验证. Decoder log: `vd: Using hardware decoding (videotoolbox).`, `Decoder format: 640x360 videotoolbox[nv12]`.
- **hevc-8bit:** zero-copy interop chain holds on the hosted VM; Apple hardware 未验证. Decoder log: `Decoder format: 640x360 videotoolbox[nv12]`.
- **hevc-10bit:** zero-copy interop chain holds on the hosted VM; Apple hardware 未验证. Decoder log: `Decoder format: 640x360 videotoolbox[p010]`.

**P010:** `hevc-10bit` has `hwPixelformat` = `p010` and `p010` true, so P010 零拷贝在托管 VM 上成立 (decoder output `videotoolbox[p010]`, VO screenshot matches the software reference with diff 0.0). Whether Apple's hardware engine or its software decoder produced it is not distinguishable.

Run-to-run: the three `gate:true` rows are identical in runs `40627862041`, `40617697853` and `40616234145` (the weakest outcome across runs is therefore `zero-copy` for every sample, nothing was downgraded). The only difference between runs is the informational `gate:false` default-list row (see Notes for Phase 16): its screenshot is `match` (diff 0.0) in the two earlier runs and `mismatch` (diff 73.1167) in the final run, while the outcome `software` is the same in all three.

Wordings used (`zero-copy-render-unverified` and `unavailable` did not occur):

- `zero-copy`: "zero-copy interop chain holds on the hosted VM; Apple hardware 未验证".
- `zero-copy-render-unverified`: "zero-copy interop selected, but the rendered picture is not proven by a VO screenshot".
- `unavailable`: "not reachable on the hosted VM, 未验证", with the `ROUTE-HWDEC-LOG` failure line quoted verbatim.

None of the outcomes may be written as "passed on real hardware".

## Not verified

Boundaries registered as unresolved by 13-01 to 13-04 (the edge probe returned `unclassified / unresolved` for MAC-01, MAC-02 and HWD-04). None of them is marked covered by "backstop".

- Multi-ICD development machines: the `unknown Vulkan driver` carrier branch and the `CarrierFor` branch for one device name with several drivers have no CI environment.
- Pixel consistency during playback, after a resize, and with more than one controller. The probe covers the first controller, a paused first frame, 640x360.
- 4K, HDR metadata, concurrent VideoToolbox sessions (Pitfall 14: sessions can fail on a VM) and `hwdec-image-format` variants.
- Apple hardware decoder behaviour and performance, MoltenVK overhead on real GPUs, Intel Macs, dual-GPU Macs. VideoToolbox in the VM may be Apple's software decoder.
- The finding from Phase 12 that the second controller's first frame may never be presented affects how `flutterFrame` readings are to be read (all `flutterFrame` readings above are for the first controller).
- `debugFrameProbe` frame ownership: when armed, the plugin keeps one extra `CVPixelBuffer` reference. Whether that can collide with the renderer's quarantine rotation is not proven beyond the 13-03 argument (the read holds the texture lock and reads the frame the compositor currently holds). IOSurface statistics are therefore used only as a non-black / approximate judgement, and the deciding SC2 channel is `toImage`. The only evidence that the unarmed path is unchanged is the INTEGRATION and INTEGRATION-SOAK lines of integration-test (macos) on the same SHA as the route run (`unarmed run=40627862148 sha=091228abd70b22fbe2f425fdd1efb75eb8cfcb54`, in `route-runs.txt`: `cycles":10,"renderErrors":0,"deviceLost":0`); the real-plugin test never calls `debugFrameProbe`.
- Results come from one libmpv bundle (`v0.1.0-dev.3`), not from a build of the current vendored tree.

## Notes for Phase 16

The h264-8bit default-list row (`hwdec` left at its default, `gate:false`) reads, run `40627862041`:

```
ROUTE-HWDEC {"tree":"head","sample":"h264-8bit","hwdec":"default","outcome":"software","gate":false,"hwdecCurrent":"no","hwdecInterop":"videotoolbox,vulkan","pixelformat":"yuv420p","hwPixelformat":null,"p010":false,"screenshot":"mismatch","screenshotPath":"vo","screenshotDiff":73.1167,"failureEvidence":1,"evidence":2,"flutterFrame":"match"}
```

With the default list (`defaultHwdec` in `ROUTE-IDENTITY`: `vulkan`, `d3d11va-copy`, `auto-safe`) mpv does not select VideoToolbox on this VM: `hwdec-current` is `no` and the outcome is `software`; the log says `vd: Unsupported hwdec: [no]`. `hwdecInterop` lists `videotoolbox,vulkan`, so the interop exists and an explicit `hwdec=videotoolbox` works (table above). HWD-01's ordered macOS list must follow this section: videotoolbox has to be placed explicitly, the default does not pick it. In the two earlier runs the default row's screenshot was `match` (diff 0.0), in the final run `mismatch` (diff 73.1167); the screenshot of a software-decoded default row is informational only (`gate:false`). This is a record only; no default value changes.

## Reproduce

- Hosted: the `macos-route` workflow, job `route-probe (macos-15)`. Steps by name: `Generate route samples`, `Probe unit tests`, `Parity self-test`, `Frame probe patch matches HEAD`, `Route probe (HEAD plugin)`, `Route probe (pre-Phase-12 plugin)`, `Pixel parity`. `PRE12_SHA` is `3a5f4500f38577e4dcba2023b73c7f4a4b1b3920`.
- Gate (evaluated on 2026-10-28 against runs `40627862148`, `40627862039`, `40627862041`):
  `CI_GATE_WORKFLOWS="native-verify.yml flutter-plugin.yml macos-route.yml" bash .planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh --jobs-success '.'` plus the `--log` assertions recorded in `13-03-SUMMARY.md`, `13-04-SUMMARY.md` and `13-05-SUMMARY.md`.
- Local Mac (not available to this project so far): `brew install ffmpeg`, generate the three samples with the commands in the workflow step `Generate route samples` into `example/integration_test/route_samples/`, then from `example/` run `flutter test integration_test/macos_route_test.dart -d macos --dart-define=MPV_KIT_ROUTE_TREE=head --dart-define=MPV_KIT_ROUTE_SECTIONS=pixel,hwdec`. Do not commit the samples.
- Local, any host: `cd example && flutter analyze --fatal-infos && flutter test test/macos_route_probe_test.dart` and `python3 tools/check_route_probe.py --self-test`.
