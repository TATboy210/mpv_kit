---
quick_id: 261028-moj
slug: strict-mpvlibrary-open-for-explicit-path
type: quick
decision: option C (user, 2026-10-28)
---

# Quick 261028-moj: strict MpvLibrary.open for explicitly named libraries

Goal: an explicit `path` or a non-empty `MPV_KIT_LIBMPV_PATH` is tried alone;
only with neither given do the platform default names run. Failure throws
`MpvLibraryNotFound` carrying the loader's reason (API-version mismatch counts).

## Tasks

1. `packages/mpv_kit/lib/src/ffi/library.dart` strict resolution + doc comments
   + `MpvLibraryNotFound.toString` hint; CHANGELOG entry (`packages/mpv_kit`).
   verify: `cd packages/mpv_kit && dart analyze --fatal-infos`
2. `packages/mpv_kit/test/library_test.dart` rewritten for the new contract
   (explicit-missing throws with only that path; env-missing via a subprocess;
   defaults resolve; cache-ignores-different-path stays).
   verify: `dart test test/library_test.dart` (with and without
   `MPV_KIT_LIBMPV_PATH`), then the full `dart test`.
3. Docs: README (two spots), docs/ARCHITECTURE.md, docs/MIGRATING_FROM_MEDIA_KIT.md.
4. Remove `example/integration_test/libmpv_guard.dart` and its call sites in
   `d3d11_backend_test.dart` / `d3d11_device_lost_test.dart`; grep for other
   fall-through reliance.
   verify: `flutter analyze --fatal-infos` in example and packages/mpv_kit_video.
5. Golden freeze + push + CI (native-verify, flutter-plugin, macos-route);
   fix workflow setup (not the loader) for jobs that relied on fall-through.
   verify: `sha256sum -c .planning/phases/14-windows-native-d3d11-backend/evidence/golden-freeze-14.sha256`

## Constraints
Protected planning files untouched; stage by explicit path; no ROADMAP changes.
