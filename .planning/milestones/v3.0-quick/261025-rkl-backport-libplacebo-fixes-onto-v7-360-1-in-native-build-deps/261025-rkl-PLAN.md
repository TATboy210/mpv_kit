---
phase: quick-261025-rkl
plan: 261025-rkl
type: execute
depends_on: []
files_modified:
  - native/build/deps.sh
  - native/deps/libplacebo/
  - native/patches/UPSTREAM.md
  - .github/workflows/native-verify.yml
  - .github/workflows/release.yml
autonomous: true
---

# 261025-rkl: Backport libplacebo stability fixes onto v7.360.1

Verified facts: deps.sh fetches `libplacebo-v7.360.1.tar.gz` (pinned sha256
14c0a99f...) and already edits its tree in place (sed on src/glsl/meson.build,
fast_float copy) before `meson_build libplacebo`. `native/deps/` exists.

## Task 1: applicability result (checked 2026-10-25, done)
Pinned tarball verified (sha256 14c0a99f...). Cumulative `patch -p1 --dry-run`
in upstream commit-date order (the requested order caused a spurious
13d0b798 conflict: it edits lines that 285d1cc8 adds):

Accepted (14, apply in this order, 0 rejects):
f89d3224a2 (renderer OOB), b1e1ea4f5e (vk_pool UAF), c4e054a044 (pl_calloc
overflow), 2ba21c07c0 (hold_ex signal after reads on other queues — our
zero-copy path), b9484d2852 (wait for all commands at sync points),
de357dcdd8 (present under recording lock; gpu.c/gpu.h part matters, swapchain
part unused by us), 3330a515d6 (poll pending through sync copy), 1937beef3a
(don't reuse a command while a thread waits on it), 285d1cc8af (pl_queue init
leak), 3ef51741f8 (partial-init cmd cleanup), 13d0b79827 (pl_queue init UAF),
ca33bdacfd (release cached textures on pl_queue_reset), 4aa872a15b (drop
invalid mastering primaries), 1532bf6893 (reject white point on gamut boundary).

Dropped (record in UPSTREAM.md): b6c62d4f04 and d5a5b4abbe — the timer
pending-bitmask pair sits on an intermediate refactor (`uint_fast8_t pending`)
absent from 7.360.1 (`uint64_t pending`); timers only feed perf statistics,
not a crash path.
Helper used: `C:/Users/35490/qb_scripts/fetch_placebo.sh <fresh_dir> <sha>...`
(diffs from haasn/libplacebo; regenerate the stored patches from these, LF).

## Task 2: wire into deps.sh
- Store the accepted patches as `native/deps/libplacebo/NNNN-<sha>.patch` (LF)
  plus a `SHA256SUMS`. deps.sh verifies the sums and applies them with
  `patch -p1` right after unpack (before the existing sed), failing hard on any
  reject.
- UPSTREAM.md: a libplacebo section (applied list, drops, and the FFmpeg 9
  prerequisites: libplacebo 409c9a8 and mpv 6a262d1, mpv #18588). LGPL
  unchanged.

## Verify
- Locally: the Task 1 dry-run log; `bash -n native/build/deps.sh`.
- CI: native-verify builds libplacebo and libmpv on all targets, the ASan job,
  render_vk_smoke.
- Commit: `build(native): backport libplacebo Vulkan sync and pl_queue fixes`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- Cache keys: native-verify.yml:60, :256 and release.yml:56, :127, :213 key on
  `hashFiles('native/build/deps.sh')` only; change all five to
  `hashFiles('native/build/deps.sh', 'native/deps/libplacebo/**')`, else a
  patch change reuses stale deps.
- Windows release MSYS2 (release.yml:205) installs only `make diffutils`; add
  `patch`.
- GNU patch everywhere: in deps.sh pick `PATCH=$(command -v gpatch || command -v patch)`
  and fail unless `"$PATCH" --version` mentions GNU; add `gpatch` to the macOS
  brew install (release.yml ~119). Apply with
  `"$PATCH" -p1 --batch --forward --fuzz=0 -i "$f"` under `set -e`.
- Checksums: reuse deps.sh's `sha256()` helper (~46; falls back to `shasum`),
  parse SHA256SUMS line by line and require exactly 14 entries matching the
  14 files; no `sha256sum -c`.
- Line endings: after writing the patches run `! grep -l $'\r' native/deps/libplacebo/*.patch`,
  then generate SHA256SUMS.
- Untrusted source: compare each stored diff with the upstream commit (`gh api
  repos/haasn/libplacebo/commits/<sha>` diff) before committing, and re-run the
  ordered dry-run on a clean 7.360.1 unpack; keep the log (and read the .err
  files).
- Coverage gap, stated honestly: native-verify builds libplacebo from deps.sh
  only on Linux (its macOS jobs use brew's libplacebo). macOS/Windows patch
  application is exercised only by release.yml; run it once via
  `workflow_dispatch` (needs user approval, it is outward-facing) or record the
  gap in the summary.

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
