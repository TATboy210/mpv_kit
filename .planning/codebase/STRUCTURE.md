---
last_mapped_commit: cd47d6761925b8ccb49e153864bf9789dc3f5039
last_mapped_at: 2026-10-27
---
# Codebase Structure

**Analysis Date:** 2026-10-27

## Directory Layout

```
mpv_kit/
├── pubspec.yaml              # Pub workspace root (packages + example)
├── packages/
│   ├── mpv_kit/              # Pure Dart FFI bindings + Player
│   │   ├── lib/mpv_kit.dart  # Barrel
│   │   ├── lib/src/ffi/      # bindings.dart, library.dart
│   │   ├── lib/src/core/     # mpv, events, node, errors, stream_bridge
│   │   ├── lib/src/player/   # player.dart, models.dart
│   │   ├── lib/src/generated/# catalog/options (generated, committed)
│   │   └── test/             # package:test suites + fixtures/
│   ├── mpv_kit_video/        # Flutter plugin
│   │   ├── lib/src/          # video_controller.dart, mpv_video.dart
│   │   ├── src/              # Shared C++ engine + RenderBackend seam
│   │   │   └── include/mpv/  # Vendored client.h, render.h, render_vk.h
│   │   ├── windows/          # Win plugin + d3d11_interop
│   │   ├── linux/            # GTK plugin + gl_interop
│   │   ├── macos/            # podspec, Classes/ (Obj-C++, metal_interop)
│   │   ├── third_party/      # Vulkan-Headers, volk (vendored)
│   │   └── test/             # flutter_test suites
│   └── mpv_kit_libs/         # Native-assets hook delivering libmpv bundle
│       ├── hook/build.dart
│       └── lib/src/          # bundle.dart, bundles.dart (pins), tar.dart
├── example/                  # Demo app + integration_test/
├── native/
│   ├── mpv/                  # Vendored upstream mpv tree (third-party)
│   ├── patches/              # Downstream mpv patches + UPSTREAM.md
│   ├── deps/libplacebo/      # libplacebo backport patches + SHA256SUMS
│   ├── build/                # build.sh, deps.sh, ffmpeg.sh, package.sh
│   └── tests/                # meson C/C++ tests, golden/ traces
├── tools/                    # Generators, pinning, audits, benches
├── docs/                     # ARCHITECTURE, adr/, perf/, reverse-engineering/
└── .github/workflows/        # flutter-plugin, native-verify, release
```

## Directory Purposes

**`packages/mpv_kit/lib/src/`:**
- Purpose: all Dart libmpv logic, layered `ffi/` -> `core/` -> `player/`
- Key files: `core/mpv.dart`, `player/player.dart`, `ffi/library.dart`

**`packages/mpv_kit_video/src/`:**
- Purpose: platform-independent native renderer
- Key files: `render_backend.h` (RenderBackend, BackendCandidate, DefaultCandidates, TargetView, WaitResult), `video_renderer.h/.cc` (engine, Interop, SoftwareBackend, MPV_KIT_VIDEO_API), `vulkan_backend.h/.cc` (VulkanContext, VulkanInterop, VulkanRenderBackend), `mpv_api.h`

**`packages/mpv_kit_video/{windows,linux,macos}/`:**
- Purpose: platform plugin + interop; macOS compiles shared sources through `macos/Classes/shared_sources.cpp` and `volk_unity.c`
- Build: `windows/CMakeLists.txt`, `linux/CMakeLists.txt`, `macos/mpv_kit_video.podspec`

**`native/mpv/`:**
- Purpose: upstream mpv source (963 files, `MPV_VERSION`) — do not edit; change via `native/patches/`

**`native/tests/`:**
- Purpose: `render_vk_smoke.c`, `stream_bridge_test.c`, `renderer_harness.h` (fake libmpv), `video_renderer_golden_*.cc` + `golden/*.txt` (frozen), `video_renderer_affinity_test.cc`, `video_renderer_api_test.cc`, `video_renderer_sw_hold_front_test.cc`; declared in `meson.build`

**`docs/`:**
- `ARCHITECTURE.md`, `ARCHITECTURE-diagrams.md`, `MIGRATING_FROM_MEDIA_KIT.md`, `adr/0001`–`0004`, `perf/` measurements, `reverse-engineering/` notes

**`tools/`:**
- `gen_catalog.dart`, `gen_options.dart`, `pin_bundles.dart`, `check_consistency.dart`, `check_patches.sh`, `check_matrix.py`, `bench_decode.dart`, `bundle_report.sh`, `make_format_samples.sh`, `rea_abi_audit/`

## Key File Locations

**Entry Points:**
- `packages/mpv_kit/lib/mpv_kit.dart`, `packages/mpv_kit_video/lib/mpv_kit_video.dart`, `packages/mpv_kit_libs/lib/mpv_kit_libs.dart`: barrels
- `packages/mpv_kit_libs/hook/build.dart`: native-assets hook
- `example/lib/main.dart`: demo app

**Configuration:**
- `pubspec.yaml` (workspace), `packages/*/pubspec.yaml`, `packages/*/analysis_options.yaml`, `packages/mpv_kit/dart_test.yaml`
- `packages/mpv_kit_libs/lib/src/bundles.dart`: bundle tag + sha256 pins

**Core Logic:**
- `packages/mpv_kit/lib/src/core/mpv.dart`, `packages/mpv_kit/lib/src/player/player.dart`
- `packages/mpv_kit_video/src/video_renderer.cc`, `render_backend.h`, `vulkan_backend.cc`

**Testing:**
- `packages/mpv_kit/test/`, `packages/mpv_kit_video/test/`, `packages/mpv_kit_libs/test/bundle_test.dart`, `example/test/`, `example/integration_test/`, `native/tests/`

## Naming Conventions

**Files:**
- Dart: `snake_case.dart`, one primary type per file (`video_controller.dart`); tests `<subject>_test.dart`
- C++ shared/Linux: `snake_case.cc/.h`; Windows `.cpp`; macOS `PascalCase.mm` for plugin, `snake_case.mm` for interop
- Native tests: `video_renderer_<topic>_test.cc`, goldens `video_renderer_golden_<case>.cc` + `golden/<case>.txt`
- Patches: `NNNN-<area>-<summary>.patch`; ADRs: `docs/adr/NNNN-<slug>.md`; perf: `docs/perf/YYYY-MM-DD-<slug>.md`

**Directories:**
- Dart `lib/src/<area>/` by layer (`ffi`, `core`, `player`, `generated`)

## Where to Add New Code

**New Dart feature on the player:**
- Primary code: `packages/mpv_kit/lib/src/player/` (or `core/` for client-API mirror)
- Tests: `packages/mpv_kit/test/`; public API is frozen — check `api_freeze_test.dart`

**New render backend (e.g. D3D11, OpenGL):**
- Implementation: `RenderBackend` subclass in platform folder (`packages/mpv_kit_video/windows/` or `linux/`) or `src/` if shared
- Wire-up: override `Interop::BackendCandidates` / `Interop::CreateBackend` in the platform interop; add wire name to Dart exact-match set in `video_controller.dart`
- Tests: new file in `native/tests/` + entry in `native/tests/meson.build` (never edit frozen goldens)

**Platform interop change:** `packages/mpv_kit_video/{windows,linux,macos}/`

**mpv change:** new patch in `native/patches/`, record in `UPSTREAM.md`

**Utilities/tools:** `tools/`

**Design decisions:** `docs/adr/`

## Special Directories

**`packages/mpv_kit/lib/src/generated/`:**
- Purpose: catalog/options
- Generated: Yes (`tools/gen_*.dart`) | Committed: Yes

**`native/mpv/`:**
- Purpose: vendored upstream mpv | Generated: No | Committed: Yes

**`packages/mpv_kit_video/third_party/`, `src/include/mpv/`:**
- Purpose: vendored Vulkan-Headers, volk, mpv headers | Committed: Yes

**`native/tests/golden/`:**
- Purpose: frozen renderer call traces | Committed: Yes

**`example/{windows,linux,macos}/flutter/`:**
- Purpose: Flutter-generated registrants | Generated: Yes | Committed: Yes

**`.planning/`:**
- Purpose: GSD planning artifacts | Committed: Yes

**`pubspec.lock`, `build/`, `coverage/`:**
- Generated: Yes | Committed: lock listed in `.gitignore`

---

*Structure analysis: 2026-10-27*
