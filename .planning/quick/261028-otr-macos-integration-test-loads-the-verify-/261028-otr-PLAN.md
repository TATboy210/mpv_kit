---
type: quick
task: 261028-otr
slug: macos-integration-test-loads-the-verify-
---

# Quick 261028-otr: macOS integration leg loads the branch libmpv

## Goal
The `integration-test (macos-15, ...)` leg of native-verify.yml must load the
branch's `libmpv.2.dylib` (artifact `libmpv-verify-macos-macos-15`), not the
pinned v0.1.0-dev.3 bundle, and prove it.

## Investigation
- Hook (`packages/mpv_kit_libs/hook/build.dart`) accepts `libmpv_bundle` as a
  dir with `lib/*.dylib` (+ optional MANIFEST.txt) and emits one CodeAsset per
  dylib; Flutter wraps each in a framework.
- Option (a), self-contained artifact via `native/build/package.sh`: rejected.
  The Darwin branch requires libavcodec to resolve from the build PREFIX (LGPL
  FFmpeg from `ffmpeg.sh`) and `check_gpl` fails on GPL libs. The verify job
  builds against Homebrew FFmpeg (x264/x265 closure) and no headerpad, so the
  script fails by design there, and rebuilding the LGPL stack in the verify
  job is out of scope for a CI-only change.
- Option (b) chosen: the staged dylib's Homebrew deps are blocked only by the
  app sandbox. On the CI runner only, flip `com.apple.security.app-sandbox` to
  false in the checked-out `example/macos/Runner/DebugProfile.entitlements`
  (PlistBuddy, never committed), then use MPV_KIT_LIBMPV_PATH exactly like the
  Linux leg. Strict MpvLibrary means the staged build or a hard failure.

## Tasks
1. native-verify.yml: macOS-only step disabling the sandbox for the test build;
   MPV_KIT_LIBMPV_PATH set on macOS too; export MPV_KIT_EXPECT_LIBMPV_API=2.6
   on macOS.
2. real_plugin_test.dart (test-only): add `libmpvApi` and `mpvVersion` to the
   INTEGRATION line; when MPV_KIT_EXPECT_LIBMPV_API is set, expect equality.
3. Push, poll CI (max 3 fix rounds), SUMMARY, STATE row.
