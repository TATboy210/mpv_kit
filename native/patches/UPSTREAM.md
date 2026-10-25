# Upstreaming status of the mpv_kit patches

Base: mpv 0.41.0-1115 (gb2c255c13, 2026-10-09 "wayland: use configure
bounds in window geometry"; vendored as `native/mpv`, `MPV_VERSION`
records the exact base). Previously 0.41.0-1113 (gfd9265a905); advanced
2026-10-24 (milestone v2 Phase 7).

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

## Rebase onto 0.41.0-1115 (2026-10-24, milestone v2 Phase 7)

The user-provided mpv-master snapshot (no git metadata) was identified by
blob-hash walk and FULL-TREE verification as exactly `b2c255c13e8e`
(diff count 0, excluding the zip's stray .code-review-graph). The advance
from the previous base is just two upstream commits:

- `06ee185d3` "osdep/io: restore umask-based file creation permissions" —
  upstream adopted the exact open-mode change (0600 -> 0666) our old 0008
  carried: **that delta is superseded and dropped**.
- `b2c255c13` "wayland: use configure bounds in window geometry" — the
  wayland_common.c refactor our old 0008 papered over by keeping the
  pre-refactor snapshot: **that delta is superseded and dropped**; the
  vendor now carries upstream's refactored wayland.

Consequences: 0001..0007 replayed onto the new base with zero rejects
(only fuzz/offset notes: 0001 x3, 0002 x1, 0006 x2, 0007 x3 — recorded in
the patch files' application, no hunks hand-ported this time);
**0008 shrank to the MPV_VERSION vendor stamp** (the version file is
build-generated upstream, UNKNOWN without git). PATCH-DRIFT verifies
byte-identity at the new base.

| Patch | Upstream fit | Plan |
|---|---|---|
| 0001 vo_libmpv Vulkan render backend | A previous RFC (mpv-player/mpv#18258, closed 2026-07-13) was rejected on process grounds: maintainers asked for preserved authorship, small commits and for porting vo_gpu_next to the render API *first*. | RFC series in that order: (1) gpu-next render backend for the existing GL API, (2) Vulkan API type, (3) host-image semaphores. Needs maintainer buy-in before code. |
| 0002 hwdec_vulkan: imported device extensions | Small, self-contained, only meaningful together with 0001 (no imported devices exist upstream). Master changed the surrounding code (lock_queue deprecation, queue creation flags), so it must be rebased. | Submit as part of the 0001 series. |
| 0003 persistent pl_cache for libmpv_vk | Depends on 0001. vo_gpu_next already has the same cache layout. | Part of the series. |
| 0004 gpu-next render backend + active renderer via get_info | This is step (1) the maintainers asked for; 0005's tiny API addition is folded in (it depends on 0004 and shares its files). | First PR to propose (split 0005 back out for review). |
| 0006 asynchronous stream bridge | mpv-specific glue for hosts that cannot answer stream_cb synchronously (Dart). Upstream's view so far is that stream_cb is enough. | Keep downstream. |
| 0007 audio device enumeration crashes | Two real upstream bugs: (a) macOS builds with `-Dcocoa=disabled` leave `cfstr_get_cstr` and Foundation/Metal symbols as dynamic lookups (hidden by upstream's `b_lundef=false`), so reading a device UID calls NULL; (b) WASAPI ties its hotplug/playback COM objects to the init thread's apartment, but `mpv_terminate_destroy` releases them on the client thread after the core thread exited, after COM unloaded mmdevapi. Fixed with `CoIncrementMTAUsage` and thread-checked `CoUninitialize`. | Keep downstream (both fixes are generic and could be offered upstream later). |
| 0008 vendor integration fixes | The MPV_VERSION vendor stamp only — upstream commits `06ee185d3`+`b2c255c13` superseded the old io.c/wayland deltas in the 2026-10-24 rebase. | N/A (re-generated at each rebase). |

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

## Stability fixes (2026-10-25)

- 0006: `stream_cb.c s_close` detaches the cancel callback before
  `close_fn`. `p->cancel` is freed with the stream, after `close_fn`, so a
  cancel arriving in between called `cancel_fn` on a closed cookie
  (use-after-free in the bridge). Generic upstream bug: any `stream_cb`
  host that sets `cancel_fn` and frees its cookie in `close_fn` is exposed.
- 0006: `bridge_open` sends `MPV_KIT_STREAM_CLOSE` to the host and returns
  `MPV_ERROR_LOADING_FAILED` when allocating the bridge stream fails after
  the host opened its side (the host source leaked until shutdown).
- 0006: `bridge_seek` fails (`MPV_ERROR_GENERIC`) when the host lands on a
  different offset than requested. Behaviour change: a host that clamps an
  out-of-range seek (e.g. past EOF) now fails the seek instead of silently
  desynchronising mpv's stream position.
- 0001/0004: `libmpv_gpu_context_fns.done_frame` returns `bool`; when
  `pl_vulkan_hold_ex` fails to hand the target back, `render()` (gpu) and
  `libmpv_render()` (gpu-next) return `MPV_ERROR_GENERIC` instead of
  reporting success for a frame whose host semaphore is never signalled.
- 0001: `render_vk` rejects `num_extensions < 0` or a NULL extension list
  with a positive count, and a NULL `signal_semaphore`
  (`MPV_ERROR_INVALID_PARAMETER`). Contract clarification, not a
  narrowing: a NULL signal semaphore already hit
  `pl_assert(params->semaphore.sem)` in `pl_vulkan_hold_ex` (libplacebo
  7.360.1), so this replaces an abort; render_vk.h now says the signal is
  required and only signalled on success.
- 0001: a pending wrapper reused by `wrap_fbo` takes the signal semaphore,
  value, final layout and queue family of the current call, so a wrapper
  left over from an aborted frame signals the value the host waits for now.
