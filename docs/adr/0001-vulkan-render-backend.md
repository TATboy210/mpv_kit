# ADR 0001 — Add a Vulkan backend to the libmpv render API

Status: accepted (2026-10-14)

## Context
Requirement: Vulkan rendering, smooth 4K, embedding inside Flutter on
Windows/Linux/macOS. libmpv 0.41 offers only OpenGL and SW render backends;
Vulkan exists only for mpv's own windowed VOs.

Options considered:
1. **Patch libmpv** with `MPV_RENDER_API_TYPE_VULKAN` (chosen).
2. `--wid` child-window embedding: best raw performance, but Flutter widgets
   cannot draw over the video and each OS needs window plumbing.
3. OpenGL only: works today, but keeps GL interop costs (and deprecated CGL
   on macOS).

## Decision
Implement `video/out/vulkan/libmpv_vk.c` against the existing 4-function
`libmpv_gpu_context_fns` interface. The host owns the `VkDevice`
(`pl_vulkan_import`) so the Flutter plugin can enable the platform interop
extensions. Images are wrapped per frame (`pl_vulkan_wrap`) and synchronised
with host semaphores (`pl_vulkan_release_ex` / `pl_vulkan_hold_ex`).
Parameter IDs use a private range (`0x6d6b0001…`) so they never collide with
future upstream values; `MPV_CLIENT_API_VERSION` is not bumped.

## Consequences
* Renderer, shaders, HDR, scaling and hwdec are 100% upstream mpv code.
* Patch is small (+402/−1, 8 files) and upstreamable.
* OpenGL and SW remain as fallbacks (device without Vulkan 1.3, missing
  interop extensions, adapter mismatch).
* We must build libmpv ourselves on all targets (ADR 0002).

## Findings while enabling Vulkan hwdec (2026-10-15)

* libplacebo leaves `pl_vulkan.extensions` empty for imported devices, so
  mpv's hwdec_vulkan gave FFmpeg no extensions and Vulkan Video decoding
  silently fell back to `*-copy` hwdecs. Patch 0002 passes the host's list.
  Verified on an RTX 4060: `Using hardware decoding (vulkan)`.
* The legacy renderer's disk shader cache (`gpu-shader-cache`) is a no-op
  on the libplacebo `ra`: `ra_pl` never fills `cached_program`. First
  frames therefore pay SPIR-V compilation (~0.4 s, a few dropped frames at
  start). A gpu-next based backend (libplacebo `pl_cache`) would fix this.

## Update 2026-10-15: gpu-next and the shader cache

- Patch 0003 attaches a persistent `pl_cache` to the imported `pl_gpu`
  (`--gpu-shader-cache-dir`, vo_gpu_next's `shader_<key>` file layout).
  mpv_kit_video defaults the directory to a per-user cache
  (`%LOCALAPPDATA%/mpv_kit/shader-cache`, `~/Library/Caches/...`,
  `$XDG_CACHE_HOME/...`). Paths use `/` on Windows: `mp_mkdirp` only splits
  on `/` and silently fails to create nested backslash paths.
- Patch 0004 adds `render_backend_gpu_next`: vo_gpu_next's renderer driven
  by the render API through a private `struct vo`. It is the default for
  `MPV_RENDER_API_TYPE_VULKAN`; `MPV_RENDER_PARAM_VULKAN_RENDERER = "gpu"`
  selects gl_video. The target is treated as an SDR sRGB surface (no
  swapchain colorspace hint). The plugin falls back to `gpu` if gpu-next
  cannot initialise. Both renderers pass the lavapipe pixel test in CI.
- Measured on RTX 4060 Laptop, 4K (4096x2160) H.264 25 fps, hwdec=vulkan,
  gpu-next: first start 4 dropped frames (shader compilation), every later
  start 0 dropped / 0 delayed (13 of 18 cache objects reused).
- mpv_kit_video skips rendering (`SKIP_RENDERING`) while the compositor has
  not taken a frame for 500 ms (hidden/minimised) and redraws once on the
  next acquisition.
