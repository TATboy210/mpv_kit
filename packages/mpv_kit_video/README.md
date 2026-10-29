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
| Windows | D3D11 texture (KMT handle) imported into Vulkan, or rendered by mpv directly through its D3D11 render API (`d3d11`) | `GpuSurfaceTexture` (DXGI shared handle) |
| Linux | Vulkan `OPAQUE_FD` memory imported with `GL_EXT_memory_object_fd`, or mpv's OpenGL render API into an export texture shared as an `EGLImage` (`opengl`) | `FlTextureGL` |
| macOS | IOSurface `CVPixelBuffer` bound by MoltenVK (`VK_EXT_metal_objects`) | `FlutterTexture` |

Real-hardware testing so far: Windows x64 (NVIDIA RTX 4060). The other
targets are compiled and smoke-tested in CI.

## Usage

```yaml
dependencies:
  mpv_kit_video: ^0.1.0-dev.4
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
which path is active and why: `backend` is `vulkan` for the GPU zero-copy
path or `software`, and `reason` starts with the real graphics API, e.g.
`vulkan (gpu-next) on <device>` or
`software (sw) on cpu; vulkan/gpu-next unavailable: <why>`. Set the
environment variable `MPV_KIT_VIDEO_RENDERER` (`auto`, `gpu-next`, `gpu`,
`software`) to override the renderer without code changes.

On Windows the plugin has a native Direct3D 11 backend next to the Vulkan
one: `MPV_KIT_VIDEO_API=d3d11` forces it. `auto` currently tries
`vulkan/gpu-next`, `d3d11/gpu-next`, `vulkan/gpu`, `d3d11/gpu`, then
software: where Vulkan works nothing changes, and where it does not (no
driver, older GPUs) D3D11 renders instead of the CPU.

Hybrid-GPU laptops: the plugin always renders on the adapter Flutter's
compositor uses (shared textures cannot cross adapters), so on a laptop where
Flutter lands on the integrated GPU, decode and rendering do too. On the 14-10
test laptop (GeForce GTX 960M + Intel HD 530) that meant d3d11 gpu-next on the
HD 530 with 477-3310 dropped frames and dec-drop 0. An app opts in from its
own runner, because the engine picks its adapter before any plugin registers:
in `windows/runner/main.cpp`, before creating the window (Flutter 3.41 or
newer, flutter/flutter#177653):

```cpp
flutter::DartProject project(L"data");
project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
```

Without a discrete GPU the engine uses the default adapter. The plugin writes
one stderr / DebugView line per controller,
`mpv_kit: compositor adapter "<name>" luid=<hi>:<lo>`, that shows which
adapter is in use.

On Linux the plugin has an OpenGL backend next to the Vulkan one (mpv's
`gpu` renderer only): `auto` tries `vulkan/gpu-next`, `opengl/gpu`,
`vulkan/gpu`, then software, and `MPV_KIT_VIDEO_API=opengl` forces it. It
needs libEGL.so.1 and is verified on Mesa llvmpipe only (real GPU drivers and
Wayland are not verified).

`MPV_KIT_VIDEO_API` (read by the native plugin) forces one graphics API,
for example `vulkan`, `d3d11` (Windows), `opengl` (Linux) or `software`, for CI and
diagnostics. It never falls back: if that API cannot be used, `create` throws `render_init`. See
[ADR 0004](https://github.com/TATboy210/mpv_kit/blob/main/docs/adr/0004-render-backend-reporting.md)
for the `reason` grammar and the exact semantics.

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
