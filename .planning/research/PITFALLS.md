# Pitfalls Research

**Domain:** libmpv to Flutter external-texture video output on desktop. v3.0 adds a unified `RenderBackend` lifecycle, native D3D11 on Windows (libplacebo `pl_d3d11`, no ANGLE/EGL in mpv_kit's own chain), OpenGL plus `FlTextureGL` on Linux, a macOS "Metal" route, a native → Vulkan → software fallback chain, and zero-copy hardware decoding (d3d11va, vaapi/nvdec, videotoolbox).
**Researched:** 2026-10-26
**Confidence:** MEDIUM overall. Facts from the vendored tree, the build scripts and the upstream mpv headers are HIGH (read directly). Issue-tracker reports read in full through `gh` are MEDIUM (primary reports, often one reporter and one machine). Claims tagged "(LOW)" come only from search summaries and must be re-checked before they gate any design.

Phase labels used below:
- **P-A Backend extraction.** `RenderBackend` interface; the Vulkan and software backends move behind it with behaviour unchanged; pre-extraction baseline.
- **P-B Windows D3D11.** gpu-next on `pl_d3d11`, a DXGI handle passed to `GpuSurfaceTexture`, d3d11va zero-copy.
- **P-C Linux GL.** mpv OpenGL render API, `FlTextureGL`, vaapi (EGL dma-buf) and nvdec.
- **P-D macOS.** Route decision, then implementation.
- **P-E Fallback + CI.** auto chain, honest backend/reason reporting, real-plugin CI, UHD soak.

---

## Critical Pitfalls

### Pitfall 1: "Native D3D11" is read as "no fence needed". The consumer side is still ANGLE.

**What goes wrong:**
The team assumes that once mpv renders with D3D11 there is no cross-API hazard, and drops or shrinks the quarantine (`CompositorLatency() == 4`, ring 7). Flutter's engine still opens our DXGI handle through ANGLE's own `Renderer11` device (`eglCreatePbufferFromClientBuffer` + `eglBindTexImage`). There is still no fence and no keyed-mutex acquire. `release_callback` fires right after the bind, so it says nothing about when reading finished. Recycling a slot early gives tearing or a use-after-release. That is the same failure family as the unexplained D-05 soak abort.

**Why it happens:**
"No ANGLE/EGL in mpv_kit's chain" is a constraint on the **producer** side. ADR 0003 shows that the **consumer** side goes through ANGLE on every Windows surface type, with or without Impeller. Upstream's `render_d3d11.h` says outright that cross-device access is the embedder's job: "If another device uses the texture, the API user has to synchronize the access, for example with a keyed mutex". The keyed-mutex half does not apply to us, because ANGLE never acquires one.

**How to avoid:**
- Keep `D3D11_RESOURCE_MISC_SHARED` (legacy KMT handle). Never add `SHARED_KEYEDMUTEX` (the consumer never acquires it) or `SHARED_NTHANDLE` (ADR 0003 shows ANGLE uses `OpenSharedResource`).
- Producer side: after `mpv_render_context_render`, issue an `ID3D11Query` of type `D3D11_QUERY_EVENT` (or an `ID3D11Fence` where available) on the render thread. Publish the slot only after the GPU has finished. `Flush()` alone only submits; it does not mean the work completed.
- Consumer side: keep the quarantine for the D3D11 backend at the Vulkan-path value (4) until it has been **measured** with Impeller on and off (ADR 0003 Q4). Make `CompositorLatency()` a per-(platform × backend) value, not something inherited.

**Warning signs:**
Torn frames or one stale frame during fast seeking. Flutter's raster thread crashing in `flutter_windows.dll` during resize/dispose interleaving. The black-frame ratio rising only when Impeller is on.

**Phase to address:** P-B (design rule), verified in P-E (D-05 soak per backend).
**Sources:** `docs/adr/0003-windows-composition-path.md`; [mpv render_d3d11.h @ 4255130](https://github.com/mpv-player/mpv/blob/4255130de410e0cbdab694b951085409d466b704/include/mpv/render_d3d11.h); [flutter#191468](https://github.com/flutter/flutter/issues/191468)

---

### Pitfall 2: Writing a downstream D3D11 render ABI while upstream just merged one

**What goes wrong:**
The plan says "new downstream patch for a libmpv D3D11 render backend". Upstream mpv merged [PR #17764 "libmpv: add D3D11 render API backend"](https://github.com/mpv-player/mpv/pull/17764) on 2026-10-15 (commit `4255130de4`). It adds `MPV_RENDER_API_TYPE_D3D11 "d3d11"` and `MPV_RENDER_PARAM_D3D11_INIT_PARAMS = 21` / `MPV_RENDER_PARAM_D3D11_FBO = 22`, ships `render_d3d11.h`, and bumps the client API to 2.6. Our vendored tree (`v0.41.0-1115`) predates it: there is no `render_d3d11.h` and no `video/out/d3d11/libmpv_d3d11.c`. A downstream ABI with different names or numbers would collide on the next vendor advance, and every later rebase would carry two D3D11 paths.

**Why it happens:**
The milestone was scoped before the upstream merge. In addition, upstream's backend drives **vo_gpu** (`video/out/gpu/libmpv_gpu.c`, `ra_d3d11`), not gpu-next. That makes it easy to conclude "upstream doesn't do what we need" and fork the ABI.

**How to avoid:**
- First step of P-B: advance the vendor tree to include `4255130de4`, regenerate the patch set (the Phase 5 process; PATCH-DRIFT gate byte-equal), and adopt upstream's public ABI unchanged.
- Put gpu-next-on-D3D11 into the existing 0004-style patch as a second API branch inside `libmpv_init`, reusing upstream's device import (`mpv_d3d11_init_params.device`) and target (`mpv_d3d11_fbo.tex`). Only gpu-next-specific knobs get downstream params, in the existing `0x6d6b....` namespace.
- `renderer: gpu` on Windows D3D11 can then use upstream's vo_gpu path at no extra cost.
- Regenerate `tools/gen_options.dart`/`gen_catalog.dart` output and sync `packages/mpv_kit_video/src/include/mpv/` in the same commit as the vendor advance.

**Warning signs:**
A new `render_d3d11*.h` appearing under `native/patches/`. Param IDs 21/22 being reused with a different meaning. `MPV_CLIENT_API_VERSION` differing between vendored and plugin headers.

**Phase to address:** P-B (first plan); the drift gate lives in P-E.
**Sources:** [mpv PR #17764](https://github.com/mpv-player/mpv/pull/17764); `native/mpv/include/mpv/render_vk.h:57-72` (downstream namespace `0x6d6b0001..3`)

---

### Pitfall 3: gpu-next on D3D11 is not a copy of the Vulkan libmpv backend. hwdec requires `ra_d3d11`, and the build has D3D11 disabled everywhere.

**What goes wrong:**
The Vulkan gpu-next backend (patch 0004) gets `p->gpu = ra_pl_get(p->ra_ctx->ra)`. On D3D11 there is no `ra_pl`:
- mpv's gpu-next D3D11 path (`video/out/gpu_next/context.c:53-105`) builds `pl_d3d11` from an mpv `ra_d3d11` device and **requires a DXGI swapchain**. It fails with "Failed to receive required components" if either is missing.
- `hwdec_d3d11va` refuses anything that is not `ra_is_d3d11` (`hwdec_d3d11va.c:111`).
- vo_gpu_next maps hwdec frames with `ra_d3d11_get_raw_tex` + `pl_d3d11_wrap` (`vo_gpu_next.c:777-783`).

A naive port renders software-decoded video and silently loses d3d11va. Separately, the Windows build passes `-Dd3d11=disabled -Dshaderc=disabled -Dspirv-cross=disabled` to mpv and `-Dd3d11=disabled` to libplacebo, and glslang is built with `ENABLE_HLSL=OFF`. mpv's meson **requires shaderc and spirv-cross** for the `d3d11` feature (`meson.build:1079-1082`). libplacebo's D3D11 backend needs SPIRV-Cross (`spirv-cross-c-shared`, a shared library by default) plus a SPIR-V compiler, and at run time it needs `d3dcompiler_47.dll`.

**Why it happens:**
The Vulkan backend was written against `ra_pl`. The D3D11 stack in mpv is older and centred on `ra_d3d11`. The build scripts deliberately stripped every D3D11 dependency for bundle size.

**How to avoid:**
- Construct `ra_d3d11` from the host device (upstream `libmpv_d3d11.c` does exactly this) and create `pl_d3d11` on the **same** `ID3D11Device` (`pl_d3d11_params.device`), with no swapchain. Patch `d3d11_pl_init` or add a swapchain-less variant.
- Build changes are a separate, reviewable plan:
  - add shaderc **or** patch mpv's meson to accept glslang;
  - link SPIRV-Cross statically (patch libplacebo's `spirv-cross-c-shared` lookup), or add the DLL to MANIFEST, the ABI audit and the license list;
  - keep `-Degl-angle=disabled`, so `hwdec_d3d11egl` (ANGLE) is never compiled.
- Extend `tools/rea_abi_audit/pe_audit.py` so that `libEGL.dll`/`libGLESv2.dll` imports in `libmpv-2.dll` or the plugin DLL fail CI. That makes the "no ANGLE" rule machine-checked.

**Warning signs:**
`hwdec-current` stays `no` or becomes `d3d11va-copy` under the D3D11 backend. The log contains "d3d11 libplacebo context" errors. The configure summary shows `d3d11: false`. The bundle gains an unlisted `spirv-cross-c-shared.dll`.

**Phase to address:** P-B (build plan before the render plan).
**Sources:** `native/mpv/video/out/gpu_next/context.c`, `video/out/d3d11/hwdec_d3d11va.c`, `video/out/vo_gpu_next.c:777`, `native/mpv/meson.build:1052-1087`, `native/build/build.sh:41-43`, `native/build/deps.sh:193-255`; [mpv discussion #14389](https://github.com/mpv-player/mpv/discussions/14389) (LOW); [libplacebo d3d11 initial commit](https://github.com/rossy/libplacebo/commit/8c24d112e52c3a6e71e32a606a1b106423cc42e2) (LOW)

---

### Pitfall 4: The default `hwdec` list silently defeats zero-copy on the new backends

**What goes wrong:**
`Player()` sets `hwdec=vulkan,d3d11va-copy,auto-safe` (`player.dart:86`). mpv tries the entries in order. Under the D3D11 backend, `vulkan` fails (there is no Vulkan device) and **`d3d11va-copy` succeeds**. That is a GPU-to-RAM readback followed by a re-upload, the opposite of zero-copy. The UHD gate still passes on a fast PC, so nobody notices until 8K commit-memory pressure returns (CONCERNS.md, 8K exhaustion). Linux has a similar effect: `auto-safe` reaches vaapi only after `vulkan`.

**Why it happens:**
The list was tuned for the Vulkan-only renderer. Changing `Player` defaults looks like an API change, so it gets left alone.

**How to avoid:**
- Treat hwdec selection as part of the backend contract. The value can be `vulkan,d3d11va,d3d11va-copy,auto-safe`: `d3d11va` fails cleanly under the Vulkan backend (no `ra_d3d11`), so the Vulkan path is unchanged. Alternatively, the controller can set an interop-matched `hwdec` when the user has not overridden it.
- Make `hwdec-current` plus a "zero-copy: yes/no" fact part of every soak assertion. Do not rely on "it played".
- 8K on D3D11: `d3d11va-zero-copy=yes` is needed for gpu-next to keep up ([mpv#17626](https://github.com/mpv-player/mpv/issues/17626)). The default copies into one texture on the GPU (`hwdec_d3d11va.c:200-233`): no CPU cost, but extra VRAM bandwidth.
- Do not confuse the three d3d11 modes. `d3d11va-copy` is a readback. `d3d11va` with the default `d3d11va-zero-copy=no` is a GPU-side copy. `d3d11va-zero-copy=yes` samples the decoder's array slices directly.

**Warning signs:**
`hwdec-current=d3d11va-copy` (or `vaapi-copy`) during the soak. Commit charge rising with resolution while VRAM stays flat.

**Phase to address:** P-B and P-C (per-backend hwdec contract); asserted in P-E.
**Sources:** `packages/mpv_kit/lib/src/player/player.dart:86`, `native/mpv/video/out/d3d11/hwdec_d3d11va.c`; [mpv#17626](https://github.com/mpv-player/mpv/issues/17626)

---

### Pitfall 5: Linux GL. Context ownership, share groups and the Mesa EGLImage black-frame bug

**What goes wrong:**
Four separate failure modes, all seen in media_kit's Linux GL path.
1. Since Flutter 3.38, Flutter's EGL context is current only on the **raster** thread. Code that calls `eglGetCurrentDisplay()/eglGetCurrentContext()` on the platform thread gets `EGL_NO_DISPLAY` and silently falls back to software. On some hosts this depends on timing ([media-kit#1404](https://github.com/media-kit/media-kit/issues/1404), [#1321](https://github.com/media-kit/media-kit/issues/1321)).
2. A context created on the platform thread is not in the raster context's share group, so a GL texture name returned from `populate` points at nothing ([media-kit#1463 root-cause comment](https://github.com/media-kit/media-kit/issues/1463)).
3. On Mesa (confirmed Intel Xe2, Mesa 25), **creating an `EGLImageKHR` from the texture mpv renders into makes mpv's rendering into it vanish**. The result is uniform black with no GL error and no mpv error, while hwdec and decoding look healthy. The verified fix is to render into a private texture and `glBlitFramebuffer` into a separate export texture that backs the EGLImage ([media-kit#1463](https://github.com/media-kit/media-kit/issues/1463)).
4. Cross-context sampling without proper synchronization tears ([media-kit#1463](https://github.com/media-kit/media-kit/issues/1463), [#1345](https://github.com/media-kit/media-kit/issues/1345)).

**Why it happens:**
`FlTextureGL::populate` runs on the raster thread with Flutter's context current and returns only a texture name. There is no fence and no per-frame release callback ([flutter#190044](https://github.com/flutter/flutter/issues/190044)).

**How to avoid:**
- Get the EGLDisplay the way `gl_interop.cc` already does (`FlutterEglDisplay()` via GDK and `eglGetPlatformDisplayEXT`). Never use the current-context query.
- mpv gets its **own** EGL context on our render thread.
- Hand frames over through EGLImage export textures that are **never** mpv's render target (render, then blit).
- Synchronize with an EGL fence: `eglCreateSyncKHR` after the blit, `eglWaitSyncKHR` inside `populate`. Use `glFinish` only as the fallback, because it stalls the render thread.
- Keep a ring plus quarantine. With no release callback, recycling is necessarily heuristic, exactly as today.
- The existing Vulkan→GL memory-object path proves the share-group question is already solved there. Reuse its `populate` structure.

**Warning signs:**
"S/W rendering" on Flutter ≥3.38. Black video with `hwdec-current=vaapi` and zero dropped frames. A frame that is correct in `screenshot-to-file` but black on screen.

**Phase to address:** P-C.
**Sources:** links above; `packages/mpv_kit_video/linux/gl_interop.cc:37-56`

---

### Pitfall 6: Calling `mpv_render_*` from the wrong thread is undefined behaviour under OpenGL, and the current code does it

**What goes wrong:**
`render.h` (Threading) says that with the OpenGL backend, for **all** `mpv_render_*` functions, mpv's GL context "must be current in the calling thread, and it must be the same OpenGL context", and that only one `mpv_render_*` call may run at a time. Today `VideoRenderer::AcquireFront` calls `mpv_render_context_report_swap` from the **compositor/raster** thread (`video_renderer.cc:254, 309`) while the render thread calls `update`/`render`. Under Vulkan this works because libmpv's internal locking happens to cover it (CONCERNS.md, Fragile Areas). Under GL it is documented undefined behaviour: Flutter's context is current, not ours. `mpv_render_context_free` has the same rule. Freeing without mpv's context current, or deleting GL objects with no context current, aborts in libepoxy ([media-kit#1287](https://github.com/media-kit/media-kit/issues/1287): `epoxy_get_proc_address: Couldn't find current GLX or EGL context`).

**Why it happens:**
The renderer's threading was designed for Vulkan, which has no implicit per-thread context.

**How to avoid:**
- During P-A, move `report_swap` into the backend interface as a **queued event that the render thread drains** (count of swaps since the last render). This is behaviour-preserving for Vulkan and mandatory for GL.
- Make `Destroy()` run on the render thread with the backend's context current, before the thread exits: unregister the update callback, then `mpv_render_context_free`, then delete GL objects, then destroy the context.
- Never set `MPV_RENDER_PARAM_ADVANCED_CONTROL` on GL unless the render thread provably never waits on a non-render mpv call. render.h: "a real deadlock will freeze the mpv core thread forever". Today's design does not need it.
- If anything ever renders on the raster thread, pass `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME=0`. The default of 1 blocks the raster thread for a full video frame and makes the whole Flutter scene judder ([media-kit#1439](https://github.com/media-kit/media-kit/issues/1439); [mpv#4237](https://github.com/mpv-player/mpv/issues/4237)).

**Warning signs:**
Crashes inside the GL driver during resize. `mpv_render_context_render() not being called or stuck` in the log. Aborts in libepoxy at dispose or exit.

**Phase to address:** P-A (interface shape), enforced in P-C.
**Sources:** `native/mpv/include/mpv/render.h:55-123, 245-287`; `packages/mpv_kit_video/src/video_renderer.cc`; issues above; [mpv#8509](https://github.com/mpv-player/mpv/issues/8509) (render_context_free crash caused by handling events on another thread)

---

### Pitfall 7: The libmpv OpenGL render API is vo_gpu, not gpu-next. The `renderer` enum quietly changes meaning.

**What goes wrong:**
Upstream libmpv exposes only the legacy `gl_video` renderer over OpenGL ([mpv#10810](https://github.com/mpv-player/mpv/issues/10810); the gpu-next OpenGL PRs [#16818](https://github.com/mpv-player/mpv/pull/16818) and [#18607](https://github.com/mpv-player/mpv/pull/18607) are unmerged, and maintainers are asking for a real design). Our 0004 patch adds gpu-next for Vulkan only (`vo_gpu_next.c:3132`). On the Linux GL backend, `MpvVideoRenderer.gpuNext` (doc: "libplacebo's renderer… best HDR tone mapping") would therefore be served by vo_gpu, a silent feature downgrade: different tone mapping, different options, no `gpu-shader-cache-dir` semantics. The GLES legacy renderer also has driver-specific quality bugs, for example the `mediump sampler2D` colour shift on NVIDIA ([media-kit#1438](https://github.com/media-kit/media-kit/issues/1438)), and black hwdec video with subtitles on nvidia-open ([mpv#18259](https://github.com/mpv-player/mpv/issues/18259)).

**Why it happens:**
"Use the mpv OpenGL render API" sounds like a drop-in replacement. The renderer × backend matrix is not written down anywhere.

**How to avoid:**
- Write the renderer × backend matrix into an ADR before P-C. One honest option: `gpuNext` on Linux auto keeps Vulkan as primary, and GL serves `gpu`/fallback. The other is to extend 0004 with a `pl_opengl` branch, which is downstream work on code upstream is redesigning.
- Prefer a desktop GL (`EGL_OPENGL_API`) context over GLES where the driver offers it.
- Whatever is chosen, the active renderer (patch 0004's renderer report) must say `gpu` when vo_gpu is serving.

**Warning signs:**
The HUD says gpu-next while `vo`/the renderer report says gpu. HDR clips look different between the Linux GL and Vulkan backends. User-shader colour shifts on NVIDIA only.

**Phase to address:** P-C (decision), P-E (reporting).
**Sources:** issues above; `native/mpv/video/out/vo_gpu_next.c:3100-3182`, `vo_libmpv.c:119-126`

---

### Pitfall 8: Linux VA-API zero-copy needs things our bundle does not build or pass

**What goes wrong:**
- The Linux mpv build has `-Dgl=disabled -Degl=disabled -Dx11=disabled -Dwayland=disabled`, and libplacebo has `-Dopengl=disabled`, so the GL render API and `dmabuf_interop_gl` do not exist in the bundle at all.
- With X11/Wayland compiled out, `hwdec_vaapi` can only open a VA display through **DRM**, and only if the host passes `MPV_RENDER_PARAM_DRM_DISPLAY_V2` with a valid `render_fd` (`hwdec_vaapi.c:63-104`). Without it, vaapi silently is not used.
- `dmabuf_interop_gl` reads `eglGetCurrentDisplay()` and needs `EGL_EXT_image_dma_buf_import` plus `GL_OES_EGL_image` (GLES) or `GL_EXT_EGL_image_storage` (desktop GL). Modifiers are used only when `EGL_EXT_image_dma_buf_import_modifiers` is present (`dmabuf_interop_gl.c:346-363`). Tiled or compressed surfaces imported without modifiers display garbage or black.
- The render node must be the **same GPU** as the EGL display. On hybrid laptops it often is not.
- 10-bit (P010) dma-buf import has a history of failing where `vaapi-copy` works ([mpv#8668](https://github.com/mpv-player/mpv/issues/8668) (LOW), [mpv#9657](https://github.com/mpv-player/mpv/issues/9657)).

**Why it happens:**
The bundle was minimized for the Vulkan-only renderer. VA-API interop depends on how the display was opened, and that host contract is not documented in the render API.

**How to avoid:**
- Separate build plan: `-Dgl=enabled -Degl=enabled`, libplacebo `-Dopengl=enabled`, verify `HAVE_GL`/`HAVE_EGL`/`HAVE_VAAPI_DRM` in `config.h` (extend the existing `for feature in VULKAN LIBPLACEBO` check), and keep `package.sh`'s system allowlist (libEGL/libGL/libva already allowed).
- In the plugin, derive the render node from the EGL device: `EGL_EXT_device_query` + `EGL_DRM_RENDER_NODE_FILE_EXT`. Pass it as `MPV_RENDER_PARAM_DRM_DISPLAY_V2` and log mismatches.
- Include an HEVC Main10 clip in the hwdec matrix. Accept `vaapi-copy` as an explicit, reported fallback, never a silent one.

**Warning signs:**
"Trying to open a drm VA display" followed by software decode. `hwdec-current=no` with vainfo healthy. Green/garbled frames on AMD or Intel compressed modifiers.

**Phase to address:** P-C.
**Sources:** `native/build/build.sh:25-31, 70-79`, `native/build/deps.sh:255`, `native/mpv/video/out/hwdec/hwdec_vaapi.c`, `dmabuf_interop_gl.c`; [mpv#10424](https://github.com/mpv-player/mpv/issues/10424); [mpv#11400](https://github.com/mpv-player/mpv/issues/11400) (LOW)

---

### Pitfall 9: NVDEC is not in the bundle, and CUDA–GL interop is context-fragile

**What goes wrong:**
FFmpeg's configure in `ffmpeg.sh` does not include nv-codec-headers, so `ffnvcodec`/nvdec are autodetected **off** on every target, and mpv's `cuda-hwaccel`/`cuda-interop` are off as well. When enabled, CUDA GL interop calls `cuGLGetDevices` against **whatever GL context is current at `mpv_render_context_create`**. It fails with `CUDA_ERROR_INVALID_GRAPHICS_CONTEXT` if that context is on Mesa/Intel instead of NVIDIA, or if no context is current ([mpv#8215](https://github.com/mpv-player/mpv/issues/8215) (LOW)). Multiple players can also hit `CUDA_ERROR_DEVICE_UNAVAILABLE` ([mpv#16397](https://github.com/mpv-player/mpv/issues/16397)).

**Why it happens:**
nv-codec-headers is an extra build dependency (MIT, header-only, loaded at run time with dlopen), and nvdec is not nonfree. Nobody added it because the Vulkan path used Vulkan Video and `auto-safe`.

**How to avoid:**
- Add nv-codec-headers explicitly: `--enable-ffnvcodec --enable-nvdec` (Windows and Linux), and set mpv's `-Dcuda-hwaccel=enabled -Dcuda-interop=enabled` explicitly. Keep the LGPL gate: never `--enable-cuda-nvcc`/`libnpp`, which are nonfree.
- Create the render context with mpv's EGL context current on the render thread, and check `GL_VENDOR` before claiming nvdec.
- Treat `nvdec-copy` as the reported fallback.

**Warning signs:**
"CUDA hwdec only works with OpenGL or Vulkan backends". The line before it holds the real error.

**Phase to address:** P-C (and P-B if nvdec is wanted on Windows; d3d11va already covers NVIDIA there).
**Sources:** `native/build/ffmpeg.sh:40-90`; issues above; [edde746/mpv-build#4](https://github.com/edde746/mpv-build/issues/4) (LOW)

---

### Pitfall 10: Public API freeze vs honest backend reporting. `MpvVideoBackend` has only `{vulkan, software}`.

**What goes wrong:**
`MpvVideoBackend` is a public enum with two values (`video_controller.dart:13`). `create` treats any other `backend` string as a protocol break and throws `PlatformException(render_init)` (`video_controller.dart:181-196`; STAB-04 / Phase 2). Adding `d3d11`/`opengl`/`metal` values is a public API change, and in Dart 3 it is **source-breaking** for users with exhaustive `switch`es. The reflection-based API-freeze test (Phase 1) will catch it. The tempting workarounds are worse: report `vulkan` for a D3D11 path (dishonest), or loosen validation (reopens STAB-04).

**Why it happens:**
The backend vocabulary was designed when Vulkan was the only GPU path. The milestone says "via the existing `MpvVideoRenderer` enum, no new public API", but the *reporting* side was never planned.

**How to avoid:**
- Decide in an ADR at the start of P-A, with the user. Option (a): keep the enum, define `MpvVideoBackend.vulkan` as "GPU zero-copy path", and carry the concrete backend in `reason`/the HUD/the `mpv_kit_video: <backend> (<reason>)` line. That needs no API change but weakens the name. Option (b): get explicit approval for an additive enum value and document the exhaustive-switch break.
- Either way, the wire protocol keeps strict validation: the plugin and Dart agree on an **enumerated** set, and anything else stays a `render_init` error.

**Warning signs:**
A PR that touches `backendName != 'vulkan' && backendName != 'software'`. The API-freeze test going red. HUD backend text that disagrees with the native log.

**Phase to address:** P-A (decision before any new backend reports itself).
**Sources:** `packages/mpv_kit_video/lib/src/video_controller.dart:12-46, 170-205`; `.planning/PROJECT.md` (API freeze, STAB-04)

---

### Pitfall 11: The refactor erases the only evidence for the unexplained D-05 abort

**What goes wrong:**
P-A moves the ring, quarantine, backoff and teardown behind `RenderBackend`. D-05 (a soak abort seen once, never reproduced or explained; the harness gate itself was defective) is still open. If the extraction lands first, any later soak failure cannot be attributed: was it a pre-existing race, or the refactor? The milestone then repeats v2.0's "inconclusive" close-out.

**Why it happens:**
Refactor-first feels like the right order. The harness defect (no `setSize` before the part-1 gate) is easy to forget because it is recorded only in ADR 0003.

**How to avoid:**
- First plan of P-A: fix the harness (ADR 0003 precondition), then run D-05 and the 100-round resize/dispose plus 100 create/dispose soaks on the **current** Vulkan path, Impeller on and off, recording the engine renderer line. That is the baseline.
- After every extraction step, rerun the same harness with identical parameters. Extraction plans are pure moves: no constant changes (ring 5/7, quarantine 2/4, 50 ms present timeout, 100 ms→5 s backoff) and no reason-string changes. Phase 3 tests assert reasons.
- Fixes found along the way (the `call_once` failure caching, `D3D11CreateDevice` HRESULT, raw `Instance*`) go in **separate** commits with their own tests, so each change can be rolled back alone.

**Warning signs:**
An extraction diff that also changes a number. A soak that goes green and red with no code change (flaky means not attributable). Baseline numbers without a renderer line (ADR 0003 forbids that).

**Phase to address:** P-A (gate before the first move); P-E reuses the harness.
**Sources:** `docs/adr/0003-windows-composition-path.md` (D-05, harness defect); `.planning/codebase/CONCERNS.md` (Fragile Areas)

---

### Pitfall 12: Texture unregistration is asynchronous on every platform. Freeing on "unregister returned" crashes the raster thread.

**What goes wrong:**
- On Windows, `TextureRegistrar::UnregisterTexture` is asynchronous. Plugins that destroy their D3D objects right after calling it crash on the raster thread inside the descriptor callback: [fvp#397](https://github.com/wang-bin/fvp/issues/397) (null `ID3D11DeviceContext` in `CopyResource`) and [flutter_inappwebview#2896](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2896) (crash in `ExternalTextureD3d::CreateOrUpdateTexture`).
- On Linux, `fl_texture_registrar_unregister_texture` returns before the raster-side removal, and there is no completion signal ([flutter#190044 comment](https://github.com/flutter/flutter/issues/190044)). mpv_kit's 1 s timer heuristic exists for this reason.
- On macOS, the engine keeps the last `CVPixelBuffer` and wraps it through `CVMetalTextureCacheCreateTextureFromImage` while releasing the `CVMetalTextureRef` early ([flutter#157379](https://github.com/flutter/flutter/issues/157379)).

A new backend that "simplifies" teardown reintroduces all three.

**Why it happens:**
Each backend gets its own release code, written fresh.

**How to avoid:**
Put a single deferred-release rule in the `RenderBackend` contract. Images are freed only after (1) the platform's unregister completion (Windows callback overload; Linux timer and orphan drain; macOS `dead` flag), **and** (2) the quarantine count has elapsed. The rule belongs to the shared lifecycle code, not to each backend. Also drain Linux orphans on plugin dispose (CONCERNS gap).

**Warning signs:**
A crash with `flutter_windows.dll` or the plugin at the top of the raster-thread stack right after dispose. Leaked GL objects after many create/dispose cycles on Linux.

**Phase to address:** P-A (contract); each platform phase implements it.
**Sources:** issues above; `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc:29-37, 360-390`; `windows/mpv_kit_video_plugin.cpp` (deferred deletion)

---

### Pitfall 13: macOS "write a Metal backend" is a multi-month libplacebo project. The other routes have known crash histories.

**What goes wrong:**
libplacebo has no Metal `pl_gpu`, and its backends are Vulkan, OpenGL and D3D11 ([libplacebo README](https://github.com/haasn/libplacebo)). A "self-written Metal backend" therefore means writing a new libplacebo GPU backend or a Metal `ra`. The OpenGL plus IOSurface route (IINA's historical path) runs on Apple's deprecated GL-over-Metal layer and only gets vo_gpu (Pitfall 7). mpv's macOS GL has resize crashes in the GL driver ([mpv#10406](https://github.com/mpv-player/mpv/issues/10406)) and resize lag ([mpv#14173](https://github.com/mpv-player/mpv/issues/14173)). media_kit's macOS output freezes during window resize ([media-kit#1176](https://github.com/media-kit/media-kit/issues/1176)). The existing MoltenVK→IOSurface route **is** already Metal underneath.

**Why it happens:**
"Platform-native graphics" is read literally.

**How to avoid:**
- Keep MoltenVK→IOSurface as the macOS primary and spend P-D on its known MoltenVK pitfalls instead:
  - biplanar 4:2:0 IOSurfaces imported with the wrong plane handling or as NV12, relevant to videotoolbox P010 zero-copy ([streamlib#2488](https://github.com/tatolab/streamlib/issues/2488) (LOW); [displayxr#2190](https://github.com/DisplayXR/displayxr-runtime/issues/2190) (LOW));
  - the CVMetalTexture lifetime issue (Pitfall 12);
  - Flutter accepting only `32BGRA`/`420v`/`420f` CVPixelBuffers ([flutter#147242](https://github.com/flutter/flutter/issues/147242) (LOW)).
- Record the route decision as an ADR with the cost comparison the milestone asks for. That makes P-D mostly a decision plus a hardening phase, not a new backend.

**Warning signs:**
The P-D plan contains "pl_gpu" or "Metal ra". 10-bit HEVC is black or green only with videotoolbox zero-copy ([media-kit#717](https://github.com/media-kit/media-kit/issues/717)).

**Phase to address:** P-D.
**Sources:** links above; `packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm`, `metal_interop.mm`

---

### Pitfall 14: "Verified on CI runners" cannot cover hardware decoding on GitHub-hosted runners

**What goes wrong:**
- `windows-latest` has no GPU. D3D11 is **WARP** ("Microsoft Basic Render Driver") with no video decoder, so d3d11va cannot run. WARP also crashes when several render tests run in parallel ([egui#8772](https://github.com/emilk/egui/issues/8772) (LOW)) and is several times slower.
- Ubuntu runners are llvmpipe with no VA-API.
- macOS arm64 runners are paravirtualized M1 VMs. VideoToolbox exists, but concurrent sessions fail and chroma differs from software decode ([zvidlib PR #566](https://github.com/lsegal/zvidlib/pull/566) (LOW); [GitHub runner docs](https://docs.github.com/en/actions/reference/github-hosted-runners-reference)).

The temptation is a green CI that skipped every hwdec assertion (Phase 6 already fought silent skips), or claiming "verified" from the developer's RTX 4060 only.

**Why it happens:**
The requirement "real plugin behaviour verified on CI runners" and "hardware decode zero-copy" conflict on hosted infrastructure.

**How to avoid:**
- Split the requirement explicitly. **Render path**: verified on hosted runners for every backend (D3D11 on WARP with `pl_d3d11 allow_software`; GL on llvmpipe EGL surfaceless or Xvfb; MoltenVK on the arm64 VM), with `hwdec=no` plus a non-black pixel probe.
- **Hardware zero-copy**: verified on a self-hosted GPU runner (Windows RTX 4060 first). It needs an `MPV_KIT_REQUIRE_HWDEC`-style loud-fail guard modelled on `MPV_KIT_REQUIRE_LIBMPV`, and the evidence must state which tier ran.
- Serialize D3D tests when the adapter is WARP.

**Warning signs:**
A job that is green but has `hwdec-current` absent from the logs. Hosted-runner logs claiming d3d11va.

**Phase to address:** P-E (CI design), with requirement wording fixed during requirements definition.
**Sources:** links above; `.planning/PROJECT.md` (Phase 6 guard, Verification constraint)

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Copy Windows' `CompositorLatency()==4` to the D3D11 and GL backends | No measurement needed | Unmeasured safety margin. Hides use-after-release or adds 4 frames of latency (132 ms at 30 fps) | Only as the initial value, with a tracked measurement task (ADR 0003 Q4) |
| `glFinish()` instead of EGL fences on Linux | Simple, fixes tearing ([media-kit#1463](https://github.com/media-kit/media-kit/issues/1463)) | Stalls the render thread every frame; at 4K60 eats the frame budget | Fallback when `EGL_KHR_fence_sync`/`wait_sync` is missing |
| Downstream D3D11 ABI instead of upstream's `render_d3d11.h` | Avoids a vendor advance now | Permanent dual ABI and rebase conflicts with `4255130de4` | Never |
| Loosening `backend` validation in Dart to accept "anything GPU" | Unblocks new backends | Reopens STAB-04 (garbage backends silently accepted) | Never |
| `d3d11va-copy`/`vaapi-copy` as the silent default | Always works | Not zero-copy; 8K commit-memory pressure returns | As a *reported* fallback only |
| Shipping `spirv-cross-c-shared.dll` unlisted | Faster D3D11 build | Bundle/MANIFEST/ABI audit drift; supply-chain gap | Never (static link or list it) |
| One extraction commit that also "fixes" constants | Fewer commits | D-05 baseline becomes unattributable | Never during P-A |
| GLES2 context for mpv on Linux (as media_kit does) | Maximum compatibility | `glBlitFramebuffer` is ES3; mediump sampler artifacts; vo_gpu features limited | Only if no desktop GL / ES3 context is available |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Flutter Windows `GpuSurfaceTexture` | Treating `release_callback` as "consumer done reading" | It fires right after the ANGLE bind (ADR 0003). Keep quarantine and producer completion queries |
| Flutter Windows `GpuSurfaceTexture` | Using `kFlutterDesktopGpuSurfaceTypeD3d11Texture2D` with our own device's texture pointer | Fails to bind across devices ([flutter#121046](https://github.com/flutter/flutter/issues/121046)). Use `DxgiSharedHandle` + legacy `MISC_SHARED` |
| Flutter Windows resize | Recreating shared textures (new handles) on every drag step | The engine side leaks GPU memory when the handle changes ([flutter#154716](https://github.com/flutter/flutter/issues/154716)). Debounce, grow-only during interaction, and track dedicated GPU memory in the soak (a D-05 suspect) |
| Flutter Windows snapshot / route transition | Assuming Impeller paths are equivalent | Snapshotting a GPU-surface texture crashed in `ResolveTextureSkia` under Impeller ([flutter#190774](https://github.com/flutter/flutter/issues/190774), closed as completed 2026-08-17; confirm the pinned Flutter contains the fix). Pin the Flutter version and include a route push/pop in the soak |
| Flutter Windows adapter | Creating our D3D11 device on the default adapter | Create on Flutter's adapter LUID (the current code does this). On hybrid laptops Flutter may itself sit on the "wrong" GPU ([flutter#190200](https://github.com/flutter/flutter/issues/190200) (LOW)) |
| Flutter Windows multi-engine | Static plugin singletons or a static registrar | A second engine steals routing and hangs `create` ([media-kit#1383](https://github.com/media-kit/media-kit/issues/1383); [three_js#144](https://github.com/Knightro63/three_js/issues/144) (LOW)). Keep per-registrar state |
| libmpv D3D11 (upstream ABI) | Creating the device with `D3D11_CREATE_DEVICE_SINGLETHREADED` | That disables d3d11va zero-copy; only `-copy` works (render_d3d11.h). mpv sets multithread protection itself (`hwdec_d3d11va.c:128-137`) |
| libmpv D3D11 (upstream ABI) | Using the immediate context from the raster thread (fvp-style `CopyResource` in the callback) | mpv does not restore D3D11 state, and other threads must not use the immediate context during `mpv_render_*`. Keep all D3D11 calls on the render thread; the descriptor callback only returns a cached descriptor |
| libmpv D3D11 target | sRGB, array, mipmapped or MSAA target; `UAV` on a shared BGRA texture | Plain `B8G8R8A8_UNORM`, `BIND_RENDER_TARGET|SHADER_RESOURCE`, `USAGE_DEFAULT`, check every HRESULT ([rive-flutter#620](https://github.com/rive-app/rive-flutter/issues/620) (LOW)) |
| libplacebo `pl_d3d11` | Accepting the default `min_feature_level` 9_1 | Set `min_feature_level = D3D_FEATURE_LEVEL_10_0` (libplacebo header recommendation). FL 9_x has no texelFetch, `gl_FragCoord` or high-bit FBOs. Flutter 3.47 itself is broken on FL 9_3 ([flutter#191978](https://github.com/flutter/flutter/issues/191978)) |
| libplacebo `pl_d3d11` | Assuming feature parity with Vulkan | FBO texture creation failures on Intel ([mpv#15327](https://github.com/mpv-player/mpv/issues/15327)); error diffusion compute shader fails ([libplacebo#228](https://code.videolan.org/videolan/libplacebo/-/issues/228) (LOW)); AV1 film grain + HDR compute shader rejected by D3DCompile ([jellium-desktop#691](https://github.com/andrewrabert/jellium-desktop/issues/691) (LOW)). Run the existing gpu-next regression on D3D11 and record per-backend deltas |
| libplacebo output format | Letting auto-format pick `rgb10_a2` | Flutter consumes only 8-bit (Impeller `GL_RGBA8` gate → silent black, ADR 0003). We own the target, so force BGRA8 ([mpv#14242](https://github.com/mpv-player/mpv/issues/14242)) |
| `FlTextureGL` | Leaving GL state modified in `populate` | Skia/Impeller assume untouched state ([flutter#179322](https://github.com/flutter/flutter/issues/179322), [PR #178697](https://github.com/flutter/flutter/pull/178697)). Bind, return, restore nothing else; no GL calls beyond the minimum |
| `FlTextureGL` | Calling `mark_texture_frame_available` from inside `populate` | Crashed on Flutter 3.22 ([flutter#150668](https://github.com/flutter/flutter/issues/150668)). Mark only from the render thread |
| Linux Mesa | Multi-context sharing with `mesa_glthread` | Null deref on the glthread worker at start or exit ([flutter#189379](https://github.com/flutter/flutter/issues/189379)). Add an exit/start loop to the Linux soak |
| macOS `copyPixelBuffer` | Returning NULL after a non-NULL frame | Behaviour differs between engine texture classes ([flutter#159162](https://github.com/flutter/flutter/issues/159162)). Always return the last good frame |
| mpv `report_swap` | Never calling it (media_kit) | `vsync-ratio` stays null and display-sync modes run blind ([media-kit#1425](https://github.com/media-kit/media-kit/issues/1425)). Keep it, but marshal it to the render thread (Pitfall 6) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| D3DCompile on first frame / every resize | Multi-hundred-ms stall when playback starts or the window resizes on D3D11 | Generalize patch 0003's shader cache to `pl_cache` for D3D11/GL; prewarm once per process | Every cold start; worse with many scalers or HDR peak detection |
| `hdr-compute-peak` + AV1 10-bit at 8K on gpu-next D3D11 | Render time ~50 ms vs ~17 ms on vo_gpu ([mpv#17626](https://github.com/mpv-player/mpv/issues/17626)) | `d3d11va-zero-copy=yes`; frame-size-derived options (UHD-01 style) | 8K HDR |
| Immediate-context contention (decode + render on one multithread-protected device) | GPU idle gaps, decode stalls at 4K/8K | Keep the render thread the only non-decoder user; never add raster-thread D3D work | ≥4K60 or multiple players |
| GL blit plus fence per frame | Extra full-frame copy | Acceptable (sub-ms at 1080p on Xe2, [media-kit#1463](https://github.com/media-kit/media-kit/issues/1463)); measure at 4K | 8K on iGPUs |
| Ring size per backend | VRAM 5-7 full frames per controller (8K ≈ 930 MB) | Do not grow the ring for new backends without measurement; D3D11 max 2D texture is 8192 at FL 10_x vs 16384 at FL 11+ (from memory, verify against MS Resource Limits) | 8K, multiple controllers |
| Resize reallocation waits under the renderer mutex | Compositor freeze during drag (CONCERNS) | Keep the extraction behaviour-equal first, then fix as a separate measured change | Hung GPU / TDR |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Loading `d3dcompiler_47.dll` / `nvcuda.dll` / `libcuda.so.1` by bare name | DLL planting before any media is opened (same class as the CONCERNS library-loading item) | Load from System32 only (`LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_SYSTEM32)`); document it |
| Enabling new FFmpeg hwaccels without the license gate | GPL/nonfree contamination (`cuda-nvcc`, `libnpp`) | Keep the `CONFIG_GPL/NONFREE/VERSION3 == 0` gate; add a nonfree-flag deny-list in `ffmpeg.sh` |
| Bundling ANGLE by accident (media_kit ships loose `libEGL.dll`/`libGLESv2.dll`, [flutter#190200](https://github.com/flutter/flutter/issues/190200) (LOW)) | Violates the user's no-ANGLE rule; confusing runtime | PE import audit fails on `libEGL`/`libGLESv2`; `-Degl-angle=disabled` |
| Trusting a host-supplied DRM fd / EGL device | Wrong-GPU interop, or opening an attacker-controlled path | Derive the render node from the EGL device query, never from environment variables |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent fallback D3D11 → Vulkan → software | "Why is my CPU at 40%?" with no explanation | Every fallback emits the existing `softwareFallback`-style event plus a reason; the HUD shows backend × renderer × hwdec × zero-copy |
| Black texture instead of an error on a format/feature mismatch (Impeller `GL_RGBA8` gate, Mesa EGLImage bug) | Audio plays, picture is black, no error | A non-black probe in debug builds; surface a `renderError` when the first frames read back black while `estimated-vf-fps > 0` |
| Different look between backends (vo_gpu on GL vs gpu-next on Vulkan) | HDR clips look different per machine | Report the actual renderer; document the matrix |

## "Looks Done But Isn't" Checklist

- [ ] **D3D11 backend:** `hwdec-current` is `d3d11va` (not `-copy`) on the RTX 4060 runner, and the PE audit shows no `libEGL`/`libGLESv2` imports.
- [ ] **D3D11 backend:** producer completion query in place; quarantine value measured with Impeller on and off, with the engine renderer line recorded.
- [ ] **D3D11 backend:** survives a 100-round resize/dispose + route push/pop soak with flat dedicated GPU memory ([flutter#154716](https://github.com/flutter/flutter/issues/154716)).
- [ ] **Linux GL backend:** works on Flutter ≥3.38 without relying on a current context on the platform thread; never uses the EGLImage source as mpv's render target.
- [ ] **Linux GL backend:** `report_swap` and `render_context_free` run on the render thread with mpv's context current (no epoxy abort across 1000 create/dispose cycles).
- [ ] **Linux vaapi:** `MPV_RENDER_PARAM_DRM_DISPLAY_V2` passed with a render node matching the EGL device; HEVC Main10 tested.
- [ ] **nvdec:** nv-codec-headers present and the license gate still green.
- [ ] **macOS:** route ADR written; P010 videotoolbox zero-copy shows no green/black frames.
- [ ] **Fallback:** each step of native → Vulkan → software is forced once in CI (`MPV_KIT_VIDEO_RENDERER` / fault injection) and yields an event plus reason.
- [ ] **Vulkan path unchanged:** `render_vk_smoke` (gpu-next and gpu), Phase 3 reason tests, Phase 2 atomic-create tests and the 4K 30-min gate are all green after P-A, with numbers compared against the pre-extraction baseline.
- [ ] **API freeze:** reflection test green; `backend` wire set still strictly validated.
- [ ] **CI honesty:** hosted jobs assert `hwdec=no` explicitly; hwdec jobs fail loudly when no GPU is present.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Quarantine too small on the new backend (tearing/UAF) | LOW | Raise `CompositorLatency()` for that backend only; rerun the soak |
| Downstream D3D11 ABI already shipped | HIGH | Add an upstream-ABI shim, deprecate the downstream params, regenerate patches; two-release migration |
| Extraction regressed Vulkan | MEDIUM | Each move is its own commit; bisect against the baseline harness; revert the single move |
| GL backend broken on a driver (Mesa EGLImage, NVIDIA GLES) | LOW | auto chain falls to Vulkan with a reason; add a driver deny-list keyed on `GL_RENDERER` |
| Zero-copy interop fails in the field | LOW | Reported fallback to `-copy`; event surfaced; no crash |
| macOS route chosen wrong | MEDIUM | Keep MoltenVK as the shipping default until the alternative has passed the same gates |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 11 D-05 baseline before refactor | P-A (first plan) | Harness fixed; baseline soak numbers + renderer line committed |
| 10 Backend reporting vs API freeze | P-A (ADR) | API-freeze reflection test green; strict wire validation tests |
| 6 `mpv_render_*` thread affinity (`report_swap`, free) | P-A (interface), P-C | Debug assert: every `mpv_render_*` call on the render thread |
| 12 Async unregistration / deferred release | P-A (contract) | 1000 create/dispose cycles per platform, zero raster-thread crashes |
| Vulkan unchanged (constants, reasons, `call_once`) | P-A | `render_vk_smoke`, Phase 2/3 suites, 4K 30-min gate vs baseline |
| 2 Upstream D3D11 ABI adoption | P-B (first plan) | PATCH-DRIFT byte-equal on the advanced vendor; header sync check |
| 3 `ra_d3d11` + `pl_d3d11` + build deps | P-B | `config.h` HAVE_D3D11; `hwdec-current=d3d11va`; PE audit |
| 1 Consumer still ANGLE: completion query + quarantine | P-B, P-E | D-05 soak on the D3D11 backend, Impeller on/off |
| 4 hwdec list vs zero-copy | P-B, P-C | Soak asserts `hwdec-current` |
| 5 Linux GL context/share/EGLImage | P-C | Non-black probe on llvmpipe CI; Intel/AMD/NVIDIA manual matrix |
| 7 vo_gpu vs gpu-next on GL | P-C (ADR) | Renderer report matches the requested renderer or reports a downgrade |
| 8 vaapi DRM display + modifiers | P-C | Main10 clip on a real Intel/AMD host |
| 9 nvdec build + CUDA context | P-C | `cuda-interop` in config; GL_VENDOR check logged |
| 13 macOS route | P-D (ADR) | Cost comparison recorded; videotoolbox P010 test |
| 14 CI tiers (WARP/llvmpipe/VM vs GPU) | P-E | Loud-fail guard for hwdec tier; serialized WARP jobs |

## Sources

Primary sources read directly (HIGH):
- Vendored mpv: `native/mpv/include/mpv/render.h` (Threading, ADVANCED_CONTROL, lifecycle), `video/out/gpu_next/context.c`, `video/out/d3d11/hwdec_d3d11va.c`, `video/out/vo_gpu_next.c`, `video/out/vo_libmpv.c`, `video/out/hwdec/hwdec_vaapi.c`, `dmabuf_interop_gl.c`, `meson.build`
- Build: `native/build/build.sh`, `deps.sh`, `ffmpeg.sh`, `package.sh`
- Plugin: `packages/mpv_kit_video/lib/src/video_controller.dart`, `src/video_renderer.cc`, `linux/gl_interop.cc`, `windows/d3d11_interop.cpp`
- Project: `docs/adr/0003-windows-composition-path.md`, `.planning/codebase/CONCERNS.md`, `.planning/PROJECT.md`
- Upstream mpv: [PR #17764 D3D11 render API (merged 2026-10-15)](https://github.com/mpv-player/mpv/pull/17764), [render_d3d11.h](https://github.com/mpv-player/mpv/blob/4255130de410e0cbdab694b951085409d466b704/include/mpv/render_d3d11.h)
- libplacebo D3D11 header: [d3d11.h](https://github.com/haasn/libplacebo/blob/master/src/include/libplacebo/d3d11.h) (feature-level notes, `pl_d3d11_wrap` rules)

Issue reports read in full (MEDIUM):
- media_kit: [#1463](https://github.com/media-kit/media-kit/issues/1463), [#1404](https://github.com/media-kit/media-kit/issues/1404), [#1425](https://github.com/media-kit/media-kit/issues/1425), [#1439](https://github.com/media-kit/media-kit/issues/1439), [#1287](https://github.com/media-kit/media-kit/issues/1287), [#1345](https://github.com/media-kit/media-kit/issues/1345), [#1321](https://github.com/media-kit/media-kit/issues/1321), [#1366](https://github.com/media-kit/media-kit/issues/1366), [#1383](https://github.com/media-kit/media-kit/issues/1383), [#1438](https://github.com/media-kit/media-kit/issues/1438), [#1176](https://github.com/media-kit/media-kit/issues/1176), [#1097](https://github.com/media-kit/media-kit/issues/1097), [#717](https://github.com/media-kit/media-kit/issues/717), [#296](https://github.com/media-kit/media-kit/issues/296), [#249](https://github.com/media-kit/media-kit/issues/249), [#672](https://github.com/media-kit/media-kit/issues/672), [#1361](https://github.com/media-kit/media-kit/issues/1361), [#1207](https://github.com/media-kit/media-kit/issues/1207), [#10](https://github.com/media-kit/media-kit/issues/10)
- mpv: [#10810](https://github.com/mpv-player/mpv/issues/10810), [#16818](https://github.com/mpv-player/mpv/pull/16818), [#18607](https://github.com/mpv-player/mpv/pull/18607), [#18343](https://github.com/mpv-player/mpv/issues/18343), [#18259](https://github.com/mpv-player/mpv/issues/18259), [#18214](https://github.com/mpv-player/mpv/issues/18214) (heap growth fixed by `f74adc4243`; confirm the vendored tree contains it), [#17626](https://github.com/mpv-player/mpv/issues/17626), [#15327](https://github.com/mpv-player/mpv/issues/15327), [#14242](https://github.com/mpv-player/mpv/issues/14242), [#16397](https://github.com/mpv-player/mpv/issues/16397), [#10424](https://github.com/mpv-player/mpv/issues/10424), [#9657](https://github.com/mpv-player/mpv/issues/9657), [#8509](https://github.com/mpv-player/mpv/issues/8509), [#10406](https://github.com/mpv-player/mpv/issues/10406), [#4237](https://github.com/mpv-player/mpv/issues/4237)
- Flutter: [#191468](https://github.com/flutter/flutter/issues/191468), [#190774](https://github.com/flutter/flutter/issues/190774), [#154716](https://github.com/flutter/flutter/issues/154716), [#121046](https://github.com/flutter/flutter/issues/121046), [#191978](https://github.com/flutter/flutter/issues/191978), [#193080](https://github.com/flutter/flutter/issues/193080), [#190044](https://github.com/flutter/flutter/issues/190044), [#179322](https://github.com/flutter/flutter/issues/179322), [PR #178697](https://github.com/flutter/flutter/pull/178697), [#189379](https://github.com/flutter/flutter/issues/189379), [#150668](https://github.com/flutter/flutter/issues/150668), [#124009](https://github.com/flutter/flutter/issues/124009), [#157379](https://github.com/flutter/flutter/issues/157379), [#159162](https://github.com/flutter/flutter/issues/159162), [#160520](https://github.com/flutter/flutter/issues/160520)
- Others: [fvp#397](https://github.com/wang-bin/fvp/issues/397), [fvp#395](https://github.com/wang-bin/fvp/issues/395), [flutter_inappwebview#2896](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2896)

Search-summary only, re-verify before relying (LOW):
[flutter#190200](https://github.com/flutter/flutter/issues/190200), [flutter#147242](https://github.com/flutter/flutter/issues/147242), [flutter#191797](https://github.com/flutter/flutter/issues/191797), [mpv#8215](https://github.com/mpv-player/mpv/issues/8215), [mpv#11400](https://github.com/mpv-player/mpv/issues/11400), [mpv#8668](https://github.com/mpv-player/mpv/issues/8668), [mpv#11769](https://github.com/mpv-player/mpv/issues/11769), [libplacebo#228](https://code.videolan.org/videolan/libplacebo/-/issues/228), [jellium-desktop#691](https://github.com/andrewrabert/jellium-desktop/issues/691), [streamlib#2488](https://github.com/tatolab/streamlib/issues/2488), [displayxr#2190](https://github.com/DisplayXR/displayxr-runtime/issues/2190), [zvidlib PR #566](https://github.com/lsegal/zvidlib/pull/566), [egui#8772](https://github.com/emilk/egui/issues/8772), [three_js#144](https://github.com/Knightro63/three_js/issues/144), [rive-flutter#620](https://github.com/rive-app/rive-flutter/issues/620), [edde746/mpv-build#4](https://github.com/edde746/mpv-build/issues/4), [mpv discussion #14389](https://github.com/mpv-player/mpv/discussions/14389), [Microsoft: WARP limitations](https://learn.microsoft.com/en-us/windows/desktop/direct3d11/overviews-direct3d-11-devices-limitations), [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/github-hosted-runners-reference)

---
*Pitfalls research for: libmpv → Flutter desktop render backends (v3.0)*
*Researched: 2026-10-26*
