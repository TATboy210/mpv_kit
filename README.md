# mpv_kit

Flutter / Dart bindings for **libmpv v0.41.0-1115-gb2c255c13** (vendored
under `native/mpv`) with a **Vulkan** render
backend added by a small set of patches, rendering zero-copy into Flutter
textures on Windows, Linux and macOS.

> Status: early development (`0.1.0-dev.4`). APIs may change.

| Package | Purpose |
|---|---|
| [`mpv_kit`](packages/mpv_kit) | Pure Dart FFI: the complete libmpv client API, typed events, `mpv_node` conversion, a typed high-level `Player`, typed `MpvOptions`, custom stream protocols served from Dart, and a catalog of every mpv property/command/option generated from mpv's docs |
| [`mpv_kit_video`](packages/mpv_kit_video) | Flutter plugin: `MpvVideoController` + `MpvVideo` widget. mpv renders through Vulkan into images the compositor samples directly — D3D11 shared textures (Windows), GL memory objects (Linux), IOSurface via MoltenVK (macOS) — with a software fallback everywhere |
| [`mpv_kit_libs`](packages/mpv_kit_libs) | Build hook that downloads and bundles a prebuilt LGPL libmpv for the target, verified by sha256 |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit
together, and [docs/adr/](docs/adr) for the design decisions.

Prebuilt libmpv runs on Windows 10+, macOS 12+ and Linux with glibc 2.35+
and libEGL.so.1 (libglvnd; x64 and arm64), plus libva.so.2 and libva-drm.so.2
(VA-API; the bundle links them as host libraries). Coming from media_kit? See
[docs/MIGRATING_FROM_MEDIA_KIT.md](docs/MIGRATING_FROM_MEDIA_KIT.md).

## Quick start

Depend on **`mpv_kit_video` only**: it re-exports the whole `mpv_kit` API
and pulls in `mpv_kit_libs`, which bundles libmpv into the app.

```yaml
dependencies:
  mpv_kit_video: ^0.1.0-dev.4
```

```dart
import 'package:flutter/material.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final player = Player(); // vo=libmpv, per-platform zero-copy hwdec, keep-open=yes
  MpvVideoController? video;

  @override
  void initState() {
    super.initState();
    MpvVideoController.create(player).then((controller) {
      if (!mounted) return;
      setState(() => video = controller);
      player.open('/path/to/video.mkv');
    });
  }

  @override
  void dispose() {
    player.dispose(); // disposes the controller first (dispose hook)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = video;
    return controller == null
        ? const SizedBox.expand()
        : MpvVideo(controller: controller, fit: BoxFit.contain);
  }
}
```

Requirements: Dart 3.10 / Flutter 3.38 or newer (the build hook of
`mpv_kit_libs` uses native assets). All package `sdk:` constraints in this
repository are pinned to the same floor and checked by
`tools/check_consistency.dart`.

### Dependency locking

The workspace `pubspec.lock` is **committed**: CI and fresh clones resolve
against the same pinned dependency set. Update it deliberately
(`dart pub upgrade`) and commit it together with any `pubspec.yaml` change.

### Local libmpv for tests and benches

The tests need a real libmpv unless they are pure-Dart. Two supported ways:

1. **Default — nothing to do.** `dart pub get`/`flutter pub get` triggers the
   `mpv_kit_libs` build hook, which downloads the pinned, sha256-verified
   libmpv bundle for your platform.
2. **Explicit — `MPV_KIT_LIBMPV_PATH`.** Point it at a `libmpv-2.dll` /
   `libmpv.so.2` (e.g. from the hook cache under
   `.dart_tool/hooks_runner/shared/mpv_kit_libs/build/`) **and put that
   directory on `PATH`** — on Windows the dependency DLLs must be reachable
   or loading fails with `MpvLibraryNotFound` (an explicit path is never
   fallen back from). Git Bash note: `PATH`
   entries must use the POSIX form (`/d/mpv_kit/...`); a `D:/...` entry is
   not converted and dependency resolution fails.

The old `bt/` directory of prebuilt DLLs was retired and removed from the
repository (stale pre-rebase binaries without the working Vulkan render
path, ~44 MB); use the hook bundle instead.

The low-level client API is always available, standalone or as
`player.mpv`:

```dart
final mpv = Mpv.create(options: {'vo': 'null'});
mpv.events.where((e) => e is FileLoadedEvent).listen((_) => print('loaded'));
mpv.command(['loadfile', 'video.mkv']);
mpv.observeProperty('time-pos').listen(print);
```

`Mpv.create` disables `config`, `load-scripts`, `ytdl`, `osc` and the
default key bindings (`Mpv.secureDefaultOptions`); pass them in `options`
to enable them explicitly.

### Locating libmpv

`MpvLibrary.open()` is strict about libraries you name: an explicit
`libraryPath` is tried alone; otherwise a non-empty `MPV_KIT_LIBMPV_PATH`
environment variable is tried alone. If that library cannot be loaded (missing
file, unresolved dependency DLL, incompatible client API) it throws
`MpvLibraryNotFound` with the loader's reason and does **not** fall back to
another copy. Only when neither is given are the platform default names tried
in order (`libmpv-2.dll`; `@rpath/mpv.2.framework/mpv.2`, `libmpv.2.dylib`;
`libmpv.so.2`), which resolve to the copy bundled by `mpv_kit_libs`. A local
bundle can be supplied with the `libmpv_bundle` hook user define (see
[mpv_kit_libs](packages/mpv_kit_libs/README.md)).

> Until a `v*` release is pinned in
> `packages/mpv_kit_libs/lib/src/bundles.dart`, the hook emits no assets;
> use `libmpv_bundle` or `MPV_KIT_LIBMPV_PATH` with a bundle produced by the
> `release` workflow.

## Renderer selection and fallback

`MpvVideoController.create(player, renderer: ...)` takes an
`MpvVideoRenderer`:

| Value | Behaviour |
|---|---|
| `auto` (default) | gpu-next → gpu → software |
| `gpuNext` | gpu-next, then software |
| `gpu` | mpv's gl_video renderer, then software |
| `software` | CPU rendering (`MPV_RENDER_API_TYPE_SW`) |

Software is used whenever Vulkan 1.3, the platform interop extensions or a
suitable GPU are missing, or both Vulkan renderers fail to initialise. After
`create` returns:

* `controller.backend` is `MpvVideoBackend.vulkan` (the GPU zero-copy
  path) or `.software` (CPU rendering). The enum is frozen; the real
  graphics API is the first token of `controller.reason`;
* `controller.reason` explains it, e.g. `vulkan (gpu-next) on <device>` or
  `software (sw) on cpu; vulkan/gpu-next unavailable: <why>`. The format is
  `<api> (<renderer>) on <device>` followed by one
  `; <api>/<renderer> unavailable: <why>` per candidate that was ranked
  before the winner ([ADR 0004](docs/adr/0004-render-backend-reporting.md)).
  On macOS the GPU head also names the Vulkan implementation that carries the
  rendering onto Metal, e.g. `vulkan (gpu-next) on <device> via MoltenVK`.
  It is also printed once with `debugPrint`.

The environment variable **`MPV_KIT_VIDEO_RENDERER`** (`auto`, `gpu-next`,
`gpu`, `software`) takes precedence over the requested renderer, so driver
problems in a shipped app can be diagnosed without code changes.

On Windows, mpv can also render through its own Direct3D 11 API (native
`d3d11` backend, own `ID3D11Device` on Flutter's adapter, no Vulkan): set
`MPV_KIT_VIDEO_API=d3d11` to force it. For now `auto` tries, in order,
`vulkan/gpu-next`, `d3d11/gpu-next`, `vulkan/gpu`, `d3d11/gpu`, then
software. A machine with a usable Vulkan 1.3 device behaves as before; a
machine without one (no driver, an old GPU) renders on `d3d11` instead of
falling back to software. Making D3D11 the first choice on Windows is a
separate, later change.

On Linux, mpv can also render through its upstream OpenGL render API (native
`opengl` backend: a context of its own on Flutter's `EGLDisplay`, frames
handed to Flutter as an `EGLImage`; it serves mpv's `gpu` renderer only, never
`gpu-next`). `auto` tries `vulkan/gpu-next`, `opengl/gpu`, `vulkan/gpu`, then
software, so a machine where Vulkan 1.3 is unusable renders on `opengl`
instead of the CPU. `MPV_KIT_VIDEO_API=opengl` forces it.

The native environment variable **`MPV_KIT_VIDEO_API`** forces one graphics
API (`vulkan` or `software` everywhere, `d3d11` on Windows, `opengl` on
Linux). It is strict: only that API is tried, there is
no fallback to any other API (software included), and `create` throws
`PlatformException(code: 'render_init')` when it cannot be used or does not
match the selected renderer. Leave it unset in shipped apps; it exists for
CI and diagnostics. See
[ADR 0004](docs/adr/0004-render-backend-reporting.md).

## Hardware decoding defaults

`Player()` sets a per-platform, zero-copy-first `hwdec` list
([ADR 0006](docs/adr/0006-hwdec-defaults.md)):

| Platform | Default `hwdec` | Zero-copy on | Falls back to |
|---|---|---|---|
| Windows | `vulkan,d3d11va,d3d11va-copy,auto-safe` | `vulkan` (Vulkan Video) on the Vulkan backend, `d3d11va` on the D3D11 backend | `d3d11va-copy`, then `auto-safe` |
| Linux | `vulkan,vaapi,auto-safe` | `vulkan` (Vulkan Video) or `vaapi` (dma-buf; not verified on real hardware) | `vaapi-copy` inside `auto-safe`, then software |
| macOS | `videotoolbox,auto-safe` | `videotoolbox` | `auto-safe`, then software |
| Other | `auto-safe` | n/a | software |

This is a behavior change from the old single list on every platform
(`vulkan,d3d11va-copy,auto-safe`). mpv tries the entries in order. An entry
without an interop on the active renderer is skipped (it never copies back),
while `-copy` entries and `auto-safe` decode on their own device and copy the
frames back to system memory, so they come last. Override the list at creation
with `Player(options: {'hwdec': 'vulkan'})` (your value always wins), or at
runtime with `player.setHardwareDecoding('no')` (applies to the next decoder).

To tell zero-copy from a copy-back, read the decoder in use,
`player.hwdecCurrent` (`hwdec-current`; null or `no` means software), together
with `video-params/pixelformat` (`player.mpv.getProperty('video-params/pixelformat')`):
a hardware format name such as `videotoolbox` means the frame stays on the GPU,
a software format such as `nv12` means it was copied back. With mpv's default
`d3d11va-zero-copy=no`, `hwdec-current=d3d11va` includes one GPU-memory copy
per frame (no CPU round trip). Windows only benefits on the D3D11 backend; the
Vulkan backend behaves as before. Verification tiers and measurements are in
[docs/perf/hwdec-zero-copy.md](docs/perf/hwdec-zero-copy.md).

## Troubleshooting

* **Which renderer is active?** `controller.backend` / `controller.reason`
  (the first token of `reason` is the graphics API); force a renderer with
  `MPV_KIT_VIDEO_RENDERER`, or a graphics API, with no fallback, with
  `MPV_KIT_VIDEO_API`. On Linux `opengl (gpu) on <GL_RENDERER>; vulkan/gpu-next
  unavailable: <why>` means mpv renders through OpenGL and the Vulkan reason
  is in the trail. The OpenGL backend is verified on Mesa llvmpipe only; real
  GPU drivers and Wayland are not verified.
* **Is hardware decoding active?** `player.hwdecCurrent.value` or
  `player.mpv.getProperty('hwdec-current')`. Also check
  `video-params/pixelformat`: a hardware format name means the frame stays on
  the GPU, `nv12` and the like mean it was copied back.
* **Dropped frames:** read mpv's statistics properties such as
  `frame-drop-count`, `decoder-frame-drop-count`, `vo-delayed-frame-count`,
  `estimated-vf-fps` and `display-fps` with `player.mpv.getProperty(...)` or
  `player.mpv.observeProperty(...)`.
* **mpv logs:** `player.setLogLevel('v')` and listen to `player.logs`, or
  write a log file:
  `Player(options: {'log-file': '/tmp/mpv.log', 'msg-level': 'all=v'})`.
* **Renderer diagnostics:** `controller.events` emits `MpvVideoEvent`s:
  `resize`, `idle`/`active` (texture hidden/shown), `renderError` and
  `gpuTimeout` (retried with backoff), `recovered`, and `deviceLost` (the
  controller renders nothing anymore — dispose it and create a new one,
  e.g. with `MpvVideoRenderer.software`).
* **Slow first frames:** compiled shaders are cached persistently (patch
  0003). Unless the app sets `gpu-shader-cache-dir` before creating the
  controller, it uses `%LOCALAPPDATA%/mpv_kit/shader-cache` (Windows),
  `~/Library/Caches/mpv_kit/shader-cache` (macOS) or
  `${XDG_CACHE_HOME:-~/.cache}/mpv_kit/shader-cache` (Linux). Deleting the
  directory is safe.
* **Display refresh rate:** the render API has no vsync source, so the
  controller sets `display-fps-override` from Flutter's display info unless
  the app already set it.
* **Library not found:** `MpvLibraryNotFound` lists every candidate and
  why it failed; set `MPV_KIT_LIBMPV_PATH` to the full library path.

## LGPL compliance

Applications may be closed-source: libmpv and FFmpeg are distributed as
LGPL-2.1-or-later builds and are **dynamically linked**.

* **FFmpeg** 8.1.3 is built from the sha256-pinned release tarball by
  [`native/build/ffmpeg.sh`](native/build/ffmpeg.sh) without
  `--enable-gpl`, `--enable-nonfree` or `--enable-version3`. Its license
  gate aborts the build unless `config.h` has `CONFIG_GPL`,
  `CONFIG_NONFREE` and `CONFIG_VERSION3` all set to 0.
* **libmpv** 0.41.0 is configured with `-Dgpl=false`.
* [`native/build/package.sh`](native/build/package.sh) collects libmpv and
  its dependency closure, checks that libavcodec resolves from the LGPL
  prefix (never a system copy), fails if any GPL-only library ended up in
  the bundle (x264, x265, postproc, rubberband, vidstab, …), runs the ABI
  audit on Windows, and writes a per-file sha256 `MANIFEST.txt`. Each bundle
  ships `LICENSE.LGPL` and the mpv_kit patches it was built with.
* **Relinking / replacing libmpv:** the libraries stay separate files next
  to the executable (Windows, Linux) or frameworks inside the app bundle
  (macOS). Users can replace them with their own build of the same ABI —
  rebuild from this repository, or point `MPV_KIT_LIBMPV_PATH` / the
  `libmpv_bundle` user define at another bundle.
* **Corresponding source:** this repository — mpv 0.41.0 in `native/mpv`,
  the patches in `native/patches`, the build scripts in `native/build`, the
  pinned FFmpeg version and checksum in `ffmpeg.sh`, and the remaining
  dependency setup in `.github/workflows/release.yml`.

See [NOTICE](NOTICE) and
[ADR 0002](docs/adr/0002-lgpl-self-built-binaries.md). Dart and plugin code
is MIT.

## mpv patches

Applied on top of mpv 0.41.0 (`native/patches/`); the client API version is
unchanged.

| Patch | Summary |
|---|---|
| 0001 | `vo_libmpv`: Vulkan render backend (`<mpv/render_vk.h>`, `MPV_RENDER_API_TYPE_VULKAN`) importing a host-owned `VkDevice` |
| 0002 | `hwdec_vulkan`: pass the imported device's extensions to FFmpeg so Vulkan video decoding works |
| 0003 | `libmpv_vk`: persistent libplacebo shader/pipeline cache in `--gpu-shader-cache-dir` |
| 0004 | gpu-next (libplacebo's renderer) as a Vulkan render backend, chosen with `MPV_RENDER_PARAM_VULKAN_RENDERER` |
| 0005 | Report the active Vulkan renderer through `mpv_render_context_get_info` |
| 0006 | Asynchronous stream bridge (`<mpv/stream_bridge.h>`): custom protocols answered asynchronously, used by `Mpv.registerStreamProtocol` |
| 0007 | Audio device enumeration fixes: link the macOS helpers/frameworks the CoreAudio and AVFoundation outputs use without cocoa; keep WASAPI's COM objects valid when libmpv is destroyed on the client thread |

## CI workflows

| Workflow | What it does |
|---|---|
| `native-verify` | Builds the patched libmpv on all six targets, runs the Vulkan render smoke test, the ABI audit and the Dart tests (artifacts are not distributed) |
| `flutter-plugin` | Compiles `mpv_kit_video` through the example app on Windows, Linux and macOS |
| `release` | LGPL release bundles (FFmpeg from source, license-gated, packaged with a sha256 manifest); `v*` tags publish them with `SHA256SUMS` |
