---
phase: quick-261025-rki
plan: 261025-rki
type: execute
depends_on: []
files_modified:
  - packages/mpv_kit/lib/src/core/mpv.dart
  - packages/mpv_kit/test/mpv_test.dart
  - packages/mpv_kit/test/fixtures/dispose_with_children.dart
autonomous: true
---

# 261025-rki: Mpv.dispose: destroy live child clients before terminating the core

Verified facts: `mp_shutdown_clients` (client.c:556) loops while
`clients->num_clients` (weak clients included) is non-zero. `Mpv.dispose` on
the owner calls `terminateDestroy` synchronously, so a child created via
`createClient` (destroyable only from this now-blocked isolate) hangs the
process forever. Existing tests always dispose children first (mpv_test.dart:188,
api_surface_test.dart:37).

## Task 1 (RED): test in mpv_test.dart
- Create an owner plus `createClient('child')` and a weak child; call
  `mpv.dispose()` without disposing the children. The hang is a synchronous
  FFI call, so a Dart `timeout:` can never fire: run the scenario in a child
  process (`Process.start(Platform.resolvedExecutable, ['run', <script>])`
  with a small script under test/fixtures/, forwarding
  MPV_KIT_LIBMPV_PATH), `.timeout(15 s)` on `exitCode`, kill on timeout,
  and assert exit code 0. Assert both children report `isDisposed` and
  that later calls on them throw `StateError`. Runs locally against
  bt/libmpv-2.dll.

## Task 2 (GREEN): mpv.dart
- Private `final _children = <Mpv>{};` and `Mpv? _parent` (set by `createClient`
  through the private constructor). `dispose()` first runs
  `for (final c in _children.toList()) c.dispose();` (each child shuts down its
  own stream bridges and calls `mpv_destroy`), then the existing sequence; a
  child's dispose removes itself from `_parent?._children`. No public API change
  (api_freeze_test unchanged). Match the file's Chinese/English comment style.

## Verify
- Locally: `dart test test/mpv_test.dart test/api_freeze_test.dart test/api_surface_test.dart`;
  `dart analyze --fatal-infos`.
- Commits: the failing test first, then `fix(mpv_kit): dispose child clients before terminating the core`.

## Review revisions (2026-10-25, plan-checker pass; these are authoritative and supersede any conflicting text above)
- RED is observed locally (the child process times out and is killed); the
  test is committed together with the fix, never alone, so CI cannot hang.
- `_parent` is set to null when the child is disposed. Grandchildren (a client
  created from a child) are disposed recursively through the same loop; cover
  one grandchild in the test.
- Add one sentence to `dispose()`'s doc comment: disposing the owner also
  disposes clients created from it (behaviour change, no signature change).

**Host facts:** this host is Windows (MSYS Git Bash, MSVC on PATH, no meson/ninja),
so libmpv and `native/tests` cannot be built locally; native build/tests run on
CI (`.github/workflows/native-verify.yml`, incl. the ASan/UBSan job). Dart
tests run locally with `MPV_KIT_LIBMPV_PATH=D:/mpv_kit/bt/libmpv-2.dll`
(mpv v0.41.0-689, an older local build without this branch's patches; tests
that need patched native behaviour must skip locally and run on CI).


