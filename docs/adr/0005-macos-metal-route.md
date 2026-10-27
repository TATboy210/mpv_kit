# ADR 0005 — macOS Metal route

Status: proposed
Date: 2026-10-27
Related: ADR 0001 (Vulkan render backend), ADR 0004 (render backend
reporting), `.planning/REQUIREMENTS.md` MAC-01 / MAC-02 / HWD-04,
`.planning/research/STACK.md` §5.

Every factual cell below cites a record `[G<n>]` in
`.planning/phases/13-macos-metal-route-decision/evidence/adr-0005-grounding.txt`
(repository path and line, or the verbatim output of a query run on
2026-10-27). A statement that this project cannot prove is marked
`unverified`. The project has no Apple hardware: nothing in this ADR is
claimed about real Apple GPUs.

## Context

Flutter on macOS accepts a frame only as an IOSurface-backed `32BGRA`
`CVPixelBuffer` returned by `copyPixelBuffer` with a +1 reference [G15].
There is no Metal `pl_gpu` in any tagged libplacebo release [G1], and the
libmpv render API types in mpv master are OpenGL, software and Direct3D 11
[G4]; mpv_kit's patch 0001 adds Vulkan [G12]. None of them is Metal.

Today macOS renders through the Vulkan render API, with MoltenVK as the Vulkan
implementation, into IOSurface-backed images imported with
`VK_EXT_metal_objects` [G11]. Since Phase 12 that path runs behind the
`RenderBackend` interface, and Phase 13 plan 01 makes the reason string name
the carrier (`via MoltenVK`, see ADR 0004 Decision 3).

The decision to make: which route carries the frame to Flutter on macOS in
v3.0, and what would make us change it.

## Options

### (a) MoltenVK → IOSurface (the current Vulkan backend)

Keep `MPV_RENDER_API_TYPE_VULKAN` on MoltenVK. Both libmpv Vulkan renderers,
gpu-next and gpu, are available [G12]. VideoToolbox frames reach the renderer
through mpv's `hwdec_vt_pl` [G9].

### (b) OpenGL (CGL) + IOSurface

Use upstream's `MPV_RENDER_API_TYPE_OPENGL` with a CGL context and bind the
IOSurface as a GL texture, the route media_kit and IINA took historically.
This needs the `gl` and `cocoa` features, which the bundle disables [G6] [G7].

### (c) Own Metal backend

Add a Metal `pl_gpu` to libplacebo (or a Metal `ra` to mpv) and a Metal render
API type to libmpv, then write the matching plugin interop.

## Comparison

| Criterion | (a) MoltenVK → IOSurface | (b) CGL + IOSurface | (c) Own Metal backend |
|---|---|---|---|
| Implementation cost in v3.0 | None. It is the shipping path and already sits behind `RenderBackend` [G11]; the only v3.0 work is carrier reporting. | A new backend, plus enabling `cocoa` and `gl` in the libmpv build, which are disabled today [G6] [G7]. Size of the plugin code: unverified. | Rewrite scale. Needs a libplacebo Metal `pl_gpu` that no tagged release has [G1] (the upstream efforts are open issues [G2] [G3]) and a libmpv Metal render API that mpv master lacks [G4]. |
| Renderers available | gpu-next and gpu: both libmpv backends accept the Vulkan API type [G12]. | gpu only: the upstream OpenGL API type is served by the gl_video backend, and the gpu-next libmpv backend accepts only Vulkan [G12]. Research also records GL on macOS capped at 4.1 without compute shaders [G14] (research source, not verified here). | None today. gpu-next would need the missing `pl_gpu` [G1]. |
| VideoToolbox zero-copy | Designed path: `hwdec_vt_pl` requires `PL_HANDLE_MTL_TEX` import [G9]; libplacebo's Vulkan backend declares that import when `ExportMetalObjectsEXT` is available [G10]; the plugin device enables `VK_EXT_metal_objects` [G11]; `videotoolbox-pl` is enabled in the build [G6]. Whether it holds at run time, including P010, is unverified until the Phase 13 hosted-CI evidence (13-04); on real Apple hardware it is unverified. | `videotoolbox-gl` requires `gl-cocoa` [G8], which the build disables on purpose [G6] [G16]. Not available without a build change. | No interop code exists. Would be new work [G18]. |
| Deprecation and platform risk | Metal underneath. MoltenVK is pinned at 1.4.2, which is also the latest release at the query date [G5]. Cost of the translation layer on real GPUs: unverified. | OpenGL has been deprecated since macOS 10.14, and on Apple silicon it is a Metal-backed shim (research source) [G14]. The project already lists a CGL backend as out of scope [G13]. | Depends on unmerged upstream work and on IINA-fork branches [G2] [G3] [G18]. Quality of those branches: unverified. |
| Build and licensing impact | None. MoltenVK is already linked and ships with its license [G6] [G17]. | Re-enables `cocoa` and `gl` in the libmpv macOS build [G6] [G7]; the licensing effect of that was not examined: unverified. | Would carry an unmerged libplacebo and mpv fork. Their licensing: unverified. |
| Flutter texture contract | Satisfied today: IOSurface-backed `32BGRA`, +1 from `copyPixelBuffer` [G15]. | Same contract; the GL texture would have to be backed by the IOSurface. Not implemented: unverified. | Same contract through a Metal texture over an IOSurface. Not implemented: unverified. |
| Hosted-CI verifiability | The real plugin runs on the hosted `macos-15` runner and reports `vulkan (gpu-next) on Apple Paravirtual device via MoltenVK` [G19]. Real Apple GPU behaviour: unverified. | Not implemented, so no evidence exists: unverified. | Not implemented, so no evidence exists: unverified. |
| Upstream status | Vulkan render API is a downstream patch series on mpv [G12]; libplacebo's Vulkan backend is upstream [G1]. | The OpenGL API type is upstream [G4]; gpu-next over the OpenGL API is mpv PR #16818, open and unmerged at the query date [G18]. | libplacebo issues #370 and #380 were open at the query date [G2] [G3]; no Metal directory at v7.360.1 or at the newest tag [G1]; no Metal header in mpv master [G4]. |

## Decision

Choose **(a)**: macOS keeps MoltenVK → IOSurface.

- macOS gets no platform-specific candidate. The chain stays
  `DefaultCandidates`: vulkan/gpu-next → vulkan/gpu → software (ADR 0004
  Decision 5).
- On macOS, `Interop::CreateBackend("vulkan")` only decorates the built-in
  Vulkan backend with the carrier report (13-01). The reason reads
  `vulkan (gpu-next) on <device> via MoltenVK`.
- VideoToolbox zero-copy goes through mpv's `hwdec_vt_pl` (CVPixelBuffer →
  `CVMetalTextureCache` → `PL_HANDLE_MTL_TEX` import) [G9]. No new interop
  code is written.

## Consequences

- No new backend code on macOS. Phase 12's `RenderBackend` stays the single
  rollback point.
- MoltenVK stays in the bundle and its license stays with it [G17].
- Hardware decoding on macOS is VideoToolbox through `hwdec_vt_pl`. Whether
  the mapping is zero-copy on the hosted VM is for 13-04 to show; real Apple
  hardware is unverified.
- Phase 16 (HWD-01) will have to place `videotoolbox` ahead of copy-back
  candidates in the macOS hwdec order, subject to the 13-04 evidence.
- MoltenVK performance on real Apple GPUs, Intel Macs and dual-GPU Macs are
  unverified.

## Alternatives rejected

- **(b) CGL + IOSurface.** Rejected: gpu only [G12], OpenGL is deprecated
  [G14], VideoToolbox zero-copy would need `cocoa` enabled against a deliberate
  setting [G8] [G16]. `.planning/REQUIREMENTS.md` lists a macOS CGL backend
  under Out of Scope [G13].
- **(c) Own Metal backend.** Rejected for v3.0: it depends on a libplacebo
  `pl_gpu` that does not exist in any tag [G1] and a libmpv API that does not
  exist in mpv master [G4]. It is tracked as the Future requirement MAC-F1
  [G13].

## Re-evaluation triggers

1. **libplacebo merges a Metal `pl_gpu` in a tagged release.** How to check:
   `gh api 'repos/haasn/libplacebo/contents/src?ref=<tag>' --jq '.[] | select(.type=="dir") | .name'`
   and look for `metal` (at v7.360.1 the list is d3d11 glsl gpu include opengl
   shaders tests utils vulkan [G1]). This is Future requirement MAC-F1.
2. **mpv adds a Metal libmpv render API.** How to check:
   `gh api 'repos/mpv-player/mpv/contents/include/mpv?ref=master' --jq '.[].name'`
   and look for a `render_*` header that names Metal [G4].
3. **MoltenVK is no longer maintained, is archived, or stops providing
   `VK_EXT_metal_objects` or Vulkan 1.3.** How to check:
   `gh api repos/KhronosGroup/MoltenVK --jq '[.archived,.pushed_at]|@tsv'` and
   `gh api repos/KhronosGroup/MoltenVK/releases/latest --jq '[.tag_name,.published_at]|@tsv'`
   against the pinned 1.4.2 [G5]; then confirm the extension in the
   release's `MoltenVK/include` headers.
4. **Flutter's macOS external texture contract changes** (no longer accepts
   `CVPixelBuffer`, or asks for an `MTLTexture`). How to check: read
   `FlutterTexture.h` of the Flutter version in
   `.github/workflows/flutter-plugin.yml` and compare it with [G15].
5. **Real-hardware evidence shows VideoToolbox zero-copy cannot be repaired on
   the MoltenVK path** (for example green P010 frames), **or MoltenVK
   translation overhead makes 4K60 unreachable.** How to check: run the
   example app on Apple hardware with `hwdec-current` and the frame-drop
   counters, then compare with the 13-04 hosted evidence. No such run exists
   today: unverified.

## Verification

The evidence for this ADR comes from Phase 13's hosted CI:

- The reason string `via MoltenVK` is proven by the native-verify
  integration-test job on macOS (13-01) [G19].
- Pixel-probe consistency and VideoToolbox zero-copy are proven by the new
  `macos-route` workflow (13-03, 13-04).
- The classified conclusions are collected in
  `docs/perf/macos-route-verification.md`, and 13-05 writes the result into
  this section.

The project has no macOS hardware, so every real-hardware conclusion stays
`unverified`.
