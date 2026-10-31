<!-- GSD:project-start source:PROJECT.md -->

## Project

**mpv_kit**

libmpv 的 Dart/Flutter 绑定工程：`mpv_kit` 提供纯 Dart FFI 的完整客户端 API 与高层 `Player`，`mpv_kit_video` 通过 Vulkan 把 mpv 画面零拷贝渲染到 Flutter 纹理，`mpv_kit_libs` 以构建钩子分发 sha256 校验过的 LGPL libmpv。面向需要在 Windows、Linux、macOS 的 x64 与 arm64 上做高质量本地播放的 Flutter 应用。

**Core Value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。

### Constraints

- **Compatibility**: Windows 10+、macOS 12+（实际 bundle 目前需 macOS 15）、Linux glibc 2.35+；x64 与 arm64 六个桌面目标。
- **API**: 公共 API 冻结，不新增、不破坏。
- **Change size**: 每项改动尽量小、可独立回滚；拒绝大范围重写。
- **Platform**: 不做移动端与 web。
- **License**: libmpv/FFmpeg 保持 LGPL，禁止 GPL/nonfree 依赖进入 bundle。
- **Verification**: 真实插件行为必须在 CI runner 上验证；mock channel 不能替代。

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Dart 3.8+ (`^3.8.0` in `packages/mpv_kit/pubspec.yaml`, `example/pubspec.yaml`, root `pubspec.yaml`) — FFI bindings, event loop, high-level `Player`, Flutter video output. `packages/mpv_kit_libs/pubspec.yaml` and `packages/mpv_kit_video/pubspec.yaml` require `^3.10.0` because the native-assets build hook needs Dart 3.10.
- Dart SDK resolved by the workspace lock: `>=3.11.0 <4.0.0` (`pubspec.lock`, `sdks` section).
- C11 — native smoke tests (`native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c`) and vendored `volk` loader (`packages/mpv_kit_video/third_party/volk/volk.c`).
- C++17 — Flutter plugin native code (`packages/mpv_kit_video/src/video_renderer.cc`, `vulkan_backend.cc`, `windows/mpv_kit_video_plugin.cpp`, `windows/d3d11_interop.cpp`, `linux/mpv_kit_video_plugin.cc`, `linux/gl_interop.cc`).
- Objective-C++ — macOS plugin (`packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm`, `metal_interop.mm`).
- Bash — native build/release tooling (`native/build/build.sh`, `deps.sh`, `ffmpeg.sh`, `package.sh`, `tools/*.sh`).
- Python 3 — ABI audit tooling (`tools/rea_abi_audit/pe_audit.py`) and Meson/Jinja2 in CI.
- C (upstream) — vendored mpv tree under `native/mpv/` and its patches in `native/patches/`.

## Runtime

- Dart VM, plus the Flutter engine on the consumer side (`flutter: ">=3.38.0"` in `packages/mpv_kit_video/pubspec.yaml`).
- CI pins `FLUTTER_VERSION: 3.47.6` in `.github/workflows/flutter-plugin.yml`.
- Native runtime target: libmpv 0.41.0 (`native/mpv/MPV_VERSION`: `v0.41.0-1113-gfd9265a905`), client API 2.5, loaded into the process once by `MpvLibrary.open` (`packages/mpv_kit/lib/src/ffi/library.dart`).
- Supported OS baselines (from `.github/workflows/release.yml` and `README.md`): Windows 10+ (UCRT), macOS 12+, Linux glibc 2.35+; x64 and arm64.
- Dart `pub` with a single pub workspace: root `pubspec.yaml` lists `packages/mpv_kit`, `packages/mpv_kit_libs`, `packages/mpv_kit_video`, `example`. Each member sets `resolution: workspace`.
- Lockfile: `pubspec.lock` present at the repo root, but listed in `.gitignore`; resolved versions are not committed.
- Native dependency managers: Meson + Ninja (`native/build/deps.sh`, `native/build/build.sh`), CMake (`native/build/deps.sh`, Flutter plugin `CMakeLists.txt`), CocoaPods (`packages/mpv_kit_video/macos/mpv_kit_video.podspec`).

## Frameworks

- Flutter plugin API — `packages/mpv_kit_video/pubspec.yaml` declares Windows (`MpvKitVideoPluginCApi`), Linux (`MpvKitVideoPlugin`), macOS (`MpvKitVideoPlugin`).
- `dart:ffi` — all libmpv calls in `packages/mpv_kit/lib/src/ffi/bindings.dart` (hand-written, 54 exported symbols, not ffigen-generated), event delivery via `NativeCallable.listener`.
- Dart native assets — build hook in `packages/mpv_kit_libs/hook/build.dart` using `code_assets` 2.1.0 and `hooks` 2.2.0.
- libmpv 0.41.0 (client API 2.5) with seven downstream patches in `native/patches/` (Vulkan VO backend, hwdec device extensions, persistent shader cache, gpu-next Vulkan backend, active-renderer report, asynchronous stream bridge, audio device enumeration fixes). Upstream notes in `native/patches/UPSTREAM.md`.
- libplacebo 7.360.1, Vulkan-only build (`native/build/deps.sh`).
- FFmpeg 8.1.3, LGPL build (`native/build/ffmpeg.sh`, pinned sha256).
- `package:test` 1.31.1 — `packages/mpv_kit/test/` (8 files), `packages/mpv_kit_libs/test/bundle_test.dart`.
- `flutter_test` — `packages/mpv_kit_video/test/` (`controller_channel_test.dart`, `video_controller_test.dart`).
- Meson test suite — `native/tests/meson.build` builds `render_vk_smoke` (gpu-next and gpu variants) and `stream_bridge_test`.
- Coverage: `coverage` package in CI; `packages/mpv_kit/coverage/lcov.info`; CI fails below 80% line coverage (`.github/workflows/native-verify.yml`).
- Sanitizers: ASan + UBSan debug libmpv and native tests (`.github/workflows/native-verify.yml`, `sanitizers` job).
- `analysis_options.yaml` per package; `packages/mpv_kit` and `packages/mpv_kit_libs` use `package:lints/recommended.yaml`, `packages/mpv_kit_video` and `example` use `package:flutter_lints/flutter.yaml`. Strict casts/inference/raw types everywhere.
- `packages/mpv_kit/dart_test.yaml` declares tag `format` (excluded from default runs).
- Code generation scripts: `tools/gen_options.dart` (typed `MpvOptions` from the runtime option table), `tools/gen_catalog.dart` (property/command catalog from mpv docs), `tools/pin_bundles.dart` (sha256 pins from a GitHub release).

## Key Dependencies

- `ffi` ^2.1.0 (resolved 2.2.0) — `calloc`, `Utf8`, FFI helpers used throughout `packages/mpv_kit`.
- `meta` ^1.15.0 (resolved 1.19.0) — annotations in the public API.
- `code_assets` ^2.1.0 (2.1.0) and `hooks` ^2.2.0 (2.2.0) — the native-assets build hook in `packages/mpv_kit_libs/hook/build.dart`.
- `crypto` ^3.0.6 (3.0.7) — sha256 verification of downloaded libmpv bundles (`packages/mpv_kit_libs/lib/src/bundle.dart`, `bundles.dart`).
- Flutter SDK packages — `packages/mpv_kit_video/lib/src/video_controller.dart` uses `MethodChannel`/`EventChannel`-style events (`MethodChannel('mpv_kit_video')`) and texture widgets.
- `lints` ^6.0.0 (6.1.0), `flutter_lints` ^6.0.0 (6.0.0), `test` ^1.25.0 (1.31.1).
- `cupertino_icons` ^1.0.8 (1.0.9) — example only.
- Vendored (not pub): Vulkan-Headers `vulkan-sdk-1.4.363.0` and volk same tag (`packages/mpv_kit_video/third_party/README.md`).
- Native stack pinned in `native/build/deps.sh` and `native/build/ffmpeg.sh`: Vulkan headers/loader 1.4.363.0, MoltenVK 1.4.2 (macOS), libdisplay-info 0.2.0 (Linux), glslang 16.6.0, lcms2 2.19.1, libplacebo 7.360.1, fast_float 8.3.2, dav1d 1.5.4, freetype 2.14.3, fribidi 1.0.17, harfbuzz 14.6.0, libass 0.17.5, uchardet 0.0.8, FFmpeg 8.1.3.

## Configuration

- `MPV_KIT_LIBMPV_PATH` — explicit libmpv path override (`packages/mpv_kit/lib/src/ffi/library.dart`, used in all CI workflows).
- `libmpv_bundle` build user-define — local bundle archive/directory for `mpv_kit_libs` (`packages/mpv_kit_libs/hook/build.dart`).
- `MPV_KIT_VIDEO_RENDERER` — forces a renderer (`MpvVideoRenderer.tryParse`, `packages/mpv_kit_video/lib/src/video_controller.dart`).
- `MPV_KIT_FORMAT_SAMPLES` — sample directory for the format matrix test (`packages/mpv_kit/test/format_matrix_test.dart`).
- `MPV_KIT_EXAMPLE_AO`, `MPV_KIT_EXAMPLE_LOG` — example app only (`example/lib/main.dart`).
- `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` — honored by bundle downloads (`packages/mpv_kit_libs/lib/src/bundle.dart`) and `tools/pin_bundles.dart`.
- Bundle pins: `bundleTag = 'v0.1.0-dev.3'` plus per-target sha256 in `packages/mpv_kit_libs/lib/src/bundles.dart`.
- No `.env` files exist in the repository (checked with a glob; no secrets files committed).
- Workspace manifest `pubspec.yaml`; per-package manifests and `analysis_options.yaml`.
- Native plugin builds: `packages/mpv_kit_video/windows/CMakeLists.txt`, `packages/mpv_kit_video/linux/CMakeLists.txt`, `packages/mpv_kit_video/macos/mpv_kit_video.podspec`.
- Native libmpv build: `native/build/build.sh`, `deps.sh`, `ffmpeg.sh`, `package.sh`; Meson options are explicit to keep an LGPL-only bundle.
- CI: `.github/workflows/flutter-plugin.yml` (plugin build/analyze/test on Linux/Windows/macOS), `.github/workflows/native-verify.yml` (libmpv build, ABI audit, smoke tests, Dart tests, sanitizers), `.github/workflows/release.yml` (six-target LGPL bundles published to GitHub Releases on `v*` tags).

## Platform Requirements

- Dart 3.10+ (lock resolves 3.11.0+); Flutter 3.38+ for `packages/mpv_kit_video` and `example`.
- A prebuilt libmpv for running tests: either `MPV_KIT_LIBMPV_PATH` or the bundle from `mpv_kit_libs`.
- Building libmpv locally: Meson, Ninja, CMake, pkg-config, nasm (x86), Python 3 + Jinja2, a C/C++ toolchain. Linux test runners also need `libepoxy-dev`/GTK for the plugin and lavapipe or a Vulkan GPU for smoke tests.
- macOS plugin building goes through CocoaPods and requires Xcode with C++17 support.
- Windows 10+, macOS 12+, or Linux with glibc 2.35+; x64 or arm64.
- A Vulkan 1.3 driver for hardware rendering (falls back to mpv software rendering via `MPV_RENDER_API_TYPE_SW`).
- Host-provided system libraries on Linux: libc/libstdc++, X11/xcb, Wayland, EGL/GL, Vulkan loader, VA-API, ALSA/PulseAudio/PipeWire, fontconfig (`native/build/package.sh` system allowlist).

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Naming Patterns

- `snake_case.dart` everywhere: `video_controller.dart`, `stream_bridge.dart`, `bundle_test.dart`.
- One primary public type per file, named after the type in snake_case (`MpvVideoController` → `video_controller.dart`).
- Generated files are marked in their header and grouped under `lib/src/generated/`: `options.dart`, `catalog.dart`, `option_types.dart`, `catalog_types.dart`.
- Test files are `<subject>_test.dart` (`player_test.dart`, `models_test.dart`, `bundle_test.dart`).
- Public classes are `final class` unless designed for extension. Observed counts across `packages/*/lib`: 61 `final class`, 5 `abstract final class` (namespaces: `MpvOptions`, `MpvLibrary`, `MpvFormat`), 1 `abstract interface class` (`MpvStreamSource`), 1 `sealed class` (`MpvEventData`).
- Closed hierarchies use `sealed` + exhaustive `switch`:
- Namespaces that only hold constants/methods are `abstract final class` (`MpvLibrary`, `MpvBindings` is a `final class` because it is instantiated).
- Enums use lowerCamelCase values; wire names are carried as fields where the C/native side differs: `MpvVideoRenderer.gpuNext('gpu-next')` in `packages/mpv_kit_video/lib/src/video_controller.dart`, `MpvVideoEventKind.renderError` mapped from `render_error`.
- lowerCamelCase, verb-first: `setProperty`, `tryGetProperty`, `registerStreamProtocol`, `syncDisplayRefreshRate`, `defaultShaderCacheDir`.
- Boolean getters use `is`/`has`-style prefixes: `isDisposed`, `isBroken`, `isAlbumArt`, `subtitlesVisible`.
- Private helpers are `_`-prefixed and frequently thin one-liners: `_bind`, `_maps`, `_trackId`, `_nonEmpty`, `_join`, `_safePath`, `_octal`, `_checkChecksum`.
- Static constructors use named factories: `Mpv.create`, `Player.wrap`, `MpvTrack.fromNode`, `MpvScreenshot.fromNode`.
- `final` locals are enforced by the `prefer_final_locals` lint (`packages/mpv_kit/analysis_options.yaml`).
- Top-level constants are lowerCamelCase (Dart style, not SCREAMING_SNAKE): `secureDefaultOptions` in `packages/mpv_kit/lib/src/core/mpv.dart`, `bundleTag` / `bundleSha256` in `packages/mpv_kit_libs/lib/src/bundles.dart`, `requiredMajor` in `packages/mpv_kit/lib/src/ffi/library.dart`.
- Private test constants are lowerCamel with a leading underscore: `_lavfi`, `_timeout`, `_block`, `_opOpen`.
- Record types are used for lightweight pairs instead of ad-hoc classes: `(int, int)? _size`, `(String, Object?) _prop(...)`, `(int major, int minor) apiVersion(...)`.
- Every library starts with a doc comment and a `library;` directive (19 of 21 files in `packages/*/lib`; the two exceptions are `example/lib/main.dart` and the Flutter plugin entrypoint files).
- Import order is enforced by convention, not lint: `dart:` → `package:` (external) → relative imports of sibling `src/` files.
- Inside a package, cross-directory imports are **relative** (`import '../core/errors.dart';` in `packages/mpv_kit/lib/src/player/player.dart`), not `package:mpv_kit/...`. Tests and the build hook import via `package:mpv_kit/...` (`packages/mpv_kit/test/player_test.dart`, `packages/mpv_kit_libs/hook/build.dart`).
- The single public barrel per package re-exports `src/` and selectively hides internals:
- No barrel files inside `src/`; each file imports exactly what it uses.

## Code Style

- Code is `dart format` output: 2-space indent, 80-column target, trailing commas on every multi-line argument/parameter list (see `packages/mpv_kit/lib/src/player/player.dart`, `packages/mpv_kit_video/lib/src/mpv_video.dart`).
- Long lines exist only in placeholders/docs and generated files; generated files opt out explicitly with `// ignore_for_file: lines_longer_than_80_chars` (`packages/mpv_kit/lib/src/generated/catalog.dart`).
- CI runs `flutter analyze --fatal-infos` / `dart analyze --fatal-infos` but does **not** run a `dart format --set-exit-if-changed` gate (`.github/workflows/flutter-plugin.yml`, `.github/workflows/native-verify.yml`). Formatting is expected, not enforced.
- `packages/mpv_kit` and `packages/mpv_kit_libs` extend `package:lints/recommended.yaml`.
- `packages/mpv_kit_video` and `example` extend `package:flutter_lints/flutter.yaml`.
- All library packages enable strict analyzer modes:
- Explicit rules shared by all three packages:
- The plugin/example exclude native scaffolding from analysis: `build/**`, `windows/**`, `macos/**`, `linux/**`.
- There are **no** `// ignore:` / `// ignore_for_file:` directives in hand-written code; only generated files use them.
- Dart 3 pattern matching and switch expressions: `bundleTarget` in `packages/mpv_kit_libs/lib/src/bundle.dart`, `MPV_KIT_VIDEO_RENDERER` parsing in `video_controller.dart`, format dispatch in `node.dart`.
- Null-aware collection elements: `?path`, `?Platform.environment['MPV_KIT_LIBMPV_PATH']` in `packages/mpv_kit/lib/src/ffi/library.dart`, `'ao': ?Platform.environment[...]` in `example/lib/main.dart`.
- Records and record patterns: `(int, int)?`, `for (final (name, video, audio, sub) in rows)` in `packages/mpv_kit/test/format_matrix_test.dart`.
- `@immutable` for value objects: `MpvVideoEvent` in `packages/mpv_kit_video/lib/src/video_controller.dart`.
- Large classes separate concerns with full-width comment rules:

## Immutability and Value Types

- All fields are `final` unless the type is an explicit mutable holder.
- Constructors are `const` wherever possible (`MpvAudioDevice`, `MpvMediaInfo`, `MpvOption`, `MpvCatalogEntry`, `MpvException`).
- Exceptions are `final class X implements Exception` with `const` constructors where fields allow: `MpvException` (`packages/mpv_kit/lib/src/core/errors.dart`), `MpvLibraryNotFound` (`packages/mpv_kit/lib/src/ffi/library.dart`), `BundleIntegrityException` (`packages/mpv_kit_libs/lib/src/bundle.dart`), `TarFormatException` (`packages/mpv_kit_libs/lib/src/tar.dart`).
- Value objects override `==`, `hashCode`, `toString` when compared in tests or maps (`MpvAudioDevice` in `packages/mpv_kit/lib/src/player/models.dart`).
- `toString` follows `Type(field: value)` and is tested: `MpvException(propertyNotFound @ get_property(foo)): ...`, `MpvPlaybackError(loadingFailed: ...)`, `MpvVideoEvent(resize: 640x360)`.
- Collections returned to users are copied/unmodifiable where mutation would leak state: `Map.unmodifiable` in `packages/mpv_kit/lib/src/player/player.dart:698`.
- Mutable state is intentionally concentrated in `MpvState<T>` (value + broadcast stream) and in `Mpv`/`Player`/`MpvVideoController` disposables; everything else is immutable.

## Error Handling

- FFI failures are wrapped in `MpvException(code, message, operation:)`; the typed `MpvError` is derived from the numeric code (`packages/mpv_kit/lib/src/core/errors.dart`).
- Library loading failures throw `MpvLibraryNotFound` with a `Map<String, String>` of every attempted path and its reason, plus a hint to set `MPV_KIT_LIBMPV_PATH` (`packages/mpv_kit/lib/src/ffi/library.dart`).
- Bundle integrity failures throw `BundleIntegrityException`; malformed archives throw `TarFormatException` (`packages/mpv_kit_libs/lib/src/`).
- Native return codes funnel through one checker:
- Programmer errors use core Dart errors, not `MpvException`:
- Cleanup paths catch narrowly and rethrow: `Mpv.create` disposes the handle on any failure with `} on Object { mpv.dispose(); rethrow; }` (`packages/mpv_kit/lib/src/core/mpv.dart`).
- Expected-but-absent features are tolerated by error code, never by broad catch:
- `dispose()` is idempotent (`if (_disposed) return;`) and awaits every subscription/controller close (`Player.dispose`, `MpvVideoController.dispose`).
- No bare `catch (e)` exists in `packages/*/lib`; only `on MpvException`, `on ArgumentError`, `on UnsupportedError`, `on PlatformException`, `on Object` when the intent is "clean up then rethrow".

## Async and Resource Conventions

- Every ignored future is explicitly marked `unawaited(...)` — the `unawaited_futures` lint is on. Examples: `packages/mpv_kit/lib/src/core/mpv.dart:183`, `stream_bridge.dart:211`, `packages/mpv_kit_video/lib/src/mpv_video.dart:61`, `example/lib/main.dart:58`.
- Subscription/controller lifetimes are tracked in fields and cancelled in `dispose`: `_subs`, `_states`, `_events`, `_observers` in `Mpv`/`Player`.
- Waits are bounded with `.timeout(...)`; no unbounded awaits in library or test code (e.g. `packages/mpv_kit/test/player_test.dart`).
- Broadcast controllers use `sync: true` when state must update before the next event: `MpvState` in `packages/mpv_kit/lib/src/player/player.dart`.
- Debounce/resize work is done with `Timer` fields cancelled in `dispose`: `_MpvVideoState._debounce`, `_PositionSliderState._timer`.

## Logging

- `packages/mpv_kit_video/lib/src/video_controller.dart:188` prints one line per controller creation: `mpv_kit_video: <backend> (<reason>)`.
- `example/lib/main.dart` prints a one-second stats line; it also mirrors mpv logs to stderr through `log-file`/`msg-level` options (`MPV_KIT_EXAMPLE_LOG`), not through a logger abstraction.
- User-visible diagnostics travel as data, not logs: `MpvVideoEvent` stream (`renderError`, `gpuTimeout`, `deviceLost`, `softwareFallback`) and `Player.errors` / `decodeWarning`.
- Libmpv's own log is exposed to callers as `Player.logs`; `terminal=no` is a secure default in `Mpv.create`.

## Comments and Documentation

- Module-level `///` docs and rationale-heavy comments are often Chinese: `packages/mpv_kit/lib/src/core/mpv.dart`, `packages/mpv_kit/lib/src/player/player.dart` (59 Chinese-comment lines), `packages/mpv_kit_video/lib/src/video_controller.dart` (14), `errors.dart`, `events.dart`.
- Public API member docs, `mpv_kit_video`, `mpv_kit_libs`, generated files, and most test comments are English.
- Expect either language in new comments; match the surrounding file. Do not "translate" existing comments.
- Every public class, enum, enum value, field, and method carries `///` documentation. `packages/mpv_kit/lib` has ~3,078 doc-comment lines across 14 files.
- Doc comments reference the native contract by name and source: `mpv_error` (client.h:278), `MPV_FORMAT_*`, `mpv_render_context_*`, "mirrors `src/mpv_api.h`".
- Rationale comments explain *why* with measured evidence, e.g. the `Player` factory's video-sync and cache explanation in `packages/mpv_kit/lib/src/player/player.dart` (backlog of 603 frames, 4K memory bandwidth numbers), and `mpv_video.dart`'s 250 ms seekbar rationale.
- Non-obvious FFI memory ownership, thread boundaries, and fallback ordering are always commented.
- Magic numbers get named constants or an adjacent explanatory comment (`1920 * 1088` decode-warning threshold with derivation in `player.dart`).
- No `TODO`/`FIXME`/`HACK` markers exist in `packages/` or `native/tests/`.
- Generated files begin with `// GENERATED by tools/gen_*.dart ... — do not edit.` and an `ignore_for_file` for line length / constant naming (`packages/mpv_kit/lib/src/generated/options.dart`, `catalog.dart`).
- Generated data is committed; do not hand-edit. Regenerate with `tools/gen_catalog.dart` / `tools/gen_options.dart` / `tools/pin_bundles.dart`.

## Function and Module Design

- Small, single-purpose; helpers extracted aggressively (`_nonEmpty`, `_join`, `_videoSize`, `_requestSize`).
- Expression-bodied functions for one-liners: `Future<T> _until<T>(...) => ...`, `String? _nonEmpty(String? s) => ...`.
- Public APIs take named parameters with defaults for anything optional: `Mpv.create({String? libraryPath, Map<String,String> options = const {}, bool secureDefaults = true, bool initialize = true})`, `MpvVideoController.create(player, {renderer = MpvVideoRenderer.auto})`.
- Constructors validate arguments at the boundary and fail fast (`openPlaylist` checks `startIndex`, `MpvOption.check` validates choices/ranges before calling mpv).
- Test-only seams are annotated instead of made public for convenience: `@visibleForTesting static String? defaultShaderCacheDir({String? os, Map<String, String>? environment})` (`packages/mpv_kit_video/lib/src/video_controller.dart`).
- Public API lives in the package barrel; implementation lives under `lib/src/<area>/`:
- Dependencies point inward: `player/` → `core/`; `core/` → `ffi/` and `generated/`; `generated/` depends only on sibling type files. `mpv_kit_video` and `mpv_kit_libs` never import each other's `src/`.
- Public classes expose primitives/records/`Object?`, not FFI pointers, except where the pointer is the contract (`Mpv.handle`, `Mpv.bindings`).
- Deprecations keep a documented migration path: `@Deprecated('Use renderer: MpvVideoRenderer.software')` on `forceSoftware` in `video_controller.dart`.

## Native Code Conventions (C/C++)

- C tests and headers use C11 with `warning_level=3` and `werror=true` (`native/tests/meson.build`).
- Native tests return 0 pass / 1 fail / 77 skip (meson skip), documented in each file header (`native/tests/render_vk_smoke.c`, `stream_bridge_test.c`).
- Files begin with a block comment stating what the test proves, how it runs headless, and exit-code semantics.
- Sections are separated with `// --- Name ----------------` comments.
- C++ plugin sources follow the platform folders: `packages/mpv_kit_video/src/*.cc/.h` (shared), `windows/*.cpp`, `linux/*.cc`, `macos/Classes/*.mm`.
- No `.clang-format` file exists; match the surrounding style (4-space indent in C/C++ tests, pointer stars on the name).

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

```

```text

```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `Mpv` | 1:1 wrapper over the libmpv client API; owns the handle, event loop, observer streams, pending async replies | `packages/mpv_kit/lib/src/core/mpv.dart` |
| `MpvBindings` | Raw FFI symbol table (54 symbols), memory ownership helpers | `packages/mpv_kit/lib/src/ffi/bindings.dart` |
| `MpvLibrary` | Process-wide single libmpv load + client API major-version check | `packages/mpv_kit/lib/src/ffi/library.dart` |
| Event model | Sealed `MpvEventData` hierarchy decoding `mpv_event*` immediately (pointer lifetime) | `packages/mpv_kit/lib/src/core/events.dart` |
| `node.dart` | Recursive `mpv_node` ↔ Dart values conversion | `packages/mpv_kit/lib/src/core/node.dart` |
| `StreamBridge` | Custom `protocol://` streams served from Dart via `NativeCallable.listener` | `packages/mpv_kit/lib/src/core/stream_bridge.dart` |
| `Player` | High-level API: one `MpvState<T>` per mpv property, typed commands, dispose hooks | `packages/mpv_kit/lib/src/player/player.dart` |
| Models | Typed decode of `track-list`, `video-params`, `audio-params`, playlist, chapters, screenshots | `packages/mpv_kit/lib/src/player/models.dart` |
| Catalog / options | Generated metadata (`mpvProperties`, `mpvCommands`, `mpvOptions`) and typed `MpvOptions` | `packages/mpv_kit/lib/src/generated/` |
| `MpvVideoController` | Dart side of video output: creates the native renderer, owns texture id, routes events, sets size/ICC/display-fps | `packages/mpv_kit_video/lib/src/video_controller.dart` |
| `MpvVideo` | Widget that letterboxes the texture, debounces resizes, follows display refresh rate | `packages/mpv_kit_video/lib/src/mpv_video.dart` |
| `VideoRenderer` (C++) | Render thread, renderer fallback (gpu-next → gpu → software), frame ring, quarantine, backoff, swap reporting | `packages/mpv_kit_video/src/video_renderer.cc` |
| `VulkanContext` (C++) | Vulkan instance/device/queues, timeline semaphore, shared-image ring | `packages/mpv_kit_video/src/vulkan_backend.cc` |
| `Interop` / `VulkanInterop` | Platform abstraction for zero-copy sharing and software pixel order | `packages/mpv_kit_video/src/video_renderer.h`, `src/vulkan_backend.h` |
| Platform plugins | Method channel contract, Flutter texture registration, event marshalling | `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp`, `.../linux/mpv_kit_video_plugin.cc`, `.../macos/Classes/MpvKitVideoPlugin.mm` |
| Build hook | Resolves/verifies/extracts the libmpv bundle and emits code assets | `packages/mpv_kit_libs/hook/build.dart`, `lib/src/bundle.dart` |
| Native test harness | C tests for the Vulkan render backend and stream bridge | `native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c` |

## Pattern Overview

- **One library, one handle, one owner per concern.** `MpvLibrary` caches a single `DynamicLibrary`; every `Mpv` wraps an `mpv_handle*`. The video plugin never loads libmpv — Dart passes the handle address and nine render-API symbol addresses across the method channel (`MpvVideoController._symbols` in `packages/mpv_kit_video/lib/src/video_controller.dart`, `MpvApi::Load` in `packages/mpv_kit_video/src/mpv_api.h`).
- **Generated surface, hand-written behavior.** Properties/commands/options tables are generated from mpv's own docs and option table (`tools/gen_catalog.dart`, `tools/gen_options.dart`); all behavior lives in hand-written `core/` and `player/` files.
- **Async at the Dart boundary, synchronous at the C boundary.** FFI calls are synchronous and documented thread-safe; native callbacks (`wakeup`, stream requests) enter Dart through `NativeCallable.listener`, never by upcalling a JIT isolate.
- **Single native render thread per controller.** The compositor, UI and raster threads only request frames; rendering and swap reporting happen on the renderer thread.
- **Fallback-first rendering.** Vulkan gpu-next → Vulkan gpu → software; every failure is reported as a typed event instead of failing the app.

## Layers

- Purpose: expose every mpv property, command and option with docs and types matching the bundled binary.
- Location: `packages/mpv_kit/lib/src/generated/`
- Contains: `catalog.dart` (4346 lines), `catalog_types.dart`, `option_types.dart`, `options.dart` (7617 lines).
- Depends on: nothing but `dart:core`.
- Used by: `Mpv.getOptionValue`/`setOptionValue`, `Player`, application code. Never edited by hand.
- Purpose: declare libmpv symbols and locate/load the library.
- Location: `packages/mpv_kit/lib/src/ffi/`
- Contains: `bindings.dart` (raw symbol table, opaque types, enums), `library.dart` (resolution order, API version gate).
- Depends on: `package:ffi`, `dart:ffi`, `dart:io`.
- Used by: `Mpv`, `StreamBridge`, `MpvVideoController` (symbol lookup for the plugin).
- Purpose: represent libmpv semantics safely in Dart.
- Location: `packages/mpv_kit/lib/src/core/`
- Contains: `mpv.dart`, `events.dart`, `node.dart`, `errors.dart`, `stream_bridge.dart`.
- Depends on: FFI layer, generated option types.
- Used by: `Player`, application code, `mpv_kit_video`.
- Purpose: ergonomic state and commands for applications.
- Location: `packages/mpv_kit/lib/src/player/`
- Contains: `player.dart`, `models.dart`.
- Depends on: `core/mpv.dart`, `core/events.dart`, `core/errors.dart`.
- Used by: applications and `mpv_kit_video` (controller registers a dispose hook on `Player`).
- Purpose: connect an `Mpv` instance to a Flutter texture and expose diagnostics.
- Location: `packages/mpv_kit_video/lib/src/`
- Contains: `video_controller.dart`, `mpv_video.dart`.
- Depends on: `package:mpv_kit`, Flutter services/widgets.
- Used by: applications that render video.
- Purpose: own the mpv render context, render thread, frame ring and Vulkan device.
- Location: `packages/mpv_kit_video/src/`
- Contains: `video_renderer.h/.cc`, `vulkan_backend.h/.cc`, `mpv_api.h`, vendored mpv render headers (`src/include/mpv/`).
- Depends on: vendored Vulkan headers + volk (`third_party/`).
- Used by: every platform plugin.
- Purpose: Flutter texture registration, compositor sharing, event marshalling.
- Location: `packages/mpv_kit_video/windows/`, `linux/`, `macos/`.
- Contains: plugin entry points, `d3d11_interop.*`, `gl_interop.*`, `metal_interop.*`.
- Depends on: native renderer layer, Flutter embedding APIs.
- Used by: Flutter engine.
- Purpose: deliver libmpv and its dependency closure, verify integrity, produce release artifacts.
- Location: `packages/mpv_kit_libs/`, `native/build/`, `tools/`, `.github/workflows/`
- Contains: build hook, tar reader, manifest verification, pinning tool, shell build scripts, ABI audit.
- Depends on: GitHub release assets; no runtime code.
- Purpose: buildable mpv source plus mpv_kit patches and upstream-tracking notes.
- Location: `native/mpv/`, `native/patches/`, `native/tests/`
- Contains: full mpv tree (963 tracked files), `UPSTREAM.md`, 7 patches, C smoke tests.
- Depends on: nothing at runtime; only the release workflow builds it.

## Data Flow

### Property observation (primary state path)

### Video frame path

### Controller resize / display sync

### Custom stream protocol

### Dispose ordering

## Key Abstractions

- Purpose: exact client-API mirror with safe lifetime and event delivery.
- Examples: `packages/mpv_kit/lib/src/core/mpv.dart`
- Pattern: facade + native callback registration; IDs are monotonic ints used as `reply_userdata`.
- Purpose: current value + change stream for one observed property.
- Examples: `packages/mpv_kit/lib/src/player/player.dart:16`
- Pattern: value object with sync broadcast controller; deduplicates equal values; resets on `ShutdownEvent`.
- Purpose: typed option with declared choices/range validation.
- Examples: `packages/mpv_kit/lib/src/generated/option_types.dart`, `options.dart`
- Pattern: const value object generated from the running library's option table.
- Purpose: lifetime and identity of one native renderer + Flutter texture.
- Examples: `packages/mpv_kit_video/lib/src/video_controller.dart`
- Pattern: static registry `_live` keyed by `textureId` for event routing; create/dispose returns through the method channel.
- Purpose: platform-independent rendering with a narrow platform seam.
- Examples: `packages/mpv_kit_video/src/video_renderer.h`, `src/vulkan_backend.h`
- Pattern: template-method (platform objects implement `CreateImage`, `DestroyImage`, `FrameReady`, `CompositorLatency`) plus a render-thread state machine.
- Purpose: host-provided byte stream for custom protocols.
- Examples: `packages/mpv_kit/lib/src/core/stream_bridge.dart:26`, `MpvMemoryStreamSource`
- Pattern: async interface with one in-flight call per stream, enforced by mpv's synchronous reads.

## Entry Points

- Location: `example/lib/main.dart`
- Triggers: `flutter run -d windows|linux|macos`
- Responsibilities: create `Player`, create `MpvVideoController`, render `MpvVideo`, display live stats and renderer events.
- Location: `packages/mpv_kit/lib/mpv_kit.dart`, `packages/mpv_kit_video/lib/mpv_kit_video.dart`, `packages/mpv_kit_libs/lib/mpv_kit_libs.dart`
- Triggers: import by applications.
- Responsibilities: barrel exports; `mpv_kit_video` re-exports all of `mpv_kit`, so apps depend on one package.
- Location: `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:304` (`MpvKitVideoPluginCApiRegisterWithRegistrar`), `linux/mpv_kit_video_plugin.cc`, `macos/Classes/MpvKitVideoPlugin.mm:144`
- Triggers: Flutter plugin registrant generated at build time (`example/windows/flutter/generated_plugin_registrant.cc`).
- Responsibilities: install the `mpv_kit_video` method channel, texture registrar, and platform event transport.
- Location: `packages/mpv_kit_libs/hook/build.dart`
- Triggers: `flutter pub get` / `flutter build` native-assets hook.
- Responsibilities: resolve bundle source, verify hashes, emit `CodeAsset`s.
- Location: `native/tests/meson.build`, `native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c`
- Triggers: `meson test` in `native/tests`.
- Responsibilities: exercise the Vulkan render backend and asynchronous stream bridge against a locally built patched libmpv.
- `tools/gen_catalog.dart` — regenerate property/command/option catalog from `native/mpv/DOCS/man`.
- `tools/gen_options.dart` — regenerate typed options by querying a running libmpv.
- `tools/pin_bundles.dart` — update `bundles.dart` from a release's `SHA256SUMS`.
- `tools/rea_abi_audit/pe_audit.py` — verify the Windows DLL export set and GPL-free imports.
- `native/build/build.sh` — full release build (deps → FFmpeg → patched mpv → package).

## Architectural Constraints

- **Single libmpv mapping:** `MpvLibrary._bindings` is a static cache; a later `open(path:)` with a different path is ignored. Changing the library requires a new process (`packages/mpv_kit/lib/src/ffi/library.dart:29-56`).
- **Client API major version 2 only:** `MpvLibrary._checkApiVersion` rejects other majors before any handle is created (`library.dart:75`).
- **Plugin never links or loads libmpv:** all render symbols arrive as addresses over the method channel; `MpvApi::Load` requires exactly nine non-null addresses (`packages/mpv_kit_video/src/mpv_api.h:22`).
- **Rendering is confined to one native thread per controller:** `mpv_render_context_render` must be called from the renderer thread; UI/raster callbacks only publish frames (`packages/mpv_kit_video/src/video_renderer.cc:282`).
- **Render context must die before the mpv core:** enforced by the `Player.addDisposeHook` contract; bypassing it causes libmpv to wait/fail (`docs/ARCHITECTURE.md:76-90`).
- **Frame ring quarantine:** an image the compositor returned stays quarantined for `Interop::CompositorLatency()` acquisitions — Windows 4 (ring 7), others 2 (ring 5); ring = front + in use + quarantine + one free (`packages/mpv_kit_video/src/video_renderer.h:197-230`).
- **No cross-API fences:** correctness relies on the quarantine + Vulkan timeline waits; there is no keyed mutex/fence with ANGLE or Metal (`docs/ARCHITECTURE.md:96-119`).
- **Stream requests block mpv's demuxer thread:** a source that never completes a request stalls playback; every registered protocol is shut down before core destruction (`packages/mpv_kit/lib/src/core/stream_bridge.dart`, `mpv.dart:168`).
- **Platform event marshalling:** native render events must reach the platform thread before the method channel — `PostMessage` (Windows), `g_idle_add` (Linux), `dispatch_async(main)` (macOS).
- **Native asset bundling only:** `mpv_kit_libs` has no runtime Dart code; `mpv_kit` resolves the bundle by default library names via the OS loader (`docs/ARCHITECTURE.md:23-27`).
- **Workspace resolution:** root `pubspec.yaml` lists all packages plus `example` under `workspace:`; each package uses `resolution: workspace` and versions are kept in lockstep (`0.1.0-dev.3`).
- **Dart/Flutter floor differs per package:** `mpv_kit` requires Dart `^3.8.0`; `mpv_kit_video` and `mpv_kit_libs` require Dart `^3.10.0` / Flutter `>=3.38.0` because of native assets (`packages/*/pubspec.yaml`).

## Anti-Patterns

### Loading libmpv from the plugin or a second location

### Disposing the player before the controller

### Editing generated files

### Awaiting long work inside a stream source without regard to the demuxer

### Treating Flutter's display refresh rate as reliable on Windows

### Rendering a texture at the widget's logical size

## Error Handling

- libmpv negative return codes → `MpvException` with `MpvError` enum, operation label and `mpv_error_string` text (`packages/mpv_kit/lib/src/core/errors.dart`).
- “Unavailable” reads use `tryGetProperty` returning null for `propertyUnavailable`/`propertyNotFound`, rethrowing everything else (`mpv.dart:322`).
- Unknown option names during `Mpv.create` are tolerated only for `optionNotFound` (feature compiled out), so older builds still work (`mpv.dart:58-76`).
- Async request failures complete their futures with `MpvException`; `Mpv.dispose` completes pending futures with `StateError`.
- Library loading aggregates every attempted path/reason in `MpvLibraryNotFound`.
- Stream bridge maps source failures to mpv error codes (`loadingFailed`, `unsupported`, `generic`) instead of throwing across FFI (`stream_bridge.dart:221-279`).
- Native renderer: failed frames are advanced with `SKIP_RENDERING` and retried with exponential backoff 100 ms → 5 s; device loss stops rendering permanently and emits `device_lost` (`packages/mpv_kit_video/src/video_renderer.h:172-191`).
- Dart controller surfaces `PlatformException` on failed creation and emits `softwareFallback` as an explicit event (`video_controller.dart:174-204`).

## Cross-Cutting Concerns

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-fast` for a trivial task inline, with no subagents and no PLAN.md
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
