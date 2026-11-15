---
phase: 15-linux-opengl-backend
verified: 2026-10-28T12:00:00Z
status: passed
score: 4/4 roadmap success criteria verified (llvmpipe-only by design; unverified list user-accepted)
behavior_unverified: 0
overrides_applied: 0
gaps: []
accepted_unverified:
  - "NVIDIA / AMD / Intel real drivers, Mesa Xe2 EGLImage black frame, Wayland EGL, real X11+libglvnd+GLX, GL device loss, arm64 real-plugin GL path, Impeller external-texture origin, populate EGLImage import failure, native D-LOG lines (evidence/unverified.txt; accepted by user, decisions.txt decision=sc3-wording 2026-10-28)"
---

# Phase 15: Linux OpenGL Backend Verification Report

**Phase Goal:** On Linux, mpv renders through the upstream OpenGL render API in a separate EGL context on the render thread, delivers frames via an export texture + EGLImage to FlTextureGL, as a tier after Vulkan gpu-next, and honestly reports the actual renderer.
**Verified:** 2026-10-28
**Status:** passed (with a user-accepted unverified list; see below)
**Re-verification:** No, initial verification
**Evidence scope:** every runtime proof is hosted ubuntu runner, xvfb + Mesa llvmpipe (software GL and software Vulkan). This is the design of the phase (no Linux GPU hardware); real-driver behavior is NOT claimed.

## Method

SUMMARY claims were not trusted. Checked: ROADMAP Phase 15 + SC wording (SC3 updated in commit 2251ef2 with user approval), REQUIREMENTS GLX-01..04, code in `packages/mpv_kit_video/linux/*`, `src/linux_candidates.h`, `src/render_backend.h` (RunBound), `src/video_renderer.cc`, `native/tests/render_gl_smoke.c`, `native/build/build.sh`, workflows; recorded evidence files; CI run conclusions via `gh run view <id> --json conclusion`; and the saved raw log `/tmp/gsd-bak/ci/nv-40661093250.log` (grep for the claimed marker lines).

## Goal Achievement: Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| SC1 | Linux bundle built with `-Dgl -Degl -Dplain-gl` (x11/wayland off), upstream `MPV_RENDER_API_TYPE_OPENGL`, allowlist + ABI audit green; `render_gl_smoke` non-black on ubuntu (EGL surfaceless + llvmpipe) | VERIFIED | `native/build/build.sh:32,42` (`-Dx11=disabled -Dwayland=disabled`; `-Dgl=enabled -Degl=enabled -Dplain-gl=enabled -Degl-drm=disabled`). `OpenGLBackend::Create` passes `MPV_RENDER_API_TYPE_OPENGL` (opengl_backend.cc ~L229). `native/tests/render_gl_smoke.c` (736 lines) registered in `native/tests/meson.build:237-240` (gl and gles). native-verify run 40661093250 (success, sha e7bc162): raw log has `CONFIG-GL ok` x6, `RENDER_GL ok api=gl renderer=gpu` x3, `RENDER_GL ok api=gles renderer=gpu` x3. release run 40662838575 (success, sha e7bc162; publish skipped): linux-x64 + linux-arm64 green; release-runs.txt shows `NEEDED libEGL.so.1` (host lib, user decision bundle-egl=adopt), `packaged 17 libraries`, `requires GLIBC_2.35`. |
| SC2 | `MPV_KIT_VIDEO_API=opengl` real-plugin test on xvfb+llvmpipe renders non-black; mpv -> private texture -> blit -> export texture -> FlTextureGL; EGLSync before publish; no mpv render in populate; resize keeps texture id | VERIFIED | Code: opengl_backend.cc `glBlitFramebuffer` (~L345) from private target into per-slot export texture; `eglCreateSyncKHR` (~L351) + `eglClientWaitSyncKHR` in `Wait` (~L361, 1 s bound); `mpv_kit_gl_texture_populate` (mpv_kit_video_plugin.cc:121-150) only does `AcquireFront` + texture-name lookup + graveyard drain, no `mpv_render_*`. Runs 40653685694 / 40661093250: forced-opengl `PROBE {"api":"opengl",...,"supported":true,"nonBlackRatio":1.0,"orientation":"upright","afterResizeNonBlackRatio":1.0}`; `INTEGRATION-SOAK resizeEvents=30 renderErrors=0 deviceLost=0`. Texture-id stability asserted in `example/integration_test/texture_probe_test.dart` (`textureBeforeResize` vs `controller.textureId`). Caveat: "populate does not render" and "fence before publish" are proven by code structure plus the handoff smoke (`RENDER_GL handoff ok`), not by a dedicated runtime negative test. |
| SC3 | (reworded 2026-10-28, user-approved) GL context on Flutter's `EGLDisplay`, no Flutter share group; after render thread starts all `mpv_render_*` calls on render thread; create-time calls on the `RunBound` thread with mpv's context current at both places; no epoxy abort / `EGL_BAD_ACCESS` in create/dispose and resize/dispose soak | VERIFIED | Code: `display_(FlutterEglDisplay())`, `eglCreateContext(display_, config, EGL_NO_CONTEXT, ...)` (no share group, opengl_backend.cc ~L441-457); `RenderBackend::RunBound` seam (render_backend.h:127-129), implemented by OpenGLBackend on a short-lived bound helper thread (opengl_backend.cc:187-214) that unbinds before join; `VideoRenderer` runs create/first `set_update_callback`/release inside `RunBound` (video_renderer.cc:291-295, 343-348); render thread does `BindThread ... Release ... UnbindThread`. Tests: `video_renderer_bind_test` (`BIND ok` x6) and `video_renderer_affinity_test` (`AFFINITY ok sw` x6 / `vk` x4) in run 40661093250 raw log; soak with 13 forced-opengl controllers and `SECOND-CONTROLLER opengl/opengl`; `EGL_BAD_ACCESS` count 0 in whole log. Rationale for helper thread (platform thread gets EGL_BAD_ACCESS because a GDK GL context is current) in spike-flutter-linux.txt D-THREAD. The original wording ("all mpv_render_* on the render thread") was knowingly narrowed by user decision (decisions.txt: sc3-interpretation=runbound, sc3-wording=approve); verified against the current ROADMAP text. |
| SC4 | Linux auto chain vulkan/gpu-next -> opengl/gpu -> vulkan/gpu -> software; vo_gpu reason is `opengl (gpu) on <device>`, never gpu-next; Vulkan unavailable falls to GL with the reason stated | VERIFIED | `src/linux_candidates.h` `LinuxBackendCandidates` yields exactly that chain; wired via `GlInterop::BackendCandidates` (linux/gl_interop.h:70-72) and consumed by `video_renderer.cc:310`; `GlInterop` creates `"opengl"` backend (gl_interop.cc:232). `LINUX-CHAIN ok` x6 (golden `native/tests/golden/linux_chain.txt`). Real-plugin: default `vulkan (gpu-next) on llvmpipe`; forced `opengl (gpu) on llvmpipe (...); vulkan/gpu-next unavailable: excluded by MPV_KIT_VIDEO_API=opengl`; Vulkan-unavailable run `opengl (gpu) on llvmpipe (...); vulkan/gpu-next unavailable: vkCreateInstance failed`. `opengl (gpu-next)` occurrences: 0. Note: the opengl -> vulkan/gpu tier is proven by chain data test only. |

**Score:** 4/4

## Requirements Coverage

| Req | Status | Evidence |
|-----|--------|----------|
| GLX-01 | SATISFIED | SC1 (build.sh options, CONFIG-GL, release run 40662838575, upstream GL render API) |
| GLX-02 | SATISFIED | SC1 (`RENDER_GL ok` gl + gles, x64/arm64/sanitizers; pixel 254,0,0) |
| GLX-03 | SATISFIED (llvmpipe) | SC2 + SC3; REQUIREMENTS text already carries the RunBound wording. final-audit.txt labelled it "部分证明" before the user approved the wording; after approval (2251ef2) the requirement text and evidence match. |
| GLX-04 | SATISFIED | SC4 |

No orphaned requirements: GLX-01..04 all claimed by plans and mapped to Phase 15 in REQUIREMENTS.md.

## CI Run Spot-Check (`gh run view <id> --json conclusion`)

| Run | Workflow | sha | Conclusion |
|-----|----------|-----|-----------|
| 40661093250 | native-verify | e7bc162 | success |
| 40661093368 | flutter-plugin | e7bc162 | success |
| 40661093429 | macos-route | e7bc162 | success |
| 40662838575 | release (dispatch, publish skipped) | e7bc162 | success |
| 40653685694 | native-verify (15-06 probes) | fbcd55a | success |
| 40627862148 | native-verify (15-02 spike) | 091228a | success |

final-audit.txt states `packages/mpv_kit_video/linux`, `src`, `native/` unchanged since fbcd55a, so the evidence matches the code now on the branch.

## Anti-Patterns / Findings

| File | Finding | Severity |
|------|---------|----------|
| `packages/mpv_kit_video/src/linux_candidates.h:6` | Stale comment "Nothing in the plugin includes it yet, so the chain a Linux user gets is unchanged"; it is now included by `linux/gl_interop.h` and is the live chain. Documentation drift only. | Info |
| `.planning/ROADMAP.md:57` | Phase 15 bullet still `[ ]` although plans list 7/7 `[x]`. Bookkeeping, left to the orchestrator. | Info |
| `linux/opengl_backend.cc` Wait | No device-lost signal (non-robust context); 1 s timeout reports gpu_timeout only. Recorded in unverified.txt. | Info (accepted) |
| debt markers | No TBD/FIXME/XXX introduced in checked Linux files. | none |

## Accepted Unverified Items (not gaps)

Per phase design and user decision (decisions.txt 2026-10-28: "unverified list accepted, SC2 proved accepted, SC3 wording approved"), all of the following are explicitly NOT claimed and remain unverified in `evidence/unverified.txt`: NVIDIA proprietary EGL; AMD/Intel Mesa hardware; Mesa Xe2 EGLImage black frame; Wayland EGL; real X11 + libglvnd + GLX interaction with the plugin's EGL context; GL device loss / context reset; arm64 real-plugin GL path (arm64 has only `render_gl_smoke`); Impeller external-texture origin (source reading of Skia path only); populate-time EGLImage import failure (g_warning only); native D-LOG lines. Real-hardware Linux validation is a standing project blocker, not a Phase 15 gap.

## Gaps Summary

None. Every ROADMAP success criterion is backed by code present, wired and exercised in recorded green CI runs on llvmpipe. The only residual risk is the user-accepted real-driver list above.

---

_Verified: 2026-10-28_
_Verifier: Claude (gsd-verifier)_
_Note: `verification.fingerprint` fields (covered_files/covered_digest) were not generated, as gsd-tools commands were out of scope for this run._
