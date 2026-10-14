# mpv_kit

Flutter / Dart bindings for **libmpv 0.41** with a **Vulkan** render backend,
targeting Windows, Linux and macOS on x86_64 and arm64.

> Status: early development (0.1.0-dev). APIs may change.

| Package | Purpose |
|---|---|
| [`mpv_kit`](packages/mpv_kit) | Pure Dart FFI: the complete libmpv client API (all 54 symbols), typed events, `mpv_node` conversion, a typed `Player`, and a catalog of every mpv property/command/option generated from mpv's docs |
| [`mpv_kit_video`](packages/mpv_kit_video) | Flutter plugin: mpv renders through Vulkan straight into textures the compositor samples — D3D11 shared textures (Windows), GL memory objects (Linux), IOSurface via MoltenVK (macOS) — with a software fallback |
| [`mpv_kit_libs`](packages/mpv_kit_libs) | Build hook that bundles a verified prebuilt LGPL libmpv for the target platform |

## Why a patched mpv?

Upstream libmpv's render API only offers OpenGL and software backends.
mpv_kit adds `MPV_RENDER_API_TYPE_VULKAN` (`native/patches/`), which imports
the host's `VkDevice` into libplacebo and reuses mpv's own renderer, HDR
handling and Vulkan hardware decoding unchanged. See
`native/mpv/include/mpv/render_vk.h` and `docs/adr/`.

## Quick start

```dart
import 'package:mpv_kit/mpv_kit.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

final player = Player();
final video = await MpvVideoController.create(player);
await player.open('video.mkv');

// in build():
MpvVideo(controller: video);
```

Add `mpv_kit_libs` to your dependencies to ship libmpv with the app, or
point `MPV_KIT_LIBMPV_PATH` at your own build. The low-level API is
available too:

```dart
final mpv = Mpv.create(options: {'vo': 'null'});
mpv.events.whereType<FileLoadedEvent>().listen((_) => print('loaded'));
mpv.command(['loadfile', 'video.mkv']);
mpv.observeProperty('time-pos').listen(print);
```

By default `config`, `load-scripts`, `ytdl` and default key bindings are
disabled (`Mpv.secureDefaultOptions`); enable them explicitly if needed.

## Building libmpv

| Workflow | What it does |
|---|---|
| `native-verify` | Builds the patched libmpv on all six targets, runs the Vulkan render smoke test (lavapipe / MoltenVK), the ABI audit and the Dart tests |
| `flutter-plugin` | Compiles `mpv_kit_video` through the example app on Windows, Linux and macOS |
| `release` | LGPL release bundles: FFmpeg 8.1.3 from source (`native/build/ffmpeg.sh`), license-gated, packaged with its dependency closure and a sha256 manifest (`native/build/package.sh`); `v*` tags publish them |

## Licensing

See [NOTICE](NOTICE). Dart and plugin code is MIT; libmpv and FFmpeg are
distributed as LGPL builds (dynamically linked, with the patch and build
scripts in this repository).
