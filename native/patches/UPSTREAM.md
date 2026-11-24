# Upstreaming status of the mpv_kit patches

Base: **mpv master snapshot `v0.42.0-228-g35efcf53d`** (2026-11-23, the
`0.43.0`-dev base; 228 commits past the v0.42.0 tag). `native/mpv/MPV_VERSION`
carries the git-describe string, stamped by the revived patch 0008 —
upstream master commits carry `0.42.0-UNKNOWN` until a release tags the
version file, so the vendor-stamp patch is back.
Previously the base was the **v0.42.0 release tag**
(`b0841e8c4d156b8403dc1876c4cbd9011eb583f3`, 2026-11-04); before that
`v0.41.0-1115-gb2c255c13` (2026-10-09 master snapshot).

**Provenance gate (2026-11-07):** `tools/check_patches.sh` now accepts
both forms in `MPV_VERSION`:

- a release version (`0.42.0`) -> upstream tag `v0.42.0`;
- a git describe string (`v0.41.0-1113-gfd9265a905`) -> that commit.

It clones upstream blobless with `core.autocrlf=false`, applies every
`0*.patch` in name order with GNU `patch -p1`, and requires the result to
be byte-identical to `native/mpv` (only `.git` and `.gitignore` are
excluded). GNU patch is required; `git apply` reports false success on
these files on this host.

## Rebase to v0.42.0-228-g35efcf53d (2026-11-24)

Upstream took the gpu-next render backend into master (commits
`ad9d8503e`, `eb565a237`, `3e8aa53ec` et al., 2026-11-12..17, client API
2.7 for 0.43.0): `render_backends[]` now carries gpu-next/gpu/sw with
`MPV_RENDER_PARAM_RENDERER` (char*, `"gpu-next"`/`"gpu"`, default
gpu-next) selection and NOT_IMPLEMENTED fallback, `video/out/gpu_next/`
gained the `mppl_video` abstraction (`video.c`/`libmpv_gpu_next.c`),
`libmpv_gpu_context_create` dispatches API types for all backends, and
`mpv_render_context_get_info` still has no active-renderer query. The
patch set shrinks accordingly:

| Patch | State | What changed in this rebase |
|---|---|---|
| 0001 Vulkan render backend | kept, 2 hunks re-landed | `done_frame` bool + `libmpv_gpu_context_vk` extern re-landed on the refactored `libmpv_gpu.h`; `render_vk.h` now also defines the private-range `MPV_RENDER_PARAM_ACTIVE_RENDERER` (0x6d6b0003). The old `MPV_RENDER_PARAM_VULKAN_RENDERER` is retired: creation-time selection is upstream's `MPV_RENDER_PARAM_RENDERER`. |
| 0002 hwdec_vulkan extensions | kept | Applied clean. |
| 0003 persistent shader cache | kept | Applied clean. Upstream's `mppl_video` attaches its own mpv file cache (`video.c`, same `shader_<key>` layout and directory), so on the gpu-next path it replaces ours with an equivalent; ours remains the only cache on the gpu fallback path, where `libmpv_gpu.c` attaches none. The old vo_gpu_next double-attach guard is gone with the rest of that file's libmpv hunks. |
| 0004 gpu-next backend additions | **rewritten** | The gpu-next backend, D3D11 gpu-next branch and all vo_gpu_next.c libmpv hunks are upstream now (the ICC host profile is `mppl_video_set_icc_profile`, the OSD guard is `54f8cff47`, the target hint is `mppl_video_get_target_hint`). What remains: the `mpv_render_context_get_info` report answering `MPV_RENDER_PARAM_ACTIVE_RENDERER` with "gpu-next"/"gpu"/"sw" (upstream logs the choice but never exposes it; `controller.reason` consumes it), and the DRM render-node registration on upstream's gpu-next backend — `MPV_RENDER_PARAM_DRM_DISPLAY_V2` → `drm_params_v2` native resource + the verbose log line the render_vk DRM smoke test scans for, mirroring `libmpv_gpu.c`'s `native_resource_map` (found missing in the first CI round: `render_vk_smoke_drm` failed on all Linux/macOS jobs). |
| 0006 stream bridge | kept | Applied clean (offsets only). |
| 0007 audio fixes | kept | Applied clean. |
| 0008 vendor stamp | **revived** | Master snapshots carry `0.42.0-UNKNOWN`; 0008 stamps `MPV_VERSION` with the describe form the provenance gate parses. |
| 0012 libdrm floor | kept | 0.43-dev still requires libdrm >= 2.4.114; the release job still builds in `ubuntu:22.04`. |

Independent re-verification: `tools/check_patches.sh` passes with
`base=35efcf53d… patches=8`; the regenerated 0001/0004 patch files were
additionally applied to a fresh upstream checkout and the result matched
the vendored tree byte for byte.

Numbering gaps stay intentional (0005 folded into 0004; 0009/0010 were
upstreamed in 0.42.0 and stay gone).

## Upstream fit after 0.43-dev

| Patch | Upstream status | Plan |
|---|---|---|
| 0001/0002/0003 | Still not upstream. The process precondition the maintainers set for the 2026-07 RFC (#18258) — a gpu-next render backend — is now merged (#16818 → #17828 → the 2026-11-12 series), so a Vulkan render API re-proposal is the natural next upstream step. | Keep downstream for now; re-propose separately. |
| 0004 | The backend half is upstream; the get_info report is mpv_kit-only. | Keep downstream. |
| 0006 | Not upstream; upstream considers `stream_cb` sufficient. | Keep downstream. |
| 0007 | Hotplug half upstream in 0.42; the rest stays generic. | Keep the remainder downstream. |
| 0012 | Not upstreamable as-is. | Keep downstream until the release container moves. |

```text
$ bash tools/check_patches.sh
PATCH-DRIFT OK base=35efcf53d59470b3941e61a50c8a3133035a093d patches=8
```

**Independent re-verification (2026-11-15):** the official release tarball
`mpv-v0.42.0.tar.gz` (sha256
`bcfebbfa2b65a6d88dc97ea18117831072373e38b5785a2afb874ed4df5070dd`, from
`github.com/mpv-player/mpv/archive/refs/tags/v0.42.0.tar.gz`) with all seven
`0*.patch` applied in name order matches `native/mpv` exactly
(`diff -rq --strip-trailing-cr` -> 0 differences). The shipped v0.1.3
bundles report `mpv-version` = `0.42.0` at runtime and expose mpv 0.42's
`curl-enabled` option; the Linux artifacts are byte-identical to the v0.1.1
builds, macOS/Windows differ only by CI toolchain drift. An earlier note in
this repo's history claimed a version drift to `v0.41.0-689`; that was a
misread of a system `libmpv-2.dll` found on PATH, not of the bundle.

## Patch set after the 0.42.0 rebase

| Patch | State | What changed in this rebase |
|---|---|---|
| 0001 vo_libmpv Vulkan render backend | kept | Rebased onto 0.42's Vulkan context (maintenance11, internally synchronized queues, shader-object removal). Absorbs the `done_frame` bool adaptation for upstream `video/out/d3d11/libmpv_d3d11.c` (upstream still returns `void`). Adds `render_vk.h` to the pkg-config header list conditionally. |
| 0002 hwdec_vulkan imported extensions | kept | Applied with fuzz at `hwdec_vulkan.c:124`; the `imported_extensions` branch now sits next to 0.42's `queue_flags`/`lock_queue` handling. |
| 0003 persistent shader cache for libmpv_vk | kept | `libmpv_vk.c` is our own file; only offsets. |
| 0004 gpu-next render backend + renderer report | kept | 18 hunks, no rejects. Keeps the Windows D3D11 **gpu-next** branch: upstream 0.42's D3D11 render API only serves the `gpu` renderer. Rebased over 0.42's color-management and queue changes. |
| 0006 asynchronous stream bridge | kept | `stream/stream_cb.c` is unchanged upstream; only the `meson.build` header list needed a manual hunk (0.42 installs `render_d3d11.h`). |
| 0007 audio device enumeration fixes | shrunk | The hotplug MTA half is upstream (`4dfee616d0fd`); only the playback-path COM lifetime, the CoreAudio NULL guards and the changenotify double-uninit guard remain. |
| 0008 vendor integration fixes | **deleted** | Upstream release tags commit `MPV_VERSION` (`0.42.0`); no vendor stamp patch is needed. |
| 0009 upstream backports | **deleted** | All four backported commits are in 0.42.0. |
| 0010 upstream D3D11 render API | **deleted** | PR #17764 merged as `4255130de4`; client API 2.6 and `render_d3d11.h` are upstream. |
| 0012 libdrm 2.4.113 floor | kept | 0.42 still requires libdrm >= 2.4.114 and the release job still builds in `ubuntu:22.04` (libdrm 2.4.113). Drop only when the release container ships >= 2.4.114. |

Numbering gaps are intentional (0005 was folded into 0004; 0008/0009/0010
were upstreamed) so existing references keep their meaning.

## Rebase notes (0.42.0, 2026-11-07)

- **0001**: `video/out/vulkan/context.c` moved by 12 lines; manual
  adaptations were the pkg-config header list and the new upstream
  `libmpv_gpu_context_d3d11` extern in `video/out/gpu/libmpv_gpu.h`.
- **0002**: fuzz 2 at `hwdec_vulkan.c:124`; the branch is semantically
  intact and coexists with the queue flags code.
- **0004**: offsets up to 30 lines. Fuzz-2 hunks are the `sw` null guards
  in `get_ref_luma()` and `apply_target_options()`; `update_overlays()`
  clears `num_overlays` before `osd_render()` and returns when `vo->osd`
  is not attached; `update_render_options()` stores `req_frames` and skips
  `vo_set_queue_params()` under libmpv, where
  `libmpv_update_external()` applies it to the real VO.
- **0006**: only the `meson.build` header list needed a manual hunk.
- **0007**: the two hotplug hunks were rejected because 0.42 already
  keeps an MTA usage cookie (`hotplug_mta`); the playback instance keeps
  its own `mta_cookie`/`com_thread`.
- **0012**: offsets only.

## libplacebo

0.42 requires **libplacebo >= 7.387.0** (`meson.build`). The 16 patches
in `native/deps/libplacebo/` were backports of upstream commits that are
all ancestors of `v7.387.0`; the dependency bump for 0.1.0-dev.10 removes
them together with the hard-coded patch count and the `glsl/meson.build`
workaround.

## Upstream fit

| Patch | Upstream status | Plan |
|---|---|---|
| 0001/0002/0003 | Not upstream. The previous RFC (mpv-player/mpv#18258) was rejected on process grounds; maintainers asked for a gpu-next render backend first. | Keep downstream. |
| 0004 | Not upstream. It is the first step the maintainers asked for and also carries the D3D11 gpu-next branch. | Keep downstream; propose separately later. |
| 0006 | Not upstream; upstream considers `stream_cb` sufficient. | Keep downstream. |
| 0007 | Hotplug half is upstream (`4dfee616d0fd`); playback COM lifetime and CoreAudio guards are generic and still downstream. | Keep the remainder downstream. |
| 0012 | Not upstreamable as-is (upstream deliberately requires libdrm 2.4.114). | Keep downstream until the release container moves. |

**Decision:** the patches stay downstream-only. Their priorities are
runtime efficiency and stability in mpv_kit, not upstream acceptability.

## License

0.1.0-dev.10 switches the distributed bundle to **GPL full**:
`-Dgpl=true` plus libcdio/libcdio-paranoia/libdvdnav/libdvdread/libdvdcss
for CD and DVD,
and libbluray/libaacs/libbdplus for Blu-ray/UHD HDMV. See `NOTICE`,
`docs/adr/0007-gpl-full-bundle.md` and `README.md`.
