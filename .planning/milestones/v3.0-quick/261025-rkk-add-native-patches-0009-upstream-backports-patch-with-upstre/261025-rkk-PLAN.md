---
phase: quick-261025-rkk
plan: 261025-rkk
type: execute
depends_on: [261025-rke, 261025-rkf]
files_modified:
  - native/mpv/ta/ta_talloc.h
  - native/mpv/video/out/vo_gpu_next.c
  - native/mpv/video/sws_utils.c
  - native/mpv/video/zimg.c
  - native/patches/0009-upstream-backports.patch
  - native/patches/UPSTREAM.md
  - tools/check_patches.sh
autonomous: true
---

# 261025-rkk: 0009: low-risk upstream mpv backports

`tools/check_patches.sh` globs `native/patches/0*.patch`, so 0009 is picked up
automatically and applies after 0001..0008. Final touched-file list depends on
Task 1 (player/* and filters/f_decoder_wrapper.c are added only if 691a86b and
228e02c are accepted).

## Task 1: applicability result (checked 2026-10-25 against the vendored tree, done)
Cumulative `patch -p1 --dry-run` on a copy of native/mpv:

| sha | result | subject |
|---|---|---|
| 270367e8af7e | CLEAN (ta/ta_talloc.h, 2 lines) | ta_talloc: fix assert in MP_TARRAY_REMOVE_AT |
| 1f7ad6d31270 | FUZZ (vo_gpu_next.c, 8 lines) | vo_gpu_next: map queued frames again when baked-in options change |
| b6cab8fa0cc1 | FUZZ (vo_gpu_next.c, 35 lines) | vo_gpu_next: only re-upload OSD textures when they change |
| 5ce308b5730e | CLEAN (sws_utils.c, zimg.c, 9 lines) | keep the scalers across frames with dynamic HDR metadata |
| 691a86bfb8d0 | **DROP**: hunks in player/audio.c and player/video.c fail (needs earlier upstream player refactors) | fall back to the next track when a decoder fails to initialize |
| 228e02c2cd5e | **DROP**: follow-up of 691a86b, meaningless without it | handle the decoder init failure in the chain init functions |

Accepted, in this order: 270367e8af7e, 1f7ad6d31270, b6cab8fa0cc1, 5ce308b5730e.
Re-run the dry-run after rke and rkf land (they edit vo_gpu_next.c); the two
vo_gpu_next.c picks must stay fuzz-only, else stop and report.
Helper used: `C:/Users/35490/qb_scripts/fetch_mpv.sh <repo> <fresh_dir> <sha>...`.

## Task 2: apply and generate 0009
- Apply the accepted diffs with GNU `patch -p1` to native/mpv; resolve fuzz
  against 0004 by hand only where trivial.
- 0009 = `diff -u` of the touched files (tree before 0009 -> after), with a
  header listing the upstream shas.
- UPSTREAM.md: a 0009 row (taken shas; dropped shas with reasons; explicitly
  not taken: c1a7e4b42c4b, maintenance11 with an AMD Windows perf regression,
  and 6a262d11f637, a no-op until libplacebo >= 365 and lavu >= 60.32).

## Verify
- check_patches.sh OK; CI native-verify full; render_vk_smoke gpu-next.
- Commit: `feat(native): backport upstream gpu-next and talloc fixes (0009)`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- Gate: re-run the cumulative dry-run after rke and rkf; the output must
  contain no `FAILED`, `.rej`, `Reversed` or `can't find` (fuzz/offset lines
  are fine). Otherwise stop and report.
- After generating 0009, run `bash tools/check_patches.sh` and require
  `PATCH-DRIFT OK` with the patch count including 0009; update the stale
  "0001..0007" comment at check_patches.sh:3 (add to files_modified).
- 1f7ad6d sets `want_reset` from `update_render_options` and `last_ref_white`
  starts at 0, so the first options update after init triggers one reset.
  Harmless; note it. rkf no longer changes reset semantics.
- UPSTREAM.md also lists 4dfee616d0fd as not taken (0007 is a superset, see
  rkg).

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
