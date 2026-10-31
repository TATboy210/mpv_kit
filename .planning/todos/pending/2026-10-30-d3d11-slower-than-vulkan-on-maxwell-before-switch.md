---
created: 2026-10-30T00:00:00.000Z
title: Find why D3D11 renders slower than Vulkan on the GTX 960M, then revisit the Windows D3D11-first switch
area: native
severity: minor
files:
  - packages/mpv_kit_video/windows/d3d11_interop.cpp
  - packages/mpv_kit_video/windows/d3d11_backend.cpp
  - packages/mpv_kit/lib/src/player/hwdec_defaults.dart
---

## Problem

The user wants Windows auto to prefer D3D11 (the plugin's native path, no
Vulkan import of the KMT textures). On the GTX 960M + HD 530 laptop
(Maxwell, D3D11 feature level 11_0) the forced-d3d11 run of package4
(0e792c8, FIFO queue) still has ~3.5 % effective drops and `done=` 3–13 ms
(max ~30 ms), against ~0.5 % and ~0.05 ms for auto/Vulkan
(`.planning/phases/14-windows-native-d3d11-backend/evidence/gtx960-laptop.txt`).
On the RTX 4060 both paths are drop-free. 14-11 therefore kept Vulkan first
(D3D-08 not-switched:keep; user decision 2026-10-29, confirmed 2026-10-30:
"先保持 Vulkan，查 D3D11 慢的原因后再切").

## Candidates (from the 2026-10-29 mpv source research, unproven)

- `d3d11va` copy path: one `CopySubresourceRegion1` per frame plus an
  implicit wait on decode (`native/mpv/video/out/d3d11/hwdec_d3d11va.c:254-268`);
  try `d3d11va-zero-copy=yes` (`:270-283`; padding/edge caveat in
  `DOCS/man/options.rst`).
- libplacebo D3D11 at FL 11_0: 8 UAV slots instead of 64, SPIRV-Cross →
  HLSL → FXC shaders.
- One immediate context shared with the decoder under `ID3D10Multithread`.
- `done=` rising from ~8 to ~17 ms over a minute: log GPU clocks
  (`nvidia-smi`) next to it to separate thermal decay from contention.
- Low-cost scaler settings (`linear-downscaling=no`, `cscale=bilinear`) as an
  A/B on both APIs.

## Done when

D3D11 effective drops on the 960M are within ~1 % of Vulkan in a 2-minute
4K59.94 run, then the one-line `kWindowsApiOrder` switch (14-11 Task 2
procedure: ci scratch branch green, RTX 4060 post-switch checks) is offered
to the user again, together with pinning a bundle that contains the D3D11
backend (todo 2026-10-27-pin-a-bundle-with-the-d3d11-backend).
