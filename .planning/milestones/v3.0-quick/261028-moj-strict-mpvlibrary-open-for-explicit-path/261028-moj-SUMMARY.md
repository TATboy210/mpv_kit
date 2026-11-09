---
quick_id: 261028-moj
slug: strict-mpvlibrary-open-for-explicit-path
status: complete
date: 2026-10-28
commits: [dd75d28, 2c5e638, c603092, 6d64c6a, 0151606]
---

# Quick 261028-moj: strict MpvLibrary.open for explicitly named libraries

`MpvLibrary.open` now tries an explicit `path`, else a non-empty
`MPV_KIT_LIBMPV_PATH`, ALONE and throws `MpvLibraryNotFound` (with the loader's
reason; API-version mismatch included) instead of falling through; defaults are
tried only when neither is given. Process cache, `resolvedPath` and
`lastOpenAttempts` semantics unchanged.

## Commits
- dd75d28 feat(mpv_kit): strict resolution, doc comments, `toString` hint, CHANGELOG (also removes `libmpv_guard.dart`)
- 2c5e638 test(mpv_kit): `library_test.dart` rewritten + `test/fixtures/open_probe.dart`
- c603092 docs: README, ARCHITECTURE, MIGRATING_FROM_MEDIA_KIT
- 6d64c6a test(example): drop `expectConfiguredLibmpv()` call sites; CI comment
- 0151606 ci: macOS integration test no longer sets `MPV_KIT_LIBMPV_PATH`

## Tests
Env-var cases run in a child process (`dart run test/fixtures/open_probe.dart`,
the same pattern as `dispose_with_children.dart`): the environment is fixed per
process and the loader caches the first successful load. Cases: explicit
missing path (only that path in attempts), missing env var (child), empty env
counts as unset (child), defaults resolve (skip unless `MPV_KIT_REQUIRE_LIBMPV`),
cache ignores a different path, valid explicit path beats a broken env (child).

## Verification
- `dart analyze --fatal-infos` (mpv_kit), `flutter analyze --fatal-infos` (example, mpv_kit_video): clean.
- `library_test.dart`: 7/7 pass with and without `MPV_KIT_LIBMPV_PATH` (with the
  pinned Windows bundle on PATH the "defaults" test runs for real; without it
  the dependent cases skip).
- Full `dart test` (mpv_kit, bundle libmpv): all pass except
  `player_test.dart` "default hwdec-codecs ... without ffv1" (the pinned
  v0.1.0-dev.3 bundle's mpv default list contains `apv`); unrelated to the
  loader, not touched.
- Golden freeze `sha256sum -c golden-freeze-14.sha256`: all OK (library.dart is not in the frozen set).
- CI on feat/mpv-master-upgrade (PR #1), head 0151606: flutter-plugin 40658822251, macos-route 40658822289, native-verify 40658822303 all success.

## Deviation: job that relied on fall-through
native-verify `integration-test (macos-15)` failed on the first push (run
40657124863, `MpvLibraryNotFound`: the sandboxed example app could not read the
staged dylib's `/opt/homebrew/opt/libass` dependency, "file system sandbox
blocked open()"); previously it silently fell through to the bundled libmpv.
Fixed in the workflow (0151606): `MPV_KIT_LIBMPV_PATH` is empty on macOS for
that step (empty = unset), the bundle is loaded deliberately; the staged path
moved to `STAGED_LIBMPV` for the PATH/DYLD setup. Loader not loosened. One fix round used.
The Windows D3D11 jobs (the original reason for `libmpv_guard`) passed strict.

## Not verified
Local macOS/Linux behaviour (only Windows locally; CI covers the others).
