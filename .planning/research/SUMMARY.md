# Project Research Summary

**Project:** mpv_kit — milestone v3.0 (unified render lifecycle + platform-native graphics backends)
**Domain:** libmpv render API backends (D3D11 / OpenGL / Metal-class) feeding Flutter desktop external textures, zero-copy hwdec
**Researched:** 2026-10-26
**Confidence:** MEDIUM-HIGH (code mapping and upstream status HIGH; D3D11/GL sync designs MEDIUM until run; Linux GLES hwdec and anything requiring non-Windows GPU hardware LOW-MEDIUM)
**Phase numbering:** continues at **Phase 12**

> **Hard user constraint (verbatim):** Windows must NOT use ANGLE/EGL anywhere in mpv_kit's own render chain (media_kit may only be read).
> ANGLE inside Flutter's engine (which consumes our DXGI handle) is outside our control and not covered by this rule (ADR 0003).
>
> **Already decided by the user:** macOS route = "decide after research"; v2.0 leftovers UHD-02 / COMP-02 / COMP-03 stay deferred.

## Executive Summary

v3.0 turns a Vulkan-centric native renderer into a lifecycle engine (render thread, frame ring, quarantine, retire-on-resize, backoff, swap reporting, typed events) with pluggable graphics backends. Experts build this kind of plugin exactly the way mpv_kit already does — better than media_kit and fvp: one render thread and one device/context per controller, never render in the compositor callback, a stable texture id across resizes, a completion-gated ring instead of a per-frame copy, and explicit fallback reporting. All four research files agree ~85% of `VideoRenderer` is already API-independent; the Vulkan-specific ~15% moves behind a `RenderBackend` interface that needs two hooks the user's original list lacked: a `Wait(slot)` completion gate and `BindThread/UnbindThread` (required by the GL render API). `FrameReady` stays on the platform side.

The single most important finding is timing: **upstream mpv merged a native D3D11 libmpv render API** (PR #17764, `4255130de4`, 2026-10-15, client API 2.6), 64 commits after our vendored base. It is native D3D11 with no ANGLE (host passes its own `ID3D11Device`; mpv renders into the host's texture) but only drives the legacy `gpu` renderer. So mpv_kit should **adopt upstream's ABI verbatim** and write only a gpu-next D3D11 branch in patch 0004 (`pl_d3d11` on the same device), which is also what makes d3d11va truly zero-copy. Linux GL needs no mpv patch for the `gpu` renderer, but upstream has no gpu-next over GL either — hence the fallback order must be **renderer-quality first, graphics-API second**, or Linux/Windows users would silently drop from Vulkan gpu-next to `gpu`. On macOS libplacebo has no Metal backend; the existing MoltenVK→IOSurface path already runs on Metal and already has VideoToolbox zero-copy compiled in (`hwdec_vt_pl`) — recommendation: keep it, document in an ADR, verify.

Key risks: (1) assuming native D3D11 removes the need for sync — the Flutter consumer still opens the handle through ANGLE with no fence, so quarantine 4 + a producer fence stay mandatory; (2) a refactor that destroys the D-05 baseline — take a soak baseline first and keep extraction commits pure moves; (3) `mpv_render_*` thread affinity (`report_swap` is called from the raster thread today — UB under GL); (4) the `hwdec` default `vulkan,d3d11va-copy,auto-safe` silently choosing copy-back on the new backend; (5) honest backend reporting vs the frozen `MpvVideoBackend {vulkan, software}` enum; (6) hosted CI runners (WARP, llvmpipe, M1 VM) cannot prove hwdec.

## Key Findings

### Recommended Stack

No new Dart dependencies and no new libmpv symbols (`MpvApi` stays at 9; Dart `_symbols` unchanged). All new work rides render params and native build flags.

**Core technologies:**
- **Upstream mpv D3D11 render API** (`render_d3d11.h`, `MPV_RENDER_API_TYPE_D3D11`, params 21/22, client API 2.6): native D3D11 for the `gpu` renderer — upstream code, no collision with our `0x6d6b00xx` range, forward-compatible with libmpv 0.42.
- **gpu-next D3D11 branch in patch 0004**: pairs `ra_d3d11` (needed for hwdec) with `pl_d3d11_create(.device = ra_d3d11_get_device(ra))` and wraps the host texture with `pl_d3d11_wrap`; upstream `gpu_next/context.c` already shows the pattern. Our `done_frame` returns `bool`, so the backport hunk must `return true;`. Extend 0003's persistent shader cache to the DXBC path (otherwise every launch stutters on D3DCompile).
- **libplacebo 7.360.1 `-Dd3d11=enabled`** (Windows) + backport pair `82224764a9` + `c43baa7a0c`; uses system `d3dcompiler_47.dll` (not bundled; load from System32 only).
- **SPIRV-Cross `vulkan-sdk-1.4.363.0`** (shared `spirv-cross-c-shared`) + **shaderc v2026.4** built against our pinned glslang 16.6.0 — both Apache-2.0 (LGPL-compatible); mpv's meson requires both for `-Dd3d11`, and without `-Dd3d11` `hwdec_d3d11va.c` is never compiled (why d3d11va is copy-back only today).
- **Linux: mpv `-Dgl=enabled -Degl=enabled -Dplain-gl=enabled`** (x11/wayland stay disabled), upstream `MPV_RENDER_API_TYPE_OPENGL`; `libEGL`/`libGL` already on the system allowlist.
- **Explicit ANGLE ban in the build:** `-Degl-angle=disabled -Degl-angle-lib=disabled -Degl-angle-win32=disabled -Dgl-win32=disabled -Dgl-dxinterop=disabled`, plus a new `pe_audit.py` rule failing CI if any of our DLLs imports `libEGL.dll`/`libGLESv2.dll` or references `eglGetPlatformDisplayEXT`.
- **Optional:** nv-codec-headers `n13.0.19.1` for nvdec (`--enable-ffnvcodec --enable-nvdec --enable-cuvid` only; never `cuda-nvcc`/`libnpp`/`nonfree`).

**Flutter contracts (3.47.x, unchanged):** Windows `GpuSurfaceTexture` + `DxgiSharedHandle`, legacy KMT `MISC_SHARED` (never NTHANDLE/KEYEDMUTEX; never the `D3d11Texture2D` type); `release_callback` is lifetime-only, not read-completion. Linux `FlTextureGL::populate` runs on the raster thread with Flutter's GLES context current and must return a `GL_RGBA8` texture. macOS `copyPixelBuffer` returns a +1, IOSurface-backed `32BGRA` buffer.

### Expected Features

**Must have (table stakes):**
- TS-1 one `RenderBackend` lifecycle; Vulkan + software migrated with zero behaviour change (rollback baseline)
- TS-2/TS-3 resize never changes the texture id and never flashes black; render size = widget physical size capped at video size, on every backend
- TS-4 no rendering on UI/raster threads; frame-ready from the render thread
- TS-5/TS-12 deterministic deferred release (after unregister completion + quarantine); correct producer→compositor sync
- TS-6 one device/context + one render thread per controller (no global serialisation)
- TS-7 hwdec on by default with per-backend zero-copy → copy-back → software fallback
- TS-8/TS-11 honest backend/reason chain (native → Vulkan → software) and `MPV_KIT_VIDEO_RENDERER` honoured
- TS-9/TS-10/TS-13–15 10-bit sources correct on an 8-bit target, typed device loss, robustness to Flutter Linux embedder changes, no static singletons, ICC/display-fps/shader-cache/`report_swap` keep working

**Should have (differentiators):**
- D-1 true zero-copy hwdec on every native backend (d3d11va, vaapi dma-buf, videotoolbox)
- D-2 compositor-latency-sized ring instead of per-frame `CopyResource` (media_kit and fvp pay ~4 GB/s at 4K60)
- D-3 explicit producer fences (`ID3D11Fence`, EGL sync) instead of `glFinish`
- D-4 gpu-next on native backends (Windows needs it so `auto` can prefer D3D11 without an HDR regression)
- D-5/D-6 full fallback trail in `reason`; native-only env switch (`MPV_KIT_VIDEO_API`) to force a backend for CI without a Dart API change

**Defer (v3.x+):** D-7 in-place device-loss rebuild; gpu-next over GL (patch 0011) unless the user puts it in scope; nvdec verification (no NVIDIA Linux hardware); consumer-side fences (need Flutter changes); macOS Metal `pl_gpu` (wait for libplacebo); UHD-02/COMP-02/COMP-03 (user decision).

**Anti-features:** ANGLE/EGL in our Windows chain (A-1); copy-back as silent default; rendering inside the compositor callback; re-registering the texture on resize; one global render thread; silent fallback; new public enum values; a CGL backend on macOS; `--wid` embedding; `hwdec=auto-unsafe`.

### Architecture Approach

`VideoRenderer` keeps the generic engine (render thread, ring bookkeeping, publish gate, swap, idle, backoff, ICC, events, probe) and runs a candidate loop over `(renderer, api)` pairs returned as data by `PlatformSink::BackendCandidates()`. Each platform contributes its native backend via `PlatformSink::CreateBackend(kind)` so `src/` never includes platform headers. A backend is rolled back by deleting one list entry.

**Major components:**
1. **`RenderBackend` interface** (`src/render_backend.h`) — `Create`, `AllocTargets`, `FrameFor`/`RetiredFront`, `Render`, `Wait(slot)` → `{kOk, kTimeout, kDeviceLost}`, `pipelined()`, `BindThread`/`UnbindThread`, `Release` (render context before device), dtor (device last).
2. **`VulkanRenderBackend` / `SoftwareBackend`** (`src/`) — pure extractions of today's `StartVulkan`/`StartSoftware` and render branches; `VulkanContext`/`VulkanInterop` unchanged.
3. **`D3D11Backend`** (`windows/`) — own `ID3D11Device` on Flutter's adapter LUID with `BGRA_SUPPORT | VIDEO_SUPPORT` (retry without), `SetMultithreadProtected(TRUE)`, never `SINGLETHREADED`; KMT shared-texture ring reusing `D3D11Interop::Texture`; `ID3D11Fence` signalled on the render thread after each render, `D3D11_QUERY_EVENT` fallback; quarantine stays 4 (ring 7).
4. **`OpenGLBackend`** (`linux/`) — own surfaceless EGL context on Flutter's `EGLDisplay`, outside Flutter's share group; per-slot render texture + FBO and a separate export texture backing the `EGLImage` (see decision 6); `EGLSync` waits; `GlInterop::Image` gains an `egl_image` kind; DRM render-node fd passed to mpv as `MPV_RENDER_PARAM_DRM_DISPLAY_V2`.
5. **macOS unchanged** — MoltenVK→IOSurface reported as `vulkan (gpu-next) ... via MoltenVK`.
6. **Wire protocol (private)** — `create` returns `backend: "d3d11"|"opengl"|"vulkan"|"software"` (still strictly validated); reason grammar `<api> (<renderer>) on <device>[; <api>/<renderer> unavailable: <why>]*`.

**Recommended auto chain (renderer-first, API-second):**

| Platform | Chain |
|---|---|
| Windows | d3d11/gpu-next → vulkan/gpu-next → d3d11/gpu → vulkan/gpu → sw |
| Linux (no 0011) | vulkan/gpu-next → opengl/gpu → vulkan/gpu → sw |
| macOS | vulkan/gpu-next → vulkan/gpu → sw |

Flipping Windows `auto` to D3D11 is a visible change: one reviewed list edit in its own commit, only after CI and the RTX 4060 are green.

### Critical Pitfalls

1. **Consumer is still ANGLE (P1)** — do not shrink quarantine for D3D11; keep a producer completion fence; `MISC_SHARED` only; make `CompositorLatency()` per (platform × backend) and measure it with Impeller on/off.
2. **Refactor erases D-05 evidence (P11)** — the first Phase 12 plan fixes the soak harness (missing `setSize`) and records a Vulkan baseline (D-05, 100-round resize/dispose, 100 create/dispose, Impeller on/off, renderer line). Extraction commits change no constants (ring 5/7, quarantine 2/4, 50 ms present timeout, 100 ms→5 s backoff) and no reason strings; bug fixes go in separate commits.
3. **`mpv_render_*` thread affinity (P6)** — `report_swap` currently runs on the raster thread (UB under GL); in Phase 12 turn it into a queued count drained by the render thread; `render_context_free` with the backend's context bound; never set `ADVANCED_CONTROL`.
4. **hwdec list defeats zero-copy (P4)** — under D3D11 `vulkan` fails and `d3d11va-copy` wins. Change the default to an ordered list with every zero-copy candidate first (e.g. `vulkan,d3d11va,d3d11va-copy,auto-safe`, extended per platform); every soak asserts `hwdec-current` and reports zero-copy yes/no.
5. **Parallel downstream D3D11 ABI (P2) and the build gap (P3)** — never invent `render_d3d11` params; the build plan (shaderc, SPIRV-Cross, `-Dd3d11`, audit allowlists) lands before the render plan; verify `config.h` `HAVE_D3D11` and `hwdec-current=d3d11va` (not `-copy`).
6. **Linux GL failure modes (P5)** — never query the current context on the platform thread; never use mpv's render target as the EGLImage source (Mesa Xe2 black frames, no error); fences, not flush alone; `gdk_gl_context_clear_current()` before `eglMakeCurrent` on the GTK thread.
7. **CI cannot prove hwdec (P14)** — two verification tiers: render path on hosted runners (WARP/llvmpipe/M1 VM, `hwdec=no`, non-black pixel probe); zero-copy on the RTX 4060 behind an `MPV_KIT_REQUIRE_HWDEC` loud-fail guard; serialise WARP jobs.

## Implications for Roadmap

### Phase 12: RenderBackend seam (pure refactor, baseline first)
**Rationale:** every later backend inherits resize/release/sync correctness only if this lands first; independent rollback point.
**Delivers:** harness fix + D-05/soak baseline on the current Vulkan path; fake-libmpv golden tests of the `VideoRenderer` state machine before any move; `RenderBackend` + `VulkanRenderBackend` + `SoftwareBackend` extraction; `PlatformSink` candidates (Vulkan/software only); `report_swap` marshalled to the render thread; shared deferred-release contract; `wire_name()`, reason grammar and Dart acceptance of the new wire names; `MPV_KIT_VIDEO_API` override; backend-reporting ADR (decision 1).
**Addresses:** TS-1, TS-5, TS-8, D-6. **Avoids:** P6, P10, P11, P12.
**Verification:** RTX 4060 4K 30-minute run vs the Phase 4 baseline; `render_vk_smoke`, Phase 2/3 suites green.

### Phase 13: macOS route decision (ADR + verification)
**Rationale:** cheap, settles an open question early; only needs the Phase 12 reason grammar.
**Delivers:** ADR comparing (a) keep MoltenVK→IOSurface, (b) CGL+IOSurface (rejected: deprecated, `gpu` only, GL 4.1, needs cocoa), (c) own Metal backend (rejected: no libplacebo Metal, rewrite-scale); re-evaluation trigger "libplacebo merges a Metal `pl_gpu`"; `via MoltenVK` in reason; VideoToolbox zero-copy check including P010.
**Avoids:** P13.

### Phase 14: Windows native D3D11 backend
**Rationale:** most unknowns and the only real hardware; can run in parallel with Phase 15.
**Delivers:** (a) bundle build: SPIRV-Cross, shaderc, libplacebo + mpv `-Dd3d11`, explicit ANGLE-off flags, PE-audit rule failing on `libEGL`/`libGLESv2`; (b) upstream D3D11 ABI (decision 2) + gpu-next D3D11 branch in 0004 + DXBC `pl_cache` + `render_d3d11_smoke.c` on WARP; (c) `D3D11Backend` with fence/query waits and device-removed → `device_lost`; (d) `d3d11` added to the Windows candidate list in its own commit.
**Addresses:** TS-6, TS-10, TS-12, D-2, D-3, D-4. **Avoids:** P1, P2, P3.

### Phase 15: Linux OpenGL backend
**Rationale:** no mpv patch for `gpu`, lower risk, no file overlap with Phase 14.
**Delivers:** mpv GL/EGL build; `render_gl_smoke.c` (EGL surfaceless on llvmpipe); `OpenGLBackend` (isolated context, EGLImage export, EGL sync); candidate placement per the renderer-first rule; optionally patch 0011 (decision 5).
**Addresses:** TS-13, D-3. **Avoids:** P5, P6, P7.
**Hardware limit:** no Linux GPU hardware — say so in verification.

### Phase 16: Hardware-decode zero-copy across backends
**Rationale:** zero-copy depends on each backend's `ra`; CI can only prove the negative/fallback paths.
**Delivers:** d3d11va zero-copy on D3D11 (evaluate `d3d11va-zero-copy=yes` for 8K); `DRM_DISPLAY_V2` render fd for vaapi on GL and on Vulkan gpu-next (native-resource follow-up in 0004); VideoToolbox on MoltenVK; new cross-backend hwdec default list documented as a behaviour change; nvdec build enabled or explicitly deferred (decision 8).
**Addresses:** D-1, TS-7, TS-9. **Avoids:** P4, P8, P9.

### Phase 17: Fallback hardening + UHD regression
**Delivers:** fault injection via a fake backend (device lost, timeout storms, allocation failure → next candidate); forced-API CI matrix per platform; two-tier CI with `MPV_KIT_REQUIRE_HWDEC`; 4K 30-minute runs on D3D11 and Vulkan; per-backend 100-round resize/dispose/route push-pop soak with flat dedicated GPU memory.
**Avoids:** P14 and P1 regressions.

### Phase Ordering Rationale
- 12 first and pure — every later phase rolls back to it.
- 13 early because it is cheap and resolves an open question.
- 14 ∥ 15 are independent; if sequential, D3D11 first (higher risk, only real hardware).
- 16 after the backends to isolate the unverifiable parts; 17 closes with gates.
- Decisions 1 and 3 (reporting, auto order) block Phase 12's reporting work and the candidate-list edits in 14/15.

### Research Flags
- **Needs `/gsd-plan-phase --research-phase`:** Phase 14 (shaderc vs glslang 16.6.0; shaderc/SPIRV-Cross on MSYS2 CLANGARM64; `ID3D11Device5` fences and `VIDEO_SUPPORT` on WARP; typed UAV on BGRA8; 0004/0010 hunk conflicts). Phase 15 (Flutter 3.47 Linux raster-thread identity, EGL vs GLX `EGL_BAD_ACCESS`, FLIP_Y, GLES vs desktop GL for the isolated context). Phase 16 (per-hwdec: vaapi render node on hybrid GPUs, P010 dma-buf modifiers, CUDA with GLES).
- **Standard patterns (skip research):** Phase 12 (code fully mapped), Phase 13, Phase 17.

## Open Decisions for the User

1. **Backend reporting under the API freeze.** (a) Keep `MpvVideoBackend {vulkan, software}`, re-document `.vulkan` as "GPU zero-copy", carry the true API in a machine-checkable `reason` prefix (ARCHITECTURE, FEATURES lean here); (b) one documented exception adding enum values (breaks exhaustive switches, API-freeze test goes red). **Recommend (a)**, recorded in a Phase 12 ADR; wire set still strictly validated (STAB-04).
2. **How the upstream D3D11 render API enters the tree.** STACK: backport the 4 commits (`f0b70a87c2`, `b96f286532`, `2a97b84b39`, `69920fdcaf`) as `0010-upstream-d3d11-render-api.patch` (0009 style). PITFALLS: advance the vendored tree past `4255130de4` (64 commits) via the Phase 5 regenerate process. ARCHITECTURE's downstream `render_d3d11.h` with `0x6d6b0011/12` conflicts with upstream and is **rejected**. **Recommend the backport patch for v3.0** (smaller, independently revertible, avoids 60 unrelated commits); keep upstream ABI byte-for-byte (21/22, client API 2.6), fix the `done_frame` bool signature, drop the hunks at the next vendor advance. Choose the advance instead if the 64 commits turn out to touch 0004 heavily anyway.
3. **`auto` order.** Renderer-first, API-second (all four agree on the hazard). Windows `auto` moves to D3D11 only once gpu-next on D3D11 exists; until then D3D11 is only the `gpu` tier. **Recommend adopting.**
4. **shaderc / SPIR-V compilation for mpv `ra_d3d11`.** STACK/ARCHITECTURE: bundle shaderc built on our glslang (keeps the `gpu` fallback on D3D11, no mpv source change). PITFALLS: patch mpv's meson to accept glslang or use a null-compiler stub (smaller bundle, loses `gpu` on D3D11, larger patch surface). **Recommend bundling shaderc.** SPIRV-Cross shared vs static (PITFALLS suggests patching libplacebo to link statically; STACK uses the shared DLL): **recommend the shared DLL** listed in MANIFEST, ABI audit and licenses — never an unlisted DLL.
5. **gpu-next over the GL render API (patch 0011).** In scope: GL truly first on Linux, but downstream work in an area upstream is redesigning (#16818, #18607 open). Out of scope: GL is a fallback tier below Vulkan gpu-next. **Recommend out of v3.0 core**, optional stretch inside Phase 15; renderer report must say `gpu` whenever vo_gpu serves.
6. **Linux GL export texture.** ARCHITECTURE: EGLImage from each slot's render texture. PITFALLS/FEATURES: mpv renders into a private texture blitted into a separate export texture (Mesa Xe2 black-frame bug, media-kit #1463). **Recommend separate export texture + blit** (well under 1 ms at 1080p; measure at 4K).
7. **VA display parameter.** FEATURES: pass `X11_DISPLAY`/`WL_DISPLAY` like media_kit. STACK/ARCHITECTURE/PITFALLS: x11/wayland are compiled out, so only `MPV_RENDER_PARAM_DRM_DISPLAY_V2` with a render node derived from the EGL device works. **Recommend DRM_DISPLAY_V2** (also unlocks vaapi on the existing Vulkan path).
8. **nvdec.** Enable in the build unverified, or defer explicitly. No NVIDIA Linux hardware; on Windows d3d11va covers NVIDIA. **Recommend explicit deferral** (at most build-enabled, marked "unverified").
9. **`Player` hwdec default change.** Behaviour change, not a signature change. **Recommend** doing it in Phase 16 and documenting it.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Upstream PR/commit/compare checked via the GitHub API; meson/build flags read locally. shaderc against glslang 16.6.0 and arm64 MSYS2 availability MEDIUM. |
| Features | MEDIUM | Reference player behaviour from source at pinned commits (HIGH); field failures from issue trackers (MEDIUM); IINA/MPVKit LOW. |
| Architecture | HIGH / MEDIUM | Code-to-interface mapping HIGH; D3D11/GL sync designs follow documented contracts but have not run (MEDIUM). |
| Pitfalls | MEDIUM | Vendored-tree facts HIGH; many issue reports are single-reporter; LOW-tagged items need re-checking. |

**Overall confidence:** MEDIUM-HIGH for the plan shape; LOW-MEDIUM for hwdec outcomes outside Windows.

### Gaps to Address
- **D-05 still unexplained** — re-baseline before Phase 12 moves any code.
- **D3D11 quarantine value unmeasured** — 4 is inherited; measure with Impeller on/off (touches deferred COMP-03: measure only, do not re-parameterise).
- **WARP behaviour** — fences, `VIDEO_SUPPORT`, parallel-test stability on windows-2025.
- **Flutter Linux embedder** — raster-thread identity, GLX vs EGL context, FLIP_Y: spike.
- **Unverified hardware paths** — vaapi, nvdec, P010 dma-buf have no hardware; VideoToolbox inside the macOS VM unverified; report honestly.
- **D3D11 max 2D texture size** — 8192 at FL 10_x was quoted from memory; check Microsoft's resource limits before planning the 8K ring.
- **Flutter#190774** — confirm the pinned Flutter contains the Impeller snapshot-crash fix.

## Sources

### Primary (HIGH confidence)
- Vendored mpv: `vo_gpu_next.c`, `vo_libmpv.c`, `gpu/libmpv_gpu.c`, `gpu_next/context.c`, `d3d11/{ra_d3d11,hwdec_d3d11va}.c`, `hwdec/{hwdec_vaapi.c,hwdec_vt_pl.m}`, `dmabuf_interop_gl.c`, `include/mpv/{render.h,render_vk.h}`, `meson.build`
- Build scripts and plugin sources: `native/build/{build,deps,ffmpeg,package}.sh`; plugin `src/`, `windows/`, `linux/`, `macos/`; `video_controller.dart`; ADR 0003; `docs/reverse-engineering/03`
- Upstream mpv PR #17764 (merged `4255130de4`), `render_d3d11.h` at that commit; open PRs #16818, #18607
- libplacebo v7.360.1 `d3d11` headers/meson, commits `82224764a9`, `c43baa7a0c`; Metal status #370, #380, MR !858
- Flutter 3.47.6 `fl_opengl_manager.cc`, `fl_texture_gl.h`, `FlutterTexture.h`, `flutter_texture_registrar.h`

### Secondary (MEDIUM confidence)
- media_kit `c533e44` and fvp `fb4e11e` plugin sources (read only)
- media_kit issues #296, #1278, #1099, #363, #1321, #1345, #1463, #1383, #1443
- mpv issues #17626, #10810, #11151, #10424
- Flutter issues #154716, #190044, #190774, #191468

### Tertiary (LOW confidence)
- IINA/MPVKit web summaries; CUDA interop on GLES; WARP parallel-test crashes; macOS VM VideoToolbox; search-summary-only issues in PITFALLS.md

---
*Research completed: 2026-10-26*
*Ready for roadmap: yes (pending the user decisions above)*
