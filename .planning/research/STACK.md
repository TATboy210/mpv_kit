# Stack Research: milestone v3.0 (unified RenderBackend and platform-native graphics backends)

**Domain:** libmpv render API backends (D3D11 / OpenGL / Metal-class) feeding Flutter desktop external textures
**Researched:** 2026-10-26
**Confidence:** HIGH for Windows and the upstream status facts (verified against the mpv/libplacebo/Flutter sources and the GitHub API). MEDIUM for Linux hwdec on GLES. HIGH for the macOS recommendation, MEDIUM for its long-term outlook.
**Scope:** This file covers only what v3.0 adds. It treats the existing Vulkan path (patches 0001-0004, MoltenVK, KMT->Vulkan import) as the fallback and does not research it again.

---

## 0. Headline findings (read first)

1. **Upstream mpv already has a D3D11 libmpv render API, merged after our base.** mpv-player/mpv PR [#17764](https://github.com/mpv-player/mpv/pull/17764) "libmpv: add D3D11 render API backend" (kasper93, co-author dragonflylee) was merged on **2026-10-15** as `4255130de4`. Our vendored base `b2c255c13` is dated 2026-10-09, and `4255130de4` is **64 commits ahead** of it (GitHub compare API: ahead_by=64, behind_by=0).
   - It adds `MPV_RENDER_API_TYPE_D3D11 "d3d11"`, `MPV_RENDER_PARAM_D3D11_INIT_PARAMS = 21` (`mpv_d3d11_init_params { void *device; }`), `MPV_RENDER_PARAM_D3D11_FBO = 22` (`mpv_d3d11_fbo { void *tex; }`), a public `include/mpv/render_d3d11.h`, `video/out/d3d11/libmpv_d3d11.c` (101 lines), and bumps the client API to **2.6**.
   - **It only implements the legacy `gpu` renderer** (it is a `libmpv_gpu_context_fns` built on mpv's own `ra_d3d11`). It has **no gpu-next support**.
   - It is **not ANGLE**: the host passes its own `ID3D11Device`, and mpv renders straight into the host's `ID3D11Texture2D`.
   - **We do not write the D3D11 render API ourselves. We backport it.** Our own work is a **gpu-next D3D11 branch** added to patch 0004's `render_backend_gpu_next`.
2. **Its enum numbers do not collide with our patches.** Our Vulkan params sit in a private range, `MPV_RENDER_PARAM_VULKAN_* = 0x6d6b0001..3` (`native/mpv/include/mpv/render_vk.h:57-72`), and upstream uses 21 and 22. The backport therefore keeps upstream's ABI verbatim, and apps built against it stay compatible with upstream libmpv 0.42.
3. **Enabling D3D11 adds two native dependencies to the Windows build: SPIRV-Cross and shaderc.**
   - **SPIRV-Cross** is needed by both libplacebo's `pl_d3d11` and mpv's `ra_d3d11`. pkg-config name `spirv-cross-c-shared`; libplacebo requires >= 0.29.0.
   - **shaderc** is needed because mpv's meson gates `d3d11` on `win32-desktop and shaderc and spirv-cross` (`native/mpv/meson.build:1079-1082`), and because `ra_d3d11_create` / `libmpv_d3d11.c init` call `spirv_compiler_init`. mpv's only SPIR-V compiler is shaderc (`video/out/gpu/spirv.c`).
   - Both are Apache-2.0 and LGPL-compatible. Both are absent today: `build.sh` passes `-Dshaderc=disabled -Dspirv-cross=disabled -Dd3d11=disabled`, and `deps.sh` passes libplacebo `-Dd3d11=disabled`.
4. **libplacebo `pl_d3d11` at 7.360.1 can wrap a host texture but cannot export or share one, and it has no sync API.**
   - `pl_d3d11_create(.device = existing)` AddRefs the device and ignores every other param.
   - `pl_d3d11_wrap` accepts any `D3D11_USAGE_DEFAULT`, non-mip, non-MSAA texture from the same device. It derives renderable from `D3D11_BIND_RENDER_TARGET` and sampleable from `..._SHADER_RESOURCE`, and never inspects `MiscFlags`.
   - There is no keyed mutex, no fence export and no `SetMultithreadProtected`.
   - So **the host creates the shared texture**, which the current `d3d11_interop.cpp` already does, and **the host does cross-device sync**.
5. **No Metal renderer exists in mpv or in upstream libplacebo.** There are three unmerged efforts:
   - libplacebo MR [!858](https://code.videolan.org/videolan/libplacebo/-/merge_requests/858) by simonchrz, see [haasn/libplacebo#370](https://github.com/haasn/libplacebo/issues/370);
   - [haasn/libplacebo#380](https://github.com/haasn/libplacebo/issues/380), opened 2026-09-28, which is Apple-GPU-only;
   - IINA's experimental `lhc70000/libplacebo@a962968` (+3416 lines) plus a gpu-next render backend, `lhc70000/mpv@97179bce`, described in [mpv#16818 comments](https://github.com/mpv-player/mpv/pull/16818).

   **Recommendation: keep MoltenVK -> IOSurface as the macOS "native" backend for v3.0** (option a).
6. **gpu-next over the libmpv OpenGL API is not upstream either.** mpv PR [#16818](https://github.com/mpv-player/mpv/pull/16818) "vo_libmpv: introduce 'gpu-next' render backend" (OpenGL only) has been open since 2025-09-20 and was last updated 2026-09-16. Upstream `MPV_RENDER_API_TYPE_OPENGL` drives only `vo_gpu` (`libmpv_gpu_context_gl`). Like D3D11, Linux GL with gpu-next is "ours to write" as an extension of patch 0004.

---

## 1. Recommended stack

### 1.1 Core technologies (new or changed in v3.0)

| Technology | Version | Purpose | Why |
|---|---|---|---|
| **mpv upstream D3D11 render API** (backport of 4 commits: `f0b70a87c2`, `b96f286532`, `2a97b84b39`, `69920fdcaf`; merge `4255130de4`) | upstream master 2026-10-15, client API 2.6 | `MPV_RENDER_API_TYPE_D3D11` for the `gpu` renderer; the ABI that our gpu-next D3D11 branch reuses | Upstream code, so we carry no API of our own. The companion commits fix the immediate context being shared with the API user (rasterizer state re-set per draw, live-object report moved to the VO). Carry them as a new `0010-upstream-d3d11-render-api.patch` in the 0009 style ("drop each hunk when rebasing onto a base that contains it"). |
| **gpu-next D3D11 branch in patch 0004** | ours | Run `vo_gpu_next` under `MPV_RENDER_API_TYPE_D3D11` | Upstream `video/out/gpu_next/context.c:53-105` already pairs `ra_d3d11` (for hwdec mapping) with `pl_d3d11_create(.device = ra_d3d11_get_device(ra))`. `vo_gpu_next.c:776-790` already re-wraps d3d11va textures with `pl_d3d11_wrap`. We only add the libmpv entry. |
| **libplacebo `pl_d3d11`** | 7.360.1 (pinned) + `-Dd3d11=enabled` on Windows | GPU backend for gpu-next on D3D11 | The real D3D11 renderer behind `vo_gpu_next --gpu-api=d3d11`. It needs `d3d11.h`, `d3d11_4.h`, `dxgi1_6.h` (mingw-w64 in MSYS2 CLANG64/CLANGARM64 has them), `spirv-cross-c-shared >= 0.29.0` and `-lversion` (`src/d3d11/meson.build`). GLSL->SPIR-V reuses our static glslang. HLSL is produced by SPIRV-Cross and compiled by the **inbox `d3dcompiler_47.dll`**, loaded at run time with `LOAD_LIBRARY_SEARCH_SYSTEM32` on Windows 8.1+ (`src/d3d11/gpu.c`), so it is not bundled. |
| **SPIRV-Cross** | `vulkan-sdk-1.4.363.0` (matches `VK_SDK` in deps.sh) | SPIR-V -> HLSL for libplacebo d3d11 and mpv `ra_d3d11` | Mandatory for both. Build with CMake `-DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF`. Both consumers look up the pkg-config name `spirv-cross-c-shared`, which only the shared build installs. Apache-2.0. Adds one DLL. |
| **shaderc** | `v2026.4` (latest tag) | GLSL->SPIR-V for mpv's own `ra_d3d11` (the `gpu` renderer on D3D11) | mpv's meson makes it mandatory for `d3d11`. Build it against **our pinned glslang 16.6.0 source** plus SPIRV-Tools / SPIRV-Headers `vulkan-sdk-1.4.363.0` (`SHADERC_GLSLANG_DIR`, `SHADERC_SPIRV_TOOLS_DIR`, `SHADERC_SPIRV_HEADERS_DIR`, `SHADERC_SKIP_TESTS=ON`, `SHADERC_SKIP_EXAMPLES=ON`), so one glslang version exists in the tree. Apache-2.0. See §4 for the "patch it out" alternative. |
| **libmpv OpenGL render API** (upstream `MPV_RENDER_API_TYPE_OPENGL`, `render_gl.h`) | as vendored (0.41.0-1115) | Linux GL backend, `gpu` renderer first | Exists upstream with no patch. Needs mpv `-Dgl=enabled -Degl=enabled -Dplain-gl=enabled` on Linux. Without `plain-gl` (or egl-x11/egl-wayland/egl-drm) the `gl` feature stays false, and `-Dx11=disabled -Dwayland=disabled` are kept (`meson.build:1180-1330`). |
| **gpu-next OpenGL branch in patch 0004** | ours | gpu-next under `MPV_RENDER_API_TYPE_OPENGL` | Keeps Linux GL at gpu-next quality. `pl_opengl_create` + `pl_opengl_wrap(.framebuffer = fbo)`. `hwdec_get_tex` already has the `pl_opengl_wrap` path (`vo_gpu_next.c:762-774`). Reference designs: mpv#16818 and the IINA branch. |
| **libplacebo `pl_opengl`** | 7.360.1 + `-Dopengl=enabled` on Linux only | GPU backend for gpu-next GL | Needs the **glad >= 2.0 Python generator**. The libplacebo source tarball ships `3rdparty/glad` as an empty submodule pinned at `Dav1dde/glad@73db193f85` (2024-09-29), so fetch it like `fast_float` today. `src/opengl/include/glad/meson.build` runs `python -m glad --api=gl:core,gles2,egl`. The jinja2 already required by deps.sh covers its dependency. |
| **Flutter desktop texture APIs** | Flutter 3.47.x (CI 3.47.6; RE on 3.47.8) | Hand-off targets | Unchanged public API. Exact contracts are in §6. |

### 1.2 Supporting libraries and build flags

| Library / flag | Version | Purpose | When |
|---|---|---|---|
| mpv `-Dd3d11=enabled -Dshaderc=enabled -Dspirv-cross=enabled` | — | Compiles `ra_d3d11`, `context.c`, `libmpv_d3d11.c` and **`hwdec_d3d11va.c`** (`d3d-hwaccel and d3d11`, `meson.build:1462`) | Windows only. Today d3d11va is copy-back only, because `hwdec_d3d11va.c` is not built while `-Dd3d11=disabled`. Enabling it gives true **d3d11va zero-copy** on the D3D11 backend. |
| mpv `-Degl-angle=disabled -Degl-angle-lib=disabled -Degl-angle-win32=disabled -Dgl-win32=disabled -Dgl-dxinterop=disabled -Dgl-dxinterop-d3d9=disabled` | — | Make the ANGLE ban explicit in the build | Windows. `-Dgl=disabled` already implies most of these, but Linux now needs `gl` enabled, so `-Dgl` becomes per-platform and the ANGLE options must be pinned off. |
| mpv `-Dgl=enabled -Degl=enabled -Dplain-gl=enabled` (Linux) | host `libEGL.so.1` (libglvnd) | libmpv GL + `dmabuf_interop_gl.c` (`features['egl'] and drm`, `meson.build:1539`) | Linux. `libEGL`/`libGL` are already on the `package.sh:45` system allowlist. The build container needs `libegl-dev` and `libgl-dev` (headers only). |
| **nv-codec-headers (ffnvcodec)** | `n13.0.19.1` (stable-line; `n13.1.15.0` is newest) | FFmpeg `--enable-ffnvcodec --enable-nvdec --enable-cuvid`; mpv `cuda-hwaccel` + `cuda-interop` (needs >= 11.1.5.1, `meson.build:1405`) | Linux only, and only if nvdec is in scope. MIT, header-only, loads `libcuda.so.1` at run time. **Do not** pass `--enable-cuda-nvcc`, `--enable-libnpp` or `--enable-cuda-llvm`: the first two are nonfree, and cuda-llvm is not needed for decoding. |
| libplacebo d3d11 backports (new `native/deps/libplacebo/` entries) | post-7.360.1 master | Correctness of `pl_d3d11` | Take `82224764a9` + `c43baa7a0c` **as a pair**. The first fixes D3DCompile "overlapping register semantics" with AV1 film grain ([mpv#17685](https://github.com/mpv-player/mpv/issues/17685)); the second fixes the UAV slot regression the first introduced and bumps the DXBC cache key. Also consider `de33d3adb0` (missing error check) and `eec54224b3` (fence message mapping). `c94dfd373e` (texture-size probe) is irrelevant at FL11, where 16384 is guaranteed. Raise the hard-coded `14` in `deps.sh:231`. |
| libplacebo opengl backports | post-7.360.1 master | GLES correctness | `3be579e6c7` (disable invalidate-fb on NVIDIA), `4a13740ed4` (index buffer vertex format), `bca3473622`/`cf3712ead8`/`4d664bbb9d` (GLES 3.0 float formats; Flutter's share group is GLES). Evaluate during the Linux phase. |
| D3D11 sync primitives (`ID3D11Device5::CreateFence`, `ID3D11DeviceContext4::Signal`, `ID3D11Fence::SetEventOnCompletion`) | Windows 10 1703+ (`d3d11_3.h` / `d3d11_4.h`) | Producer-side completion before `MarkExternalTextureFrameAvailable` | Windows D3D11 backend. Fall back to a `D3D11_QUERY_EVENT` query on older builds. |
| EGL fence (`EGL_KHR_fence_sync` + `EGL_KHR_wait_sync`) and `EGL_KHR_gl_texture_2D_image` / `GL_OES_EGL_image` | host EGL | Linux GL hand-off and sync | Linux GL backend (see §5.2). |

### 1.3 Development and verification tools

| Tool | Purpose | Notes |
|---|---|---|
| `tools/check_patches.sh` (PATCH-DRIFT) | Proves base + patches == vendor | 0010 (the D3D11 backport) and the extended 0004 must pass it. Regenerate from the vendor tree, as in Phase 5. |
| `tools/rea_abi_audit/pe_audit.py` | DLL export/import audit | **Add a rule:** `libmpv-2.dll`, `libplacebo-*.dll` and `mpv_kit_video_plugin.dll` must import neither `libEGL.dll` nor `libGLESv2.dll`, and must not reference the `eglGetPlatformDisplayEXT` string. This turns the "no ANGLE" constraint into a CI gate. Also extend the GPL-free import check to `spirv-cross-c-shared.dll` and `shaderc_shared.dll`. |
| D3D11 debug layer (`D3D11_CREATE_DEVICE_DEBUG`, `pl_d3d11_params.debug`) | Validation in dev builds | It reports objects created by the API user as well (upstream commit `2a97b84b39` moved the live-object report for exactly this reason). |
| `MTL_DEBUG_LAYER=1`, MoltenVK `MVK_CONFIG_LOG_LEVEL` | macOS validation | Unchanged path. |

---

## 2. Windows: native D3D11 backend (no ANGLE)

### 2.1 What exists upstream versus what we must write

| Piece | Status | Source |
|---|---|---|
| `MPV_RENDER_API_TYPE_D3D11`, `render_d3d11.h`, params 21/22, `libmpv_gpu_context_d3d11` (gpu renderer) | **Exists upstream** (master, after our base) | PR #17764, merge `4255130de4` |
| `ra_d3d11` (mpv RA on a caller-owned device) | Exists (vendored) | `native/mpv/video/out/d3d11/ra_d3d11.c:2389` `ra_d3d11_create(ID3D11Device*, log, spirv)` |
| `hwdec_d3d11va` (zero-copy: wraps decoder texture-array slices) | Exists (vendored, not compiled today) | `video/out/d3d11/hwdec_d3d11va.c`. Calls `ID3D10Multithread_SetMultithreadProtected(TRUE)` on the device (lines 128-137) and requires `ra_is_d3d11`. |
| gpu-next on D3D11 (ra_d3d11 + pl_d3d11 pairing, hwdec re-wrap) | Exists for the windowed VO only | `video/out/gpu_next/context.c:53-105`, `vo_gpu_next.c:776-790` |
| **gpu-next under the D3D11 render API** | **Must be written by us** (extend 0004) | `libmpv_init` in `vo_gpu_next.c:3126` accepts only `MPV_RENDER_API_TYPE_VULKAN` |
| Host side: device, shared ring, fence, `GpuSurfaceTexture` | Mostly exists (`d3d11_interop.cpp`); **we adapt it** | The Vulkan import goes away on this backend |

### 2.2 gpu-next D3D11 branch design (what 0004 gains)

1. `libmpv_init`: when `api == MPV_RENDER_API_TYPE_D3D11`, create the context with `libmpv_gpu_context_d3d11` (upstream). This yields `ra_ctx->ra = ra_d3d11` on the host device.
2. Set `p->gpu = pl_d3d11_create(pllog, pl_d3d11_params(.device = ra_d3d11_get_device(ra)))->gpu` instead of `ra_pl_get(...)`, which is NULL for `ra_d3d11`. Destroy it in `libmpv_destroy` before the ra, mirroring `gpu_next/context.c:220-224`.
3. `libmpv_render`: wrap `mpv_d3d11_fbo.tex` with `pl_d3d11_wrap(p->gpu, .tex = tex)` and use it as `p->libmpv_target.fbo`, then call `pl_gpu_flush` before returning. The upstream render_d3d11.h contract is "submits all its rendering to the immediate context before it returns, and keeps no reference to the texture".
4. **Signature conflict:** upstream `libmpv_d3d11.c` has `static void done_frame(...)`, but our 0001/0004 changed `libmpv_gpu_context_fns.done_frame` to return `bool` (UPSTREAM.md, 2026-10-25 stability fixes). The backport hunk must become `return true;`. Record this in UPSTREAM.md.
5. Shader cache: libplacebo d3d11 caches DXBC in `pl_cache` (c43baa7a0c "bump DXBC cache key"). **Extend patch 0003's persistent cache to the D3D11 path.** D3DCompile is slow, and without a cache the first frames stutter on every launch.
6. Renderer report (0004's `get_info`) gains `"gpu-next"`/`"gpu"` under the d3d11 API. `MpvVideoRenderer` stays unchanged (API frozen), and the backend name travels in the existing `backend`/`reason` fields.

### 2.3 Device and texture contract (host side)

- **Device:** create it as today on Flutter's adapter (`FlutterDesktopViewGetGraphicsAdapter`), **adding `D3D11_CREATE_DEVICE_VIDEO_SUPPORT`**, which d3d11va needs for `ID3D11VideoDevice`. The current flags are `BGRA_SUPPORT` only (`d3d11_interop.cpp:37-40`). **Never** use `D3D11_CREATE_DEVICE_SINGLETHREADED`: render_d3d11.h says that limits hwdec to `d3d11va-copy`. FL 11_0/11_1 as today.
- **Render target:** `DXGI_FORMAT_B8G8R8A8_UNORM` (upstream-supported, non-sRGB), `D3D11_USAGE_DEFAULT`, `BIND_RENDER_TARGET | BIND_SHADER_RESOURCE`, **`D3D11_RESOURCE_MISC_SHARED` (legacy KMT handle)**. Do **not** switch to `SHARED_NTHANDLE`. Flutter/ANGLE opens the `DxgiSharedHandle` with `ID3D11Device::OpenSharedResource` (docs/reverse-engineering/03 §B), which accepts only KMT handles; NT handles need `OpenSharedResource1`. `SHARED_KEYEDMUTEX` gains nothing, because ANGLE queries `IDXGIKeyedMutex` but the Flutter chain never acquires it (doc 03).
- **Threading:** mpv uses the device's **immediate context** and does not restore state (render_d3d11.h). The plugin must not use the immediate context concurrently with `mpv_render_*`. Device-level calls such as `CreateTexture2D` are free-threaded, and `SetMultithreadProtected(TRUE)` (set by mpv's d3d11va) serializes context use with the decoder thread.
- **Sync:** after `mpv_render_context_render` (mpv has flushed), signal an `ID3D11Fence` on the render thread and wait for completion (`SetEventOnCompletion`) before `FrameReady`. This replaces the Vulkan timeline wait. Keep the **quarantine ring (latency 4, ring 7)**, because consumer-side reads by ANGLE are still unfenced (ADR 0003, doc 03).

### 2.4 Hardware decode on the D3D11 backend

| hwdec | Path | Zero-copy? |
|---|---|---|
| `d3d11va` | FFmpeg decodes on the host device; `hwdec_d3d11va` wraps the slice (`ra_d3d11_wrap_tex_video`); gpu-next re-wraps it with `pl_d3d11_wrap(.array_slice, .fmt = NV12/P010, .w, .h)` | **Yes** (same device) |
| `d3d11va-copy`, `dxva2-copy` | Unchanged | No (already works today) |
| `nvdec`, `vulkan` | Stay on the Vulkan fallback backend | n/a |

FFmpeg already has `--enable-d3d11va --enable-dxva2` (`ffmpeg.sh:44`), so no FFmpeg change is needed.

---

## 3. Linux: OpenGL backend

### 3.1 Upstream availability

| Piece | Status |
|---|---|
| `MPV_RENDER_API_TYPE_OPENGL` with `vo_gpu` | **Exists upstream** (`video/out/opengl/libmpv_gl.c`) |
| gpu-next under the GL render API | **Not upstream.** PR #16818 is open; we extend 0004 |
| vaapi -> GL zero-copy (`dmabuf_interop_gl.c`) | Exists. Needs an **EGL** current context (`eglGetCurrentContext()` check, line 346), `EGL_EXT_image_dma_buf_import`, and `GL_OES_EGL_image` on GLES or `GL_EXT_EGL_image_storage` on desktop GL (line 354) |
| VA display for libmpv | Exists, but the **host must pass `MPV_RENDER_PARAM_DRM_DISPLAY_V2` with `render_fd`** (`hwdec_vaapi.c:63-70`), because x11 and wayland are disabled in our build. Without it vaapi has no display. That probably also explains why vaapi on today's Vulkan path is unverified. |
| nvdec -> GL (`hwdec_cuda_gl.c`, `cuGraphicsGLRegisterImage`) | Exists. **Behaviour with a GLES context is unverified** (LOW): NVIDIA documents GL interop for "OpenGL" only, and community reports show it working on NVIDIA's own EGL stack. Keep nvdec zero-copy on the Vulkan backend (`hwdec_cuda_vk.c`) and use `nvdec-copy` on GL until it is measured. |

### 3.2 Flutter Linux facts that drive the design

At Flutter 3.47.6, `engine/src/flutter/shell/platform/linux/fl_opengl_manager.cc` creates the engine's own **EGL** contexts on the GDK display (`EGL_PLATFORM_X11_EXT` / `EGL_PLATFORM_WAYLAND_EXT`), **`EGL_CONTEXT_CLIENT_VERSION 2` (GLES)**. It creates render, resource and platform contexts in one share group. `fl_engine_gl_external_texture_frame_callback` calls `FlTextureGL::populate` on the **raster thread with the engine's render context current**.

The `fl_texture_gl.h` doc comment saying "create a GdkGLContext ... it will be shared with the one used by Flutter" is **stale**: Flutter no longer renders through a GdkGLContext.

### 3.3 Recommended hand-off: isolated context plus EGLImage

This is media_kit's proven Linux pattern (`media_kit_video/linux/video_output.cc`, `texture_gl.cc`), used for reference only.

- mpv gets its **own** EGL context on the same `EGLDisplay` that `FlutterEglDisplay()` already resolves (`gl_interop.cc:41`). It is **not** in Flutter's share group, so mpv's GL state can never corrupt Flutter's. Prefer GLES 3.x or desktop GL via `eglBindAPI`.
- Each ring slot is a GL texture rendered through an FBO. It is exported once as `eglCreateImageKHR(EGL_GL_TEXTURE_2D_KHR)` and imported in `populate` with `glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image)`.
- **Format:** `GL_RGBA8`, because the fl_texture_gl.h docs say "Flutter only accepts textures in GL_RGBA8 format".
- **Sync:** `eglCreateSyncKHR(EGL_SYNC_FENCE_KHR)` after the render, then `eglWaitSyncKHR` (GPU-side) in `populate`. Fall back to `eglClientWaitSyncKHR` if `EGL_KHR_wait_sync` is missing.
- vaapi: open the DRM render node that belongs to the EGL device (`eglQueryDisplayAttribEXT(EGL_DEVICE_EXT)` -> `eglQueryDeviceStringEXT(EGL_DRM_RENDER_NODE_FILE_EXT)`) and pass it as `render_fd`.

---

## 4. Licensing and dependency deltas

| Add | License | Bundle impact | Verdict |
|---|---|---|---|
| SPIRV-Cross (shared) | Apache-2.0 | `+spirv-cross-c-shared.dll` (Windows) | OK. Apache-2.0 is compatible with LGPL-2.1-**or-later** (it combines as LGPLv3). The bundle already links Apache-2.0 code: MoltenVK on macOS and the Vulkan headers. Ship its license under `share/licenses`. |
| shaderc (+ SPIRV-Tools, SPIRV-Headers) | Apache-2.0 | `+shaderc_shared.dll`, several MB | OK, but the largest new item. **Alternative (our patch):** let `ra_d3d11` work without a SPIR-V compiler when it is only used as gpu-next's hwdec wrapper, and relax the meson `d3d11` requirement. That avoids shaderc, at the cost of losing the `gpu` fallback on D3D11 and carrying another downstream patch. Recommendation: **build shaderc**. The gpu fallback on D3D11 keeps the D3D11 backend self-sufficient before dropping to Vulkan, and it matches how MSYS2/upstream builds mpv. |
| glad generator (build-time only) | MIT (generated loader code) | None (header-only, compiled into libplacebo) | OK |
| nv-codec-headers | MIT | None (headers; `libcuda` is the host driver) | OK, without `--enable-nonfree` |
| `d3dcompiler_47.dll` | Windows system component | Not shipped (inbox since 8.1) | OK |

**Never add:**

| Avoid | Why | Instead |
|---|---|---|
| ANGLE (`libEGL.dll`/`libGLESv2.dll`), mpv `egl-angle*`, `context_angle.c`, `hwdec_d3d11egl.c` | User hard ban for mpv_kit's own chain. media_kit's Windows route is exactly this | `MPV_RENDER_API_TYPE_D3D11` + pl_d3d11 |
| `gl-dxinterop` (WGL_NV_DX_interop) | GL on Windows; not native D3D11, and driver-dependent | D3D11 |
| `kFlutterDesktopGpuSurfaceTypeD3d11Texture2D` | ANGLE binds it with `EGL_D3D_TEXTURE_ANGLE`, which needs the texture on ANGLE's own device. Flutter does not expose that device | `DxgiSharedHandle` (KMT) |
| `D3D11_RESOURCE_MISC_SHARED_NTHANDLE` | The consumer opens it with `OpenSharedResource` (KMT only) | `MISC_SHARED` |
| FFmpeg `--enable-cuda-nvcc`, `--enable-libnpp`, `--enable-nonfree`, `--enable-gpl` | Nonfree/GPL in the bundle | `--enable-nvdec --enable-cuvid --enable-ffnvcodec` only |
| Desktop-GL share group with Flutter's GLES contexts | EGL forbids sharing across client APIs; it also couples mpv state to Flutter's | Isolated context + EGLImage |
| macOS OpenGL (CGL) backend | See §5 | MoltenVK |
| A libplacebo Metal fork (IINA / MR !858) in v3.0 | Unmerged, about 3.4k LOC, needs a libmpv Metal API type of our own; Apple-GPU-only in #380 | Track; reconsider when libplacebo merges Metal |

---

## 5. macOS: the "Metal" decision

| Criterion | (a) MoltenVK -> IOSurface (current) | (b) OpenGL (CGL) + IOSurface (media_kit) | (c) Write a libmpv Metal backend |
|---|---|---|---|
| Upstream support | Our patches 0001-0004; libplacebo Vulkan | Upstream `MPV_RENDER_API_TYPE_OPENGL`, **`vo_gpu` only** | **None.** Requires an unmerged libplacebo Metal backend (MR !858 / #380 / IINA) **plus** a new render API type (IINA `lhc70000/mpv@97179bce`) |
| Renderer quality | gpu-next | gpu only. GL on macOS is capped at **4.1, with no compute shaders** (compute is GL 4.3), so compute-based paths are lost | gpu-next |
| VideoToolbox zero-copy | **Yes**: `hwdec_vt_pl.m` (`-Dvideotoolbox-pl=enabled`, already on) imports CVPixelBuffer/MTLTexture through MoltenVK `VK_EXT_metal_objects` | Yes via `hwdec_mac_gl.c` (`CGLTexImageIOSurface2D`, `GL_TEXTURE_RECTANGLE`), **but `videotoolbox-gl` requires `gl-cocoa`, which requires `-Dcocoa=enabled`**. We set `-Dcocoa=disabled` on purpose (0007 / UPSTREAM.md) | Would need new interop code |
| Platform outlook | Metal underneath; MoltenVK actively maintained (1.4.2 pinned) | OpenGL **deprecated since macOS 10.14**; on Apple silicon it is a Metal-backed shim | Best in theory, but years of upstream churn |
| Cost in v3.0 | Wrap it in the `RenderBackend` interface only | New backend + cocoa build change + quality regression | Very high; violates "small, independently revertible" |

**Recommendation: (a).** Present it in the API/HUD as the macOS native backend ("vulkan (MoltenVK/Metal)") and record the decision in an ADR, with the re-evaluation trigger "libplacebo merges a Metal `pl_gpu`".

The Flutter side already consumes Metal: `copyPixelBuffer` returns an IOSurface-backed `kCVPixelFormatType_32BGRA` buffer.

---

## 6. Flutter desktop texture contracts (3.47.x)

### Windows: `FlutterDesktopGpuSurfaceDescriptor` (`flutter_texture_registrar.h`, local copy `example/windows/flutter/ephemeral/`)

- `FlutterDesktopGpuSurfaceTextureConfig{struct_size, type, callback, user_data}`, with type `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`. The callback `(width, height, user_data) -> const FlutterDesktopGpuSurfaceDescriptor*` runs on the raster thread.
- `FlutterDesktopGpuSurfaceDescriptor{struct_size, handle (HANDLE for DxgiSharedHandle), width, height, visible_width, visible_height, format (optional: kFlutterDesktopPixelFormatBGRA8888), release_callback, release_context}`.
- **Ownership:** the producer owns the texture. "The referenced resource needs to stay valid until it has been opened by Flutter", and `release_callback` fires once it is opened. Per doc 03 it fires after `eglBindTexImage` and before the compositor reads, so it is **a lifetime signal, not read-complete**.
- **Sync:** none (no fence, no keyed-mutex acquire), so quarantine is mandatory.
- Register, unregister and `MarkExternalTextureFrameAvailable` may be called from any thread.
- Consumption is always via ANGLE inside `flutter_windows.dll`, with Impeller or Skia. That is outside mpv_kit's chain and allowed by PROJECT.md.

### Linux: `FlTextureGL` (`fl_texture_gl.h`)

- `populate(texture, *target, *name, *width, *height, **error)` is called on the raster thread with Flutter's EGL GLES render context already current. Return `GL_TEXTURE_2D` with a `GL_RGBA8` texture name. `fl_texture_registrar_mark_texture_frame_available` triggers it.
- The texture name must be valid in Flutter's context, so it must be created there: in `populate`, from the EGLImage.

### macOS: `FlutterTexture` (`FlutterTexture.h`)

- `- (CVPixelBufferRef _Nullable)copyPixelBuffer` is called on the raster thread. The pixel format is `32BGRA` or `420YpCbCr8BiPlanar{Video,Full}Range`. It follows the Create Rule, so return +1 and the engine releases it.
- `textureFrameAvailable:` triggers it. `registerTexture:`/`unregisterTexture:` must be called on the platform thread. The optional `onTextureUnregistered:` is called on the raster thread.
- The buffer must be IOSurface-backed and Metal-compatible for zero-copy. The current `metal_interop.mm` already does this.

---

## 7. Version compatibility

| Component | Compatible with | Notes |
|---|---|---|
| D3D11 backport (client API 2.6) | `MpvLibrary` major-version gate (2) | The minor bump is harmless. Dart does not need the new header; the plugin vendors `render_d3d11.h` into `packages/mpv_kit_video/src/include/mpv/` (the same pattern as `render_vk.h`). |
| libplacebo 7.360.1 `pl_d3d11` | SPIRV-Cross >= 0.29.0; glslang 16.6.0 (static) | No SPIRV-Cross version check at run time |
| shaderc v2026.4 | glslang 16.6.0 / SPIRV-Tools + SPIRV-Headers `vulkan-sdk-1.4.363.0` | shaderc's own DEPS pins glslang `73b25650`. Building against 16.6.0 must be verified in the Windows build phase (MEDIUM). |
| `ID3D11Fence` | Windows 10 1703+ | The project floor is Windows 10, so fall back to an event query on RTM-1607 |
| libplacebo `pl_opengl` | GLES 3.0+ preferred; Flutter contexts are GLES ("ES 2 requested, driver returns highest") | Our own isolated context can request GLES 3.2 or desktop GL 4.x |
| mpv `dmabuf_interop_gl` | EGL >= 1.4 with `EGL_EXT_image_dma_buf_import(_modifiers)` | Mesa and NVIDIA 470+ |
| MoltenVK 1.4.2 | `VK_EXT_metal_objects` for `hwdec_vt_pl` | Unchanged |

## 8. Installation deltas (sketch for `deps.sh` / `build.sh`)

```bash
# deps.sh, windows only (before libplacebo)
fetch spirv-cross https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz <sha256>
cmake_build spirv-cross -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF \
  -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF
fetch spirv-headers .../SPIRV-Headers/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz <sha256>
fetch spirv-tools   .../SPIRV-Tools/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz <sha256>
fetch shaderc https://github.com/google/shaderc/archive/refs/tags/v2026.4.tar.gz <sha256>
cmake_build shaderc -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
  -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSHADERC_GLSLANG_DIR=... \
  -DSHADERC_SPIRV_TOOLS_DIR=... -DSHADERC_SPIRV_HEADERS_DIR=...
# libplacebo: per-OS
#   windows: -Dd3d11=enabled  -Dopengl=disabled
#   linux:   -Dd3d11=disabled -Dopengl=enabled  (+ fetch glad@73db193f85 into 3rdparty/glad)
#   macos:   unchanged (vulkan only)

# build.sh
#   windows: -Dd3d11=enabled -Dshaderc=enabled -Dspirv-cross=enabled -Dgl=disabled
#            -Degl-angle=disabled -Degl-angle-lib=disabled -Degl-angle-win32=disabled
#   linux:   -Dgl=enabled -Degl=enabled -Dplain-gl=enabled (keep -Dx11/-Dwayland=disabled)
#            optional: ffnvcodec + -Dcuda-hwaccel=enabled -Dcuda-interop=enabled
```

## Sources

**Local (HIGH):**
- `native/mpv/video/out/vo_gpu_next.c:3100-3400` (0004 libmpv backend, Vulkan-only `libmpv_init`) and `:755-790` (`hwdec_get_tex` pl_d3d11/pl_opengl wrap).
- `native/mpv/video/out/gpu_next/context.c:53-224`.
- `native/mpv/video/out/d3d11/ra_d3d11.c:2389`, `context.c:530-540`, `hwdec_d3d11va.c:111-137`.
- `native/mpv/meson.build:1052-1087,1180-1330,1399-1542,1564-1584`.
- `native/mpv/include/mpv/render.h`, `render_vk.h:51-72`.
- `native/build/build.sh`, `ffmpeg.sh`, `deps.sh`, `package.sh:45`.
- `packages/mpv_kit_video/windows/d3d11_interop.cpp`, `linux/gl_interop.cc`.
- `docs/reverse-engineering/03-flutter-windows-texture-consumption.md`.
- `example/windows/flutter/ephemeral/flutter_texture_registrar.h`.

**mpv upstream (HIGH, GitHub API):**
- [PR #17764](https://github.com/mpv-player/mpv/pull/17764) (merged 2026-10-15, `4255130de4`). `render_d3d11.h` and `libmpv_d3d11.c` were read at that commit.
- [PR #16818](https://github.com/mpv-player/mpv/pull/16818) (gpu-next render backend, open) and its IINA comments.
- [PR #18258](https://github.com/mpv-player/mpv/pull/18258) (our earlier Vulkan RFC, closed).
- [Issue #17685](https://github.com/mpv-player/mpv/issues/17685).

**libplacebo (HIGH):**
- [`src/include/libplacebo/d3d11.h`@v7.360.1](https://github.com/haasn/libplacebo/blob/v7.360.1/src/include/libplacebo/d3d11.h), `src/d3d11/meson.build`, `context.c`, `gpu.c`, `gpu_tex.c` (v7.360.1).
- `src/opengl/include/glad/meson.build`, `3rdparty/glad` submodule.
- Pinned tarball sha256 re-verified as `14c0a99f…dc39`.
- Commits [82224764a9](https://github.com/haasn/libplacebo/commit/82224764a9), [c43baa7a0c](https://github.com/haasn/libplacebo/commit/c43baa7a0c), de33d3adb0, eec54224b3.
- Metal: [#370](https://github.com/haasn/libplacebo/issues/370), [#380](https://github.com/haasn/libplacebo/issues/380), [MR !858](https://code.videolan.org/videolan/libplacebo/-/merge_requests/858), [lhc70000/libplacebo@a962968](https://github.com/lhc70000/libplacebo/commit/a96296875a067887fc75d7b74a0a4292422c204d).

**Flutter (HIGH):**
- `engine/src/flutter/shell/platform/linux/fl_opengl_manager.cc` and `fl_engine.cc` @3.47.6.
- `linux/public/flutter_linux/fl_texture_gl.h` and `darwin/common/framework/Headers/FlutterTexture.h` @3.38.0 (unchanged API).

**Versions (HIGH, GitHub tags):**
- SPIRV-Cross / SPIRV-Tools / SPIRV-Headers / glslang `vulkan-sdk-1.4.363.0`.
- shaderc `v2026.4`.
- nv-codec-headers `n13.1.15.0` / `n13.0.19.1`.
- glad `v2.0.8`.

**Reference only (MEDIUM):**
- media_kit `media_kit_video/linux/video_output.cc` and `texture_gl.cc` (isolated EGL context + EGLImage). Its Windows ANGLE route is forbidden for mpv_kit.

**CUDA on GLES (LOW):**
- [CUDA GL interop docs](https://docs.nvidia.com/cuda/cuda-driver-api/cuda_driver_api/group__CUDA__GL.html), [CUDA EGL interop](https://docs.nvidia.com/cuda/cuda-driver-api/cuda_driver_api/group__CUDA__EGL.html), [NVIDIA forum: EGL vs GLX interop](https://forums.developer.nvidia.com/t/using-cuda-to-transfer-texture-between-egl-and-opengl-glx-contexts-in-the-same-process/336421).

---
*Stack research for: mpv_kit v3.0 unified RenderBackend + platform-native graphics backends*
*Researched: 2026-10-26*
