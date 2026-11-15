---
phase: quick-261025-rkh
plan: 261025-rkh
type: execute
depends_on: [261025-rke]
files_modified:
  - packages/mpv_kit_video/src/video_renderer.cc
  - native/tests/render_vk_smoke.c
autonomous: true
---

# 261025-rkh: Balanced queue-family ownership transfer for shared images

Verified facts: `libmpv_vk.c wrap_fbo` passes `img->queue_family` to
`pl_vulkan_release_ex` (current owner); `release_target` passes the stored
`p->image.queue_family` to `pl_vulkan_hold_ex` (destination). The consumer
(video_renderer.cc ~569) sends `IGNORED` on first use and `EXTERNAL` after:
frame 1 is never released to EXTERNAL and frame 2 acquires from EXTERNAL with
no matching release. This violates the spec on every new ring image (after each
resize) and risks a corrupt or black first frame on compressing drivers.

## Task 1: consumer fix
- `target.queue_family = VK_QUEUE_FAMILY_EXTERNAL;` always; keep
  `layout = UNDEFINED` on first use (contents discarded; acquiring from EXTERNAL
  with UNDEFINED is valid). Update the comment. Check that each platform
  interop (windows d3d11_interop, linux gl_interop, macos metal_interop) expects
  the EXTERNAL handoff; MoltenVK treats EXTERNAL as a no-op.

## Task 2: smoke test models the plugin
- `render_vk_smoke.c` (:288 uses IGNORED): pass `VK_QUEUE_FAMILY_EXTERNAL`
  like the fixed consumer and render at least two frames into the same
  image (UNDEFINED then GENERAL), so the hold/release pair is exercised.
- Dropped after review: a validation-layer error counter. It cannot detect
  this bug on CI (see Review revisions) and the layer is not installed on
  any runner.

## Verify
- CI render_vk_smoke (both variants) and plugin builds on 3 OSes; record the
  run links. There is no automated RED for this fix (see below).
- Commit: `fix(video): pair queue-family ownership transfers on first frame`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
Assumptions checked against libplacebo 7.360.1 source and the Vulkan spec:
- `pl_vulkan_release_ex` stores `params->qf` as the image's current owner
  (gpu_tex.c:1498); the next internal barrier transfers from it to the queue
  that uses the image (gpu_tex.c:60-61). `pl_vulkan_hold_ex` passes `qf` as the
  barrier's destination (gpu_tex.c:1449). Plan semantics confirmed.
- `vk_tex_barrier` only rewrites IGNORED to the pool's family when libplacebo
  has exactly one queue pool (gpu_tex.c:35-40). The plugin hands mpv separate
  graphics/compute/transfer families (video_renderer.cc:86-88), so on GPUs with
  dedicated families the first frame records src=IGNORED, dst=<graphics> on an
  EXCLUSIVE image (all three interops create images with the default EXCLUSIVE
  sharing mode: gl_interop.cc:193, d3d11_interop.cpp:111, metal_interop.mm:100).
  That violates VUID-VkImageMemoryBarrier2-image-09117/09118 (src/dst must be
  EXTERNAL, FOREIGN_EXT or a valid family when they differ), and frame 2 then
  acquires from EXTERNAL with no prior release to EXTERNAL.
- With EXTERNAL always: frame 1 is an acquire from EXTERNAL with
  oldLayout=UNDEFINED. A transfer is defined when either index is a special
  external value; UNDEFINED lets the contents be discarded, so no matching
  release is needed for data that is not preserved. Every later frame pairs
  hold_ex (release to EXTERNAL) with the next release_ex (acquire from
  EXTERNAL). Single-family devices (lavapipe, MoltenVK) are unaffected either
  way, because there libplacebo maps IGNORED to its only family.
- Why no automated RED: lavapipe has a single queue family, so the IGNORED path
  is rewritten and nothing invalid is recorded; and Vulkan-ValidationLayers
  before PR #13409 (Oct 2026) accepted IGNORED in ownership transfers whenever
  external memory is enabled, so even a multi-family runner would stay silent
  with the pinned SDK 1.4.363.
- MoltenVK: no source confirms the earlier "EXTERNAL is a no-op" claim; it is
  removed. It does not matter here: MoltenVK exposes one queue family, so
  libplacebo has a single pool, and Metal has no queue-family ownership; an
  EXTERNAL barrier is at most an ordinary memory barrier. Cross-API ordering on
  macOS still comes from the timeline semaphore plus quarantine, not barriers.

**Host facts:** this host is Windows (MSYS Git Bash, MSVC on PATH, no meson/ninja),
so libmpv and `native/tests` cannot be built locally; native build/tests run on
CI (`.github/workflows/native-verify.yml`, incl. the ASan/UBSan job). Dart
tests run locally with `MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll`
(mpv v0.41.0-689, an older local build without this branch's patches; tests
that need patched native behaviour must skip locally and run on CI).


