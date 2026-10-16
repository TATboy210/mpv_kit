# mpv_kit_video

Flutter video output for [mpv_kit](https://pub.dev/packages/mpv_kit).
This is the only package a Flutter app needs: it re-exports the mpv_kit API
and depends on [mpv_kit_libs](https://pub.dev/packages/mpv_kit_libs), which
bundles libmpv.

mpv renders with its own renderer (gpu-next or gpu, via libplacebo) through
the Vulkan render API added by mpv_kit's libmpv patches, directly into
images the Flutter compositor samples — no per-frame copies:

| Platform | Shared image | Flutter texture |
|---|---|---|
| Windows | D3D11 texture (KMT handle) imported into Vulkan | `GpuSurfaceTexture` (DXGI shared handle) |
| Linux | Vulkan `OPAQUE_FD` memory imported with `GL_EXT_memory_object_fd` | `FlTextureGL` |
| macOS | IOSurface `CVPixelBuffer` bound by MoltenVK (`VK_EXT_metal_objects`) | `FlutterTexture` |

Real-hardware testing so far: Windows x64 (NVIDIA RTX 4060). The other
targets are compiled and smoke-tested in CI.

## Usage

```yaml
dependencies:
  mpv_kit_video: ^0.1.0-dev.3
```

```dart
import 'package:mpv_kit_video/mpv_kit_video.dart';

final player = Player();
final video = await MpvVideoController.create(player);
await player.open('/path/to/video.mkv');

// in build():
MpvVideo(controller: video, fit: BoxFit.contain);

// when done (disposes the controller first):
await player.dispose();
```

`MpvVideo` renders at the exact physical pixel size of the visible video
rectangle (honouring rotation and pixel aspect), so scaling uses mpv's
scalers rather than texture filtering. Resizes are debounced
(`resizeDebounce`, 80 ms by default).

## Renderers and fallback

| `MpvVideoRenderer` | Behaviour |
|---|---|
| `auto` (default) | gpu-next → gpu → software |
| `gpuNext` | gpu-next, then software |
| `gpu` | gpu, then software |
| `software` | CPU rendering only |

If Vulkan 1.3, the interop extensions or a suitable GPU are missing, the
software renderer is used. `MpvVideoController.backend` and `.reason` say
which path is active and why. Set the environment variable
`MPV_KIT_VIDEO_RENDERER` (`auto`, `gpu-next`, `gpu`, `software`) to override
the renderer without code changes.

## Diagnostics

* `controller.events` — `MpvVideoEvent`s: `resize`, `idle`, `active`,
  `renderError`, `gpuTimeout`, `recovered`, `deviceLost`. After
  `deviceLost` (`controller.isBroken`) dispose the controller and create a
  new one, e.g. with `MpvVideoRenderer.software`.
* `controller.setIccProfile(bytes)` — color-manage for a display ICC
  profile (Vulkan renderers only).
* Compiled shaders are cached in a per-user `mpv_kit/shader-cache`
  directory unless the app sets `gpu-shader-cache-dir`.
* `display-fps-override` is set from Flutter's display refresh rate unless
  the app set it.

libmpv itself is loaded by `mpv_kit` (bundled binaries or
`MPV_KIT_LIBMPV_PATH`); this plugin never loads a second copy.

## License

MIT for this package. Vendored Vulkan-Headers (Apache-2.0 OR MIT) and volk
(MIT) are listed in `third_party/README.md`.
