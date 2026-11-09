---
phase: quick-261025-rke
plan: 261025-rke
type: execute
depends_on: []
files_modified:
  - native/mpv/video/out/gpu/libmpv_gpu.h
  - native/mpv/video/out/gpu/libmpv_gpu.c
  - native/mpv/video/out/opengl/libmpv_gl.c
  - native/mpv/video/out/vulkan/libmpv_vk.c
  - native/mpv/video/out/vo_gpu_next.c
  - native/mpv/include/mpv/render_vk.h
  - packages/mpv_kit_video/src/include/mpv/render_vk.h
  - packages/mpv_kit_video/src/video_renderer.cc
  - packages/mpv_kit_video/src/vulkan_backend.h
  - packages/mpv_kit_video/src/vulkan_backend.cc
  - native/tests/render_vk_smoke.c
  - native/patches/0001-vo_libmpv-add-vulkan-render-backend.patch
  - native/patches/0004-libmpv-gpu-next-render-backend-and-renderer-report.patch
  - native/patches/UPSTREAM.md
autonomous: true
---

# 261025-rke: Propagate render-target return failures; validate render_vk params; roll back unsignalled timeline value

Verified facts:
- `libmpv_gpu_context_fns.done_frame` is `void` (libmpv_gpu.h:35); implemented in
  `vulkan/libmpv_vk.c` (done_frame -> release_target) and `opengl/libmpv_gl.c:87`.
  Callers `gpu/libmpv_gpu.c render()` (:194) and `vo_gpu_next.c libmpv_render()`
  (:3251) return 0 unconditionally.
- `release_target()` only logs when `pl_vulkan_hold_ex` fails; the host semaphore
  is then never signalled, yet render reports success.
- Consumer `video_renderer.cc` (~544-590): `NextSignalValue(back)` sets
  `ring_[back].ready_value = ++timeline_value_` before render; on `err < 0` the
  frame is not published but `ready_value` keeps a value nobody signals, so the
  next `WaitImage(back)` waits 1 s and reports a false "gpu timeout". (Timeline
  waits are `>=`, so this bites when `back` is reused before a later frame
  signals a higher value, i.e. the retry path.)
- `libmpv_vk.c init` (~209) uses `ip->num_extensions` unchecked.

## Task 1: native propagation + validation (0001/0004)
- `done_frame` -> `bool`; GL impl returns `true`; VK impl returns the
  `release_target()` result (true when there was no target).
- `gpu/libmpv_gpu.c render()` and `vo_gpu_next.c libmpv_render()`:
  `if (!done_frame(...)) return MPV_ERROR_GENERIC;`.
- `libmpv_vk.c init`: reject `num_extensions < 0 || (num_extensions > 0 && !extensions)`
  with `MPV_ERROR_INVALID_PARAMETER`; `wrap_fbo`: reject
  `signal_semaphore == VK_NULL_HANDLE` before wrapping (libplacebo requires it).
- `render_vk.h`: comment-only, and rewrite :115 ("VK_NULL_HANDLE disables the
  corresponding wait/signal") to: wait may be VK_NULL_HANDLE; signal is
  required (`pl_vulkan_hold_ex` asserts it, so NULL already aborts today). (signal guaranteed only when render succeeds;
  signal_semaphore required). Mirror the identical text into the plugin copy
  `packages/mpv_kit_video/src/include/mpv/render_vk.h` (diff the two copies).
- Ownership: libmpv_gpu.*, libmpv_gl.c, libmpv_vk.c, render_vk.h -> 0001;
  vo_gpu_next.c -> 0004.

## Task 2: consumer rollback (plugin, internal C++ only)
- `VulkanContext::RollbackSignalValue(int i, uint64_t previous)` restores
  `ring_[i].ready_value`; `video_renderer.cc` saves the previous value before
  `NextSignalValue(back)` and rolls back when `err < 0`, with a comment.
- `render_vk_smoke.c`: a case with `signal_semaphore = VK_NULL_HANDLE` expects a
  negative render result; existing passes unchanged.

## Task 3: fold, document, verify
- Regenerate 0001 and 0004; UPSTREAM.md notes.
- Verify: check_patches.sh OK; `flutter analyze --fatal-infos` in
  packages/mpv_kit_video; CI plugin builds (Win/Linux/macOS) and render_vk_smoke
  (gpu-next and gpu variants).
- Commits: `fix(native): propagate render target return failures`,
  `fix(video): roll back unsignalled timeline value on render failure`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- Contract clarification, not a narrowing: record in UPSTREAM.md (0001 row)
  that a NULL `signal_semaphore` previously hit `pl_assert(params->semaphore.sem)`
  in `pl_vulkan_hold_ex` (libplacebo gpu_tex.c, 7.360.1), so rejecting it with
  `MPV_ERROR_INVALID_PARAMETER` only replaces a crash. Plugin
  (video_renderer.cc:572) and smoke (render_vk_smoke.c:289) never pass NULL.
- Stale wrapper: when `wrap_fbo` reuses the pending wrapper (`same_image`,
  libmpv_vk.c:256-285), copy `img->signal_semaphore`/`signal_value` (and
  `queue_family`/`final_layout`) into `p->image` so `release_target` signals
  the value the host is waiting for now.
- Verified in libplacebo 7.360.1 (gpu_tex.c:1413-1475): `hold_ex` returns false
  before `CMD_SUBMIT` on "already held" and on command-begin failure, so no
  signal is submitted on those paths; a failed `CMD_SUBMIT` also signals
  nothing. Rolling back `ready_value` is therefore correct.
- The NULL-semaphore smoke case runs in both the gpu and gpu-next variants.
- Record the CI run links in the summary (no local native verification).

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
