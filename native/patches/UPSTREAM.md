# Upstreaming status of the mpv_kit patches

Base: mpv 0.41.0-1113 (gfd9265a905, mpv master snapshot matching the
shinchiro 2026-10-09 build; vendored as `native/mpv`, `MPV_VERSION`
records the exact base). Previously mpv 0.41.0; rebased 2026-10-22.

**Provenance gate (2026-10-24):** `tools/check_patches.sh` fetches the
base commit, applies the patch set with GNU `patch -p1`, and diffs the
result against `native/mpv` — it must be byte-identical. The set was
regenerated from the vendored tree on 2026-10-24 to make that true:

- 0004 and 0005 were **merged** into
  `0004-libmpv-gpu-next-render-backend-and-renderer-report.patch`
  (they overlap on `render_vk.h`/`vo_libmpv.c`, and 0004's hand-rebase
  hunks — recorded below — only exist in the vendored tree, so the old
  0005 could not apply on top of them cleanly).
- **0005 is removed** (merged into 0004); the patch numbers 0006/0007
  keep their historical names.
- New **0008-vendor-integration-fixes.patch** carries the vendored-tree
  deltas that have no single-feature owner: `osdep/io.c` (open mode
  0600 → 0666), `video/out/wayland_common.c` (kept at the pre-refactor
  snapshot during vendoring; revisit before the next rebase), and
  `MPV_VERSION` (the version stamp is build-generated upstream).

`bash tools/check_patches.sh` is wired as the `patch-drift` job in
native-verify.yml.

| Patch | Upstream fit | Plan |
|---|---|---|
| 0001 vo_libmpv Vulkan render backend | A previous RFC (mpv-player/mpv#18258, closed 2026-07-13) was rejected on process grounds: maintainers asked for preserved authorship, small commits and for porting vo_gpu_next to the render API *first*. | RFC series in that order: (1) gpu-next render backend for the existing GL API, (2) Vulkan API type, (3) host-image semaphores. Needs maintainer buy-in before code. |
| 0002 hwdec_vulkan: imported device extensions | Small, self-contained, only meaningful together with 0001 (no imported devices exist upstream). Master changed the surrounding code (lock_queue deprecation, queue creation flags), so it must be rebased. | Submit as part of the 0001 series. |
| 0003 persistent pl_cache for libmpv_vk | Depends on 0001. vo_gpu_next already has the same cache layout. | Part of the series. |
| 0004 gpu-next render backend + active renderer via get_info | This is step (1) the maintainers asked for; 0005's tiny API addition is folded in (it depends on 0004 and shares its files). | First PR to propose (split 0005 back out for review). |
| 0006 asynchronous stream bridge | mpv-specific glue for hosts that cannot answer stream_cb synchronously (Dart). Upstream's view so far is that stream_cb is enough. | Keep downstream. |
| 0007 audio device enumeration crashes | Two real upstream bugs: (a) macOS builds with `-Dcocoa=disabled` leave `cfstr_get_cstr` and Foundation/Metal symbols as dynamic lookups (hidden by upstream's `b_lundef=false`), so reading a device UID calls NULL; (b) WASAPI ties its hotplug/playback COM objects to the init thread's apartment, but `mpv_terminate_destroy` releases them on the client thread after the core thread exited, after COM unloaded mmdevapi. Fixed with `CoIncrementMTAUsage` and thread-checked `CoUninitialize`. | Keep downstream (both fixes are generic and could be offered upstream later). |
| 0008 vendor integration fixes | Not a feature: `io.c` open-mode change, the wayland snapshot state, and the version stamp — the residual vendored-tree delta with no feature owner. | N/A (re-generated at each rebase). |

## Rebase onto mpv 0.41.0-1113 (2026-10-22)

`git apply` reports false success on this host (every hunk silently
"skipped"); patches are applied with GNU `patch -p1` instead — verify
with `git diff` after applying.

- 0001/0002/0003/0005/0006/0007: apply cleanly; 0002 does not touch the
  deprecated `lock_queue` mapper path, so the 2026-10-15 warning is moot.
- 0004: 8 of 13 hunks applied verbatim; the 5 conflicting ones were
  rebased by hand onto master's refactors of `vo_gpu_next.c`:
  - `update_overlays` gained 3D side-by-side handling and moved overlay
    bookkeeping to `state->num_overlays` — the `!vo->osd` guard now
    clears the count first and returns before `osd_render()`.
  - master rewrote the `dither_depth` swapchain probe as a ternary; the
    `sw` null guard is folded into it (`sw && sw->fns->color_depth`).
    The same guard was added to master's new `target_ref_luma` probe.
  - master replaced the `pass_colorspace`/`pl_swapchain_colorspace_hint`
    path with `set_colorspace_hint()`/`external_params`; the libmpv guard
    moved into `set_colorspace_hint()` (`p->libmpv` → `return false`),
    which covers both former call sites since `target_hint` is already
    forced false under libmpv.
  - `start_frame` region: the libmpv branch (`swframe = p->libmpv_target`)
    sits before master's `sw->fns->start_frame()` logic unchanged.
  - master changed `vo_set_queue_params()` to take a `num_frame_refs`
    argument; `update_render_options()` stores `p->req_frames` and skips
    the call under libmpv, and `libmpv_update_external()` now passes
    `2 * p->req_frames - 1` (same symmetric-mixing-window semantics as
    master's own call).

**Decision (2026-10-15):** the patches are maintained downstream only; no
upstream submission is planned. The table stays as the record of how each
patch relates to mpv master, which matters when rebasing onto a new mpv
release. Priorities for the patches are runtime efficiency and stability
in mpv_kit, not upstream acceptability.
