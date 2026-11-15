# Feature Research — milestone v3.0 (unified render lifecycle + platform-native graphics backends)

**Domain:** embedding libmpv video output into a Flutter desktop compositor (Windows / Linux / macOS, x64 + arm64)
**Researched:** 2026-10-26
**Confidence:** MEDIUM overall. Statements about how media_kit and fvp behave come from reading their source at pinned commits (HIGH). Statements about failures in the field come from their issue trackers (MEDIUM: user reports, sometimes with a confirmed fix). The IINA, MPVKit and Celluloid notes come from web search summaries and a few issues (LOW to MEDIUM, marked as such where used).

**Reference snapshots read (read-only, nothing reused):**
- media_kit `c533e44` (2026-08-30): `media_kit_video/{windows,linux,macos,common/darwin}`, `native_video_controller/real.dart`
- fvp `fb4e11e` (2026-10-25): `windows/fvp_plugin.cpp`, `linux/fvp_plugin.cc`, `darwin/Classes/FvpPlugin.mm`, `lib/src/{player,video_player_mdk}.dart`. libmdk is closed, so only the plugin glue and its behaviour were studied.
- Upstream mpv: PR #17764 (D3D11 render API, **merged 2026-10-15**), #16818 and #18607 (gpu-next for libmpv, **both still open**), and `native/mpv` at 0.41.0-1115 (vendored; it predates #17764).

---

## How the reference players solve each concern

This table is the evidence base. Each classification further down cites it.

| Concern | media_kit (libmpv, open) | fvp (libmdk, closed core) | mpv_kit today (Vulkan) |
|---|---|---|---|
| **Windows render API** | libmpv **OpenGL ES via ANGLE** into a private D3D11 texture. `glFinish()` after every frame. `CopyResource` into a second shared texture **inside the compositor's descriptor callback** (`angle_surface_manager.cc` `Read()`). | Native **D3D11**: own device created on `FlutterView::GetGraphicsAdapter()`, `SetMultithreadProtected(TRUE)`. Renders into a private target, then `CopyResource` + `Flush` into the shared-handle texture inside the descriptor callback. | Vulkan renders into a ring of D3D11 KMT textures (adapter matched by LUID). No copy: ring plus quarantine of 4. |
| **Linux render API** | libmpv GL in an **isolated EGL context**, bridged to Flutter by an EGLImage. **mpv renders inside `FlTextureGL::populate` on the raster thread.** Single buffer, `glFlush` only. | Renders inside `populate` on Flutter's own GL context, and has to switch off Impeller's scissor test to do it. | Vulkan `OPAQUE_FD` memory imported into Flutter's GL context through `GL_EXT_memory_object_fd`. |
| **macOS render API** | **CGL OpenGL** (deprecated) into 3 IOSurface `CVPixelBuffer`s. `DispatchQueue.main.sync` on every frame for `textureFrameAvailable`. | **Metal**: private `MTLTexture`, blitted into an IOSurface `CVPixelBuffer` inside `copyPixelBuffer` ("TODO texture pool to avoid blitting"). | MoltenVK renders into an IOSurface `CVPixelBuffer` via `VK_EXT_metal_objects`. |
| **Threading** | Windows: **one `ThreadPool(1)` shared by every player**, because "ANGLESurfaceManager & libmpv render context creation can conflict" (comment in `video_output.cc`). | Render callback per player, protected by a mutex. | One native render thread per controller. The UI and raster threads never render. |
| **Resize / video-size change** | Windows: **unregisters the texture and registers a new one with a new id** on every size change. Linux: deletes and recreates the single target in place inside `populate`. Render size defaults to the **video size**, not the widget size. | Texture is fixed to the video size (or a max clamp). A size change **releases it and creates a new texture id**. | Stable texture id. Ring reallocated lazily, and the previous ring is *retired* (keeps showing its last frame) until the first frame at the new size exists. Render size = widget physical pixels, capped at the video size. |
| **Release** | Windows destructor waits for the `UnregisterTexture` callback, then drains the pool. Linux frees GL objects in the matching context. | `ReleaseRT` replies to Dart only from the `UnregisterTexture` completion callback ("Dart waits for this result before deleting the underlying MDK player"). | Dispose hook frees the render context before the core. Windows deletes the instance in the unregister callback. |
| **hwdec default** | `hwdec=auto`, set by `VideoController.create`. On Windows there is **no zero-copy** ([#296](https://github.com/media-kit/media-kit/issues/296), open since 2023). A maintainer says "we can currently only use non-zero-copy decoding methods" and is waiting on mpv #17764 ([#1278](https://github.com/media-kit/media-kit/issues/1278)). | Hardware decoders first: Windows `MFT:d3d=11, D3D11, DXVA, CUDA`, macOS `VT`, Linux `VAAPI, CUDA, VDPAU`, then FFmpeg/dav1d. | `vulkan,d3d11va-copy,auto-safe` (Player default), `ffv1` excluded (mpv #18255). |
| **Failure reporting** | `catch (...) { /* Do nothing */ }`, then software with a `std::cout` line. Software output is capped at 1080p. | Errors go to the log; Dart gets a `PlatformException`. | Typed events (`renderError`, `gpuTimeout`, `deviceLost`, `softwareFallback`), plus `backend` and `reason`. |

---

## Feature Landscape

Complexity: **LOW** = less than 1 plan, **MEDIUM** = 1–3 plans, **HIGH** = a phase or more, or new libmpv patch work.
"Depends on" names existing mpv_kit features (see `docs/ARCHITECTURE.md`, `video_renderer.h`) that the feature must reuse or keep working.

### Table Stakes (users penalise their absence)

| # | Feature | Why expected (evidence) | Complexity | Depends on (existing) | Platform |
|---|---|---|---|---|---|
| TS-1 | **One `RenderBackend` lifecycle** (Create / AllocTarget / Render / FrameReady / Release / Destroy) under the existing render-thread state machine. Vulkan and software migrate to it with **no behaviour change**. | media_kit has three different threading models on three platforms, and its bugs are platform-specific as a result: macOS freezes during window resize ([#1176](https://github.com/media-kit/media-kit/issues/1176)), Linux tears on Flutter 3.38 ([#1345](https://github.com/media-kit/media-kit/issues/1345)), Windows players stall each other ([#1099](https://github.com/media-kit/media-kit/issues/1099)). A shared state machine is what stops a new backend from re-creating those classes of bug. | MEDIUM | `VideoRenderer` thread, `Interop`, frame ring, quarantine, retire-on-resize, backoff 100 ms → 5 s, idle `SKIP_RENDERING`, `report_swap` timing | all |
| TS-2 | **Resize with no black flash and no texture-id change.** | media_kit (Windows) and fvp re-register a new texture id on every size change, which forces a widget rebuild and an empty frame. MPVKit's MoltenVK context ignores layer resizes and shows a stale or 1×1 black picture until a patch makes it follow the layer (web summary of the MPVKit forks, LOW). mpv_kit already solves this with ring retirement. | LOW (common layer) / MEDIUM per backend for target reallocation | retired-ring logic, `MpvVideo` resize debounce, `setSize` | all |
| TS-3 | **Render at widget physical size, capped at video size**, on every backend. | By default media_kit renders at video resolution: a 4K source in a 320 px tile is a full 4K render. Its maintainer's advice for "≥4 RTSP streams flicker" is to set width/height by hand ([#363](https://github.com/media-kit/media-kit/issues/363)). | LOW | `MpvVideoController.setSize` | all |
| TS-4 | **Frame-ready notification without polling, and no rendering on the UI or raster thread.** mpv's update callback signals a condition variable; the render thread renders and then marks the texture dirty (main queue on macOS). | media_kit Linux and fvp Linux render inside `populate`, which blocks the raster thread and leaks GL state into Flutter (fvp has to switch Impeller's scissor test off and on). media_kit macOS does `main.sync` on every frame, which is consistent with the freeze during live resize (#1176; the reporter says fvp does not freeze). `textureFrameAvailable` must run on the main thread ([PR #596](https://github.com/media-kit/media-kit/pull/596)). | LOW (exists), but **every new backend must keep it**; a GL backend is tempted to render in `populate` | render thread, platform event marshalling (`PostMessage` / `g_idle_add` / `dispatch_async`) | all |
| TS-5 | **Deterministic release.** Render context freed before the mpv core. Flutter texture objects freed only after the engine's unregister completion. GL objects deleted in the context that owns them. Device released after its last texture. No native callback after the Dart side is gone. | fvp's `ReleaseRT` and media_kit's Windows destructor both wait for the unregister callback. Flutter 3.38 made "callback invoked after it has been deleted" crash media_kit on dispose in release builds on all platforms ([PR #1320](https://github.com/media-kit/media-kit/pull/1320), [#1443](https://github.com/media-kit/media-kit/issues/1443)). | MEDIUM (per backend) | `Player.addDisposeHook`, Phase 1/2 dispose soaks, Windows unregister-callback delete | all |
| TS-6 | **Many concurrent players, no global serialisation.** One device or context per controller, so one player's open or resize never stalls another. | media_kit Windows puts every player on one thread. Users report a second player stopping when the first opens a file (#1099), black flicker at ≥4 RTSP streams (#363), access violations inside `libGLESv2` with several apps running ([#743](https://github.com/media-kit/media-kit/issues/743)), and crashes when 4+ players are disposed at once on a Linux VM ([#672](https://github.com/media-kit/media-kit/issues/672)). The upstream D3D11 header says mpv renders on the **immediate context** and no other thread may touch it meanwhile, so **one D3D11 device per controller** is the simple, safe default. | MEDIUM | per-controller `VideoRenderer`, LUID adapter match (`d3d11_interop.cpp`) | all (critical on Windows) |
| TS-7 | **Hardware decoding on by default, falling back safely per backend**: zero-copy interop first, copy-back second, software last. Never crash on an unsupported codec or profile, and never override a user-set `hwdec`. | The mpv manual ties each hwdec to an API: `d3d11va` needs a D3D11 `ra` (`hwdec_d3d11va.c`: `if (!ra_is_d3d11(...)) return -1`), `vaapi` needs a GL/EGL or Vulkan dma-buf interop, `nvdec` does not work with d3d11 `gpu-next` ([mpv #11151](https://github.com/mpv-player/mpv/issues/11151)). libmpv apps on a GLX context silently lose VA-API ([mpv #6353](https://github.com/mpv-player/mpv/issues/6353), [#10424](https://github.com/mpv-player/mpv/issues/10424), [celluloid #781](https://github.com/celluloid-player/celluloid/issues/781)). `auto` can pick Vulkan Video for H.264 10-bit and crash on an FFmpeg bug ([media_kit #1366](https://github.com/media-kit/media-kit/issues/1366)). Vendor hwdec bugs are why mpv keeps hwdec off by default ([mpv #12948](https://github.com/mpv-player/mpv/issues/12948)). | MEDIUM | `Player` hwdec default and `hwdec-codecs` (ffv1 exclusion), `hwdecCurrent`, `decodeWarning` | all |
| TS-8 | **Honest backend and reason reporting**: which graphics API, which renderer, which device, and why each fallback step happened. | media_kit only prints "Using S/W rendering". Its users cannot tell why a video is slow (#1278, high CPU). mpv_kit's Phase 2/3 decisions made backend reporting strict and reasons honest. | LOW code, but **needs a scoping decision** (see below) | `MpvVideoController.backend` / `.reason`, strict `create` response validation | all |
| TS-9 | **10-bit and HDR sources handled correctly into the SDR 8-bit target**: P010/P016 hardware surfaces imported zero-copy, tone-mapped, no green or garbage frames, and no silent drop to software at 4K. HDR *output* stays out of scope. | IINA reports `videotoolbox-copy` with `p010 (SW)` and severe stutter on 10-bit HEVC SDR ([iina #5796](https://github.com/iina/iina/issues/5796)). media_kit has open HDR colour reports ([#1207](https://github.com/media-kit/media-kit/issues/1207), [#615](https://github.com/media-kit/media-kit/issues/615)). The upstream D3D11 target formats are BGRA8, RGBA8, RGB10A2 and RGBA16F, with no sRGB (`render_d3d11.h`). | MEDIUM–HIGH | `dither=no`, `hdr-compute-peak=no` defaults, `decodeWarning` | all |
| TS-10 | **Device or context loss: detected, typed, no crash, no hang.** Rendering stops and the app can dispose and recreate. Covers D3D11 `DXGI_ERROR_DEVICE_REMOVED/RESET` (TDR, driver update), GL robustness reset, and Metal command-buffer errors. | media_kit has no handling at all: its `catch (...)` swallows the error. mpv_kit has `deviceLost` and `isBroken` for Vulkan, but the event's doc says "Vulkan device" and would need rewording without changing its kind. | MEDIUM | `MpvVideoEventKind.deviceLost`, `isBroken`, `RenderResult::kDeviceLost` | all |
| TS-11 | **Create-time fallback chain: native → Vulkan → software**, each step's reason kept, the `MPV_KIT_VIDEO_RENDERER` override honoured, software never silent. | media_kit falls back silently. On very old GPUs Flutter's own software texture path fails too ([#249](https://github.com/media-kit/media-kit/issues/249)). mpv_kit already emits `softwareFallback`. | LOW–MEDIUM | `RendererChoice`, `MpvVideoRenderer` enum, `softwareFallback` | all |
| TS-12 | **Correct producer → compositor synchronisation**: no tearing, no stale or half-written frames. | Flutter Windows opens the shared handle through ANGLE on **its own device**. Its release callback fires immediately, and there is no fence or keyed mutex (COMP-01, ADR 0003), so the producer side has to bound reuse. On Linux, media_kit's `glFlush`-only path tears on 3.38 (#1345). The verified fix in [#1463](https://github.com/media-kit/media-kit/issues/1463) uses `glFinish` and states that "cross-context sampling without a finish tears". | MEDIUM–HIGH | ring + quarantine (`CompositorLatency()` 4 on Windows, 2 elsewhere), Vulkan timeline waits | all |
| TS-13 | **Robust against Flutter Linux embedder changes.** No assumption about GDK's GL context. Never render into a texture that is itself the source of an EGLImage. | Flutter moved Linux rendering into its own EGL context ([flutter 407c051](https://github.com/flutter/flutter/commit/407c051ec9eac79b97657ade60d02b7c8e3e0715), 2025-07), and media_kit hardware rendering broke on 3.38 ([#1321](https://github.com/media-kit/media-kit/issues/1321), fixed by [PR #1325](https://github.com/media-kit/media-kit/pull/1325) with an extra GPU copy). On Mesa/Xe2, creating an EGLImage from mpv's render texture makes mpv's renders vanish (all black, no error), and the verified fix is a separate export texture (#1463). | MEDIUM | `gl_interop.cc` probe-context pattern | Linux |
| TS-14 | **Multi-engine / multi-window safety**: no static plugin singleton, events routed per registrar and window. | media_kit's static `instance_` hangs `VideoController` creation on the first engine in multi-window apps ([#1383](https://github.com/media-kit/media-kit/issues/1383)). mpv_kit has no singleton; new backends must not add one. | LOW | per-registrar plugin instances, `_live` routing by texture id | all (Windows first) |
| TS-15 | **Existing output features keep working on every backend**: `display-fps-override` sync, ICC via `MPV_RENDER_PARAM_ICC_PROFILE`, shader cache dir, `idle`/`active`, `report_swap`. | These are already part of mpv_kit's API contract. A backend that drops them is a regression even though the API is unchanged. | LOW–MEDIUM (ICC/shader cache depend on which renderer the backend supports) | `syncDisplayRefreshRate`, `setIccProfile`, `_applyShaderCacheDir`, patch 0003 | all |

### Differentiators (where mpv_kit beats media_kit and fvp)

These line up with the Core Value: hours of full-frame 4K/8K playback with no crash, no leak and no backlog.

| # | Feature | Value proposition | Complexity | Depends on | Platform |
|---|---|---|---|---|---|
| D-1 | **True zero-copy hwdec on each native backend.** d3d11va frames sampled directly by the D3D11 renderer. vaapi dma-buf → EGLImage (GL). nvdec through CUDA–GL interop. videotoolbox IOSurface → Metal. | media_kit has no desktop zero-copy on Windows (#296, #1278) and mpv users see roughly 3× lower CPU with native d3d11va (#296 comment: 20 % → 7 % CPU on 4K VP9). fvp has it but is closed. At 4K60, copy-back moves 12.4 MB (NV12) or 24.9 MB (P010) per frame across PCIe, about 0.75–1.5 GB/s each way. | HIGH | D3D11: rebase onto mpv #17764 or an equivalent patch, device created with multithread protection, never `SINGLETHREADED` (the header warns this limits hwdec to copy-back). Linux: EGL context plus `MPV_RENDER_PARAM_X11_DISPLAY`/`WL_DISPLAY` (see note N-3). macOS: see note N-4. | all |
| D-2 | **Compositor-latency-aware ring instead of a per-frame copy.** | **Both** media_kit and fvp `CopyResource` (Windows) or blit (fvp macOS) the whole frame inside the compositor callback on every pull. At 4K that is 33 MB read plus 33 MB written per frame, about 4 GB/s of GPU bandwidth at 60 fps, spent only on synchronisation. mpv_kit's ring plus quarantine avoids it. Porting it to D3D11, GL and Metal keeps that advantage. | MEDIUM (exists for Vulkan) | `Interop::CompositorLatency()`, ring sizing rule, COMP-03 (deferred) parameterisation | all |
| D-3 | **Explicit per-frame fences where the platform allows.** Producer side: D3D11 `ID3D11Query(EVENT)` or `ID3D11Fence` before a slot is published (replaces the Vulkan timeline wait). Linux: `EGL_KHR_fence_sync` / `glFenceSync` instead of `glFinish`. macOS: `MTLSharedEvent` or the command-buffer completion handler. The consumer side stays quarantine-bound on Windows, because Flutter never acquires a keyed mutex. | Removes both the CPU stall (`glFinish` in media_kit Windows, in the #1463 fix, and in mpv's own GL path) and the tearing of flush-only paths. | MEDIUM–HIGH | TS-12; Vulkan timeline semantics as the reference | all |
| D-4 | **gpu-next (libplacebo) on the native backends**, not only on Vulkan. | Upstream libmpv gpu-next is **not merged** ([#16818](https://github.com/mpv-player/mpv/pull/16818), [#18607](https://github.com/mpv-player/mpv/pull/18607) opened 2026-10-13, [#10810](https://github.com/mpv-player/mpv/issues/10810)). IINA's HDR and Dolby Vision lag behind standalone mpv for exactly this reason (web summary of IINA PR #6493, LOW). Upstream's D3D11 render API is the old `gpu` (`ra_d3d11`) renderer. mpv_kit's patch 0004 is Vulkan-only (`libmpv_init` rejects other API types). `video/out/gpu_next/context.c` already shows the route: wrap the `ra_d3d11` device with `pl_d3d11`, so the d3d11va interop keeps working. | HIGH (new downstream patch) | patch 0004, patch drift gate | Windows (Linux GL later) |
| D-5 | **A complete fallback trail in `reason`**, e.g. `d3d11 gpu-next: <HRESULT>; vulkan gpu-next on RTX 4060`, plus interop/hwdec state in the HUD. | No reference player explains *why* it is slow. This is cheap once TS-8 is decided. | LOW | Phase 3 honest reasons, Phase 8 HUD | all |
| D-6 | **A native-only switch to force a backend for CI and diagnostics** (e.g. `MPV_KIT_VIDEO_BACKEND=d3d11|vulkan|gl|metal|software`, read by the plugin). Gives per-backend real-plugin CI on a single runner with **no Dart API change**. | The milestone requires real-plugin verification of every backend. Without a switch, `auto` hides whichever backend lost the race. | LOW | `MPV_KIT_VIDEO_RENDERER` precedent, Phase 6 integration tests | all |
| D-7 | **Rebuilding in place after device loss** (new backend, same `textureId`, playback continues). | Neither media_kit nor fvp does this. Windows TDRs and driver updates make it valuable for long sessions. | HIGH | TS-10, retire-on-resize machinery | Windows first |

### Anti-Features (do not build)

| # | Feature | Why requested | Why problematic | Alternative |
|---|---|---|---|---|
| A-1 | **ANGLE/EGL in mpv_kit's own Windows chain** (media_kit's route) | It works today and gives d3d11va interop through `hwdec_d3d11egl`. | **Forbidden by the user.** media_kit shows the costs: every player serialised on one thread (`ThreadPool(1)`), `glFinish` on every frame, an extra `CopyResource` on every compositor pull, and crashes inside `libGLESv2` (#743) and "Unable to create ANGLE EGL surface". ANGLE *inside Flutter's engine* is outside our control and is not affected by this rule. | Native D3D11 render API (D-1, D-4). |
| A-2 | **Copy-back hwdec as the default path** (`d3d11va-copy`, `auto-copy`) | It "always works", and some libmpv-on-Windows guides recommend `auto-copy` for embedded players because zero-copy can black-screen. | Copy-back costs 0.75–1.5 GB/s of PCIe traffic at 4K60 and roughly doubles CPU use. mpv_kit's current default lists `d3d11va-copy` second **only because the Vulkan backend cannot consume d3d11va**. Once D3D11 is native, keeping that list would silently give **copy-back on the native backend** (vulkan is skipped, then `d3d11va-copy`). | One priority list that works across backends, with zero-copy entries first and copy-back only as fallback (note N-2). |
| A-3 | **GPL or nonfree dependencies** (FFmpeg `--enable-gpl/--enable-nonfree`, libnpp, GPL builds like "MPVKit-GPL" for samba) | More codecs and protocols. | Breaks the LGPL bundle contract and the ABI audit. | nvdec through the dynamically loaded `ffnvcodec` headers (MIT) stays fine. Keep the `native/build` LGPL flags and the `pe_audit.py` gate. |
| A-4 | **Rendering inside the compositor callback** (`FlTextureGL::populate`, `GpuSurfaceTexture` descriptor, `copyPixelBuffer`) | The simplest GL integration, and both media_kit Linux and fvp Linux do it. | It blocks the raster thread, ties mpv's pacing to the compositor, leaks GL state (fvp's Impeller scissor workaround), and broke when Flutter changed contexts (#1321). | Own render thread plus publish and acquire (TS-4). |
| A-5 | **Re-registering a Flutter texture on every resize or video-size change** | Simple lifetime: one texture, one size. | Texture-id churn, a widget rebuild, a flash, and a release race on every resize (media_kit Windows, fvp). | Stable `textureId` with the ring reallocated behind it (TS-2). |
| A-6 | **One global render thread or device shared by all players** | Avoids EGL/ANGLE thread-safety bugs. | Players stall and starve each other (#1099, #363). | One device or context plus one render thread per controller (TS-6). |
| A-7 | **Silent fallback** (`catch (...)` → software, stdout only) | Nothing ever "fails". | Users see slow 4K and do not know why (#1278). This contradicts mpv_kit's Phase 2/3 decisions. | Typed events plus `reason` (TS-8, TS-11). |
| A-8 | **Sharing GL objects across non-shared contexts, or rendering into an EGLImage-source texture** | Saves a copy. | Black frames on Mesa with no error (#1463). A texture name from a non-shared context is invisible to Flutter (same report). | Export through dma-buf or memory-object fds, or render into a texture separate from the export image. |
| A-9 | **Window embedding (`--wid`) or a separate native window** (the mpv.net style; a maintainer notes "window embedding may be a better solution" for D3D11 in #17764) | mpv's own VO gets full features and swapchain timing. | It escapes Flutter composition: no overlays, no transforms, and it fights the Flutter window. #296 shows that `vo=gpu` "plays in a separate window". | Render API into a Flutter texture (the whole point of mpv_kit_video). |
| A-10 | **New public API** (new `MpvVideoRenderer` values for graphics APIs, per-backend config objects) | Direct control. | The API is frozen. New enum values also break exhaustive `switch` statements in user code. | Renderer enum plus a native-only env switch (D-6). |
| A-11 | **A new macOS OpenGL (CGL) backend** | media_kit and IINA use one, and `videotoolbox` has a GL interop. | CGL has been deprecated since 10.14. VT → GL uses rectangle textures that even gpu-next work has to normalise with an extra blit (#18607). IINA is stuck on it waiting for gpu-next. | MoltenVK → IOSurface (existing), or a Metal route (note N-4). |
| A-12 | **`hwdec=auto-unsafe` or `hwdec-codecs=all` as the default** | Maximum hardware usage. | The mpv manual warns against it. Vulkan FFV1 loses the device (mpv #18255), and H.264 10-bit on Vulkan Video crashed media_kit (#1366). | Keep the codec whitelist and pin it against mpv's `hwdec_conf` (existing test). |

---

## Scoping decisions this research surfaces (for REQUIREMENTS.md)

These are real conflicts between the milestone goals and the frozen API or the current defaults. They need an explicit user decision, not an implementer's guess.

- **N-1: `MpvVideoBackend` is a public enum with only `{vulkan, software}`, and `create` throws `render_init` for any other `backend` string** (`video_controller.dart` lines 181–196). Reporting "d3d11", "opengl" or "metal" honestly (TS-8) means either (a) adding enum values, an API addition that the freeze forbids and that breaks exhaustive switches; or (b) keeping `backend` coarse and putting the real API in `reason`. Option (b) is dishonest if `vulkan` is reported for a D3D11 path. Recommendation: ask the user for a **single documented exception (a)**, or accept (b) with `backend` redefined as "gpu vs cpu" in the docs. In either case the Dart validation and every platform plugin must change in the same commit.
- **N-2: hwdec default across backends.** The `Player` default `vulkan,d3d11va-copy,auto-safe` lives in `mpv_kit`, which does not know which backend will be chosen. mpv skips non-copy hwdecs whose interop was not loaded, so **one ordered list that includes every zero-copy candidate** (vulkan, d3d11va, videotoolbox, vaapi, nvdec, then copy-back, then `auto-safe`) selects correctly on each backend without the controller overwriting user options. The exact order (vaapi vs nvdec on NVIDIA Linux, d3d11va vs vulkan on Windows) needs per-platform verification in the backend phases. Changing a default value does not change a signature, but it is a behaviour change to document.
- **N-3: VA-API needs the native display.** `hwdec_vaapi.c` gets its VADisplay from `ra_get_native_resource("x11"/"wayland"/"drm_params_v2")`. media_kit passes `MPV_RENDER_PARAM_X11_DISPLAY`/`WL_DISPLAY` at `mpv_render_context_create`. mpv_kit passes **none of these** (grep over `packages/mpv_kit_video`). So vaapi zero-copy is likely unavailable on Linux today, on the Vulkan backend too. This is a LOW-cost fix shared by the GL and Vulkan backends, and must be verified on real hardware (MEDIUM confidence).
- **N-4: macOS route.** libplacebo has **no Metal backend** (its backends are Vulkan, OpenGL and D3D11; MEDIUM confidence, verify in STACK). A self-written Metal libmpv renderer is therefore a new renderer with no gpu-next. mpv already has `hwdec_vt_pl.m`: videotoolbox zero-copy over libplacebo/Vulkan, gated on `PL_HANDLE_MTL_TEX` import, which comes from `VK_EXT_metal_objects`, an extension mpv_kit's MoltenVK device already uses for IOSurfaces. The cheapest "Metal" route is to keep MoltenVK → IOSurface, verify VT zero-copy on it, and add Metal-side sync. A new libmpv backend is the most expensive and least capable option.
- **N-5: `auto` order versus renderer quality.** Upstream libmpv on D3D11 and GL offers only the `gpu` renderer. If `auto` became "D3D11 `gpu` → Vulkan gpu-next", Windows HDR and 10-bit content would **lose gpu-next tone-mapping quality relative to today**. Recommendation: put the renderer axis first and the graphics API second. `gpuNext` = D3D11 gpu-next (once D-4 exists) → Vulkan gpu-next. `gpu` = D3D11 gpu → Vulkan gpu. `auto` = the gpuNext chain → the gpu chain → software. Native becomes the first choice automatically once D-4 lands, and nothing regresses before that.

## Feature Dependencies

```
TS-1 RenderBackend lifecycle (Vulkan + SW migrated, parity)
    ├──requires──> existing ring / quarantine / retire / backoff / idle (unchanged)
    ├──enables───> TS-2, TS-4, TS-5, TS-12 inherited by every new backend
    └──enables───> D-6 backend forcing ──enables──> per-backend CI (Verification constraint)

N-1 backend reporting decision ──blocks──> TS-8 / D-5 for any non-Vulkan backend
N-5 auto order decision        ──blocks──> TS-11 auto chain for native backends

Windows D3D11 (gpu)  ──requires──> mpv #17764 in vendor (rebase) or an equivalent downstream patch
    ├──requires──> per-controller device, multithread-protected (TS-6, D-1)
    ├──requires──> D3D11 ring + quarantine 4 + producer query/fence (D-2, D-3)
    └──enhanced by──> D-4 gpu-next via pl_d3d11 (new patch; 0004 extension)

N-2 hwdec cross-backend list ──required by──> D-1 on every backend (otherwise copy-back, A-2)
N-3 X11/WL display param     ──required by──> vaapi zero-copy (Linux GL and Vulkan)

Linux GL backend ──requires──> isolated EGL context + export without EGLImage-on-render-target (TS-13)
                 └──requires──> GL fence sync (D-3) to avoid #1345-style tearing

macOS route (N-4) ──MoltenVK path──> VT zero-copy check (hwdec_vt_pl) + Metal-side sync
TS-10 device-loss detection ──prerequisite──> D-7 in-place recovery (defer)
```

### Dependency notes

- **Every backend inherits TS-2/4/5/12 only if TS-1 lands first.** Otherwise each backend re-implements resize and release, and the media_kit pattern of platform-specific bugs repeats.
- **D-4 depends on the vendor base.** #17764 changes `libmpv_gpu.c` and `ra_d3d11.c`, which patch 0004 also touches, so the rebase and the 0004 extension should be planned together under the PATCH-DRIFT gate.
- **A-2 conflicts with D-1** as long as N-2 is unresolved.

## MVP Definition (v3.0)

### Launch with
- [ ] TS-1 lifecycle, with Vulkan and software migrated and existing soaks and benchmarks unchanged (the rollback baseline)
- [ ] D-6 native backend switch, so each backend gets its own real-plugin CI job
- [ ] N-1 and N-5 decided; TS-8 and TS-11 implemented to match
- [ ] Windows D3D11 (`gpu` renderer) with d3d11va zero-copy, per-controller device, D3D11 ring + quarantine, device-removed detection (TS-6/7/10/12, D-1/D-2)
- [ ] N-2 hwdec list and N-3 display parameter
- [ ] Linux GL backend (FlTextureGL, isolated EGL, fence sync, vaapi/nvdec zero-copy) (TS-12/13, D-1/D-3)
- [ ] macOS route decided per N-4 (expected: MoltenVK kept, VT zero-copy verified)

### Add after validation
- [ ] D-4 gpu-next on D3D11, which is what lets `auto` prefer native on Windows without an HDR regression
- [ ] D-3 producer fences replacing `glFinish`-class stalls wherever quarantine alone is not enough
- [ ] D-5 full fallback trail in the HUD

### Future consideration
- [ ] D-7 in-place device-loss recovery (needs TS-10 data from the field)
- [ ] Linux Vulkan as a second Linux backend behind GL (it already exists; the question is only ordering)
- [ ] Consumer-side fences, if a future Flutter adds keyed-mutex or fence support to `GpuSurfaceTexture`

## Feature Prioritization Matrix

| Feature | User value | Implementation cost | Priority |
|---|---|---|---|
| TS-1 lifecycle + parity | HIGH | MEDIUM | P1 |
| TS-6 per-controller device/context | HIGH | MEDIUM | P1 |
| TS-7 / N-2 hwdec defaults per backend | HIGH | MEDIUM | P1 |
| D-1 d3d11va zero-copy (Windows) | HIGH | HIGH | P1 |
| TS-12 / D-2 ring + sync on new backends | HIGH | MEDIUM | P1 |
| TS-13 Linux GL robustness | HIGH | MEDIUM | P1 |
| TS-8 / N-1 honest backend reporting | MEDIUM | LOW (decision-bound) | P1 |
| D-6 backend forcing for CI | MEDIUM | LOW | P1 |
| TS-10 device-loss detection | MEDIUM | MEDIUM | P1 |
| TS-9 10-bit/HDR source correctness | HIGH | MEDIUM–HIGH | P1 (verify) / P2 (gpu-next parity) |
| D-4 gpu-next on D3D11 | HIGH | HIGH | P2 |
| D-3 explicit producer fences | MEDIUM | MEDIUM–HIGH | P2 |
| D-5 fallback trail | MEDIUM | LOW | P2 |
| D-7 in-place recovery | MEDIUM | HIGH | P3 |

## Competitor Feature Analysis

| Feature | media_kit | fvp | Our approach |
|---|---|---|---|
| Windows path | ANGLE GL → copy into shared texture each pull | Native D3D11 → copy into shared texture each pull | Native D3D11 → ring of shared textures, no copy (D-1/D-2) |
| Linux path | Isolated EGL + EGLImage; renders in populate | Renders in populate on Flutter's context | Own render thread; GL export + fence (TS-4/13, D-3) |
| macOS path | CGL OpenGL + 3 IOSurfaces; `main.sync` per frame | Metal + blit into IOSurface | MoltenVK → IOSurface ring (existing), VT zero-copy check (N-4) |
| Resize | New texture id per size (Windows) | New texture id per size | Stable id, retired ring (TS-2) |
| Multi-player | One thread for all (Windows) | Per-player callback + mutex | Per-controller thread + device (TS-6) |
| Zero-copy hwdec | None on Windows desktop (#296) | Yes (closed) | Yes on every backend (D-1) |
| Failure visibility | Silent software fallback | Logs | Typed events + reason trail (TS-8, D-5) |
| Release | Waits for unregister callback | Waits for unregister callback before reply | Dispose hook + unregister-callback delete (TS-5) |

## Sources

Primary source code (HIGH):
- media_kit `c533e44`: [windows/video_output.cc](https://github.com/media-kit/media-kit/blob/main/media_kit_video/windows/video_output.cc), [windows/angle_surface_manager.cc](https://github.com/media-kit/media-kit/blob/main/media_kit_video/windows/angle_surface_manager.cc), [windows/video_output_manager.h](https://github.com/media-kit/media-kit/blob/main/media_kit_video/windows/video_output_manager.h), [linux/video_output.cc](https://github.com/media-kit/media-kit/blob/main/media_kit_video/linux/video_output.cc), [linux/texture_gl.cc](https://github.com/media-kit/media-kit/blob/main/media_kit_video/linux/texture_gl.cc), [macos/.../TextureHW.swift](https://github.com/media-kit/media-kit/tree/main/media_kit_video/macos), [common/darwin/.../VideoOutput.swift](https://github.com/media-kit/media-kit/tree/main/media_kit_video/common/darwin), `native_video_controller/real.dart` (hwdec `auto`)
- fvp `fb4e11e`: [windows/fvp_plugin.cpp](https://github.com/wang-bin/fvp/blob/master/windows/fvp_plugin.cpp), [linux/fvp_plugin.cc](https://github.com/wang-bin/fvp/blob/master/linux/fvp_plugin.cc), [darwin/Classes/FvpPlugin.mm](https://github.com/wang-bin/fvp/blob/master/darwin/Classes/FvpPlugin.mm), `lib/src/video_player_mdk.dart` (default decoders), `lib/src/player.dart` (`updateTexture`)
- mpv: [PR #17764 D3D11 render API (merged 2026-10-15)](https://github.com/mpv-player/mpv/pull/17764) and `include/mpv/render_d3d11.h` on master; vendored `native/mpv` `video/out/d3d11/hwdec_d3d11va.c`, `video/out/hwdec/hwdec_vaapi.c`, `video/out/hwdec/hwdec_vt_pl.m`, `video/out/gpu_next/context.c`, `DOCS/man/options.rst` (`--hwdec`)
- mpv_kit: `packages/mpv_kit_video/lib/src/video_controller.dart`, `src/video_renderer.h`, `windows/*.cpp`, `linux/gl_interop.cc`, `native/patches/0004-*.patch`, `native/patches/UPSTREAM.md`, `docs/ARCHITECTURE.md`, `docs/adr/0003-*.md`

Issue and PR reports (MEDIUM):
- media_kit: [#296](https://github.com/media-kit/media-kit/issues/296), [#1278](https://github.com/media-kit/media-kit/issues/1278), [#1099](https://github.com/media-kit/media-kit/issues/1099), [#363](https://github.com/media-kit/media-kit/issues/363), [#743](https://github.com/media-kit/media-kit/issues/743), [#672](https://github.com/media-kit/media-kit/issues/672), [#1176](https://github.com/media-kit/media-kit/issues/1176), [#1321](https://github.com/media-kit/media-kit/issues/1321), [PR #1325](https://github.com/media-kit/media-kit/pull/1325), [#1345](https://github.com/media-kit/media-kit/issues/1345), [#1463](https://github.com/media-kit/media-kit/issues/1463), [#1366](https://github.com/media-kit/media-kit/issues/1366), [#1383](https://github.com/media-kit/media-kit/issues/1383), [#1443](https://github.com/media-kit/media-kit/issues/1443), [PR #1320](https://github.com/media-kit/media-kit/pull/1320), [PR #596](https://github.com/media-kit/media-kit/pull/596), [#249](https://github.com/media-kit/media-kit/issues/249), [#1207](https://github.com/media-kit/media-kit/issues/1207), [#615](https://github.com/media-kit/media-kit/issues/615), [#10](https://github.com/media-kit/media-kit/issues/10), [#1337 (limited maintenance)](https://github.com/media-kit/media-kit/issues/1337)
- mpv: [#16818](https://github.com/mpv-player/mpv/pull/16818), [#18607](https://github.com/mpv-player/mpv/pull/18607), [#10810](https://github.com/mpv-player/mpv/issues/10810), [#11151](https://github.com/mpv-player/mpv/issues/11151), [#6353](https://github.com/mpv-player/mpv/issues/6353), [#10424](https://github.com/mpv-player/mpv/issues/10424), [#7769](https://github.com/mpv-player/mpv/issues/7769), [#12948](https://github.com/mpv-player/mpv/issues/12948)
- Flutter: [commit 407c051 "Render Flutter in its own EGL context" (#172330)](https://github.com/flutter/flutter/commit/407c051ec9eac79b97657ade60d02b7c8e3e0715)
- IINA: [#5796](https://github.com/iina/iina/issues/5796), [PR #6493](https://github.com/iina/iina/pull/6493) (web summary, LOW)
- Celluloid: [#781](https://github.com/celluloid-player/celluloid/issues/781) (LOW; title only)
- MPVKit forks (resize-follow patch, MoltenVK `wid` usage): [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit), [GRCSAC/MPVKit](https://github.com/GRCSAC/MPVKit) (web summary, LOW)

Gaps: mpv.net's defaults were not verified, because it embeds through `--wid` and is not a render-API reference. Celluloid's GTK4 GLArea behaviour comes from search summaries only. fvp's runtime behaviour beyond its plugin glue (libmdk internals) cannot be inspected.

---
*Feature research for: libmpv → Flutter desktop render backends (v3.0)*
*Researched: 2026-10-26*
