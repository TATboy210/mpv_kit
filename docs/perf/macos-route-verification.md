# macOS Route Verification — Phase 13 (macOS Metal route decision)

**Date:** 2026-10-27
**Status of the evidence:** partial. One conclusion (the `via MoltenVK` reason) rests on a real hosted-CI run. Every other conclusion needs a hosted `macos-route` run that has **not happened**: the user deferred all hosted CI until phases 13-17 are done (decision of 2026-10-27, token budget). Items that wait for that run are marked `ci-gate: deferred`.
**Machine-readable record:** `.planning/phases/13-macos-metal-route-decision/evidence/route-runs.txt` (holds no `ROUTE-*` line yet) and `evidence/ci-runs.txt`.

Nothing in this document invents a run id, a `ROUTE-*` line or a measurement. Where a reading does not exist the table says `deferred`, not a guess.

## Summary

- **SC1 decided (ADR 0005, `Status: proposed`):** MoltenVK to IOSurface is chosen over CGL plus IOSurface and an own Metal backend, with five re-evaluation triggers ([ADR 0005](../adr/0005-macos-metal-route.md)). The ADR becomes `accepted` only after the user decision in 13-06.
- **SC2 reason proven; SC2 像素部分未测量（ci-gate: deferred）:** the `via MoltenVK` reason is proven on hosted macos-15 (native-verify run `40465908724`, sha `8103bebfde1031b5a68ba000989448fce9407654`). The pixel-parity comparison against the pre-Phase-12 plugin (3a5f450) is implemented and self-tested locally but has no `ROUTE-PIXEL`, `ROUTE-PARITY`, `ROUTE-FRAME` or `ROUTE-SC2` line, so neither "proven" nor "not achieved" can be written.
- **SC3 deferred for all three samples:** h264-8bit `deferred`, hevc-8bit `deferred`, hevc-10bit `deferred`. HWD-04 has no hosted-VM reading. That is not "unreachable" either: it is unmeasured.

## Verification tiers

- **Hosted macos-15 runner (Apple Silicon VM, Metal device `Apple Paravirtual device`):** the only tier that can prove the render path, the reason and the VideoToolbox interop chain (CVPixelBuffer to MTLTexture to VkImage to libplacebo).
  - The libmpv under test is the `mpv_kit_libs` hook bundle `v0.1.0-dev.3` (FFmpeg 8.1.3 `--enable-videotoolbox`, mpv `-Dvideotoolbox-pl=enabled`, MoltenVK 1.4.2). It is not a build of the current vendored `native/mpv` tree.
  - Inside the VM, VideoToolbox may use Apple's hardware decoder or Apple's software decoder. The process cannot tell which. A future `zero-copy` outcome would prove the interop chain, not the Apple media engine.
  - Covered today by a real run: the `reason` header (13-01). Waiting for a run: pixel parity, frame probe, HWD-04 (13-03, 13-04).
- **RTX 4060 (Windows 11):** not involved in Phase 13.
- **Unverified (未验证):**
  - macOS real hardware (Apple GPU through MoltenVK outside a VM): not run. No result in this document applies to it.
  - Intel Macs and dual-GPU Macs: not run.
  - Local macOS: the project has no macOS host. The macOS plugin code and the Dart integration tests of 13-03 and 13-04 were only analysed locally, never compiled or run on macOS.

## MAC-02: reason

Real evidence, from the 13-01 gate on the pushed commit:

```
run=40465908724 sha=8103bebfde1031b5a68ba000989448fce9407654 workflow=native-verify.yml conclusion=success
run=40465908799 sha=8103bebfde1031b5a68ba000989448fce9407654 workflow=flutter-plugin.yml conclusion=success
macos-15:     "backend":"vulkan","reason":"vulkan (gpu-next) on Apple Paravirtual device via MoltenVK"
ubuntu-24.04: "reason":"vulkan (gpu-next) on llvmpipe (LLVM 20.1.2, 256 bits)"      (no ` via ` suffix)
windows-2025: "backend":"software","reason":"software (sw) on cpu; vulkan/gpu-next unavailable: ..."  (unchanged)
```

These lines are transcribed from `13-01-SUMMARY.md` and `evidence/ci-runs.txt`; the gate asserted them with `--log` and `--log-absent` on that run. The macOS INTEGRATION-SOAK line (`cycles 10`, `renderErrors 0`, `deviceLost 0`) was asserted by the same gate.

**Not covered:** the `ROUTE-IDENTITY` line of the `macos-route` workflow (bundle identity `@rpath/mpv.2.framework/mpv.2` plus the reason inside the route probe) has not run. `ci-gate: deferred`.

## MAC-02: pixel parity

`ci-gate: deferred`. No `macos-route` run exists, so there is no `ROUTE-PIXEL`, `ROUTE-PARITY`, `ROUTE-FRAME`, `ROUTE-FRAME-PARITY` or `ROUTE-SC2` line, and SC2 像素部分未测量（ci-gate: deferred）。

What exists locally and is ready for the deferred run:

- The `macos-route` workflow (`route-probe (macos-15)`) reads the same frame from the HEAD plugin and from the pre-Phase-12 plugin (3a5f450, full SHA asserted in the workflow) with the same libmpv bundle.
- Two pixel channels: `toImage` (tolerance verdict 0.02 non-black ratio, 4.0 mean) and the plugin's private IOSurface frame probe (robust bounds 0.01 and 0.5 only). Thresholds were committed before any CI result and must not be tuned afterwards.
- `tools/check_route_probe.py --self-test` passes 14 local cases. It prints `ROUTE-SC2 pixel=proven channel=toImage|iosurface` or `pixel=not-achieved reason=...`. `not-achieved` is a finding, not a pass.
- If the deferred run gives `channel=iosurface`, the proof is of the IOSurface frame that `copyPixelBuffer` hands to Flutter; the compositor sampling it is not observed. If both channels are blind, SC2 pixel part is `not-achieved` and 13-06 must ask the user to accept it as a partial result or to add a channel. `toImage` having `informative=no` would mean "the toImage channel cannot see macOS external textures", not "the two trees agree".

## HWD-04: VideoToolbox on MoltenVK

`ci-gate: deferred` for every row. No `ROUTE-SAMPLES`, `ROUTE-HWDEC-REF`, `ROUTE-HWDEC` or `ROUTE-HWDEC-LOG` line exists.

| Sample | Outcome | hwdec-current | pixelformat | hw-pixelformat | P010 | Screenshot | Flutter frame | Evidence |
|---|---|---|---|---|---|---|---|---|
| h264-8bit | deferred | - | - | - | - | - | - | none (no run) |
| hevc-8bit | deferred | - | - | - | - | - | - | none (no run) |
| hevc-10bit | deferred | - | - | - | - | - | - | none (no run) |

`deferred` is not one of the three outcomes the plan allows (`zero-copy`, `zero-copy-render-unverified`, `unavailable`). It is used on purpose: none of those three can be claimed without a reading. When the deferred run exists, each row is replaced by its classified outcome using these wordings:

- `zero-copy`: "zero-copy interop chain holds on the hosted VM; Apple hardware 未验证".
- `zero-copy-render-unverified`: "zero-copy interop selected, but the rendered picture is not proven by a VO screenshot".
- `unavailable`: "not reachable on the hosted VM, 未验证", with the `ROUTE-HWDEC-LOG` failure line quoted verbatim.
- P010 is claimed only when `hevc-10bit` has `hwPixelformat` = `p010`. Otherwise the actual `hwPixelformat` and "P010 未验证" are written.

None of the outcomes may be written as "passed on real hardware". Two runs that disagree are listed side by side, never merged.

**P010:** no reading. P010 未验证.

## Not verified

Boundaries registered as unresolved by 13-01 to 13-04 (the edge probe returned `unclassified / unresolved` for MAC-01, MAC-02 and HWD-04). None of them is marked covered by "backstop".

- Hosted `macos-route` run: not executed at all (`ci-gate: deferred`). Everything under pixel parity and HWD-04 above.
- Multi-ICD development machines: the `unknown Vulkan driver` carrier branch and the `CarrierFor` branch for one device name with several drivers have no CI environment.
- Pixel consistency during playback, after a resize, and with more than one controller. The probe covers the first controller, a paused first frame, 640x360.
- 4K, HDR metadata, concurrent VideoToolbox sessions (Pitfall 14: sessions can fail on a VM) and `hwdec-image-format` variants.
- Apple hardware decoder behaviour and performance, MoltenVK overhead on real GPUs, Intel Macs, dual-GPU Macs.
- The finding from Phase 12 that the second controller's first frame may never be presented affects how `flutterFrame` readings are to be read.
- `debugFrameProbe` frame ownership: when armed, the plugin keeps one extra `CVPixelBuffer` reference. Whether that can collide with the renderer's quarantine rotation is not proven beyond the 13-03 argument (the read holds the texture lock and reads the frame the compositor currently holds). IOSurface statistics are therefore used only as a non-black / approximate judgement. The only evidence that the unarmed path is unchanged is the INTEGRATION and INTEGRATION-SOAK lines of integration-test (macos) on the same SHA as the route run; the real-plugin test never calls `debugFrameProbe`. Those `unarmed run=` lines are not recorded yet.
- The macOS plugin and the 13-03 / 13-04 Dart tests have never been compiled or run on macOS.

## Notes for Phase 16

No `ROUTE-HWDEC` line for the default hwdec list (h264-8bit, `gate:false`) exists, so there is no `hwdec-current` to cite. HWD-01's ordered macOS list must follow this section once the deferred run has written it; until then it has no hosted-VM evidence. This is a record only; no default value changes.

## Reproduce

- Hosted: the `macos-route` workflow, job `route-probe (macos-15)`. Steps by name: `Generate route samples`, `Probe unit tests`, `Parity self-test`, `Frame probe patch matches HEAD`, `Route probe (HEAD plugin)`, `Route probe (pre-Phase-12 plugin)`, `Pixel parity`. `PRE12_SHA` is `3a5f4500f38577e4dcba2023b73c7f4a4b1b3920`.
- Gate (when hosted CI is allowed again):
  `CI_GATE_WORKFLOWS="native-verify.yml flutter-plugin.yml macos-route.yml" bash .planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh --jobs-success '.'` plus the `--log` assertions recorded under `deferred_ci_gates` in `13-03-SUMMARY.md`, `13-04-SUMMARY.md` and `13-05-SUMMARY.md`.
- Local Mac (not available to this project so far): `brew install ffmpeg`, generate the three samples with the commands in the workflow step `Generate route samples` into `example/integration_test/route_samples/`, then from `example/` run `flutter test integration_test/macos_route_test.dart -d macos --dart-define=MPV_KIT_ROUTE_TREE=head --dart-define=MPV_KIT_ROUTE_SECTIONS=pixel,hwdec`. Do not commit the samples.
- Local, any host: `cd example && flutter analyze --fatal-infos && flutter test test/macos_route_probe_test.dart` and `python3 tools/check_route_probe.py --self-test`.
