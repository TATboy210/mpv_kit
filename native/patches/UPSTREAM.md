# Upstreaming status of the mpv_kit patches

Base: **mpv 0.42.0** (`b0841e8c4d156b8403dc1876c4cbd9011eb583f3`,
2026-11-04). `native/mpv/MPV_VERSION` is upstream's `0.42.0`: release
tags commit the version file, so the old `MPV_VERSION` patch is gone.
Previously the base was `v0.41.0-1115-gb2c255c13` (2026-10-09 master
snapshot); the advance to the release tag is 337 upstream commits.

**Provenance gate (2026-11-07):** `tools/check_patches.sh` now accepts
both forms in `MPV_VERSION`:

- a release version (`0.42.0`) -> upstream tag `v0.42.0`;
- a git describe string (`v0.41.0-1113-gfd9265a905`) -> that commit.

It clones upstream blobless with `core.autocrlf=false`, applies every
`0*.patch` in name order with GNU `patch -p1`, and requires the result to
be byte-identical to `native/mpv` (only `.git` and `.gitignore` are
excluded). GNU patch is required; `git apply` reports false success on
these files on this host.

```text
$ bash tools/check_patches.sh
PATCH-DRIFT OK base=b0841e8c4d156b8403dc1876c4cbd9011eb583f3 patches=7
```

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
`-Dgpl=true` plus libcdio/libdvdnav/libdvdread/libdvdcss for CD and DVD,
and libbluray/libaacs/libbdplus for Blu-ray/UHD HDMV. See `NOTICE`,
`docs/adr/0007-gpl-full-bundle.md` and `README.md`.
