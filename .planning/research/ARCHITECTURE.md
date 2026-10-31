# Architecture Research

**Domain:** Native render pipeline of a Flutter desktop plugin (libmpv render API → zero-copy Flutter external textures) — milestone v3.0, unified `RenderBackend` lifecycle and platform-native graphics backends
**Researched:** 2026-10-26
**Confidence:** HIGH for the code mapping and mpv integration points (read from the vendored tree and plugin sources); MEDIUM for the D3D11/GL synchronisation design (follows from documented API contracts, not yet run); LOW–MEDIUM for Flutter embedder threading details that come from web sources (marked below)

> Replaces the v2.0 file. Phase numbering for v3.0 starts at **Phase 12**.

---

## 0. Answers in one screen

1. **Most of `VideoRenderer` is already API-agnostic.** The render thread, ring bookkeeping (`front_`/`pending_front_`/`in_use_`/`quarantine_`/retired generation), swap reporting, idle detection, backoff, ICC hand-off and event emission do not depend on Vulkan. What does depend on it is about 15% of `video_renderer.cc`: `StartVulkan`, the Vulkan-only branches of `RenderOnce`/`AcquireFront`/`FreeRetiredIfDone`, and the `VK_*` result codes used as wait results. Extract those behind a `RenderBackend` interface. Leave everything else in `VideoRenderer`.
2. **The interface needs one hook the Vulkan code never needed: thread affinity** (`BindThread`/`UnbindThread`). The mpv OpenGL render API requires the GL context to be current on whichever thread calls `mpv_render_context_create`, `_render` or `_free`. Design it into the interface in Phase 12. Otherwise GL forces an interface change later.
3. **No new libmpv symbols.** All three new paths go through the nine generic `mpv_render_context_*` entry points. D3D11 passes its device and target through render params. GL gets `get_proc_address` from the plugin (`eglGetProcAddress`). `MpvApi::kSymbolCount` stays 9 and Dart `_symbols` does not change.
4. **The Windows D3D11 render API needs a new downstream mpv patch (proposed 0010) plus new bundle dependencies.** libplacebo's d3d11 backend needs SPIRV-Cross. mpv's `-Dd3d11` (which provides `ra_d3d11` and `hwdec_d3d11va`, the d3d11va zero-copy mapper) needs shaderc and SPIRV-Cross. Today both are disabled: `-Dd3d11=disabled -Dshaderc=disabled -Dspirv-cross=disabled` in `native/build/build.sh:43,76-77`, and `-Dd3d11=disabled` for libplacebo in `deps.sh:255`.
5. **Linux OpenGL needs no mpv patch for the `gpu` (gl_video) renderer.** It only needs `-Dgl=enabled -Dplain-gl=enabled -Degl=enabled`; today it is `-Dgl=disabled -Degl=disabled` (`build.sh:71`). **But upstream has no gpu-next over the GL render API.** If auto tried "native first" on Linux, it would downgrade current users from Vulkan gpu-next to GL gl_video. So the chain must be ordered by renderer quality first and graphics API second (see §6).
6. **macOS: the existing MoltenVK → IOSurface path already is the Metal route.** libplacebo has no Metal backend, and the OpenGL + IOSurface route is deprecated and gives a worse renderer. VideoToolbox zero-copy is already compiled in (`-Dvideotoolbox-pl=enabled`, `hwdec_vt_pl.m` imports IOSurface through `VK_EXT_metal_objects`) and needs verification, not a new backend.
7. **The public `MpvVideoBackend { vulkan, software }` enum conflicts with honest backend reporting.** Adding values breaks exhaustive `switch`es, so it is not an additive change. Recommendation: keep the enum frozen, extend the **private** wire protocol (`backend: "d3d11"|"opengl"|...`), map every GPU backend to `MpvVideoBackend.vulkan` (re-documented as "GPU zero-copy"), and carry the true API in a machine-checkable `reason` prefix. **This needs explicit user sign-off (ADR).**

---

## 1. Standard Architecture (target)

### System Overview

```
┌──────────────────────────────── Dart (frozen public API) ───────────────────────────────┐
│ MpvVideoController.create(player, renderer: MpvVideoRenderer.{auto,gpuNext,gpu,software})│
│   └─ method channel "create" {symbols[9], handle, renderer}                              │
│      ← {textureId, backend: "d3d11"|"opengl"|"vulkan"|"software", reason}  (private)     │
└───────────────────────────────────────────┬─────────────────────────────────────────────┘
                                            │
┌──────────────────────── Platform plugin (windows/ linux/ macos/) ───────────────────────┐
│  Texture registration per Frame kind      Event marshalling (PostMessage/g_idle_add/     │
│  GpuSurfaceTexture | FlTextureGL |        dispatch_async) — unchanged                    │
│  FlutterTexture | PixelBuffer                                                            │
│  PlatformSink (= today's Interop minus vulkan()): FrameReady, RetainFrame,               │
│  CompositorLatency, SoftwareIsBgra, BackendCandidates(), CreateBackend(kind)             │
└───────────────────────────────────────────┬─────────────────────────────────────────────┘
                                            │
┌──────────────────────── VideoRenderer (src/, API-agnostic) ─────────────────────────────┐
│ render thread · update cb · ring bookkeeping (front/pending/in_use/quarantine/retired)  │
│ publish gate · swap accounting · idle/redraw · backoff · ICC · events · probe           │
│ candidate loop: for (renderer, api) in chain → backend->Create(); first success wins     │
└───────┬─────────────────┬──────────────────┬──────────────────┬─────────────────────────┘
        │ RenderBackend   │                  │                  │
┌───────▼──────┐ ┌────────▼───────┐ ┌────────▼────────┐ ┌───────▼────────┐
│ VulkanBackend│ │ D3D11Backend   │ │ OpenGLBackend   │ │SoftwareBackend │
│ src/         │ │ windows/       │ │ linux/          │ │ src/           │
│ VulkanContext│ │ own ID3D11Dev  │ │ own EGL context │ │ CPU ring       │
│ timeline sem │ │ ID3D11Fence /  │ │ EGLSync fences  │ │ (sync)         │
│ +VulkanInterop│ │ event query    │ │ EGLImage export │ │                │
└──────────────┘ └────────────────┘ └─────────────────┘ └────────────────┘
        │                 │                  │                  │
┌───────▼─────────────────▼──────────────────▼──────────────────▼─────────────────────────┐
│ libmpv (one copy, loaded by Dart) — vo_libmpv.c render_backends[]:                       │
│   render_backend_gpu_next  (vulkan [0001/0004], d3d11 [NEW 0010], opengl [opt. 0011])    │
│   render_backend_gpu       (libmpv_gpu.c: gl [upstream], vk [0001], d3d11 [NEW 0010])    │
│   render_backend_sw                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities (new vs modified, explicit)

| Component | Status | Responsibility | File(s) |
|-----------|--------|----------------|---------|
| `RenderBackend` interface | **NEW** | Graphics-API half of rendering: device, render context creation, target ring storage, render params, GPU-completion waits, thread affinity | `packages/mpv_kit_video/src/render_backend.h` |
| `VideoRenderer` | **MODIFIED** | Keeps the render thread, ring bookkeeping, publish gate, swap/idle/backoff/ICC/events. Loses `vulkan_`, `sw_buffers_`, `sw_retired_`, `StartVulkan`, `StartSoftware` and every `backend_ ==` branch | `src/video_renderer.{h,cc}` |
| `VulkanBackend` | **NEW (extracted, no behaviour change)** | Wraps the existing `VulkanContext` + `VulkanInterop`; holds today's `StartVulkan` body, `mpv_vulkan_image` building, rollback, `initialized` layout state, timeline waits | `src/vulkan_render_backend.{h,cc}` |
| `VulkanContext` / `VulkanInterop` | **UNCHANGED** | Device, queues, timeline, shared-image ring | `src/vulkan_backend.{h,cc}` |
| `SoftwareBackend` | **NEW (extracted, no behaviour change)** | `MPV_RENDER_API_TYPE_SW`, CPU ring + one retired generation, alpha fill, pixel order | `src/software_backend.{h,cc}` |
| `Interop` → `PlatformSink` | **MODIFIED** | `vulkan()` stays (VulkanBackend needs it). Adds `BackendCandidates()` and `CreateBackend(kind)` so each platform offers its own native backend without `src/` including platform headers | `src/video_renderer.h` (or new `src/platform_sink.h`) |
| `D3D11Backend` | **NEW** | Own D3D11 device on Flutter's adapter, `MPV_RENDER_API_TYPE_D3D11` context, ring of `D3D11Interop::Texture` (same struct as today), fence/event-query waits | `windows/d3d11_backend.{h,cpp}` |
| `D3D11Interop` | **MODIFIED (small)** | Reuses `Texture{texture, shared_handle}` for D3D11 targets. Device creation becomes a shared helper (BGRA + optional VIDEO_SUPPORT) | `windows/d3d11_interop.{h,cpp}` |
| `OpenGLBackend` | **NEW** | Own EGL context on Flutter's `EGLDisplay`, `MPV_RENDER_API_TYPE_OPENGL`, per-slot GL texture + FBO exported as `EGLImage`, `EGLSync` waits, DRM render-node fd for vaapi | `linux/gl_backend.{h,cc}` |
| `GlInterop::Image` | **MODIFIED** | Second import kind: `egl_image` next to today's `fd`. `TextureFor()` binds with `glEGLImageTargetTexture2DOES`; the graveyard/orphan logic is reused | `linux/gl_interop.{h,cc}` |
| Platform plugins | **MODIFIED (small)** | Texture kind and wire name from `renderer->backend()` through one helper instead of `vk ? "vulkan" : "software"` | `windows/mpv_kit_video_plugin.cpp:216,238,243`; `linux/mpv_kit_video_plugin.cc:327,355`; `macos/Classes/MpvKitVideoPlugin.mm:92,251,261` |
| Build files | **MODIFIED** | Add new sources | `windows/CMakeLists.txt:25-29`, `linux/CMakeLists.txt:30-34`, `macos/Classes/shared_sources.cpp` (unity includes) |
| Dart controller | **MODIFIED (private only)** | Accept the new wire names, map them to the frozen enum, document `.vulkan` as "GPU zero-copy" | `lib/src/video_controller.dart:13,182-183,200-202` |
| mpv patch 0010 | **NEW** | D3D11 render API: `render_d3d11.h`, `libmpv_d3d11.c`, gpu-next libmpv path generalised beyond Vulkan | `native/patches/0010-libmpv-d3d11-render-backend.patch` |
| mpv patch 0011 | **NEW, optional** | gpu-next over the upstream GL render API (`pl_opengl`) | `native/patches/0011-libmpv-gpu-next-opengl.patch` |
| mpv patch (0004 follow-up) | **MODIFIED** | Add native resources (`MPV_RENDER_PARAM_DRM_DISPLAY_V2`) to the gpu-next libmpv init, which skips them today, so vaapi gets a VA display | fold into 0004 or 0010 |
| Native tests | **NEW** | `render_d3d11_smoke.c` (WARP), `render_gl_smoke.c` (EGL surfaceless/llvmpipe), fake-libmpv `video_renderer_test.cc` | `native/tests/`, `meson.build` |
| Bundle build | **MODIFIED** | Windows: SPIRV-Cross (+ shaderc), libplacebo `-Dd3d11=enabled`, mpv `-Dd3d11=enabled`. Linux: mpv `-Dgl -Dplain-gl -Degl`, optionally libplacebo `-Dopengl=enabled`. Allowlists and the ABI audit change to match | `native/build/{deps,build,package}.sh`, `tools/rea_abi_audit/pe_audit.py` |

---

## 2. Today's responsibilities mapped to RenderBackend steps

The user-proposed steps are Create / AllocTarget / Render / FrameReady / Release / Destroy. `FrameReady` is not a graphics-API concern: it is the Flutter texture notification, already in `Interop::FrameReady()`. It stays on the platform side. The backend needs two extra steps instead: **Wait** (GPU completion, which is the publish gate) and **BindThread/UnbindThread**.

| Code today (`video_renderer.cc`) | Lines | Generic or API-specific | Goes to |
|---|---|---|---|
| Destructor: quit, join, `set_update_callback(null)`, `render_context_free`, `vulkan_.reset()` | 26-40 | Generic order, API-specific teardown | `VideoRenderer` keeps the order. `backend_->Release(ctx)` (free the render context **before** the device) → `backend_->Destroy()` |
| `Start`: quarantine/ring sizing from `CompositorLatency()` | 42-46 | Generic | `VideoRenderer` |
| `Start`: Vulkan-then-software decision, reason strings | 47-62 | Generic policy, hard-coded to 2 APIs | `VideoRenderer::Start` candidate loop over `(renderer, api)` pairs (§6) |
| `StartVulkan`: `VulkanContext::Init`, `mpv_vulkan_init_params`, gpu-next→gpu loop, `get_info(VULKAN_RENDERER)`, reason | 70-132 | Vulkan-specific (the renderer loop and get_info are generic) | `VulkanBackend::Create(renderer)`. The renderer loop moves up into the candidate loop. `get_info` becomes a shared helper |
| `StartSoftware` | 134-150 | SW-specific | `SoftwareBackend::Create` |
| `OnMpvUpdate`, `Emit`, `SetSize` | 152-176 | Generic | `VideoRenderer` |
| `SetIccProfile`/`ApplyIccProfile` (`MPV_RENDER_PARAM_ICC_PROFILE`) | 178-205 | Generic (render API param; mpv decides support) | `VideoRenderer`. Works for gpu-next on Vulkan and D3D11 (0004's `libmpv_set_parameter`) and for gl_video on GL. Software rejects it and logs, as today |
| `AcquireFront`: present/swap flag, idle resume, quarantine shift, retired countdown | 207-244 | Generic | `VideoRenderer` |
| `AcquireFront`: `sw_buffers_[front_].data()` vs `vulkan_->ring()[front_].platform` + `RetainFrame` | 245-250 | API-specific lookup | `backend_->FrameFor(slot)` → `{platform \| pixels}`. `RetainFrame` stays on the platform side |
| `PickBackBuffer` | 258-270 | Generic | `VideoRenderer` |
| `FreeRetiredIfDone`: `sw_retired_.clear()` + `vulkan_->FreeRetired()` | 272-282 | Generic countdown, API-specific free | `backend_->FreeRetired()` |
| `RenderLoop` (wait, deadlines, update, idle/skip, backoff gate) | 284-367 | Generic | `VideoRenderer`. Adds `backend_->BindThread()` on entry and `UnbindThread()` on exit |
| `OnRenderResult` (backoff doubling, recovered/device_lost/gpu_timeout events) | 369-397 | Generic (the "Vulkan device lost" log text is not) | `VideoRenderer`; the log text becomes `backend_->name()` |
| `SkipFrame` (`SKIP_RENDERING` + `report_swap`) | 399-410 | Generic | `VideoRenderer` |
| `RenderOnce` publish gate: `WaitImage(pending_front_)`, probe, swaps, `FrameReady` | 417-467 | Generic logic, Vulkan wait | `VideoRenderer`, through `backend_->Wait(slot)` → `{kOk, kTimeout, kDeviceLost}` (replaces `VkResult`). Only when `backend_->pipelined()` |
| `RenderOnce` realloc: retire front, `AllocateRing`, 8K ring-fallback retry, `Emit("resize")` | 469-542 | Generic policy, API-specific allocation | `VideoRenderer` keeps the policy (including the ring-of-5 retry); `backend_->AllocTargets(count, w, h, keep_slot, &err)` |
| `RenderOnce` Vulkan render: `WaitImage(back)`, `mpv_vulkan_image`, `NextSignalValue`, rollback, `initialized` | 545-595 | Vulkan-specific | `VulkanBackend::Render(slot, ctx, &err)`. The reuse wait moves to `VideoRenderer` as `backend_->Wait(back)` |
| `RenderOnce` software render: `SW_SIZE/FORMAT/STRIDE/POINTER`, alpha fill | 596-611 | SW-specific | `SoftwareBackend::Render` |
| `RenderOnce` immediate publish + swaps (duplicate of lines 447-466) | 619-640 | Generic | `VideoRenderer::PublishLocked()`, one helper for both paths. **Refactor carefully:** the two copies differ only in where `front_` comes from |
| Sync-wait probe (prev/done waits, 120-frame window) | header 186-194 | Generic (measures `Wait`) | `VideoRenderer` |

**Not in the native renderer at all (unchanged by v3.0):** display-fps (Dart sets `display-fps-override`; the plugin only answers `getDisplayRefreshRate`), the shader cache dir (Dart sets `gpu-shader-cache-dir` before create), dispose ordering (`Player.addDisposeHook`).

### Proposed interface (sketch)

```cpp
// src/render_backend.h — graphics-API half of a VideoRenderer.
enum class BackendKind { kD3D11, kOpenGL, kVulkan, kSoftware };
enum class WaitResult { kOk, kTimeout, kDeviceLost };

/// What the platform texture needs for one ring slot.
struct TargetView { void* platform = nullptr; const uint8_t* pixels = nullptr; };

class RenderBackend {
 public:
  virtual ~RenderBackend() = default;
  virtual BackendKind kind() const = 0;
  virtual const char* wire_name() const = 0;          // "d3d11" | "opengl" | "vulkan" | "software"

  /// Thread affinity. GL: eglMakeCurrent / release. Others: no-op.
  /// VideoRenderer calls Bind on the creating thread around Create, on the
  /// render thread for its whole lifetime, and around Release.
  virtual bool BindThread() { return true; }
  virtual void UnbindThread() {}

  /// Device + mpv_render_context for one renderer ("gpu-next" | "gpu" | "sw").
  /// On failure *reason says why; nothing stays allocated.
  virtual bool Create(const MpvApi& api, mpv_handle* h, const char* renderer,
                      mpv_render_context** out, std::string* reason) = 0;
  /// Human-readable device for the reason string ("NVIDIA GeForce RTX 4060").
  virtual std::string device_name() const = 0;

  /// (Re)allocates the ring; only [keep_slot] of the old generation survives
  /// into retirement (today's AllocateRing contract).
  virtual bool AllocTargets(int count, int w, int h, int keep_slot, std::string* err) = 0;
  virtual void FreeRetired() = 0;
  virtual TargetView FrameFor(int slot) const = 0;
  virtual TargetView RetiredFront() const = 0;

  /// Renders into [slot]; signals that slot's completion value on success only.
  virtual int Render(const MpvApi& api, mpv_render_context* ctx, int slot, std::string* err) = 0;
  /// GPU work for [slot] finished (1 s bound). Software: always kOk.
  virtual WaitResult Wait(int slot) = 0;
  /// True: publish behind Wait at the next round (GPU). False: publish at once (SW).
  virtual bool pipelined() const = 0;

  /// Frees the render context (with the thread bound), then the targets. Device last, in ~dtor.
  virtual void Release(const MpvApi& api, mpv_render_context* ctx) = 0;
};
```

The names follow the user's list: Create, AllocTarget(s), Render, Release, Destroy (= destructor). FrameReady stays on `PlatformSink`.

---

## 3. Threading per platform

### Windows — D3D11

| Object | Owner thread | Notes |
|---|---|---|
| `ID3D11Device` (one per controller) | Created on the platform thread in `Create`. Device methods (`CreateTexture2D`) are free-threaded | Create it on **Flutter's adapter** (`GetGraphicsAdapter()`, as `D3D11Interop` does today) with `BGRA_SUPPORT \| VIDEO_SUPPORT`, retrying without `VIDEO_SUPPORT` (likely needed on WARP/Basic Render Driver — **verify**). **Separate device, never Flutter's:** Flutter's device is ANGLE's, which our chain must not use (user rule), and Flutter exposes no device API to plugins |
| Immediate context | Render thread only (mpv render, our fence `Signal`/`Flush`) + FFmpeg's d3d11va decode thread | mpv's `hwdec_d3d11va.c` init sets `ID3D10Multithread::SetMultithreadProtected(TRUE)` on the device (`hwdec_d3d11va.c:127-137`). The backend should set it itself at creation too (idempotent), so its own calls on the context are serialised against the decoder even when hwdec is off at init and enabled later. The raster thread **never** touches the context: `Describe` only reads `shared_handle`, and the release callback only calls `Release()` |
| Shared textures | Ring created on the render thread (AllocTargets), handed out under the renderer lock | Keep the **legacy KMT handle** (`D3D11_RESOURCE_MISC_SHARED` + `GetSharedHandle`), exactly what `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle` and ANGLE open today (`d3d11_interop.cpp:99`). Bind flags: `RENDER_TARGET \| SHADER_RESOURCE`, plus `UNORDERED_ACCESS` when `CheckFormatSupport2` reports typed UAV store for BGRA8 (lets libplacebo use compute; **verify** per adapter) |

**Synchronisation without keyed mutex (recommended).** Phase 10's REA established that Flutter's consumer binds the handle through ANGLE and releases immediately, with no fence and no keyed mutex (ADR 0003, `docs/ARCHITECTURE.md` §Frame ring). A keyed mutex would only help if the consumer acquired it, and it does not. So the D3D11 backend reuses the Vulkan model exactly:

- **Reuse gate + publish gate = per-slot completion value.** After a successful `mpv_render_context_render`, the backend calls `ID3D11DeviceContext4::Signal(fence, ++value)` and `Flush()` on the same immediate context. Ordering is guaranteed: libplacebo's d3d11 backend submits only on the immediate context, and the call returns after submission. `Wait(slot)` means `fence->GetCompletedValue() >= ready[slot]`, otherwise `SetEventOnCompletion` + `WaitForSingleObject(event, 1000)` → `kTimeout`. A device-removed `HRESULT` from `GetDeviceRemovedReason` maps to `kDeviceLost`.
- **Fallback when `ID3D11Device5`/fences are unavailable** (Windows 10 before 1703, possibly WARP — **verify on the CI runner**): one `D3D11_QUERY_EVENT` per slot, `End()` after render, poll `GetData(DONOTFLUSH)` with a 1 s deadline. Same `Wait` contract.
- Quarantine stays `CompositorLatency() == 4` (ring of 7). The consumer side is unchanged, so the reason for the value is unchanged.
- **Host-side signalling, not an mpv render param.** It keeps patch 0010 smaller than `render_vk.h`'s semaphore contract. It is correct because D3D11 has a single in-order immediate context. Document this in `render_d3d11.h`: "all GPU work for the frame is submitted to the device's immediate context and flushed before `mpv_render_context_render` returns".

**Frame-ready:** `TextureRegistrar::MarkTextureFrameAvailable(id)`, called from the render thread through `Interop::FrameReady()` (`mpv_kit_video_plugin.cpp:197-200`). It is thread-safe and unchanged. The texture variant (`GpuSurfaceTexture`, DXGI shared handle) and `Describe` (`:273-291`) stay the same for Vulkan and D3D11, because both hand out `D3D11Interop::Texture`.

### Linux — OpenGL

**Recommendation: render on our own render thread with our own EGL context, and hand frames to Flutter through EGLImage siblings. Do not render inside `FlTextureGL::populate` (the fvp style).**

| Option | Verdict | Why |
|---|---|---|
| A. Own EGL context on Flutter's `EGLDisplay` (`FlutterEglDisplay()`, `gl_interop.cc:41`), no share group, frames as `EGLImage` (`EGL_KHR_gl_texture_2D_image`), imported in populate with `glEGLImageTargetTexture2DOES` | **Use** | Keeps the single-render-thread architecture and pipeline depth 2. mpv's GL state changes never touch Flutter's context. Needs no access to Flutter's `EGLContext` at create time (the create response must be synchronous). Mesa llvmpipe has all of the extensions, so it is CI-verifiable on xvfb |
| B. Own context in Flutter's share group (`eglCreateContext(..., share = Flutter ctx)`) | Avoid | Flutter's context is only observable inside populate (`eglGetCurrentContext()`), so creation would happen lazily on the raster thread and "create" could not report a backend. A shared namespace means a bug on our side can delete Flutter objects |
| C. Render inside populate (raster thread, Flutter's context current) | Reject | 10–20 ms gpu-next/8K renders block the raster thread, which on Linux has historically been the GTK main thread (flutter#84930, LOW). mpv mutates GL state under Flutter's renderer. It loses `report_swap` timing and the idle logic. It also inverts the whole `VideoRenderer` model |

Details for option A:
- **Context ownership:** `BindThread()` = `eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)` (surfaceless, `EGL_KHR_surfaceless_context`, already required in `ProbeGl`). `VideoRenderer` binds on the platform thread around `Create` (mpv's `libmpv_gl` init calls `glGetString`), unbinds, then the render thread binds for its lifetime, and the destructor binds again around `render_context_free`. Wrap the platform-thread binds in the existing `EglCurrentGuard` **and** call `gdk_gl_context_clear_current()` first. Under libglvnd + X11, `eglMakeCurrent` on the GTK thread fails with `EGL_BAD_ACCESS` while a GLX `GdkGLContext` is current (flutter PR #193530, LOW–MEDIUM).
- **Targets:** each slot is a GL texture (`GL_RGBA8`, the only format Flutter accepts) + FBO in our context, plus an `EGLImageKHR`. `Render` passes `MPV_RENDER_PARAM_OPENGL_FBO {fbo, w, h, GL_RGBA8}` and `FLIP_Y` = 0, matching the texture orientation Flutter samples (**verify** with a pixel probe; gl_video renders bottom-up to FBO 0 only).
- **Sync:** after render, `eglCreateSyncKHR(EGL_SYNC_FENCE_KHR)` + `glFlush`. `Wait(slot)` = `eglClientWaitSyncKHR(sync, EGL_SYNC_FLUSH_COMMANDS_BIT_KHR, 1 s)` → `kTimeout`. Context loss: create the context with `EGL_EXT_create_context_robustness` (reset notification) when available. `glGetGraphicsResetStatus() != GL_NO_ERROR` → `kDeviceLost`.
- **Flutter side:** `GlInterop::Image` gets an `egl_image` member. `TextureFor()` creates the Flutter-context texture once per slot and calls `glEGLImageTargetTexture2DOES`. The graveyard/orphan logic (`gl_interop.cc:262-286`) stays: our-context texture deletion happens on the render thread after quarantine, the Flutter-context sibling is deleted in populate, and `eglDestroyImageKHR` may follow once both siblings exist (siblings keep the storage alive).
- **Frame-ready:** `fl_texture_registrar_mark_texture_frame_available` from the render thread (`mpv_kit_video_plugin.cc:311-314`), unchanged. The texture class (`MpvKitGlTexture`/FlTextureGL) is reused for both Vulkan and OpenGL frames.
- **vaapi zero-copy:** under libmpv, with `-Dx11/-Dwayland=disabled`, vaapi only gets a VA display from `MPV_RENDER_PARAM_DRM_DISPLAY_V2.render_fd` (`hwdec_vaapi.c:63-69`). The GL backend opens the render node of the EGL device (`EGL_EXT_device_query` → `EGL_DRM_RENDER_NODE_FILE_EXT`) and passes it at create. `render_backend_gpu` forwards it as a native resource automatically (`libmpv_gpu.c:76-89`). Then `dmabuf_interop_gl` imports the frames (needs `-Degl` + libdrm). **The same fd also unlocks vaapi on the existing Vulkan gpu-next path** (`dmabuf_interop_pl`; the dma-buf/DRM-modifier extensions are already in `kOptionalDeviceExtensions`). That path needs the gpu-next libmpv init to add native resources, which it skips today (`vo_gpu_next.c:3126-3181`).
- **nvdec:** FFmpeg needs `--enable-ffnvcodec --enable-nvdec` (nv-codec-headers, MIT; the driver is dlopened, not nonfree) and mpv `cuda-hwaccel`/`cuda-interop` (`hwdec_cuda_gl.c`/`hwdec_cuda_vk.c`). Neither is built today. **No NVIDIA Linux hardware exists in the project and none on CI.** Treat it as "build-enabled, unverified" or defer it explicitly.

### macOS — Metal route

| Route | Cost | Quality | Verdict |
|---|---|---|---|
| MoltenVK → IOSurface (existing Vulkan backend, `VK_EXT_metal_objects`) | Zero new code; it is the v1/v2 path | gpu-next, libplacebo, `videotoolbox-pl` zero-copy (`hwdec_vt_pl.m` imports IOSurface → Metal → Vulkan) | **Adopt as the macOS "native" backend** |
| OpenGL (CGL) + IOSurface (`CGLTexImageIOSurface2D`, `hwdec_mac_gl.c`) | New backend + mpv `-Dgl`/cocoa-free GL plumbing | gl_video only on GL 4.1 (deprecated since 10.14), worse HDR | Reject |
| Own Metal render API | libplacebo has **no Metal backend**; would need a new `ra` + shader pipeline | n/a | Reject (rewrite-scale, conflicts with the change-size constraint) |

Threading and frame-ready stay as today: `textureFrameAvailable:` from the render thread (`MpvKitVideoPlugin.mm:226-229`), `copyPixelBuffer` returning +1 retained `CVPixelBuffer`. macOS work in v3.0 is an ADR + `reason` reporting ("vulkan (gpu-next) on Apple M… via MoltenVK") + a VideoToolbox zero-copy verification (check `hwdec-current=videotoolbox` and the absence of copy-back).

### Sync and notification summary

| | Vulkan (today) | D3D11 (new) | OpenGL (new) | Software |
|---|---|---|---|---|
| Completion primitive | timeline `VkSemaphore`, signalled by mpv (`signal_value`) | `ID3D11Fence` signalled by host after render (fallback `QUERY_EVENT`) | `EGLSyncKHR` fence after render | none (sync CPU) |
| `Wait` timeout → event | 1 s → `gpu_timeout` | 1 s → `gpu_timeout` | 1 s → `gpu_timeout` | n/a |
| Loss → `device_lost` | `VK_ERROR_DEVICE_LOST` | `DXGI_ERROR_DEVICE_REMOVED/RESET` | robustness reset status | n/a |
| Consumer sync | none (quarantine) | none (quarantine) | none (quarantine) | copy callback |
| Frame-ready | platform `FrameReady()` from render thread, same on all paths | same | same | same |
| Quarantine | Windows 4 / others 2 | 4 | 2 | (one retired generation) |

---

## 4. mpv-side integration (patch design)

How the render API is put together today (read from the vendored tree):
- `vo_libmpv.c:119-126` `render_backends[] = { gpu_next (HAVE_VULKAN), gpu, sw }`. Each `init` returns `MPV_ERROR_NOT_IMPLEMENTED` for API types it does not handle.
- `render_backend_gpu` (`gpu/libmpv_gpu.c`) picks a `libmpv_gpu_context_fns` by `api_name` from `context_backends[]` (gl upstream, vk from 0001). It adds native resources (`:76-89`) and runs gl_video.
- `render_backend_gpu_next` (0004, `vo_gpu_next.c:3100-3367`) is `#if HAVE_VULKAN`. It hard-wires `.fns = &libmpv_gpu_context_vk` (`:3147`), takes `pl_gpu` via `ra_pl_get(ra)` (`:3163`) and treats `tex->priv` as a `pl_tex` (`:3287`), which only holds for `ra_pl`.
- The renderer report (`MPV_RENDER_PARAM_VULKAN_RENDERER`, `vo_libmpv.c:490-500`) is `#if HAVE_VULKAN` and Vulkan-named.

### Proposed patch 0010 — `libmpv-d3d11-render-backend`

| File | Status | Content |
|---|---|---|
| `include/mpv/render_d3d11.h` | NEW (installed) | `MPV_RENDER_API_TYPE_D3D11 "d3d11"`; `MPV_RENDER_PARAM_D3D11_INIT_PARAMS ((mpv_render_param_type)0x6d6b0011)` → `mpv_d3d11_init_params { ID3D11Device *device; }` (mpv AddRefs; must outlive `mpv_render_context_free`); `MPV_RENDER_PARAM_D3D11_TEXTURE (0x6d6b0012)` → `mpv_d3d11_texture { ID3D11Texture2D *texture; int width, height; }` (BGRA8/RGBA8, `USAGE_DEFAULT`, `BIND_RENDER_TARGET`). Threading and sync contract as in §3. Plain C struct: the plugin is MSVC, libmpv is MSYS2 clang, and COM pointers are ABI-stable |
| `video/out/d3d11/libmpv_d3d11.c` | NEW | `libmpv_gpu_context_d3d11`, the analogue of `libmpv_gl.c`/`libmpv_vk.c`: `init` = `spirv_compiler_init` + `ra_d3d11_create(device)` into a blank `ra_ctx`; `wrap_fbo` = `ra_d3d11_wrap_tex`; `done_frame` = `ra_d3d11_flush`; `destroy`. Registering it in `libmpv_gpu.c context_backends[]` gives the **gpu** renderer on D3D11 for free |
| `video/out/gpu/libmpv_gpu.{c,h}` | MODIFIED | `extern libmpv_gpu_context_d3d11` + list entry under `HAVE_D3D11` |
| `video/out/vo_gpu_next.c` (libmpv section) | MODIFIED | Guard `HAVE_VULKAN \|\| HAVE_D3D11`. Pick context fns by API type. Derive `pl_gpu`: Vulkan `ra_pl_get`; D3D11 `pl_d3d11_create(pllog, {.device = ra_d3d11_get_device(ra)})`, owned by `libmpv_priv` and destroyed after `uninit` (mirrors `gpu_next/context.c:54-90` without the swapchain). Wrap the target: Vulkan `tex->priv`; D3D11 `pl_d3d11_wrap(gpu, raw)`, destroyed after `draw_frame`. hwdec mapping already handles `ra_is_d3d11` (`:776-792`). **Attach the persistent `pl_cache` for D3D11 too:** `D3DCompile` is slow, and today's cache attach lives in `libmpv_vk` (0003) |
| `video/out/vo_libmpv.c` | MODIFIED | `render_backends[]` includes gpu-next under `HAVE_VULKAN \|\| HAVE_D3D11`. The renderer `get_info` stops being Vulkan-gated: document `0x6d6b0003` as the API-independent renderer selector/report (keep the `VULKAN_RENDERER` name as the alias) |
| `meson.build` | MODIFIED | `libmpv_d3d11.c` under `features['d3d11']`; install `render_d3d11.h` |
| `DOCS/client-api-changes.rst` | MODIFIED | Note, like 0001 |

The PATCH-DRIFT gate (`tools/check_patches.sh`) requires base + patches == vendor byte-for-byte. Author the change in `native/mpv`, then regenerate 0010. Use the next free number (0009 = backports).

**Bundle consequences (prerequisite for 0010):** libplacebo `-Dd3d11=enabled` needs `spirv-cross-c-shared` (libplacebo `src/d3d11/meson.build`, MEDIUM). mpv `-Dd3d11` requires `shaderc` **and** `spirv-cross` (`meson.build:1079-1081`), and `ra_d3d11_create` dereferences the SPIR-V compiler (`ra_d3d11.c:2399-2402`). Both are Apache-2.0, so the LGPL bundle is fine. MSYS2 ships both for CLANG64 and CLANGARM64 (**verify** arm64 availability). `d3dcompiler_47.dll` is a system DLL. The `pe_audit.py` import allowlist and `package.sh` must learn the new DLLs. An alternative that avoids shaderc is a "null SPIR-V compiler" stub, so `ra_d3d11` exists only for texture wrapping (d3d11va) and the **gpu** renderer on D3D11 is unavailable (`MpvVideoRenderer.gpu` → Vulkan gpu on Windows). It is a smaller bundle but more patch surface. **Default to bundling shaderc** (zero mpv source change for `ra_d3d11`/`hwdec_d3d11va`).

### Optional patch 0011 — `libmpv-gpu-next-opengl`

Extends the same generalised libmpv path to `MPV_RENDER_API_TYPE_OPENGL` + renderer "gpu-next": `pl_opengl_create(.get_proc_addr_ex = gl->get_fn, egl display/context from current)`, target `pl_opengl_wrap(gpu, {.framebuffer = fbo->fbo, .width, .height})`. Hwdec already handles `ra_is_gl` (`vo_gpu_next.c:763-773`). Needs libplacebo `-Dopengl=enabled` (no new external deps). This is the "gpu-next on the existing GL API" step upstream maintainers asked for first (`UPSTREAM.md`, 0001 row). **Without it, Linux GL is a fallback tier, not first choice** (§6).

### Native-resource follow-up (fold into 0004 or 0010)

Copy the `native_resource_map` loop (`libmpv_gpu.c:76-89`) into the gpu-next `libmpv_init`, so `MPV_RENDER_PARAM_DRM_DISPLAY_V2` reaches `hwdec_vaapi` on gpu-next (Vulkan today, GL with 0011).

---

## 5. Method channel and Dart protocol (public API frozen)

| Item | Change | Public API impact |
|---|---|---|
| `create` request `{symbols[9], handle, renderer}` | **None.** Symbols stay 9 (`mpv_api.h:30`, Dart `_symbols`). `renderer` keeps the four wire names | none |
| `create` response `backend` | Native sends `"d3d11"`, `"opengl"`, `"vulkan"` or `"software"` (from `RenderBackend::wire_name()`) | none (private wire) |
| Dart validation (`video_controller.dart:182-183`) | Accept the 4 names; still throw `render_init` on anything else (keeps the Phase 2 STAB-04 decision) | none |
| Dart mapping (`:200-202`) | `software` → `MpvVideoBackend.software`; every other name → `MpvVideoBackend.vulkan`, doc changed to "GPU zero-copy backend (Vulkan or the platform-native API named in [reason])" | doc-only. **Needs user sign-off**: honest but imperfect. Adding `d3d11`/`opengl` enum values is a breaking change (exhaustive switches), so it is deferred |
| `reason` grammar | `"<api> (<renderer>) on <device>[; <api>/<renderer> unavailable: <why>]*"`, e.g. `d3d11 (gpu-next) on NVIDIA GeForce RTX 4060`, `vulkan (gpu-next) on llvmpipe; d3d11/gpu-next unavailable: …`, `software (…)`. The first token is the wire name | none. CI asserts the prefix, so backend identity is testable without new API |
| Events | Same kinds. `device_lost` doc becomes "GPU device lost". D3D11 device-removed and GL reset map to it | doc-only |
| Diagnostic override | Native-side env `MPV_KIT_VIDEO_API=d3d11\|opengl\|vulkan` (read by `VideoRenderer::Start` and restricting the candidate list), parallel to the existing `MPV_KIT_VIDEO_RENDERER` | none (env, like the existing override). **Required for CI** to keep exercising Vulkan on Windows/Linux after a native backend becomes the default |
| `softwareFallback` event | Unchanged (still driven by `backend == software`) | none |

Existing consumers that keep working: `example/integration_test/impeller_smoke_test.dart:279` (`backend == vulkan`) and `test/controller_channel_test.dart:78`. Add channel tests for the new wire names and the malformed-name rejection.

---

## 6. Candidate chain (auto fallback through the existing enum)

Order by **renderer quality first, graphics API second**, so auto never downgrades a working gpu-next user:

| Requested | Windows | Linux (no 0011) | Linux (with 0011) | macOS |
|---|---|---|---|---|
| `auto` | d3d11/gpu-next → vulkan/gpu-next → d3d11/gpu → vulkan/gpu → sw | vulkan/gpu-next → opengl/gpu → vulkan/gpu → sw | opengl/gpu-next → vulkan/gpu-next → opengl/gpu → vulkan/gpu → sw | vulkan/gpu-next → vulkan/gpu → sw |
| `gpuNext` | d3d11/gpu-next → vulkan/gpu-next → sw | vulkan/gpu-next → sw | opengl/gpu-next → vulkan/gpu-next → sw | vulkan/gpu-next → sw |
| `gpu` | d3d11/gpu → vulkan/gpu → sw | opengl/gpu → vulkan/gpu → sw | same | vulkan/gpu → sw |
| `software` | sw | sw | sw | sw |

- The chain is **data** returned by `PlatformSink::BackendCandidates()`, not code. A newly added backend can be rolled back on its own by removing it from the list (change-size constraint).
- Device creation is per API, not per renderer. A backend that failed `Init` is skipped for later renderers (today's `StartVulkan` resets `vulkan_` per attempt; keep "one device init per API per Start").
- **Behaviour-change check:** Windows `auto` changes from Vulkan to D3D11. That is the point of the milestone, but it is a **visible** change. Make it a single, reviewed list edit in its own commit, after the D3D11 backend is green on CI and on the RTX 4060.

---

## 7. Data flow changes

### Frame path (unchanged shape, API-specific steps marked)

```
mpv update cb ──► VideoRenderer cv ──► render thread [BindThread once]
   │ render_context_update
   │ publish gate: backend->Wait(pending_front_)  ◄── VK timeline | D3D11 fence | EGLSync
   │   └─ front_ = pending; swaps; PlatformSink::FrameReady() ─► MarkTextureFrameAvailable /
   │                                                            fl_..._mark_texture_frame_available /
   │                                                            textureFrameAvailable
   │ realloc? backend->AllocTargets(ring, w, h, keep_front)
   │ back = PickBackBuffer(); backend->Wait(back)         (reuse gate)
   │ backend->Render(slot)   ◄── VULKAN_IMAGE | D3D11_TEXTURE | OPENGL_FBO | SW_POINTER
   └─ pipelined ? pending_front_ = back : PublishLocked(back)
compositor ──► AcquireFront() ──► backend->FrameFor(front_) ──► RetainFrame ──► texture
```

### Create / dispose path

```
create:  plugin → VideoRenderer::Start(choice)
           for (renderer, api) in candidates (filtered by MPV_KIT_VIDEO_API):
             backend = sink->CreateBackend(api)       (device, once per api)
             backend->BindThread(); backend->Create(...); backend->UnbindThread()
           set_update_callback; spawn render thread
         → {textureId, backend: wire_name, reason}
dispose: quit + join (render thread UnbindThread on exit)
         set_update_callback(null)
         backend->BindThread(); backend->Release(ctx)   // render context BEFORE device
         backend->UnbindThread(); backend.reset()        // device last
         (Player core destroyed afterwards by Dart — ordering unchanged)
```

---

## 8. Recommended project structure

```
packages/mpv_kit_video/
├── src/                              # API-agnostic + cross-platform backends
│   ├── mpv_api.h                     # unchanged (9 symbols)
│   ├── render_backend.h              # NEW interface + BackendKind/WaitResult
│   ├── video_renderer.{h,cc}         # MODIFIED: generic engine only
│   ├── vulkan_backend.{h,cc}         # unchanged: VulkanContext/VulkanInterop
│   ├── vulkan_render_backend.{h,cc}  # NEW: RenderBackend over VulkanContext
│   ├── software_backend.{h,cc}       # NEW
│   └── include/mpv/render_d3d11.h    # NEW vendored copy (like render_vk.h)
├── windows/
│   ├── d3d11_interop.{h,cpp}         # MODIFIED: shared device helper, Texture reuse
│   ├── d3d11_backend.{h,cpp}         # NEW
│   └── mpv_kit_video_plugin.cpp      # MODIFIED: wire name helper
├── linux/
│   ├── gl_interop.{h,cc}             # MODIFIED: EGLImage import kind
│   ├── gl_backend.{h,cc}             # NEW
│   └── mpv_kit_video_plugin.cc       # MODIFIED
└── macos/Classes/                    # MODIFIED: shared_sources.cpp includes new src files
native/
├── patches/0010-libmpv-d3d11-render-backend.patch   # NEW
├── patches/0011-libmpv-gpu-next-opengl.patch        # NEW, optional
└── tests/{render_d3d11_smoke.c, render_gl_smoke.c, video_renderer_test.cc}  # NEW
```

**Structure rationale:** API-specific backends live in the platform folder that is the only one able to compile them (D3D11 headers on Windows, EGL/epoxy on Linux). Cross-platform ones (Vulkan, software) live in `src/`. `src/` never includes platform headers. It sees platform backends only through `PlatformSink::CreateBackend`.

---

## 9. Architectural patterns

### Pattern 1: Lock behaviour with a fake libmpv before moving code

**What:** `MpvApi` is a table of function pointers (`mpv_api.h:12-27`), so `VideoRenderer` can run against fake `render_context_*` functions and a `FakeBackend` with scripted `Wait` results. Golden tests pin quarantine rotation, the publish gate, swap counts, idle/active, backoff doubling, the ring-fallback retry and the retired-front countdown.
**When:** first thing in Phase 12, before extraction. The test must pass unchanged before and after.
**Trade-offs:** it needs a small native test target (meson in `native/tests` or a CMake test in the plugin). It is the only way to prove "no behaviour change" deterministically. The real-plugin CI test only shows that one frame renders.

### Pattern 2: Thread-affinity hooks in the interface, no-op by default

**What:** `BindThread`/`UnbindThread` are called by `VideoRenderer` at the three points where mpv requires the GL context (create, render loop, free).
**When:** always. Vulkan, D3D11 and software ignore them.
**Trade-offs:** a little more ceremony in `VideoRenderer`. It avoids moving create/free onto the render thread, which would change today's synchronous `Start` semantics.

### Pattern 3: Completion values everywhere

**What:** every GPU backend exposes "slot N is done" as a monotonic value per slot (VK timeline, D3D11 fence, EGL sync per slot), with rollback when a render fails before signalling (`RollbackSignalValue` today).
**When:** all pipelined backends.
**Trade-offs:** the D3D11 query-event fallback is polling, not blocking. Acceptable on the 1 s path.

### Pattern 4: Platform image adapters instead of new texture types

**What:** a new backend produces the **same** platform payload the plugin already knows: `D3D11Interop::Texture` on Windows, `GlInterop::Image` (new `egl_image` kind) on Linux. `Describe`/`populate`/`copyPixelBuffer` barely change.
**Trade-offs:** `GlInterop::Image` grows a variant, which is cheaper than a second FlTextureGL class.

---

## 10. Suggested build order (phases from 12)

| Phase | Content | Depends on | CI-verifiable on runners | Needs real hardware |
|---|---|---|---|---|
| **12 — RenderBackend seam** | Fake-libmpv golden tests (Pattern 1) → extract `RenderBackend`, `VulkanRenderBackend`, `SoftwareBackend`; `PlatformSink` candidate list (Vulkan, software only); `wire_name()` + reason grammar; Dart accepts the new wire names (unused yet); `MPV_KIT_VIDEO_API` override | — | Yes. Golden tests on all three; real-plugin test on Linux (xvfb + lavapipe), Windows, macOS; sanitizers | Windows RTX 4060 4K 30-min regression against the Phase 4 baseline ("no behaviour change") |
| **13 — macOS route decision** | ADR "MoltenVK is the Metal route"; reason shows `via MoltenVK`; VideoToolbox zero-copy check on the existing path | 12 (reason grammar) | Mostly: macOS-15 runner has Metal; VT decode in the VM is **unverified** | Optional |
| **14 — Windows D3D11 backend** | (a) bundle: SPIRV-Cross + shaderc, libplacebo/mpv `-Dd3d11`, audit allowlists; (b) patch 0010 + `render_d3d11_smoke.c` on a WARP device; (c) `D3D11Backend` + fence/query waits; (d) add `d3d11` to the Windows candidate list as its own commit | 12 | Yes for rendering: windows-2025 has no GPU, so Flutter's adapter is the Basic Render Driver (WARP) and both the native smoke test and the real-plugin test exercise D3D11. Forced Vulkan via `MPV_KIT_VIDEO_API=vulkan` keeps the old path covered | RTX 4060 for performance, 4K 30-min, and the D3D11-vs-Vulkan comparison |
| **15 — Linux OpenGL backend** | (a) mpv `-Dgl -Dplain-gl -Degl`; (b) `render_gl_smoke.c` (EGL surfaceless, llvmpipe); (c) `OpenGLBackend` + EGLImage hand-off + EGL sync; (d) candidate list as in §6; (e) optional 0011 + libplacebo `-Dopengl` | 12 (independent of 14, can run in parallel) | Yes: xvfb + Mesa llvmpipe supports surfaceless EGL, `EGL_KHR_gl_texture_2D_image`, `GL_OES_EGL_image`, fence sync | **None available** (the only real hardware is Windows). NVIDIA/AMD Linux behaviour stays unverified, so say so in verification |
| **16 — Hardware-decode zero-copy** | d3d11va on D3D11 (`hwdec_d3d11va` via ra_d3d11 + `pl_d3d11_wrap`); `DRM_DISPLAY_V2` render fd for vaapi on GL **and** Vulkan gpu-next (native-resource follow-up patch); videotoolbox on MoltenVK; nvdec build-enable or explicit deferral | 14, 15, 13 | Only negative/fallback paths (runners have no HW decoders: no `/dev/dri` on ubuntu, WARP has no video) | RTX 4060 for d3d11va (`hwdec-current=d3d11va`, no copy-back). vaapi/nvdec: no hardware, so honest deferral or community evidence |
| **17 — Fallback hardening + UHD regression** | Fault injection through the fake backend (device lost, timeout storms, alloc failure on the native backend → next candidate); CI matrix forcing each API per platform; 4K 30-min on D3D11 and on Vulkan; 100-round resize soak per backend | 14, 15, 16 | Yes (forced-API matrix, soak) | RTX 4060 for UHD |

**Ordering rationale:**
- 12 comes first and must stay pure refactor. Every later phase rolls back to it independently.
- D3D11 (14) before GL (15) if run serially. It has the most unknowns (new mpv patch, new deps, `pl_d3d11` in libmpv, fence availability on WARP) and the only real-hardware verification, on Windows. GL needs no mpv patch for gl_video and is lower risk. The phases share no files, so they can run in parallel.
- Hardware decode (16) after the render backends. Zero-copy decode depends on the backend's `ra` (ra_d3d11 / ra_gl / ra_pl), and CI cannot prove it, so it is easier to keep its unverified parts separate.
- macOS (13) is cheap and early. It settles the "TBD" and needs only the reason grammar from 12.

**Research flags:** Phase 14 needs deeper research (shaderc/SPIRV-Cross on CLANGARM64, `ID3D11Device5` fences on WARP, BGRA8 typed-UAV support, `D3D11_CREATE_DEVICE_VIDEO_SUPPORT` on the Basic Render Driver). Phase 15 needs a spike on Flutter Linux raster-thread identity and EGL vs GLX context in the current Flutter (3.47.x). Phase 16 needs per-hwdec research. Phases 12, 13 and 17 follow standard patterns.

---

## 11. Anti-patterns

### Anti-Pattern 1: Rendering inside the compositor callback
**What people do:** call `mpv_render_context_render` from `FlTextureGL::populate` or from `copyPixelBuffer` (fvp-style).
**Why it's wrong:** it blocks the raster (often GTK main) thread for the whole render, mpv's GL state leaks into Flutter's renderer, and it breaks `report_swap`, idle detection and the pipelined publish gate.
**Do this instead:** keep the render thread. The compositor callback only calls `AcquireFront()` and binds an already-finished image.

### Anti-Pattern 2: Using Flutter's / ANGLE's D3D11 device
**What people do:** render on the engine's device so that `FlutterDesktopGpuSurfaceTypeD3d11Texture2D` can pass a raw texture pointer.
**Why it's wrong:** it puts ANGLE's device into our chain (forbidden by the user) and shares an immediate context with a renderer we do not control.
**Do this instead:** use our own device on the same adapter, legacy shared handle, quarantine + completion wait.

### Anti-Pattern 3: "Native first" ordering by API only
**What people do:** auto = [GL, Vulkan, SW] on Linux.
**Why it's wrong:** without patch 0011, GL means gl_video, a silent quality regression for every Linux user whose Vulkan gpu-next path works today.
**Do this instead:** order by (renderer, api) as in §6.

### Anti-Pattern 4: Adding `MpvVideoBackend` values or render symbols "because they are small"
**Why it's wrong:** enum values break exhaustive switches (frozen API), and new symbols change the `MpvApi::Load` count contract with Dart.
**Do this instead:** use private wire names + the reason prefix + render params.

### Anti-Pattern 5: Keyed mutex for cross-device sync
**Why it's wrong:** the consumer (ANGLE inside Flutter) does not acquire it (Phase 10 REA), so it adds cost without synchronisation.
**Do this instead:** completion fence + quarantine.

### Anti-Pattern 6: Refactor and new backend in one change
**Why it's wrong:** it makes "no behaviour change" unprovable and blocks rolling back each backend separately.
**Do this instead:** Phase 12 ships alone and green, then each backend is added as a list entry.

---

## 12. Integration points

### External

| Service | Integration pattern | Notes |
|---|---|---|
| libmpv render API | 9 generic symbols; new API types via params | `render_d3d11.h` vendored into `src/include/mpv/` like `render_vk.h` |
| libplacebo | `pl_d3d11` (Windows), `pl_opengl` (opt.), `pl_vulkan` (today) | Build flags in `deps.sh:251-257` |
| Flutter Windows embedder | `GpuSurfaceTexture` DXGI shared handle | Unchanged; ANGLE use inside the engine is outside our control (ADR 0003) |
| Flutter Linux embedder | `FlTextureGL` populate with Flutter's context current | GLX/EGL `EGL_BAD_ACCESS` pitfall; raster thread identity to verify |
| Flutter macOS embedder | `FlutterTexture` `copyPixelBuffer` | Unchanged |
| OS / drivers | D3D11 fences, EGL image/sync extensions, DRM render nodes | Probe and report through `reason`, never assume |

### Internal boundaries

| Boundary | Communication | Notes |
|---|---|---|
| `VideoRenderer` ↔ `RenderBackend` | virtual calls on the render thread (+ Create/Release with the thread bound) | the backend never touches ring bookkeeping or the renderer lock |
| `VideoRenderer` ↔ `PlatformSink` | `FrameReady` (render thread), `RetainFrame` (under the lock), candidates/factory (Start) | unchanged threading |
| Plugin ↔ Dart | method channel; private wire names; same event kinds | public API frozen |
| Plugin ↔ libmpv | addresses only; `mpv_api.h` | the plugin never loads libmpv (unchanged) |
| Patch set ↔ vendor | PATCH-DRIFT byte identity | regenerate 0010/0011 from the vendored tree |

---

## 13. Decisions needed from the user (blockers for planning)

1. **Backend reporting under the API freeze:** map D3D11/GL to `MpvVideoBackend.vulkan` (doc changed to "GPU zero-copy") with the true API in the `reason` prefix (recommended), or allow a breaking enum addition.
2. **Windows bundle growth:** bundle shaderc + SPIRV-Cross (recommended; gives both gpu-next and gpu on D3D11 with no `ra_d3d11` source change), or the null-compiler stub (smaller, gpu-next only).
3. **Linux gpu-next over GL (patch 0011):** in scope (GL becomes truly first on Linux) or out (GL is a fallback tier below Vulkan gpu-next).
4. **nvdec:** build-enable without verification, or defer explicitly (there is no NVIDIA Linux hardware).

---

## Sources

- Local code (HIGH): `packages/mpv_kit_video/src/{video_renderer.h,video_renderer.cc,vulkan_backend.h,vulkan_backend.cc,mpv_api.h}`, `windows/{d3d11_interop.cpp,mpv_kit_video_plugin.cpp}`, `linux/{gl_interop.h,gl_interop.cc,mpv_kit_video_plugin.cc}`, `macos/Classes/{metal_interop.h,MpvKitVideoPlugin.mm}`, `lib/src/video_controller.dart`; `native/mpv/video/out/{vo_libmpv.c,libmpv.h,vo_gpu_next.c,gpu/libmpv_gpu.{c,h},opengl/libmpv_gl.c,d3d11/{ra_d3d11.{c,h},hwdec_d3d11va.c},gpu_next/context.c,hwdec/{hwdec_vaapi.c,hwdec_vt_pl.m}}`, `native/mpv/include/mpv/render_vk.h`, `native/mpv/meson.build`; `native/build/{build.sh,deps.sh}`; `.github/workflows/native-verify.yml`; `docs/ARCHITECTURE.md`; ADR 0003; `native/patches/UPSTREAM.md`; commit `857ccc2` (pipeline depth 2).
- libplacebo v7.360.1 `src/d3d11/meson.build` and `src/include/libplacebo/d3d11.h` (official source at the pinned tag, fetched; MEDIUM): [meson.build](https://raw.githubusercontent.com/haasn/libplacebo/v7.360.1/src/d3d11/meson.build), [d3d11.h](https://raw.githubusercontent.com/haasn/libplacebo/v7.360.1/src/include/libplacebo/d3d11.h)
- Flutter Linux embedder (LOW–MEDIUM, web): [fl_texture_gl.h source](https://api.flutter.dev/linux-embedder/fl__texture__gl_8h_source.html) (populate runs with Flutter's context current); [flutter/flutter PR #193530](https://github.com/flutter/flutter/pull/193530) (libglvnd `EGL_BAD_ACCESS` with a GLX context current); [flutter/flutter #84930](https://github.com/flutter/flutter/issues/84930) (raster shares the main thread on Linux, historical); [media-kit fork PR](https://github.com/RadicalMuffinMan/media-kit/pull/1) (no current EGL context on the GTK thread under X11/GLX); [flutter/engine PR #24916](https://github.com/flutter/engine/pull/24916) (FlTextureGL design, shared contexts).

---
*Architecture research for: mpv_kit v3.0 unified render lifecycle and platform-native graphics backends*
*Researched: 2026-10-26*
