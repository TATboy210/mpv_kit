---
last_mapped_commit: 9f90a45322ab3537941540e6b35a76d978669ef5
last_mapped_at: 2026-10-23
---
# Coding Conventions

**Analysis Date:** 2026-10-23

## Naming Patterns

**Files:**
- `snake_case.dart` everywhere: `video_controller.dart`, `stream_bridge.dart`, `bundle_test.dart`.
- One primary public type per file, named after the type in snake_case (`MpvVideoController` → `video_controller.dart`).
- Generated files are marked in their header and grouped under `lib/src/generated/`: `options.dart`, `catalog.dart`, `option_types.dart`, `catalog_types.dart`.
- Test files are `<subject>_test.dart` (`player_test.dart`, `models_test.dart`, `bundle_test.dart`).

**Classes and types:**
- Public classes are `final class` unless designed for extension. Observed counts across `packages/*/lib`: 61 `final class`, 5 `abstract final class` (namespaces: `MpvOptions`, `MpvLibrary`, `MpvFormat`), 1 `abstract interface class` (`MpvStreamSource`), 1 `sealed class` (`MpvEventData`).
- Closed hierarchies use `sealed` + exhaustive `switch`:
  - `packages/mpv_kit/lib/src/core/events.dart` — `sealed class MpvEventData` with one subclass per `MpvEventId`; decoding is a single exhaustive `switch` with a `final id =>` fallback for unknown future events.
- Namespaces that only hold constants/methods are `abstract final class` (`MpvLibrary`, `MpvBindings` is a `final class` because it is instantiated).
- Enums use lowerCamelCase values; wire names are carried as fields where the C/native side differs: `MpvVideoRenderer.gpuNext('gpu-next')` in `packages/mpv_kit_video/lib/src/video_controller.dart`, `MpvVideoEventKind.renderError` mapped from `render_error`.

**Functions and methods:**
- lowerCamelCase, verb-first: `setProperty`, `tryGetProperty`, `registerStreamProtocol`, `syncDisplayRefreshRate`, `defaultShaderCacheDir`.
- Boolean getters use `is`/`has`-style prefixes: `isDisposed`, `isBroken`, `isAlbumArt`, `subtitlesVisible`.
- Private helpers are `_`-prefixed and frequently thin one-liners: `_bind`, `_maps`, `_trackId`, `_nonEmpty`, `_join`, `_safePath`, `_octal`, `_checkChecksum`.
- Static constructors use named factories: `Mpv.create`, `Player.wrap`, `MpvTrack.fromNode`, `MpvScreenshot.fromNode`.

**Variables and constants:**
- `final` locals are enforced by the `prefer_final_locals` lint (`packages/mpv_kit/analysis_options.yaml`).
- Top-level constants are lowerCamelCase (Dart style, not SCREAMING_SNAKE): `secureDefaultOptions` in `packages/mpv_kit/lib/src/core/mpv.dart`, `bundleTag` / `bundleSha256` in `packages/mpv_kit_libs/lib/src/bundles.dart`, `requiredMajor` in `packages/mpv_kit/lib/src/ffi/library.dart`.
- Private test constants are lowerCamel with a leading underscore: `_lavfi`, `_timeout`, `_block`, `_opOpen`.
- Record types are used for lightweight pairs instead of ad-hoc classes: `(int, int)? _size`, `(String, Object?) _prop(...)`, `(int major, int minor) apiVersion(...)`.

**Imports and libraries:**
- Every library starts with a doc comment and a `library;` directive (19 of 21 files in `packages/*/lib`; the two exceptions are `example/lib/main.dart` and the Flutter plugin entrypoint files).
- Import order is enforced by convention, not lint: `dart:` → `package:` (external) → relative imports of sibling `src/` files.
- Inside a package, cross-directory imports are **relative** (`import '../core/errors.dart';` in `packages/mpv_kit/lib/src/player/player.dart`), not `package:mpv_kit/...`. Tests and the build hook import via `package:mpv_kit/...` (`packages/mpv_kit/test/player_test.dart`, `packages/mpv_kit_libs/hook/build.dart`).
- The single public barrel per package re-exports `src/` and selectively hides internals:
  - `packages/mpv_kit/lib/mpv_kit.dart`: `export 'src/player/models.dart' hide secondsToDuration, nodeInt;`
  - `packages/mpv_kit_video/lib/mpv_kit_video.dart`
  - `packages/mpv_kit_libs/lib/mpv_kit_libs.dart`
- No barrel files inside `src/`; each file imports exactly what it uses.

## Code Style

**Formatting:**
- Code is `dart format` output: 2-space indent, 80-column target, trailing commas on every multi-line argument/parameter list (see `packages/mpv_kit/lib/src/player/player.dart`, `packages/mpv_kit_video/lib/src/mpv_video.dart`).
- Long lines exist only in placeholders/docs and generated files; generated files opt out explicitly with `// ignore_for_file: lines_longer_than_80_chars` (`packages/mpv_kit/lib/src/generated/catalog.dart`).
- CI runs `flutter analyze --fatal-infos` / `dart analyze --fatal-infos` but does **not** run a `dart format --set-exit-if-changed` gate (`.github/workflows/flutter-plugin.yml`, `.github/workflows/native-verify.yml`). Formatting is expected, not enforced.

**Linting:**
- `packages/mpv_kit` and `packages/mpv_kit_libs` extend `package:lints/recommended.yaml`.
- `packages/mpv_kit_video` and `example` extend `package:flutter_lints/flutter.yaml`.
- All library packages enable strict analyzer modes:
  ```yaml
  analyzer:
    language:
      strict-casts: true
      strict-inference: true
      strict-raw-types: true
  ```
- Explicit rules shared by all three packages:
  `prefer_final_locals`, `prefer_single_quotes`, `unawaited_futures`, `cancel_subscriptions`, `close_sinks`, `always_declare_return_types`.
- The plugin/example exclude native scaffolding from analysis: `build/**`, `windows/**`, `macos/**`, `linux/**`.
- There are **no** `// ignore:` / `// ignore_for_file:` directives in hand-written code; only generated files use them.

**Language features actively used:**
- Dart 3 pattern matching and switch expressions: `bundleTarget` in `packages/mpv_kit_libs/lib/src/bundle.dart`, `MPV_KIT_VIDEO_RENDERER` parsing in `video_controller.dart`, format dispatch in `node.dart`.
- Null-aware collection elements: `?path`, `?Platform.environment['MPV_KIT_LIBMPV_PATH']` in `packages/mpv_kit/lib/src/ffi/library.dart`, `'ao': ?Platform.environment[...]` in `example/lib/main.dart`.
- Records and record patterns: `(int, int)?`, `for (final (name, video, audio, sub) in rows)` in `packages/mpv_kit/test/format_matrix_test.dart`.
- `@immutable` for value objects: `MpvVideoEvent` in `packages/mpv_kit_video/lib/src/video_controller.dart`.

**Section organization:**
- Large classes separate concerns with full-width comment rules:
  ```dart
  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------
  ```
  Used in `packages/mpv_kit/lib/src/core/mpv.dart` (`Lifecycle`, `Properties`, `Events`, `Commands`, `Internals`) and `packages/mpv_kit/lib/src/ffi/bindings.dart` (`Opaque handles`, `Enums`, `Structs`, `Functions`).

## Immutability and Value Types

- All fields are `final` unless the type is an explicit mutable holder.
- Constructors are `const` wherever possible (`MpvAudioDevice`, `MpvMediaInfo`, `MpvOption`, `MpvCatalogEntry`, `MpvException`).
- Exceptions are `final class X implements Exception` with `const` constructors where fields allow: `MpvException` (`packages/mpv_kit/lib/src/core/errors.dart`), `MpvLibraryNotFound` (`packages/mpv_kit/lib/src/ffi/library.dart`), `BundleIntegrityException` (`packages/mpv_kit_libs/lib/src/bundle.dart`), `TarFormatException` (`packages/mpv_kit_libs/lib/src/tar.dart`).
- Value objects override `==`, `hashCode`, `toString` when compared in tests or maps (`MpvAudioDevice` in `packages/mpv_kit/lib/src/player/models.dart`).
- `toString` follows `Type(field: value)` and is tested: `MpvException(propertyNotFound @ get_property(foo)): ...`, `MpvPlaybackError(loadingFailed: ...)`, `MpvVideoEvent(resize: 640x360)`.
- Collections returned to users are copied/unmodifiable where mutation would leak state: `Map.unmodifiable` in `packages/mpv_kit/lib/src/player/player.dart:698`.
- Mutable state is intentionally concentrated in `MpvState<T>` (value + broadcast stream) and in `Mpv`/`Player`/`MpvVideoController` disposables; everything else is immutable.

## Error Handling

**Custom exception hierarchy:**
- FFI failures are wrapped in `MpvException(code, message, operation:)`; the typed `MpvError` is derived from the numeric code (`packages/mpv_kit/lib/src/core/errors.dart`).
- Library loading failures throw `MpvLibraryNotFound` with a `Map<String, String>` of every attempted path and its reason, plus a hint to set `MPV_KIT_LIBMPV_PATH` (`packages/mpv_kit/lib/src/ffi/library.dart`).
- Bundle integrity failures throw `BundleIntegrityException`; malformed archives throw `TarFormatException` (`packages/mpv_kit_libs/lib/src/`).

**Standard patterns:**
- Native return codes funnel through one checker:
  ```dart
  void _check(int rc, String op) {
    if (rc < 0) throw _error(rc, op);
  }
  ```
  Every binding call passes an operation label (`'initialize'`, `'set_property(volume)'`), so exceptions carry context (`packages/mpv_kit/lib/src/core/mpv.dart:560`).
- Programmer errors use core Dart errors, not `MpvException`:
  - `ArgumentError.value` for out-of-range/choice option values (`MpvOption.check`, `packages/mpv_kit/lib/src/generated/option_types.dart`).
  - `RangeError` for invalid indices (`Player.openPlaylist(startIndex:)`).
  - `UnsupportedError` for incompatible client API versions or unknown `mpv_format` (`library.dart`, `node.dart`).
- Cleanup paths catch narrowly and rethrow: `Mpv.create` disposes the handle on any failure with `} on Object { mpv.dispose(); rethrow; }` (`packages/mpv_kit/lib/src/core/mpv.dart`).
- Expected-but-absent features are tolerated by error code, never by broad catch:
  ```dart
  } on MpvException catch (err) {
    if (err.error != MpvError.optionNotFound) rethrow;
  }
  ```
- `dispose()` is idempotent (`if (_disposed) return;`) and awaits every subscription/controller close (`Player.dispose`, `MpvVideoController.dispose`).
- No bare `catch (e)` exists in `packages/*/lib`; only `on MpvException`, `on ArgumentError`, `on UnsupportedError`, `on PlatformException`, `on Object` when the intent is "clean up then rethrow".

## Async and Resource Conventions

- Every ignored future is explicitly marked `unawaited(...)` — the `unawaited_futures` lint is on. Examples: `packages/mpv_kit/lib/src/core/mpv.dart:183`, `stream_bridge.dart:211`, `packages/mpv_kit_video/lib/src/mpv_video.dart:61`, `example/lib/main.dart:58`.
- Subscription/controller lifetimes are tracked in fields and cancelled in `dispose`: `_subs`, `_states`, `_events`, `_observers` in `Mpv`/`Player`.
- Waits are bounded with `.timeout(...)`; no unbounded awaits in library or test code (e.g. `packages/mpv_kit/test/player_test.dart`).
- Broadcast controllers use `sync: true` when state must update before the next event: `MpvState` in `packages/mpv_kit/lib/src/player/player.dart`.
- Debounce/resize work is done with `Timer` fields cancelled in `dispose`: `_MpvVideoState._debounce`, `_PositionSliderState._timer`.

## Logging

**Framework:** Flutter's `debugPrint` only. No `print`, no `dart:developer` `log`, no logging package.

**Patterns:**
- `packages/mpv_kit_video/lib/src/video_controller.dart:188` prints one line per controller creation: `mpv_kit_video: <backend> (<reason>)`.
- `example/lib/main.dart` prints a one-second stats line; it also mirrors mpv logs to stderr through `log-file`/`msg-level` options (`MPV_KIT_EXAMPLE_LOG`), not through a logger abstraction.
- User-visible diagnostics travel as data, not logs: `MpvVideoEvent` stream (`renderError`, `gpuTimeout`, `deviceLost`, `softwareFallback`) and `Player.errors` / `decodeWarning`.
- Libmpv's own log is exposed to callers as `Player.logs`; `terminal=no` is a secure default in `Mpv.create`.

## Comments and Documentation

**Language:** Mixed Chinese and English, deliberately:
- Module-level `///` docs and rationale-heavy comments are often Chinese: `packages/mpv_kit/lib/src/core/mpv.dart`, `packages/mpv_kit/lib/src/player/player.dart` (59 Chinese-comment lines), `packages/mpv_kit_video/lib/src/video_controller.dart` (14), `errors.dart`, `events.dart`.
- Public API member docs, `mpv_kit_video`, `mpv_kit_libs`, generated files, and most test comments are English.
- Expect either language in new comments; match the surrounding file. Do not "translate" existing comments.

**Documentation density:**
- Every public class, enum, enum value, field, and method carries `///` documentation. `packages/mpv_kit/lib` has ~3,078 doc-comment lines across 14 files.
- Doc comments reference the native contract by name and source: `mpv_error` (client.h:278), `MPV_FORMAT_*`, `mpv_render_context_*`, "mirrors `src/mpv_api.h`".
- Rationale comments explain *why* with measured evidence, e.g. the `Player` factory's video-sync and cache explanation in `packages/mpv_kit/lib/src/player/player.dart` (backlog of 603 frames, 4K memory bandwidth numbers), and `mpv_video.dart`'s 250 ms seekbar rationale.

**When to comment:**
- Non-obvious FFI memory ownership, thread boundaries, and fallback ordering are always commented.
- Magic numbers get named constants or an adjacent explanatory comment (`1920 * 1088` decode-warning threshold with derivation in `player.dart`).
- No `TODO`/`FIXME`/`HACK` markers exist in `packages/` or `native/tests/`.

**Generated code:**
- Generated files begin with `// GENERATED by tools/gen_*.dart ... — do not edit.` and an `ignore_for_file` for line length / constant naming (`packages/mpv_kit/lib/src/generated/options.dart`, `catalog.dart`).
- Generated data is committed; do not hand-edit. Regenerate with `tools/gen_catalog.dart` / `tools/gen_options.dart` / `tools/pin_bundles.dart`.

## Function and Module Design

**Functions:**
- Small, single-purpose; helpers extracted aggressively (`_nonEmpty`, `_join`, `_videoSize`, `_requestSize`).
- Expression-bodied functions for one-liners: `Future<T> _until<T>(...) => ...`, `String? _nonEmpty(String? s) => ...`.
- Public APIs take named parameters with defaults for anything optional: `Mpv.create({String? libraryPath, Map<String,String> options = const {}, bool secureDefaults = true, bool initialize = true})`, `MpvVideoController.create(player, {renderer = MpvVideoRenderer.auto})`.
- Constructors validate arguments at the boundary and fail fast (`openPlaylist` checks `startIndex`, `MpvOption.check` validates choices/ranges before calling mpv).
- Test-only seams are annotated instead of made public for convenience: `@visibleForTesting static String? defaultShaderCacheDir({String? os, Map<String, String>? environment})` (`packages/mpv_kit_video/lib/src/video_controller.dart`).

**Modules:**
- Public API lives in the package barrel; implementation lives under `lib/src/<area>/`:
  - `packages/mpv_kit/lib/src/core/` — `mpv.dart`, `events.dart`, `errors.dart`, `node.dart`, `stream_bridge.dart`
  - `packages/mpv_kit/lib/src/ffi/` — `bindings.dart`, `library.dart`
  - `packages/mpv_kit/lib/src/player/` — `player.dart`, `models.dart`
  - `packages/mpv_kit/lib/src/generated/` — catalogs and typed options
  - `packages/mpv_kit_video/lib/src/` — `video_controller.dart`, `mpv_video.dart`
  - `packages/mpv_kit_libs/lib/src/` — `bundle.dart`, `bundles.dart`, `tar.dart`
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

---

*Convention analysis: 2026-10-23*
