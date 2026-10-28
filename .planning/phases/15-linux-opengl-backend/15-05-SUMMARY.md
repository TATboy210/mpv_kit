---
phase: 15-linux-opengl-backend
plan: 05
subsystem: native
tags: [linux, opengl, egl, eglimage, fltexturegl, runbound, probe]

requires:
  - phase: 15-02
    provides: render_gl_smoke handoff evidence (D-GL-API, D-FLIP-MPV, D-SYNC)
  - phase: 15-03
    provides: texture probe, D-THREAD / IMPLICATION=helper-thread
  - phase: 15-04
    provides: LinuxBackendCandidates (decision A), RenderBackend::RunBound
provides:
  - "packages/mpv_kit_video/linux/opengl_backend.cc: OpenGLBackend (own EGL context, private texture, blit, export texture, EGLImage, EGLSync, RunBound thread)"
  - "GlInterop: EGLImage import/destroy, BackendCandidates -> LinuxBackendCandidates, CreateBackend(opengl)"
  - "src/include/mpv/render_gl.h verbatim upstream copy"
  - "native-verify: forced-opengl real_plugin_test and texture probe; probe hard assertions"
affects: [15-06, 15-07]

actuals:
  tokens: 36000
  tasks: 2
  commits: 7
plan_head_before: 09a16da7316598112d3a0d71f08021df75323310
plan_head_after: 8ebf844736941300c6a810d94aa95c943d8c96a1

key-files:
  created:
    - packages/mpv_kit_video/linux/opengl_backend.cc
    - packages/mpv_kit_video/src/include/mpv/render_gl.h
    - .planning/phases/15-linux-opengl-backend/evidence/backend-runs.txt
  modified:
    - packages/mpv_kit_video/linux/gl_interop.h
    - packages/mpv_kit_video/linux/gl_interop.cc
    - packages/mpv_kit_video/linux/CMakeLists.txt
    - .github/workflows/native-verify.yml
    - example/integration_test/texture_probe_test.dart

key-decisions:
  - "FLIP_Y = 0: D-ORIENT=unknown, so the plan's rule takes D-FLUTTER-ORIGIN=top-left -> D-FLIP-MPV value (row0-top-when-flip_y=0). Confirmed by the CI probe: opengl reads upright before and after the resize."
  - "Context API order gl (3.3 core, then default), then gles 3 (D-GL-API=gl,gles); share context EGL_NO_CONTEXT; display from FlutterEglDisplay() in the constructor (platform thread), eglInitialize and context creation on the RunBound thread."
  - "Backend::kVulkan is reused as 'shared GPU image' for frame_kind (plan's wording); populate stays render-free."

requirements-completed: []
requirements-partial: [GLX-03, GLX-04]  # still open work in 15-06 (ProbeGl on a helper thread, Vulkan-unavailable auto proof) and 15-07

ci-gate: passed 2026-10-28 (Task 1 sha e047c4d: native-verify 40647806493, flutter-plugin 40647806590; Task 2 sha a76c714: native-verify 40649428663, flutter-plugin 40649428568 -- see the Task 2 gate deviation)
ci_gates_passed:
  - "15-05 Task 2 `PROBE {\"api\":\"vulkan\"` expectation (deviation 2) met by 15-06 on sha fbcd55a: native-verify 40653685694, flutter-plugin 40653685682; default probe api vulkan, supported, nonBlackRatio 1.0, upright before and after the resize (D-ORIENT=upright)."
status: complete
completed: 2026-10-28
---

# Phase 15 Plan 05: OpenGLBackend in the Linux plugin Summary

**`MPV_KIT_VIDEO_API=opengl` now renders on the real Linux plugin through mpv's OpenGL render API: a private context on Flutter's EGLDisplay, private texture -> blit -> per-slot export texture -> EGLImage -> `FlTextureGL`, published only after an EGL fence; the Linux chain (decision A) is wired in.**

## Accomplishments

- **OpenGLBackend (Task 1):** create-time calls run in `RunBound` on the backend's own short-lived thread (D-THREAD evidence), the render thread binds the context for its lifetime (`render_thread_bound_` false makes AllocTargets/Render fail with a why, never a GL call without context). EGLImages come from export textures only; `Wait` is `eglClientWaitSyncKHR` with the 1 s bound; populate only imports each image once (`glEGLImageTargetTexture2DOES`) and the graveyard frees the Flutter texture and the EGLImage. populate contains no render call (grep gate).
- **Commits as planned:** 3827f5f (backend, render_gl.h, CMake, TextureFor/FreeImages; chain unchanged), then the chain/CI-step commit b07d335 (revert it to get the Phase 12 chain back). ddbb9d6 and e047c4d are two small CI-found compile fixes (see Deviations).
- **Task 1 CI evidence (evidence/backend-runs.txt):** forced run INTEGRATION `backend:"vulkan"` (frames are shared GPU images, ADR 0004) with reason `opengl (gpu) on llvmpipe (LLVM 20.1.2, 256 bits); vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=opengl`; forced soak `{"resizeEvents":30,"cycles":10,"renderErrors":0,"deviceLost":0}`; default first controller still `vulkan (gpu-next) on llvmpipe`. 11 forced `mpv_kit_video:` lines, all opengl.
- **Task 2:** probe hard-asserts supported, nonBlack >= 0.01, upright (opengl), no renderError/deviceLost, stable textureId. Both probe steps passed on CI: `supported:true, nonBlackRatio:1.0, upright` before and after the resize, `renderErrors:0`, same textureId.

## Deviations from Plan

1. **[Rule 3 - Blocking] two CI compile fixes** in the new file only: `eglGetProcAddress` result converted through memcpy (-Werror pedantic), and `#include <mpv/render_vk.h>` for `MPV_RENDER_PARAM_VULKAN_RENDERER` (ddbb9d6 failed the Linux plugin build, run 40646593067; fixed in e047c4d; the macos-route failure on the same sha was a hwdec check that passed on the fixed sha without code changes on macOS, i.e. a flake of that probe, not this plan).
2. **Task 2 gate, vulkan PROBE line missing (documented, not fixed):** the plan's gate also wants `PROBE {"api":"vulkan"`. In the default (unset) probe run, ProbeGl fails on the platform thread (`eglMakeCurrent EGL_BAD_ACCESS`, the D-THREAD finding), so Vulkan is unavailable and the auto chain correctly falls through to opengl (`PROBE api=opengl`, hard assertions pass). A Vulkan probe line can exist only after 15-06 Task 2 moves ProbeGl to a helper thread. `--jobs-success` and the opengl PROBE expectations passed; the Task 2 evidence check on the forced opengl line passed. 15-06 should re-assert the vulkan PROBE and settle D-ORIENT; until then the Vulkan orientation is unverified and unasserted.
3. **D-PROBE is still `unknown` in spike-flutter-linux.txt;** the first opengl probe run shows `toImage` can read the external texture on Linux (supported:true, upright), so the pixel and orientation assertions are on. The spike file was not rewritten.

## Known limits (honest scope)

- Everything is llvmpipe-only (software GL). NVIDIA/AMD/Intel GL drivers, Mesa Xe2 and Wayland EGL are unverified. `Wait` has no device-lost signal without a robust context (EGL failure maps to timeout).
- Compositor-layer proof (SC2) is met on llvmpipe via the mounted probe: nonblack and upright for opengl; Vulkan orientation is not shown (see deviation 2).
- GLX-03/GLX-04 stay open: ProbeGl/Vulkan-unavailable proof (15-06) and docs/final audit (15-07).

## Known Stubs

None.

## Self-Check: PASSED

Files exist (opengl_backend.cc, render_gl.h copy, backend-runs.txt); commits 3827f5f, b07d335, ddbb9d6, e047c4d, 711982d, a76c714, 8ebf844 are on origin/feat/mpv-master-upgrade; golden-freeze sha256 check OK.
