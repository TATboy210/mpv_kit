# mpv_kit

Flutter / Dart bindings for **libmpv 0.41** with a **Vulkan** render backend,
targeting Windows, Linux and macOS on x86_64 and arm64.

> Status: early development (0.1.0-dev). APIs may change.

| Package | Purpose |
|---|---|
| [`mpv_kit`](packages/mpv_kit) | Pure Dart FFI: the complete libmpv client API (all 54 symbols), typed events, `mpv_node` conversion |
| `mpv_kit_video` *(planned)* | Flutter plugin: zero-copy texture bridge (Vulkan → D3D11 / dma-buf / IOSurface), with OpenGL and software fallbacks |
| `mpv_kit_libs` *(planned)* | Native-assets hook that downloads verified prebuilt LGPL libmpv binaries |

## Why a patched mpv?

Upstream libmpv's render API only offers OpenGL and software backends.
mpv_kit adds `MPV_RENDER_API_TYPE_VULKAN` (`native/patches/`), which imports
the host's `VkDevice` into libplacebo and reuses mpv's own renderer and
Vulkan hardware decoding unchanged. See `native/mpv/include/mpv/render_vk.h`.

## Quick start (Dart core)

```dart
import 'package:mpv_kit/mpv_kit.dart';

final mpv = Mpv.create(options: {'vo': 'null'});
mpv.events.whereType<FileLoadedEvent>().listen((_) => print('loaded'));
mpv.command(['loadfile', 'video.mkv']);
mpv.observeProperty('time-pos').listen(print);
```

By default `config`, `load-scripts`, `ytdl` and default key bindings are
disabled (`Mpv.secureDefaultOptions`); enable them explicitly if needed.

## Licensing

See [NOTICE](NOTICE). Dart code is MIT; libmpv is distributed as an LGPL build.
