---
last_mapped_commit: cd47d6761925b8ccb49e153864bf9789dc3f5039
last_mapped_at: 2026-10-27
---
# Technology Stack

**Analysis Date:** 2026-10-27

## Languages

**Primary:**
- Dart 3.10+ (`sdk: ^3.10.0` in root `pubspec.yaml`, `packages/*/pubspec.yaml`, `example/pubspec.yaml`). Used for FFI bindings, the event loop, the high-level `Player` and the Flutter video controller.
- C++17. Used for the Flutter plugin native code: `packages/mpv_kit_video/src/video_renderer.cc`, `vulkan_backend.cc`, `windows/*.cpp`, `linux/*.cc`.
- Objective-C++. Used for the macOS plugin: `packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm`, `metal_interop.mm`.

**Secondary:**
- C11. Used for the native tests (`native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c`) and the vendored `packages/mpv_kit_video/third_party/volk/volk.c`.
- Bash. Used for the build and release tooling in `native/build/build.sh`, `deps.sh`, `ffmpeg.sh` and `package.sh`.
- Python 3. Used for the ABI audit (`tools/rea_abi_audit/pe_audit.py`) and for Meson/Jinja2 in CI.
- C (third-party). `native/mpv/` holds the upstream mpv tree at `v0.41.0-1115-gb2c255c13` (`native/mpv/MPV_VERSION`). It is patched by the files in `native/patches/` and is not mapped file by file.

## Runtime

**Environment:**
- Dart VM, plus the Flutter engine `>=3.38.0` (`packages/mpv_kit_video/pubspec.yaml`). CI pins `FLUTTER_VERSION` in `.github/workflows/flutter-plugin.yml`.
- libmpv (client API 2.x, major-version gate in `packages/mpv_kit/lib/src/ffi/library.dart`). It is loaded once per process by `MpvLibrary.open`.
- Targets: Windows 10+, macOS 12+, and Linux with glibc 2.35+, each on x64 and arm64.

**Package Manager:**
- Dart `pub`, set up as a pub workspace. The root `pubspec.yaml` lists `packages/mpv_kit`, `packages/mpv_kit_libs`, `packages/mpv_kit_video` and `example`, and every member sets `resolution: workspace`.
- Lockfile: `pubspec.lock` is present at the root but gitignored.
- Native: Meson + Ninja and CMake (`native/build/`), plugin CMake files (`packages/mpv_kit_video/{windows,linux}/CMakeLists.txt`), and CocoaPods (`packages/mpv_kit_video/macos/mpv_kit_video.podspec`).

## Frameworks

**Core:**
- `dart:ffi`. Hand-written bindings live in `packages/mpv_kit/lib/src/ffi/bindings.dart`. Callbacks use `NativeCallable.listener`.
- Flutter plugin API. Platform classes: `MpvKitVideoPluginCApi` (Windows) and `MpvKitVideoPlugin` (Linux and macOS).
- Dart native assets build hook: `packages/mpv_kit_libs/hook/build.dart`.
- libmpv with downstream patches (`native/patches/0001`–`0009`, notes in `native/patches/UPSTREAM.md`). The patches cover the Vulkan render backend, hwdec extensions, the shader cache, the gpu-next backend, the async stream bridge, audio device fixes, vendor integration and upstream backports.
- libplacebo (Vulkan-only) and FFmpeg 8.1 as an LGPL build (`native/build/deps.sh`, `native/build/ffmpeg.sh`).
- Vulkan: Vulkan-Headers and volk are vendored in `packages/mpv_kit_video/third_party/`.

**Testing:**
- `test` ^1.25.0, used in `packages/mpv_kit/test/` and `packages/mpv_kit_libs/test/`.
- `flutter_test`, used in `packages/mpv_kit_video/test/`. `integration_test` is used in `example/integration_test` for benchmarks.
- Meson test suite: `native/tests/meson.build`.

**Build/Dev:**
- `lints` ^6.0.0 and `flutter_lints` ^6.0.0, configured through each package's `analysis_options.yaml`.
- Code generators: `tools/gen_options.dart`, `tools/gen_catalog.dart` and `tools/pin_bundles.dart`.

## Key Dependencies

**Critical:**
- `ffi` ^2.1.0. Provides `calloc`/`Utf8` across `packages/mpv_kit`.
- `meta` ^1.15.0. Provides annotations.
- `code_assets` ^2.1.0 and `hooks` ^2.2.0. Used by the native asset hook.
- `crypto` ^3.0.6. Verifies bundle sha256 hashes in `packages/mpv_kit_libs/lib/src/bundle.dart`.

**Infrastructure:**
- `cupertino_icons` ^1.0.8 and `desktop_drop` ^0.7.1. Used by the example app only.
- Native pins in `native/build/deps.sh`: Vulkan loader, MoltenVK (macOS), libdisplay-info (Linux), glslang, lcms2, libplacebo, dav1d, freetype, fribidi, harfbuzz, libass and uchardet.

## Configuration

**Environment:**
- `MPV_KIT_LIBMPV_PATH`: explicit path to libmpv (`packages/mpv_kit/lib/src/ffi/library.dart`).
- `MPV_KIT_VIDEO_RENDERER`: forces a renderer (`packages/mpv_kit_video/lib/src/video_controller.dart`).
- `libmpv_bundle`: hook user-define pointing at a local bundle (`packages/mpv_kit_libs/hook/build.dart`).
- `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`: proxies for bundle downloads.
- Test and benchmark only: `MPV_KIT_FORMAT_SAMPLES`, `MPV_KIT_REQUIRE_LIBMPV`, `MPV_KIT_SEEK_MEDIA`, `MPV_KIT_SMOKE_*`, `MPV_KIT_BENCH_*`.
- Example app only: `MPV_KIT_EXAMPLE_AO`, `MPV_KIT_EXAMPLE_LOG`.
- The repository contains no `.env` files.

**Build:**
- Root `pubspec.yaml` and per-package `pubspec.yaml`/`analysis_options.yaml`.
- `packages/mpv_kit_libs/lib/src/bundles.dart` pins `bundleTag = 'v0.1.0-dev.3'` and a sha256 per target. Package versions are `0.1.0-dev.4`.
- `native/build/*.sh`, `native/tests/meson.build`.

## Platform Requirements

**Development:**
- Flutter 3.38+ / Dart 3.10+.
- A libmpv, either from `MPV_KIT_LIBMPV_PATH` or a pinned bundle.
- To build libmpv locally: Meson, Ninja, CMake, pkg-config, nasm, Python 3 with Jinja2, and a C/C++ toolchain.
- On Linux: GTK/libepoxy, plus lavapipe or a GPU for the Vulkan smoke tests.
- On macOS: Xcode and CocoaPods.

**Production:**
- Desktop Flutter apps on the six targets.
- Vulkan 1.3 for hardware rendering. Without it, playback falls back to software rendering.
- Linux hosts must provide the system libraries on the allowlist in `native/build/package.sh`.

---

*Stack analysis: 2026-10-27*
