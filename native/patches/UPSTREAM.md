# Upstreaming status of the mpv_kit patches

Base: mpv 0.41.0. Checked against mpv master on 2026-10-15.

| Patch | Upstream fit | Plan |
|---|---|---|
| 0001 vo_libmpv Vulkan render backend | A previous RFC (mpv-player/mpv#18258, closed 2026-07-13) was rejected on process grounds: maintainers asked for preserved authorship, small commits and for porting vo_gpu_next to the render API *first*. | RFC series in that order: (1) gpu-next render backend for the existing GL API, (2) Vulkan API type, (3) host-image semaphores. Needs maintainer buy-in before code. |
| 0002 hwdec_vulkan: imported device extensions | Small, self-contained, only meaningful together with 0001 (no imported devices exist upstream). Master changed the surrounding code (lock_queue deprecation, queue creation flags), so it must be rebased. | Submit as part of the 0001 series. |
| 0003 persistent pl_cache for libmpv_vk | Depends on 0001. vo_gpu_next already has the same cache layout. | Part of the series. |
| 0004 gpu-next render backend | This is step (1) the maintainers asked for. | First PR to propose. |
| 0005 active renderer via get_info | Tiny API addition; depends on 0004. | Part of the series. |
| 0006 asynchronous stream bridge | mpv-specific glue for hosts that cannot answer stream_cb synchronously (Dart). Upstream's view so far is that stream_cb is enough. | Keep downstream. |

**Decision (2026-10-15):** the patches are maintained downstream only; no
upstream submission is planned. The table stays as the record of how each
patch relates to mpv master, which matters when rebasing onto a new mpv
release. Priorities for the patches are runtime efficiency and stability
in mpv_kit, not upstream acceptability.
