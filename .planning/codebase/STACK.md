---
last_mapped_commit: 9f90a45322ab3537941540e6b35a76d978669ef5
last_mapped_at: 2026-10-23
---
# Technology Stack

**Analysis Date:** 2026-10-23

## Languages

**Primary:**
- Dart 3.8+ (`^3.8.0` in `packages/mpv_kit/pubspec.yaml`, `example/pubspec.yaml`, root `pubspec.yaml`) — FFI bindings, event loop, high-level `Player`, Flutter video output. `packages/mpv_kit_libs/pubspec.yaml` and `packages/mpv_kit_video/pubspec.yaml` require `^3.10.0` because the native-assets build hook needs Dart 3.10.
- Dart SDK resolved by the workspace lock: `>=3.11.0 <4.0.0` (`pubspec.lock`, `sdks` section).

**Secondary:**
- C11 — native smoke tests (`native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c`) and vendored `volk` loader (`packages/mpv_kit_video/third_party/volk/volk.c`).
- C++17 — Flutter plugin native code (`packages/mpv_kit_video/src/video_renderer.cc`, `vulkan_backend.cc`, `windows/mpv_kit_video_plugin.cpp`, `windows/d3d11_interop.cpp`, `linux/mpv_kit_video_plugin.cc`, `linux/gl_interop.cc`).
- Objective-C++ — macOS plugin (`packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm`, `metal_interop.mm`).
- Bash — native build/release tooling (`native/build/build.sh`, `deps.sh`, `ffmpeg.sh`, `package.sh`, `tools/*.sh`).
- Python 3 — ABI audit tooling (`tools/rea_abi_audit/pe_audit.py`) and Meson/Jinja2 in CI.
- C (upstream) — vendored mpv tree under `native/mpv/` and its patches in `native/patches/`.

## Runtime

**Environment:**
- Dart VM, plus the Flutter engine on the consumer side (`flutter: ">=3.38.0"` in `packages/mpv_kit_video/pubspec.yaml`).
- CI pins `FLUTTER_VERSION: 3.47.6` in `.github/workflows/flutter-plugin.yml`.
- Native runtime target: libmpv 0.41.0 (`native/mpv/MPV_VERSION`: `v0.41.0-1113-gfd9265a905`), client API 2.5, loaded into the process once by `MpvLibrary.open` (`packages/mpv_kit/lib/src/ffi/library.dart`).
- Supported OS baselines (from `.github/workflows/release.yml` and `README.md`): Windows 10+ (UCRT), macOS 12+, Linux glibc 2.35+; x64 and arm64.

**Package Manager:**
- Dart `pub` with a single pub workspace: root `pubspec.yaml` lists `packages/mpv_kit`, `packages/mpv_kit_libs`, `packages/mpv_kit_video`, `example`. Each member sets `resolution: workspace`.
- Lockfile: `pubspec.lock` present at the repo root, but listed in `.gitignore`; resolved versions are not committed.
- Native dependency managers: Meson + Ninja (`native/build/deps.sh`, `native/build/build.sh`), CMake (`native/build/deps.sh`, Flutter plugin `CMakeLists.txt`), CocoaPods (`packages/mpv_kit_video/macos/mpv_kit_video.podspec`).

## Frameworks

**Core:**
- Flutter plugin API — `packages/mpv_kit_video/pubspec.yaml` declares Windows (`MpvKitVideoPluginCApi`), Linux (`MpvKitVideoPlugin`), macOS (`MpvKitVideoPlugin`).
- `dart:ffi` — all libmpv calls in `packages/mpv_kit/lib/src/ffi/bindings.dart` (hand-written, 54 exported symbols, not ffigen-generated), event delivery via `NativeCallable.listener`.
- Dart native assets — build hook in `packages/mpv_kit_libs/hook/build.dart` using `code_assets` 2.1.0 and `hooks` 2.2.0.
- libmpv 0.41.0 (client API 2.5) with seven downstream patches in `native/patches/` (Vulkan VO backend, hwdec device extensions, persistent shader cache, gpu-next Vulkan backend, active-renderer report, asynchronous stream bridge, audio device enumeration fixes). Upstream notes in `native/patches/UPSTREAM.md`.
- libplacebo 7.360.1, Vulkan-only build (`native/build/deps.sh`).
- FFmpeg 8.1.3, LGPL build (`native/build/ffmpeg.sh`, pinned sha256).

**Testing:**
- `package:test` 1.31.1 — `packages/mpv_kit/test/` (8 files), `packages/mpv_kit_libs/test/bundle_test.dart`.
- `flutter_test` — `packages/mpv_kit_video/test/` (`controller_channel_test.dart`, `video_controller_test.dart`).
- Meson test suite — `native/tests/meson.build` builds `render_vk_smoke` (gpu-next and gpu variants) and `stream_bridge_test`.
- Coverage: `coverage` package in CI; `packages/mpv_kit/coverage/lcov.info`; CI fails below 80% line coverage (`.github/workflows/native-verify.yml`).
- Sanitizers: ASan + UBSan debug libmpv and native tests (`.github/workflows/native-verify.yml`, `sanitizers` job).

**Build/Dev:**
- `analysis_options.yaml` per package; `packages/mpv_kit` and `packages/mpv_kit_libs` use `package:lints/recommended.yaml`, `packages/mpv_kit_video` and `example` use `package:flutter_lints/flutter.yaml`. Strict casts/inference/raw types everywhere.
- `packages/mpv_kit/dart_test.yaml` declares tag `format` (excluded from default runs).
- Code generation scripts: `tools/gen_options.dart` (typed `MpvOptions` from the runtime option table), `tools/gen_catalog.dart` (property/command catalog from mpv docs), `tools/pin_bundles.dart` (sha256 pins from a GitHub release).

## Key Dependencies

**Critical:**
- `ffi` ^2.1.0 (resolved 2.2.0) — `calloc`, `Utf8`, FFI helpers used throughout `packages/mpv_kit`.
- `meta` ^1.15.0 (resolved 1.19.0) — annotations in the public API.
- `code_assets` ^2.1.0 (2.1.0) and `hooks` ^2.2.0 (2.2.0) — the native-assets build hook in `packages/mpv_kit_libs/hook/build.dart`.
- `crypto` ^3.0.6 (3.0.7) — sha256 verification of downloaded libmpv bundles (`packages/mpv_kit_libs/lib/src/bundle.dart`, `bundles.dart`).
- Flutter SDK packages — `packages/mpv_kit_video/lib/src/video_controller.dart` uses `MethodChannel`/`EventChannel`-style events (`MethodChannel('mpv_kit_video')`) and texture widgets.

**Infrastructure:**
- `lints` ^6.0.0 (6.1.0), `flutter_lints` ^6.0.0 (6.0.0), `test` ^1.25.0 (1.31.1).
- `cupertino_icons` ^1.0.8 (1.0.9) — example only.
- Vendored (not pub): Vulkan-Headers `vulkan-sdk-1.4.363.0` and volk same tag (`packages/mpv_kit_video/third_party/README.md`).
- Native stack pinned in `native/build/deps.sh` and `native/build/ffmpeg.sh`: Vulkan headers/loader 1.4.363.0, MoltenVK 1.4.2 (macOS), libdisplay-info 0.2.0 (Linux), glslang 16.6.0, lcms2 2.19.1, libplacebo 7.360.1, fast_float 8.3.2, dav1d 1.5.4, freetype 2.14.3, fribidi 1.0.17, harfbuzz 14.6.0, libass 0.17.5, uchardet 0.0.8, FFmpeg 8.1.3.

## Configuration

**Environment:**
- `MPV_KIT_LIBMPV_PATH` — explicit libmpv path override (`packages/mpv_kit/lib/src/ffi/library.dart`, used in all CI workflows).
- `libmpv_bundle` build user-define — local bundle archive/directory for `mpv_kit_libs` (`packages/mpv_kit_libs/hook/build.dart`).
- `MPV_KIT_VIDEO_RENDERER` — forces a renderer (`MpvVideoRenderer.tryParse`, `packages/mpv_kit_video/lib/src/video_controller.dart`).
- `MPV_KIT_FORMAT_SAMPLES` — sample directory for the format matrix test (`packages/mpv_kit/test/format_matrix_test.dart`).
- `MPV_KIT_EXAMPLE_AO`, `MPV_KIT_EXAMPLE_LOG` — example app only (`example/lib/main.dart`).
- `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` — honored by bundle downloads (`packages/mpv_kit_libs/lib/src/bundle.dart`) and `tools/pin_bundles.dart`.
- Bundle pins: `bundleTag = 'v0.1.0-dev.3'` plus per-target sha256 in `packages/mpv_kit_libs/lib/src/bundles.dart`.
- No `.env` files exist in the repository (checked with a glob; no secrets files committed).

**Build:**
- Workspace manifest `pubspec.yaml`; per-package manifests and `analysis_options.yaml`.
- Native plugin builds: `packages/mpv_kit_video/windows/CMakeLists.txt`, `packages/mpv_kit_video/linux/CMakeLists.txt`, `packages/mpv_kit_video/macos/mpv_kit_video.podspec`.
- Native libmpv build: `native/build/build.sh`, `deps.sh`, `ffmpeg.sh`, `package.sh`; Meson options are explicit to keep an LGPL-only bundle.
- CI: `.github/workflows/flutter-plugin.yml` (plugin build/analyze/test on Linux/Windows/macOS), `.github/workflows/native-verify.yml` (libmpv build, ABI audit, smoke tests, Dart tests, sanitizers), `.github/workflows/release.yml` (six-target LGPL bundles published to GitHub Releases on `v*` tags).

## Platform Requirements

**Development:**
- Dart 3.10+ (lock resolves 3.11.0+); Flutter 3.38+ for `packages/mpv_kit_video` and `example`.
- A prebuilt libmpv for running tests: either `MPV_KIT_LIBMPV_PATH` or the bundle from `mpv_kit_libs`.
- Building libmpv locally: Meson, Ninja, CMake, pkg-config, nasm (x86), Python 3 + Jinja2, a C/C++ toolchain. Linux test runners also need `libepoxy-dev`/GTK for the plugin and lavapipe or a Vulkan GPU for smoke tests.
- macOS plugin building goes through CocoaPods and requires Xcode with C++17 support.

**Production:**
- Windows 10+, macOS 12+, or Linux with glibc 2.35+; x64 or arm64.
- A Vulkan 1.3 driver for hardware rendering (falls back to mpv software rendering via `MPV_RENDER_API_TYPE_SW`).
- Host-provided system libraries on Linux: libc/libstdc++, X11/xcb, Wayland, EGL/GL, Vulkan loader, VA-API, ALSA/PulseAudio/PipeWire, fontconfig (`native/build/package.sh` system allowlist).

---

*Stack analysis: 2026-10-23*
