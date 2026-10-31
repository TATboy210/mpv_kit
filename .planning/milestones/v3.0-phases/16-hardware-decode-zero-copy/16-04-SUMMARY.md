---
phase: 16-hardware-decode-zero-copy
plan: 04
subsystem: native
tags: [hwdec, vaapi, drm-render-node, vulkan, egl]

requires:
  - phase: 16-hardware-decode-zero-copy
    provides: 16-03 gpu-next drm_params_v2 registration and vaapi in the verify tier
provides:
  - "Linux host resolves the DRM render node of the rendering GPU and passes it as MPV_RENDER_PARAM_DRM_DISPLAY_V2 (Vulkan and OpenGL backends), closing the fd after the render context is freed"
  - "video_renderer_drm_params_test (DRM-RESOLVE, DRM-PARAMS)"
  - "evidence/unverified.txt (Linux part, 9 items)"
affects: [16-06]

status: complete
actuals:
  tokens: 60000
  tasks: 2
  commits: 2
plan_head_before: 14fa3d85f1de6e9c98ecd30adfd896b404cdf319
plan_head_after: f2297e85b4683cea4767e5e9f7cbaa393ebfb02c

key-files:
  created:
    - packages/mpv_kit_video/src/drm_render_node.h
    - native/tests/video_renderer_drm_params_test.cc
    - .planning/phases/16-hardware-decode-zero-copy/evidence/unverified.txt
    - .planning/phases/16-hardware-decode-zero-copy/evidence/ci-runs-16-04.txt
  modified:
    - packages/mpv_kit_video/src/vulkan_backend.h
    - packages/mpv_kit_video/src/vulkan_backend.cc
    - packages/mpv_kit_video/linux/gl_interop.h
    - packages/mpv_kit_video/linux/gl_interop.cc
    - packages/mpv_kit_video/linux/opengl_backend.cc
    - native/tests/meson.build

key-decisions:
  - "GL-vs-Vulkan cross-check and the GL UUID to Vulkan DRM fallback are not implemented (plan decision); both are listed in unverified.txt."
  - "Resolver reasons are not logged (no new log lines, ADR 0004)."

requirements-completed: []
requirements-partial: [HWD-03]
---

# Phase 16 Plan 04: Linux DRM render node hand-over Summary

Linux hosts now give mpv a render node matched to the rendering GPU: `VulkanRenderBackend` (via the new `VulkanInterop::OpenDrmRenderNode`/`CloseDrmRenderNode` hooks, default -1/no-op so Windows and macOS are unchanged) and `OpenGLBackend` (via `EGL_EXT_device_query` + `EGL_EXT_device_drm_render_node`) add `DRM_DISPLAY_V2` to every `mpv_render_context_create` and close the fd after the render context is freed. Without a node (hosted runners) no parameter is passed and playback falls back to software.

## Tasks

1. Task 1 (tracer) - `d742193`: `drm_render_node.h` (struct filler, `/dev/dri/renderD<N>` allowlist, Linux devnum lookup and `O_RDWR|O_CLOEXEC` open), Vulkan interop hooks and backend wiring (resolve once, parameter on gpu-next and the gpu fallback, close in the destructor), `video_renderer_drm_params_test` and its meson block (Linux only).
2. Task 2 - `f2297e8`: `GlInterop::OpenDrmRenderNode` from `VkPhysicalDeviceDrmPropertiesEXT`, `OpenGLBackend` EGL resolver, parameter and destructor close, `evidence/unverified.txt`.

## Verification

- Local (MSVC `/W4 /WX`, gitignored `build/phase16/build_drm.bat`): `DRM-RESOLVE ok cases=10` (portable part), `DRM-PARAMS ok scenarios=4` on the host GPU; api_test (10), golden_vk (8), golden_vk_fallback, affinity, linux_chain (10) unchanged. Mutation check: removing the parameter line turns `drm-fd` and `drm-fd-fallback` red. Golden-freeze 5 OK, constants_audit ok, `flutter analyze --fatal-infos` clean.
- CI Task 1, sha d742193: native-verify 40731973239, flutter-plugin 40731973273, `CI-GATE ok`, no reruns. `DRM-PARAMS ok scenarios=4` and `DRM-RESOLVE ok cases=17` on ubuntu x64, ubuntu arm64 (lavapipe, scenarios ran) and sanitizers. `^build \(` ubuntu/windows/macos success on the flutter-plugin run.
- CI Task 2, sha f2297e8: native-verify 40735294585 (one `gh run rerun --failed` for a macos-15 job cancelled with no steps, then success), flutter-plugin 40735294363, `CI-GATE ok`. Forced opengl, second controller and the default-chain hwdec leg unchanged; no `unexpected`.
- HWDEC comparison (acceptance): ubuntu `hevc-10bit` end row, `requested=vulkan,vaapi,auto-safe`, `outcome=software`, `hwdecInterop=null`, same reason as 16-03's row; `HWDEC-RUN playedToEnd=true deviceLost=0`. The Linux resolvers return none on llvmpipe, as designed. Records in `evidence/ci-runs-16-04.txt`.

## Deviations from Plan

**1. [Process] One infra rerun** of native-verify 40735294585 (macos-15 job cancelled with no steps).

**2. [Rule 3 - lint/format] Test constructor.** `Run` got an explicit constructor so the test builds warning-free under `/W4 /WX` with the harness; no behavior change.

## Known Stubs

None.

## Unverified

Real VA-API zero-copy (GL and Vulkan), 10-bit dma-buf modifiers, real-driver resolver output, hybrid GPU matching, NVIDIA path, real-node fd lifetime and the vaapi load log: all nine items are in `evidence/unverified.txt`, none described as verified. HWD-03 stays unticked (16-06 owns the rest).

## Self-Check: PASSED

Commits d742193 and f2297e8 are ancestors of HEAD; created files present.
