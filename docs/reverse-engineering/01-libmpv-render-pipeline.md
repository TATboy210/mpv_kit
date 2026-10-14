# libmpv 0.41.0 render pipeline — source analysis

Paths are relative to `native/mpv/`. Binary facts come from
`tools/rea_abi_audit` run against a prebuilt `libmpv-2.dll`
(sha256 `2f16cfc4…ff09d`).

## 1. Public ABI

* Headers: `include/mpv/{client,render,render_gl,stream_cb}.h`;
  `MPV_CLIENT_API_VERSION = 2.5` (`client.h:251`).
* 54 exported symbols (`tools/rea_abi_audit/expected_symbols.txt`). The
  baseline binary exports exactly these and imports only Windows system DLLs
  plus `OPENGL32.dll` — FFmpeg & co. are statically linked into the DLL.

## 2. Call chain of `mpv_render_context_render`

```
mpv_render_context_render              video/out/vo_libmpv.c:336
 ├─ renderer->fns->get_target_size     → libmpv_gpu.c get_target_size → ctx->fns->wrap_fbo   (1st wrap)
 ├─ renderer->fns->resize (if needed)
 └─ renderer->fns->render              → libmpv_gpu.c render
     ├─ ctx->fns->wrap_fbo                                                                   (2nd wrap)
     ├─ gl_video_render_frame          video/out/gpu/video.c (the full mpv renderer on `struct ra`)
     └─ ctx->fns->done_frame           (exactly once)
```

**Finding A.** `wrap_fbo` runs twice per frame but `done_frame` once
(`libmpv_gpu.c` "Mapping the surface is cheap" comments). Harmless for GL;
a Vulkan backend that waits on a host semaphore inside `wrap_fbo` would wait
on a binary semaphore twice (invalid usage). → our backend makes `wrap_fbo`
idempotent for the same image.

## 3. Backend abstraction

`render_backend_fns` (`video/out/libmpv.h:41`) has two implementations,
`render_backend_gpu` and `render_backend_sw` (`vo_libmpv.c:114`).
`render_backend_gpu` dispatches by `MPV_RENDER_PARAM_API_TYPE` over
`context_backends[]` (`video/out/gpu/libmpv_gpu.c:8`), which only contains
`libmpv_gpu_context_gl` (`video/out/opengl/libmpv_gl.c`, 110 lines).

The per-API surface is just four functions (`libmpv_gpu.h`): `init`,
`wrap_fbo`, `done_frame`, `destroy`. Everything above (`gl_video`, OSD,
scaling, HDR tone mapping, hwdec interop) is API-agnostic code on `struct ra`.

**Finding B.** mpv already has a libplacebo-backed `ra`
(`video/out/placebo/ra_pl.c`, `ra_create_pl`) used by `vo_gpu --gpu-api=vulkan`.
A Vulkan libmpv backend therefore needs no renderer work: import device →
`ra_create_pl` → wrap `VkImage` with `pl_vulkan_wrap` + `mppl_wrap_tex`.

## 4. Vulkan hardware decoding in embedded mode

`hwdec_vulkan.c:60` obtains the device via `ra_vk_ctx_get(hw->ra_ctx)`, which
only recognises `vulkan_swapchain` (`vulkan/context.c:143`), i.e. mpv's own
window. It also reads `vk->vkinst->instance/get_proc_addr`.

**Finding C.** Without changes, `--hwdec=vulkan` silently falls back to
software decoding for any external renderer → fatal for 4K. Our patch adds a
marker `vulkan_external_swapchain` recognised by `ra_vk_ctx_get` and fills a
`pl_vk_inst_t` shim with the host instance.

Requirement for the host device: a decode-capable queue family and
`VK_KHR_video_queue`, `VK_KHR_video_decode_queue`, `_h264/_h265/_av1` (the
same list `mppl_create_vulkan` requests, `vulkan/context.c:186`).

## 5. Comparison: media_kit (current dependency of simple_player_flutter)

| Aspect | media_kit 1.2.6 / video 2.0.1 | mpv_kit |
|---|---|---|
| libmpv | git snapshot 2023-09-24 | 0.41.0 + patch, built in CI |
| Windows path | mpv GL → own ANGLE → D3D11, **per-frame `CopyResource`+`Flush`** (`angle_surface_manager.cc:59-67`), two ANGLE instances | Vulkan render into D3D11-shared image, no copy |
| macOS path | CGL OpenGL (deprecated) + CVPixelBuffer | Vulkan (MoltenVK) into IOSurface |
| Linux | system libmpv, GL/EGL | bundled libmpv, Vulkan → dma-buf |
| API surface | high-level Player + generic `setProperty`/`command` | full 54-symbol client API + typed layer |
