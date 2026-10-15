# mpv_kit architecture

This document describes how the packages fit together at runtime. Design
rationale lives in [adr/](adr); the native render pipeline is analysed in
[reverse-engineering/01-libmpv-render-pipeline.md](reverse-engineering/01-libmpv-render-pipeline.md).

## Dependency chain

```
app
 └─ mpv_kit_video        Flutter plugin (Dart + C++/ObjC per platform)
     ├─ mpv_kit          pure Dart FFI over libmpv (re-exported)
     └─ mpv_kit_libs     build hook: bundles libmpv + its dependency closure
                              │
                              ▼
                    libmpv-2.dll / libmpv.so.2 / mpv.2.framework
                    (mpv 0.41.0 + native/patches, FFmpeg 8.1.3 LGPL)
```

* **mpv_kit** opens libmpv once per process (`MpvLibrary.open`: explicit
  path → `MPV_KIT_LIBMPV_PATH` → platform default names) and checks the
  client API major version (2). It never loads a second copy.
* **mpv_kit_libs** has no runtime code. Its `hook/build.dart` emits the
  libraries as bundled code assets (pinned release download verified by
  sha256 plus the bundle's per-file `MANIFEST.txt`, or a local
  `libmpv_bundle`). The OS loader then resolves the default names to the
  bundled copy.
* **mpv_kit_video** does not link libmpv either: `MpvVideoController.create`
  looks up the render API symbols in the library mpv_kit already loaded and
  passes their addresses, together with the `mpv_handle*`, over the method
  channel to the native plugin (`MpvApi::Load`, `src/mpv_api.h`).

## Dart side: Mpv and Player

* `Mpv` is a 1:1 wrapper of the client API. All calls are synchronous FFI
  calls that libmpv documents as thread-safe.
* Events: mpv's wakeup callback fires on an arbitrary native thread and
  posts to a `NativeCallable.listener`; the owning isolate then drains
  `mpv_wait_event(0)` until empty and dispatches typed `MpvEventData`
  (property changes go to the `observeProperty` streams, async replies
  complete their futures).
* `Player` builds on `Mpv`: each piece of state is an `MpvState<T>` (value
  plus change stream) backed by one `mpv_observe_property`.

## Native side: threading model

Each `MpvVideoController` owns one native `VideoRenderer`
(`packages/mpv_kit_video/src/video_renderer.h`):

* **Render thread.** `Start()` creates the mpv render context (Vulkan
  gpu-next, then gpu, then software, depending on the requested
  `MpvVideoRenderer`) and starts a dedicated thread. mpv's update callback
  only sets a flag and signals a condition variable; the render thread calls
  `mpv_render_context_update` / `_render` / `_report_swap`. The UI and
  raster threads never render.
* **Frame hand-off.** After a frame completes, the platform `Interop`
  marks its Flutter texture dirty (`FrameReady`, called from the render
  thread). When the compositor pulls the texture, `AcquireFront()` returns
  the most recent completed frame under the renderer lock.
* **Events.** Diagnostic events (`resize`, `idle`/`active`,
  `render_error`, `gpu_timeout`, `recovered`, `device_lost`) are raised on
  the render thread and marshalled to the platform thread before reaching
  the method channel: `PostMessage` to the top-level window on Windows,
  `g_idle_add` on Linux, `dispatch_async` to the main queue on macOS. In
  Dart they are routed by texture id to `MpvVideoController.events`.
* **Idle and failures.** If the compositor takes no frame for 500 ms
  (hidden/minimised window), frames are advanced with `SKIP_RENDERING`
  instead of drawn, and one redraw happens on the next acquisition. A
  failed frame is retried with exponential backoff (100 ms → 5 s); device
  loss stops rendering for good.
* **Swap reporting.** `mpv_render_context_report_swap` is reported when the
  compositor first takes a frame (or after 50 ms without one), so mpv's
  timing follows actual presentation. The display refresh rate is passed
  via `display-fps-override`, since the render API has no vsync source.

## Dispose ordering

libmpv requires every render context to be freed before the core is
destroyed. `MpvVideoController.create` therefore registers
`controller.dispose` with `Player.addDisposeHook`:

1. `player.dispose()` first runs all dispose hooks (in registration order,
   awaiting each). The controller's hook removes it from the routing table
   and asks the plugin to stop the render thread and free the render
   context and texture.
2. Only then are the `Player`'s subscriptions cancelled and `Mpv.dispose()`
   called (`mpv_terminate_destroy`).

Calling `controller.dispose()` earlier is fine; it is idempotent and
unregisters its hook (`Player.removeDisposeHook`).

## Frame ring and quarantine

The Vulkan backend renders into a small ring of shared images (one
allocation per ring slot, reallocated lazily when `setSize` changes the
target size). The compositor samples an image on the GPU some time after
taking it, and no platform reports when it is done. So:

* `front` is the last completed frame, `in_use` the frame the compositor
  currently holds;
* an image the compositor gives back is **quarantined** for a fixed number
  of further acquisitions (currently 2) before it may be rendered into
  again — a bound on the compositor's frame latency;
* ring size = front + in use + quarantine + one free image (currently 5).

The renderer therefore never writes into an image that may still be read,
without any cross-API fence. Rendering into a slot additionally waits on a
Vulkan timeline value for that slot, so a slot is never reused while mpv's
own GPU work on it is pending. The software backend keeps the previous
buffer generation alive for one extra resize for the same reason.

Platform sharing:

| Platform | Shared image | Flutter texture |
|---|---|---|
| Windows | D3D11 texture (KMT handle) imported into Vulkan | `GpuSurfaceTexture` (DXGI shared handle) |
| Linux | Vulkan `OPAQUE_FD` memory imported with `GL_EXT_memory_object_fd` | `FlTextureGL` |
| macOS | IOSurface `CVPixelBuffer` bound by MoltenVK (`VK_EXT_metal_objects`) | `FlutterTexture` |

## Stream bridge (patch 0006)

mpv reads custom streams synchronously on its demuxer thread, which a Dart
isolate cannot answer directly. Patch 0006 adds `<mpv/stream_bridge.h>`:

1. `Mpv.registerStreamProtocol(protocol, opener)` registers the protocol
   with `mpv_kit_stream_add` and a `NativeCallable.listener` as the request
   callback.
2. Every open/read/seek/close becomes a request. The bridge posts it to the
   callback and **blocks the mpv thread** until the host answers with
   `mpv_kit_stream_complete`.
3. On the Dart side, `_onRequest` first claims the request
   (`mpv_kit_stream_begin`); only a claimed request keeps its buffer and
   the waiting mpv thread valid. It then calls the `MpvStreamSource`
   (which may answer asynchronously — file, network, decryption …) and
   completes the request with the result. `close` needs no reply.
4. Each source sees one call at a time per stream, so it needs no locking.
5. On `Mpv.dispose`, `mpv_kit_stream_shutdown` fails every pending request
   *before* the core is destroyed (otherwise destruction would wait on the
   isolate that is busy disposing), late replies are dropped without
   touching freed buffers, and the callback is closed afterwards.

Against a stock libmpv the bridge symbols are absent and
`registerStreamProtocol` throws `UnsupportedError`.
