---
phase: quick-261025-rkf
plan: 261025-rkf
type: execute
depends_on: [261025-rke]
files_modified:
  - native/mpv/video/out/vo_gpu_next.c
  - native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch
  - native/patches/UPSTREAM.md
autonomous: true
---

# 261025-rkf: gpu-next libmpv: keep host ICC across option changes; document immediate reset

Verified facts:
- `libmpv_set_parameter` (vo_gpu_next.c ~3152) hands the host ICC to `update_icc()`,
  but every `draw_frame -> update_options -> update_render_options -> update_icc_opts`
  (~2752) unloads the profile when `--icc-profile` is empty, so colour
  management silently turns off after any render-option change (the plugin only
  resends on `icc_pending_`).
- `VOCTRL_RESET` sets `want_seek_reset` (deferred to the first new frame id,
  ~2246); `libmpv_reset` (~3182) sets `want_reset` (immediate queue reset plus
  `flush_cache`). vo_libmpv raises `need_reset` on VOCTRL_RESET and VO uninit,
  causing needless renderer-cache flushes and stale-frame redraws.

## Task 1: host ICC persistence
- `struct priv`: `bstr libmpv_icc` (talloc copy owned by priv).
  `libmpv_set_parameter` stores a copy (replacing the old one) and passes a
  second copy to `update_icc`.
- `update_icc_opts` "no profile" branch: if `p->libmpv && p->libmpv_icc.len`,
  re-apply `bstrdup(NULL, p->libmpv_icc)`, clear `icc_path`, return. An explicit
  `--icc-profile` path never reaches this branch, so it still wins. Confirm
  `pl_icc_update` short-circuits on an unchanged signature (no per-frame cost).

## Task 2: #16818 check (reset change dropped)
- `libmpv_reset` stays `want_reset = true` (dropped after review). vo_libmpv
  also calls reset on VO uninit/recreate (vo_libmpv.c:714-721, 388-389); the
  priv outlives the VO, so a new VO restarts frame ids below `p->last_id`
  and a deferred reset (gated on `frame_id > p->last_id`, vo_gpu_next.c:1390,
  which also disables the refill fallback at :1405) would keep the previous
  file's frames queued. Only add a comment at `libmpv_reset` explaining why
  it must stay immediate.
- grep `pl_color_adjustment` in the libmpv paths; zero-init a partially
  initialised local if one exists (mpv PR #16818 report). Record the result.

## Task 3: fold into 0004, UPSTREAM.md, verify
- check_patches.sh OK; CI render_vk_smoke (gpu-next). Manual (desktop/CI):
  set an ICC profile, change `deband` at runtime, confirm the profile stays
  applied (verbose log).
- Commit: `fix(native): keep host ICC and document immediate reset in gpu-next libmpv`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- ICC: also guard the two other unload paths, not only the no-profile branch:
  `vo_gpu_next.c:2738` (`!profile_auto && !icc_path` unloads on every
  `update_options`) and `update_auto_profile` (~1917-1931, the plugin turns on
  `--icc-profile-auto`, video_renderer.cc:196, and libmpv returns no auto
  profile). Both skip the unload when `p->libmpv && p->libmpv_icc.len`.
- Blob ownership: replace with `talloc_free(p->libmpv_icc.start);
  p->libmpv_icc = bstrdup(p, blob)`; a host NULL/size 0 (the plugin passes
  nullptr, video_renderer.cc:198) clears `libmpv_icc` and unloads. A later
  user `--icc-profile` wins; clearing it falls back to the host profile
  (record in UPSTREAM.md, 0004 row).
- Place the new field next to `icc_path` (~169), not near `paused` (~152-155),
  which is 1f7ad6d's hunk context for rkk.
- Threading: `mpv_render_context_set_parameter` does not take `ctx->lock`
  (vo_libmpv.c:461-464) and the plugin calls `ApplyIccProfile` on its render
  thread (video_renderer.cc:322), the same thread as draw; no lock needed.
  Write this premise into the code comment.

**Host facts:** this host is Windows (MSYS Git Bash, MSVC on PATH, no meson/ninja),
so libmpv and `native/tests` cannot be built locally; native build/tests run on
CI (`.github/workflows/native-verify.yml`, incl. the ASan/UBSan job). Dart
tests run locally with `MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll`
(mpv v0.41.0-689, an older local build without this branch's patches; tests
that need patched native behaviour must skip locally and run on CI).

**Patch regeneration (shared rule, see native/patches/UPSTREAM.md):** the vendored
tree must equal base + `native/patches/0*.patch` applied in order with GNU
`patch -p1`. To fold a vendored edit into its owning patch: for files the
owning patch *creates*, replace that file's section with a `/dev/null` diff of
the new content (keep its CRLF/LF bytes exactly: `git ls-files --eol`); for
upstream files, add/replace the file section with `diff -u` against the base
content (= content before this item when no other patch touches the file;
confirm with `grep -l <file> native/patches/*.patch`). Preserve each patch's
existing line endings (some are `i/mixed`). Then run
`bash tools/check_patches.sh` (needs network; runnable on this Windows/MSYS
host) and require `PATCH-DRIFT OK`.
