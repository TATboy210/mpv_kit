---
last_mapped_commit: 9f90a45322ab3537941540e6b35a76d978669ef5
last_mapped_at: 2026-10-23
---
# Codebase Structure

**Analysis Date:** 2026-10-23

## Directory Layout

```text
mpv_kit/                          # Dart workspace root (pubspec.yaml: workspace:)
├── packages/
│   ├── mpv_kit/                  # Pure Dart FFI bindings + typed Player (no Flutter)
│   │   ├── lib/
│   │   │   ├── mpv_kit.dart      # Barrel export (public API surface)
│   │   │   └── src/
│   │   │       ├── core/         # Mpv, events, node, errors, stream bridge
│   │   │       ├── ffi/          # Raw symbol table + library loader
│   │   │       ├── generated/    # Generated catalog + typed options (do not edit)
│   │   │       └── player/       # Player facade + typed models
│   │   └── test/                 # dart test suites (unit + live-lib API surface)
│   ├── mpv_kit_video/            # Flutter plugin: Dart controller/widget + native renderer
│   │   ├── lib/
│   │   │   ├── mpv_kit_video.dart
│   │   │   └── src/              # video_controller.dart, mpv_video.dart
│   │   ├── src/                  # Platform-independent C++ (shared by all platforms)
│   │   │   ├── video_renderer.{h,cc}   # Render thread, ring, fallback, backoff
│   │   │   ├── vulkan_backend.{h,cc}   # Vulkan device/queues/timeline/shared images
│   │   │   ├── mpv_api.h               # Render API function table from Dart addresses
│   │   │   └── include/mpv/            # Vendored client/render headers
│   │   ├── windows/              # Windows plugin + D3D11 interop + CMake
│   │   ├── linux/                # GTK plugin + GL/EGL interop + CMake
│   │   ├── macos/                # ObjC plugin + Metal/MoltenVK interop + podspec
│   │   ├── third_party/          # volk + Vulkan headers (vendored, hashed)
│   │   └── test/                 # flutter_test suites (channel + controller)
│   └── mpv_kit_libs/             # Build hook only (no runtime Dart dependencies)
│       ├── hook/build.dart       # Native-assets hook entry point
│       ├── lib/src/              # bundle.dart (verify/extract), bundles.dart (pins), tar.dart
│       └── test/                 # bundle integrity tests
├── example/                      # Flutter demo app (Windows/Linux/macOS runners)
│   └── lib/main.dart             # Player + MpvVideoController + MpvVideo demo
├── native/
│   ├── mpv/                      # Vendored upstream mpv 0.41.0-1113 (963 files, do not edit)
│   ├── patches/                  # 0001..0007 mpv_kit patches + UPSTREAM.md
│   ├── tests/                    # C smoke tests + meson.build (render, stream bridge)
│   ├── build/                    # Release scripts: deps.sh, ffmpeg.sh, build.sh, package.sh
│   ├── deps/                     # Local dependency build prefix (git-ignored, empty here)
│   └── out/                      # Build output (git-ignored)
├── tools/
│   ├── gen_catalog.dart          # Regenerate property/command/option catalog
│   ├── gen_options.dart          # Regenerate typed MpvOptions from a running libmpv
│   ├── pin_bundles.dart          # Pin release bundle sha256s
│   ├── bundle_report.sh          # Inspect a produced bundle
│   ├── make_format_samples.sh    # Generate media samples for format tests
│   └── rea_abi_audit/            # PE export/import audit (pure Python) + expected symbols
├── docs/
│   ├── ARCHITECTURE.md           # Runtime architecture narrative
│   ├── ARCHITECTURE-diagrams.md  # Diagram set incl. mpv source map
│   ├── MIGRATING_FROM_MEDIA_KIT.md
│   ├── adr/                      # 0001 Vulkan backend, 0002 LGPL self-built binaries
│   └── reverse-engineering/      # libmpv render pipeline + Windows external texture notes
├── bt/                           # Local Windows runtime DLL set (libmpv + FFmpeg deps), tracked
├── .github/workflows/            # flutter-plugin.yml, native-verify.yml, release.yml
├── pubspec.yaml                  # Workspace manifest
└── README.md                     # User-facing overview, defaults, troubleshooting
```

## Directory Purposes

**`packages/mpv_kit/lib/src/core`:**
- Purpose: the semantic layer over libmpv.
- Contains: `mpv.dart` (client API + event loop), `events.dart` (sealed event decode), `node.dart` (`mpv_node` conversion), `errors.dart` (`MpvException`/`MpvError`), `stream_bridge.dart` (custom protocols).
- Key files: `packages/mpv_kit/lib/src/core/mpv.dart`, `packages/mpv_kit/lib/src/core/stream_bridge.dart`.

**`packages/mpv_kit/lib/src/ffi`:**
- Purpose: ABI boundary.
- Contains: `bindings.dart` (raw `DynamicLibrary` lookups, opaque handle types, format/event/error constants), `library.dart` (single load, resolution order, API major check).
- Key files: `packages/mpv_kit/lib/src/ffi/bindings.dart`, `packages/mpv_kit/lib/src/ffi/library.dart`.

**`packages/mpv_kit/lib/src/generated`:**
- Purpose: machine-generated metadata matching the bundled libmpv.
- Contains: `catalog.dart` (`mpvProperties`, `mpvCommands`, `mpvOptions`), `catalog_types.dart`, `option_types.dart` (`MpvOption`, `MpvOptionType`), `options.dart` (`MpvOptions` constants).
- Generated: yes — by `tools/gen_catalog.dart` and `tools/gen_options.dart`.
- Committed: yes; never hand-edit.

**`packages/mpv_kit/lib/src/player`:**
- Purpose: application-facing player API.
- Contains: `player.dart` (`Player`, `MpvState<T>`, dispose hooks), `models.dart` (tracks, playlist entries, chapters, video/audio params, screenshot, media info, enums).
- Key files: `packages/mpv_kit/lib/src/player/player.dart`, `packages/mpv_kit/lib/src/player/models.dart`.

**`packages/mpv_kit_video/lib/src`:**
- Purpose: Flutter-facing video output.
- Contains: `video_controller.dart` (controller, renderer enums, events, channel contract), `mpv_video.dart` (widget, sizing, resize debounce, display sync).
- Key files: `packages/mpv_kit_video/lib/src/video_controller.dart`, `packages/mpv_kit_video/lib/src/mpv_video.dart`.

**`packages/mpv_kit_video/src`:**
- Purpose: one renderer implementation shared by all three platforms.
- Contains: render thread/ring logic, Vulkan context, symbol table, vendored mpv headers.
- Key files: `packages/mpv_kit_video/src/video_renderer.cc`, `packages/mpv_kit_video/src/vulkan_backend.cc`, `packages/mpv_kit_video/src/mpv_api.h`.

**`packages/mpv_kit_video/windows`:**
- Purpose: Windows embedding + D3D11 sharing.
- Contains: `mpv_kit_video_plugin.cpp` (channel, textures, `PostMessage` events), `d3d11_interop.cpp/.h` (shared NT-handle texture imported into Vulkan), `CMakeLists.txt`.
- Key files: `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp`, `packages/mpv_kit_video/windows/d3d11_interop.cpp`.

**`packages/mpv_kit_video/linux`:**
- Purpose: GTK embedding + GL memory-object sharing.
- Contains: `mpv_kit_video_plugin.cc` (`FlTextureGL`, `g_idle_add` events), `gl_interop.cc/.h` (EGL/GL texture from Vulkan `OPAQUE_FD`, orphan graveyard), `CMakeLists.txt`.
- Key files: `packages/mpv_kit_video/linux/mpv_kit_video_plugin.cc`, `packages/mpv_kit_video/linux/gl_interop.cc`.

**`packages/mpv_kit_video/macos`:**
- Purpose: Cocoa embedding + IOSurface/MoltenVK sharing.
- Contains: `Classes/MpvKitVideoPlugin.mm`, `Classes/MpvKitVideoPlugin.h`, `Classes/metal_interop.mm`, `Classes/metal_interop.h`, `shared_sources.cpp` (compiles the shared renderer into the pod), `volk_unity.c`, `mpv_kit_video.podspec`.
- Key files: `packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm`, `packages/mpv_kit_video/macos/Classes/metal_interop.mm`, `packages/mpv_kit_video/macos/mpv_kit_video.podspec`.

**`packages/mpv_kit_video/third_party`:**
- Purpose: vendored Vulkan headers and volk loader.
- Contains: `vulkan-headers/include/...`, `volk/volk.{c,h}`.
- Generated: no; third-party, pinned (see `third_party/README.md`). Do not modify.

**`packages/mpv_kit_libs`:**
- Purpose: deliver prebuilt libmpv at build time.
- Contains: `hook/build.dart` (native-assets hook), `lib/src/bundle.dart` (sha256 + `MANIFEST.txt` verification, atomic extraction), `lib/src/bundles.dart` (tag + per-target hashes), `lib/src/tar.dart` (minimal tar reader), `test/bundle_test.dart`.
- Runtime code: none — only the build hook.

**`native/mpv`:**
- Purpose: vendored upstream mpv source used by the release workflow.
- Contains: full mpv tree (`video/out`, `demux`, `stream`, `input`, `player`, `DOCS/man`, plus `include/mpv/`).
- Generated: no. Committed: yes. Treat as read-only; changes belong in `native/patches/`.

**`native/patches`:**
- Purpose: the downstream changes that make mpv_kit possible.
- Contains: `0001` Vulkan render backend, `0002` imported-device extensions, `0003` persistent shader cache, `0004` gpu-next render backend, `0005` active-renderer reporting, `0006` async stream bridge, `0007` audio device crash fixes, `UPSTREAM.md`.
- Key files: `native/patches/UPSTREAM.md` (base commit + rebase notes).

**`native/tests`:**
- Purpose: C-level verification against a locally built patched libmpv.
- Contains: `meson.build`, `render_vk_smoke.c` (gpu-next and gpu smoke tests), `stream_bridge_test.c` (bridge + shutdown-while-pending).

**`native/build`:**
- Purpose: reproducible LGPL libmpv production.
- Contains: `deps.sh` (dependency closure), `ffmpeg.sh` (LGPL FFmpeg build + config gate), `build.sh` (deps → FFmpeg → patched mpv), `package.sh` (collect closure, GPL check, ABI audit, `MANIFEST.txt`).

**`tools`:**
- Purpose: generators, release pinning, auditing, sample media.
- Key files: `tools/gen_catalog.dart`, `tools/gen_options.dart`, `tools/pin_bundles.dart`, `tools/rea_abi_audit/pe_audit.py`.

**`example`:**
- Purpose: living integration test and demo.
- Contains: `lib/main.dart` (player UI, stats, renderer events, env hooks `MPV_KIT_EXAMPLE_AO`/`MPV_KIT_EXAMPLE_LOG`), standard Flutter runners for Windows/Linux/macOS.
- Key files: `example/lib/main.dart`, `example/pubspec.yaml`.

**`bt`:**
- Purpose: local Windows runtime DLL set used for manual runs/tests (`libmpv-2.dll`, FFmpeg 8.1 DLLs, libplacebo, Vulkan).
- Generated: no. Committed: yes (22 DLLs). Never edit; replace via a release bundle.

**`.github/workflows`:**
- `flutter-plugin.yml` — analyze + test `mpv_kit_video` and build the example on all three OSes (`-Werror`/`/WX` path).
- `native-verify.yml` — verifies native build/patch application and tests.
- `release.yml` — builds Linux/macOS/Windows bundles for x64/arm64 and publishes `libmpv-<target>.tar.gz` + `SHA256SUMS`.

**`docs`:**
- Purpose: design record and background, not runtime code.
- Contains: runtime architecture, diagram set, migration guide, ADRs, reverse-engineering notes.

## Key File Locations

**Entry Points:**
- `packages/mpv_kit/lib/mpv_kit.dart`: public Dart API for the FFI layer.
- `packages/mpv_kit_video/lib/mpv_kit_video.dart`: single app dependency; re-exports `mpv_kit`.
- `example/lib/main.dart`: end-to-end usage.
- `packages/mpv_kit_libs/hook/build.dart`: build-time asset provider.

**Configuration:**
- `pubspec.yaml`: workspace membership and shared resolution.
- `packages/mpv_kit/pubspec.yaml`: Dart-only constraints (`sdk: ^3.8.0`).
- `packages/mpv_kit_video/pubspec.yaml`: Flutter plugin platform mapping and `sdk: ^3.10.0`/`flutter: >=3.38.0`.
- `packages/mpv_kit_libs/pubspec.yaml`: `code_assets`, `crypto`, `hooks`.
- `packages/*/analysis_options.yaml`: strict analyzer modes + lint rules.
- `packages/mpv_kit/dart_test.yaml`: test tags (`format`).
- `packages/mpv_kit_video/windows/CMakeLists.txt`, `linux/CMakeLists.txt`, `macos/mpv_kit_video.podspec`: native build definitions.
- `native/tests/meson.build`: native test build.

**Core Logic:**
- `packages/mpv_kit/lib/src/core/mpv.dart`: client API, event loop, observers, async requests, stream registration.
- `packages/mpv_kit/lib/src/player/player.dart`: state bindings, defaults, transport, dispose hooks.
- `packages/mpv_kit_video/lib/src/video_controller.dart`: controller lifecycle + channel contract.
- `packages/mpv_kit_video/src/video_renderer.cc`: render thread and fallback logic.
- `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp`, `linux/mpv_kit_video_plugin.cc`, `macos/Classes/MpvKitVideoPlugin.mm`: platform implementations of the same contract.

**Testing:**
- `packages/mpv_kit/test/`: `api_surface_test.dart`, `mpv_test.dart`, `player_test.dart`, `models_test.dart`, `options_test.dart`, `stream_bridge_test.dart`, `audio_devices_test.dart`, `format_matrix_test.dart`.
- `packages/mpv_kit_video/test/`: `controller_channel_test.dart`, `video_controller_test.dart`.
- `packages/mpv_kit_libs/test/bundle_test.dart`.
- `native/tests/`: C smoke tests run under meson.

**Documentation:**
- `README.md`: install, quick start, defaults, renderer fallback, troubleshooting, LGPL compliance.
- `docs/ARCHITECTURE.md`: dependency chain, threading, frame ring, stream bridge.
- `docs/adr/0001-vulkan-render-backend.md`, `docs/adr/0002-lgpl-self-built-binaries.md`.

## Naming Conventions

**Files:**
- Dart: `snake_case.dart` (`video_controller.dart`, `stream_bridge.dart`, `option_types.dart`).
- Dart test files: `<subject>_test.dart` under the package's `test/` (`player_test.dart`, `controller_channel_test.dart`); underscore-prefixed helper files if added.
- C++ headers/implementations: `snake_case.h` / `snake_case.cc` (`.cpp` in `windows/`) — `video_renderer.h`, `vulkan_backend.cc`, `d3d11_interop.cpp`.
- ObjC++: PascalCase class file matching the class (`MpvKitVideoPlugin.mm`).
- Platform plugin entry files: `mpv_kit_video_plugin.<ext>` on every platform.
- Patches: `NNNN-short-kebab-description.patch` (`0006-libmpv-asynchronous-stream-bridge.patch`).
- Shell tools: `snake_case.sh`.

**Dart code:**
- Classes/enums/typedefs: `PascalCase`, public API prefixed logically by area (`MpvEventData`, `MpvVideoController`, `MpvVideoEventKind`).
- Members/parameters: `camelCase`; private members start with `_`.
- Top-level generated constants: `camelCase` (`mpvProperties`, `mpvOptions`) — not `SCREAMING_SNAKE_CASE`, unlike `Mpv.secureDefaultOptions`.
- Generated option constants: snake_case names preserved from mpv via `constant_identifier_names` (`MpvOptions.demuxer_max_bytes`).

**C++ code:**
- Namespace: `mpv_kit`; anonymous namespace for file-local helpers.
- Types: `PascalCase` (`VideoRenderer`, `VulkanContext`, `D3D11Interop`, `GlInterop`, `MetalInterop`, `SharedImage`, `Frame`).
- Methods/functions: `PascalCase` for classes (`Start`, `SetSize`, `AcquireFront`), `PascalCase` free functions (`ParseRendererChoice`); locals/members snake_case with trailing underscore for fields (`render_ctx_`, `quarantine_count_`).
- Constants: `kPascalCase` (`kMaxQuarantine`, `kIdleTimeout`).

**Directories:**
- Flutter plugin platform directories are fixed by the tool: `windows/`, `linux/`, `macos/`.
- Shared native code lives in `src/`; bundled third-party code in `third_party/`.

**Public API naming:** platform-facing enums carry a `Mpv` prefix and wire spellings in strings (`MpvVideoRenderer.gpuNext` ↔ `"gpu-next"`); this mapping is the contract with `parse` in both Dart (`tryParse`) and C++ (`ParseRendererChoice`).

## Where to Add New Code

**New playback state exposed to apps:**
- Implementation: add a `final`/`late final MpvState<T>` field and a `_bind('<mpv-property>', state, parse)` call in the `Player._` constructor (`packages/mpv_kit/lib/src/player/player.dart:110-198`). Follow the `time-pos` throttle only if the property updates per frame.
- Model parsing: add a `fromNode` factory in `packages/mpv_kit/lib/src/player/models.dart`.
- Tests: `packages/mpv_kit/test/player_test.dart` (or `models_test.dart` for pure parsing).

**New command/transport helper:**
- Implementation: a thin method on `Player` calling `mpv.command`/`commandAsync`/`setProperty` (`packages/mpv_kit/lib/src/player/player.dart`).
- Low-level behavior not covered by `Mpv`: extend `packages/mpv_kit/lib/src/core/mpv.dart` and add the symbol to `packages/mpv_kit/lib/src/ffi/bindings.dart` + `tools/rea_abi_audit/expected_symbols.txt` if it is exported by libmpv.

**New typed option or catalog entry:**
- Do not hand-write. Update `tools/gen_catalog.dart` / `tools/gen_options.dart`, regenerate into `packages/mpv_kit/lib/src/generated/`, and add a regression test in `packages/mpv_kit/test/options_test.dart` / `format_matrix_test.dart` if runtime behavior changes.

**New stream source type:**
- Implementation: implement `MpvStreamSource` in `packages/mpv_kit/lib/src/core/stream_bridge.dart` (or an app file) and register with `Mpv.registerStreamProtocol`.
- Tests: `packages/mpv_kit/test/stream_bridge_test.dart`; native coverage in `native/tests/stream_bridge_test.c`.

**New renderer diagnostic event:**
- Dart: add a value to `MpvVideoEventKind`, update `MpvVideoEventKind._parse`, and document it in the enum (`packages/mpv_kit_video/lib/src/video_controller.dart:49-93`).
- Native: emit via `EventFn` (`Emit`) in `packages/mpv_kit_video/src/video_renderer.cc`; the platform plugin already forwards unknown kinds to Dart.
- Tests: `packages/mpv_kit_video/test/video_controller_test.dart`, `controller_channel_test.dart`.

**New controller capability (channel method):**
- Dart: add the call in `MpvVideoController` (`packages/mpv_kit_video/lib/src/video_controller.dart`).
- Native: implement in all three plugins (`windows/mpv_kit_video_plugin.cpp`, `linux/mpv_kit_video_plugin.cc`, `macos/Classes/MpvKitVideoPlugin.mm`) — the header comment in each file is the channel contract; keep them identical.
- Renderer: add the corresponding method on `VideoRenderer` (`packages/mpv_kit_video/src/video_renderer.h`) so platform code stays thin.

**New platform interop (e.g. Android/iOS):**
- Create the platform directory with a plugin entry and an `Interop` implementation (`windows/d3d11_interop.cpp` is the smallest reference), plus a `VulkanInterop` for zero-copy sharing.
- Register the platform in `packages/mpv_kit_video/pubspec.yaml` under `flutter.plugin.platforms`.
- Reuse `src/video_renderer.cc` and `src/vulkan_backend.cc`; do not fork them.
- Add the bundle target in `packages/mpv_kit_libs/lib/src/bundle.dart` (`bundleTarget`) and `native/build` scripts.

**New build/release automation:**
- Shell: `native/build/` (keep POSIX `sh`/bash, no Windows-only constructs).
- Dart tooling: `tools/` (standalone scripts, run from repo root).
- CI: `.github/workflows/` — `flutter-plugin.yml` for Dart/plugin changes, `native-verify.yml` for native patches, `release.yml` for bundles.

**New tests:**
- Pure Dart: `packages/mpv_kit/test/<area>_test.dart` (`dart test`).
- Flutter/Dart channel logic: `packages/mpv_kit_video/test/<area>_test.dart` (`flutter test`).
- Bundle/tar logic: `packages/mpv_kit_libs/test/bundle_test.dart`.
- Native renderer/bridge: `native/tests/` with a new executable + `test()` in `meson.build`.

## Special Directories

**`native/mpv`:**
- Purpose: vendored mpv 0.41.0-1113 source.
- Generated: no.
- Committed: yes (963 files).
- Modifications must go through `native/patches/`, not direct edits; patches are rebased with GNU `patch -p1` (see `native/patches/UPSTREAM.md`).

**`packages/mpv_kit/lib/src/generated`:**
- Purpose: generated API surface.
- Generated: yes (`tools/gen_catalog.dart`, `tools/gen_options.dart`).
- Committed: yes. Do not edit.

**`packages/mpv_kit_video/third_party`:**
- Purpose: volk + Vulkan headers.
- Generated: no; pinned third-party.
- Committed: yes. Version/hash notes in `packages/mpv_kit_video/third_party/README.md`.

**`native/deps`, `native/out`, `build`, `.dart_tool`, `coverage`:**
- Purpose: local build outputs.
- Generated: yes.
- Committed: no (`native/out/`, `build/`, `.dart_tool/`, `coverage/` are git-ignored; `native/build/` is explicitly re-included).

**`bt`:**
- Purpose: ready-to-run Windows DLL set for manual testing.
- Generated: no (assembled by `native/build/package.sh`).
- Committed: yes. Treat as an artifact, not source.

**`example/build`, `example/.idea`:**
- Purpose: generated app build output and IDE metadata.
- Committed: no.

---

*Structure analysis: 2026-10-23*
