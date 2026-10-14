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
