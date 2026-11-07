---
phase: 16-hardware-decode-zero-copy
plan: 03
subsystem: native
tags: [hwdec, vaapi, gpu-next, patch-0004, build-gates]

requires:
  - phase: 16-hardware-decode-zero-copy
    provides: 16-01 ci_gate.sh and hosted probes
provides:
  - "gpu-next libmpv path registers MPV_RENDER_PARAM_DRM_DISPLAY_V2 as the drm_params_v2 native resource before preinit (patch 0004 + vendored vo_gpu_next.c)"
  - "render_vk_smoke / render_gl_smoke --drm variants"
  - "verify-tier libmpv built with vaapi, vaapi-drm, drm; CONFIG-VAAPI ok assertion"
  - "build.sh required features: Linux VAAPI VAAPI_DRM DMABUF_INTEROP_GL, Windows D3D_HWACCEL"
affects: [16-04, 16-06]

status: complete
actuals:
  tokens: 45000
  tasks: 2
  commits: 2
plan_head_before: 6c61fa2e3f6e25d26ff340066c66d8cf401ce3ce
plan_head_after: 01af48479e09118412096e27998ccd313834d28d

key-files:
  modified:
    - native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch
    - native/mpv/video/out/vo_gpu_next.c
    - native/patches/UPSTREAM.md
    - native/tests/render_vk_smoke.c
    - native/tests/render_gl_smoke.c
    - native/tests/meson.build
    - native/build/build.sh
    - .github/workflows/native-verify.yml
    - .planning/phases/16-hardware-decode-zero-copy/evidence/ci-runs-16-03.txt

key-decisions:
  - "Only drm_params_v2 is registered (x11/wayland off in mpv_kit builds; drm_draw_surface_size only serves the drmprime overlay)."
  - "libmpv_gpu.c untouched, so 0010 stays byte-identical to upstream."

requirements-completed: []
requirements-partial: [HWD-03, HWD-02]
---

# Phase 16 Plan 03: gpu-next DRM render node and vaapi in the verify tier Summary

Patch 0004's gpu-next libmpv backend now copies `MPV_RENDER_PARAM_DRM_DISPLAY_V2` (talloc child of the backend) and registers it as `drm_params_v2` on the ra before `preinit` loads the hwdecs, matching what `libmpv_gpu.c` does for the `gpu` renderer; the verify-tier libmpv is now built with vaapi and the build script asserts the zero-copy features.

## Tasks

1. Task 1 (tracer) - `7af3431`: 0004 regenerated in a scratch worktree (`build/phase16/wt`, base b2c255c13 + 0001-0003, 0004-old, change; 0006-0012 re-stacked, offsets only, no rejects; `diff -rq` against `native/mpv` clean). New 0004 differs from the old one only in the `vo_gpu_next.c` libmpv section (new `#include "mpv/render_gl.h"`, a 20-line registration block before `preinit`) plus the changed blob index lines. `render_vk_smoke --drm` and two meson tests; UPSTREAM.md note.
2. Task 2 - `01af484`: native-verify linux job `-Dvaapi=enabled -Dvaapi-drm=enabled -Ddrm=enabled`, `CONFIG-VAAPI ok`, `libva-dev` for the linux job, integration-test and coverage deps; `build.sh` required features; `render_gl_smoke --drm` and test.

## Verification

- `bash tools/check_patches.sh`: `PATCH-DRIFT OK ... patches=10` (local and CI). 0001, 0009, 0010, `libmpv_gpu.c`, `include/mpv` unchanged vs HEAD; golden-freeze 5 OK; `check_matrix.py` ok.
- CI Task 1, sha 7af3431: native-verify 40721479785 (one `gh run rerun --failed` for the macos integration-test job cancelled while queued, then success), flutter-plugin 40721479783; `CI-GATE ok`. `RENDER_VK drm ok renderer=gpu-next native_resource=registered` and `renderer=gpu native_resource=upstream` on ubuntu x64, arm64, sanitizers (ASan/UBSan) and macos.
- CI Task 2, sha 01af484: native-verify 40727372337, flutter-plugin 40727372347, no reruns; `CI-GATE ok`. `CONFIG-VAAPI ok` on both linux runners; `RENDER_GL drm ok api=gl renderer=gpu vaapi=display-not-created` on linux; ubuntu hwdec leg still plays to the end on software, no `unexpected`.
- `vaapi=` values (information only): with vaapi compiled in, `RENDER_VK` lines report `interop-unavailable` (lavapipe has no dma-buf interop for the vulkan path), `RENDER_GL` reports `display-not-created` (render_fd -1). These describe llvmpipe/lavapipe without /dev/dri, not real VA-API interop (research A1 / Pitfall 4). Records in `evidence/ci-runs-16-03.txt`.

## Deviations from Plan

**1. [Process] One infra rerun.** The macos `integration-test` job of run 40721479785 was cancelled while queued; `gh run rerun --failed` once, then green.

**2. [Rule 1 - test design] Narrow verbose log in `--drm`.** Both smokes set `msg-level` to `all=warn,vo=v,libmpv_render=v,vaapi=v` instead of `all=v`: mpv's log queue drops the oldest entries on overflow and the registration line is the first one emitted, so `all=v` could lose it. Same gate outcome; no plan assertion changed.

**3. [Process] `hwdec-vaapi-built` line.** The ubuntu `hevc-10bit` `HWDEC` end row was recorded (software outcome, `hwdecInterop` null) as the hosted safe-fallback evidence.

## Known Stubs

None.

## Self-Check: PASSED

Commits 7af3431 and 01af484 are ancestors of HEAD; summary files present.
