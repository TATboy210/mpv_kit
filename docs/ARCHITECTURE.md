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
                    (mpv 0.41.0-1115 + native/patches, FFmpeg 8.1.3 LGPL)
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
  `MpvVideoRenderer`; see [RenderBackend seam](#renderbackend-seam)) and
  starts a dedicated thread. mpv's update callback only sets a flag and
  signals a condition variable. After `Start()`, every `mpv_render_*` call
  runs on the render thread: `mpv_render_context_update` / `_render` /
  `_set_parameter` / `_report_swap`, and finally the removal of the update
  callback and `mpv_render_context_free`. Only `_create` and `_get_info`
  run earlier, in `Start()` on the caller's thread, before the render
  thread exists. The UI and raster threads never call into the render
  context. render.h allows one `mpv_render_*` call at a time and, for
  OpenGL, only on the thread whose context is current, so this is what
  lets an OpenGL backend (Phase 15) work at all. Debug builds assert the
  render thread at every call site; `video_renderer_affinity_test`
  (native/tests) checks the same rule from a fake libmpv's call log.
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
* **Swap reporting.** A frame's swap is due when the compositor first
  takes it (or after 50 ms without one), so mpv's timing follows actual
  presentation. `AcquireFront()` runs on the raster thread and makes no
  libmpv call: it only counts the due swap (`swaps_to_report_`, under the
  renderer lock) and wakes the render thread. The render thread reports
  every counted swap with `mpv_render_context_report_swap` before its next
  `mpv_render_context_update`, outside the lock. When it woke only for
  swaps it does not call update, so mpv sees the same update pattern as
  before. The extra latency is one condition-variable wake-up, far below
  the 200 ms that vo_libmpv's `flip_page` waits for a swap. The display
  refresh rate is passed via `display-fps-override`, since the render API
  has no vsync source.
* **Render context release.** When the renderer is destroyed, the
  platform thread only sets `quit` and joins. The render thread, still
  bound to its backend (`RenderBackend::BindThread`), removes mpv's update
  callback, frees the render context through `RenderBackend::Release`,
  unbinds and exits. Only then is the backend destroyed (device last).
  Swaps not yet reported are dropped with the context.

## Dispose ordering

libmpv requires every render context to be freed before the core is
destroyed. `MpvVideoController.create` therefore registers
`controller.dispose` with `Player.addDisposeHook`:

1. `player.dispose()` first runs all dispose hooks (in registration order,
   awaiting each). The controller's hook removes it from the routing table
   and asks the plugin to stop the render thread and free the render
   context and texture. The render context is freed on the render thread
   itself, before the plugin's join returns (see Render context release
   above).
2. Only then are the `Player`'s subscriptions cancelled and `Mpv.dispose()`
   called (`mpv_terminate_destroy`).

Calling `controller.dispose()` earlier is fine; it is idempotent and
unregisters its hook (`Player.removeDisposeHook`).

## RenderBackend seam

`VideoRenderer` (`src/video_renderer.cc`) is the engine that is the same for
every graphics API. It owns the render thread, the ring bookkeeping (front,
in use, quarantine, retired front), the publish gate, failure backoff, swap
reporting, idle/active, ICC forwarding and events. Everything that depends
on the API sits behind `RenderBackend` (`src/render_backend.h`):

| Method | Job | Thread |
|---|---|---|
| `wire_name`, `frame_kind`, `pipelined` | API name for reasons and the method channel; what a frame carries (shared image or CPU pixels); whether a frame needs a GPU wait before it is published | any |
| `BindThread` / `UnbindThread` | thread affinity (an OpenGL context made current); no-ops for Vulkan and software | render thread, at start and before exit |
| `Create`, `device_failed`, `device_name`, `RendererName` | device on the first call, then the mpv render context for one renderer; the reason head's device and renderer | caller of `Start` |
| `AllocTargets`, `FreeRetired`, `FrameFor` | the ring of render targets, the retired generation, one slot's platform object or pixels | render thread (`FrameFor` under the renderer lock, also from `AcquireFront`) |
| `Render`, `Wait` | `mpv_render_context_render` into one slot; its bounded GPU completion | render thread |
| `Release` | `mpv_render_context_free`, before the device goes | render thread, before it exits |

Built-in backends: `SoftwareBackend` (`MPV_RENDER_API_TYPE_SW`,
video_renderer.cc) and `VulkanRenderBackend` (vulkan_backend.cc). The
platform keeps what is genuinely platform work: `Interop::FrameReady`
(mark the Flutter texture dirty), `RetainFrame`, `CompositorLatency` and,
for Vulkan, the `VulkanInterop` that creates images shared with the
compositor.

**Candidate chain.** `Start` tries an ordered list of `BackendCandidate`
entries (`api`, `renderer`). `DefaultCandidates(choice)` gives
`vulkan/gpu-next`, `vulkan/gpu`, `software/sw` for `auto` (a `gpu-next` or
`gpu` request keeps only its own Vulkan entry; `software` only the last).
A platform changes the chain by overriding `Interop::BackendCandidates` and
supplies its own API's backend through `Interop::CreateBackend(api)`; the
Windows interop overrides both since Phase 14 (see "D3D11 backend"). One backend instance (one device
initialisation) serves all candidates of its api, and an api's backend is
released before the next api is tried.

**`MPV_KIT_VIDEO_API`.** A native environment variable read once per
`Start`. Set to an api's wire name (`vulkan`, `software`, and `d3d11` on
Windows since Phase 14; `opengl` follows), it restricts the chain to that api and the requested renderer,
with no fallback; every other candidate becomes an
`excluded by MPV_KIT_VIDEO_API=<value>` trail. It exists so CI can verify
each backend on its own.

**Reason.** The winner's head and the trails of every candidate ranked
before it follow the grammar of
[ADR 0004](adr/0004-render-backend-reporting.md) (Decision 3), for example
`software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed`.
The plugin's create response carries the winner's `wire_name` as `backend`;
when nothing works, `render_init` carries the trails as details.

## Frame ring and quarantine

The Vulkan backend renders into a small ring of shared images (one
allocation per ring slot, reallocated lazily when `setSize` changes the
target size). The compositor samples an image on the GPU some time after
taking it, and no platform reports when it is done. So:

* `front` is the last completed frame, `in_use` the frame the compositor
  currently holds;
* an image the compositor gives back is **quarantined** for
  `Interop::CompositorLatency()` further acquisitions before it may be
  rendered into again — a bound on the compositor's frame latency. Windows
  uses 4 (ring of 7): decompiling `flutter_windows.dll` showed that
  `ExternalTextureD3d` binds the shared texture through ANGLE and calls the
  release callback immediately, without a fence or keyed mutex, so only the
  DXGI frame queue (3) plus the frame being composed bound ANGLE's reads.
  Other platforms use 2 (ring of 5);
* ring size = front + in use + quarantine + one free image;
* on reallocation (resize) the previous ring is retired, not freed: its last
  frame stays on screen until the first frame at the new size exists, then
  it is released once it has left the quarantine window. Without this the
  texture shows nothing (black) while the layout settles.

The renderer therefore never writes into an image that may still be read,
without any cross-API fence. Rendering into a slot additionally waits on a
Vulkan timeline value for that slot, so a slot is never reused while mpv's
own GPU work on it is pending. A GPU frame becomes the front only after its
own GPU work finished (publish gate, `RenderBackend::pipelined`).

**Deferred-release contract, shared by every backend.** A reallocation
retires only the old front's target; every other old target is released
once its last GPU work has completed. The retired front stays valid, and is
what `AcquireFront` hands out, until the first frame at the new size has
been published and the compositor has taken quarantine + 1 further frames.
Then `FreeRetired` releases it, exactly once. 12-07 fixed the earlier
behaviour, which destroyed it at the reallocation itself; 12-09 fixed a
resize that follows a resize without a frame, which handed out the
generation before last. A platform object the compositor still holds is kept
alive by the platform's own reference until the platform has unregistered
the texture: on Windows the D3D11 texture's COM reference (released by the
descriptor's release callback) and the instance kept until
`UnregisterTexture`'s callback; on Linux the GL graveyard, drained by the
next populate, plus a 1 s delay after unregistering before the texture
state is dropped; on macOS the `CVPixelBuffer` reference count. The
software backend keeps its whole previous buffer generation until the same
point (`FreeRetired`) or the next resize. The goldens under
`native/tests/golden/` (`vk.txt`, `sw.txt`, `vk_retire_twice.txt`,
`sw_retire_twice.txt`) pin this contract, and `real_plugin_test` exercises
it with the compositor attached (resizes of a controller whose texture is
mounted, plus create/dispose cycles).

Platform sharing:

| Platform | Shared image | Flutter texture |
|---|---|---|
| Windows | D3D11 texture (KMT handle) imported into Vulkan, or rendered into directly by mpv's D3D11 render API (`d3d11`) | `GpuSurfaceTexture` (DXGI shared handle) |
| Linux | Vulkan `OPAQUE_FD` memory imported with `GL_EXT_memory_object_fd` | `FlTextureGL` |
| macOS | IOSurface `CVPixelBuffer` bound by MoltenVK (`VK_EXT_metal_objects`) | `FlutterTexture` |

## D3D11 backend (Windows, Phase 14)

`packages/mpv_kit_video/windows/d3d11_backend.cpp` is a `RenderBackend`
(`wire_name()` is `d3d11`) that lets mpv render with its own D3D11 render
API (patch 0010; gpu-next uses the D3D11 branch of patch 0004) with no
Vulkan in the path and no ANGLE, EGL or Flutter device on mpv_kit's side.
Dart sees `MpvVideoBackend.vulkan` for it (ADR 0004: GPU zero-copy).

* **Device.** One `ID3D11Device` per controller, created on Flutter's
  `GetGraphicsAdapter()` adapter so the shared handles stay on one adapter.
  Flags `BGRA_SUPPORT | VIDEO_SUPPORT` (d3d11va decoding); when the adapter
  refuses `VIDEO_SUPPORT` (Basic Render Driver, WARP) it is created without
  it and one `mpv_kit: d3d11 device created without VIDEO_SUPPORT (0x...)`
  line is logged. Never the single-threaded or the debug flag;
  `SetMultithreadProtected(TRUE)` serialises mpv's d3d11va decode thread.
* **Targets.** A ring of `DXGI_FORMAT_B8G8R8A8_UNORM`, `D3D11_USAGE_DEFAULT`
  textures with `RENDER_TARGET | SHADER_RESOURCE` and
  `D3D11_RESOURCE_MISC_SHARED` (a legacy KMT handle, no NT handle, no keyed
  mutex, no UAV). The platform object is the `D3D11Interop::Texture` also
  used by the Vulkan path, so the plugin hands frames to Flutter through the
  same `GpuSurfaceTexture`. Sizes above `D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION`
  (16384) fail `AllocTargets`.
* **Publish gate.** After each render the render thread signals an
  `ID3D11Fence` and flushes; `Wait(slot)` returns only when that value has
  completed (1000 ms bound: a timeout is `gpu_timeout`, a removed device is
  `device_lost`). Without fence support each slot owns a
  `D3D11_QUERY_EVENT` instead. A debug plugin build reads
  `MPV_KIT_D3D11_SYNC=query` to force the query path; release builds never
  read it.
* **Threads.** The immediate context is used on the render thread only
  (mpv renders with it and does not restore its state); the raster thread's
  descriptor callback reads the cached shared handle.
* **Quarantine stays 4.** Flutter's ANGLE consumer opens the handle with no
  fence or keyed mutex, so the only bound on how long it samples an image is
  its swap chain queue; `D3D11Interop::CompositorLatency()` is unchanged.
* **Candidate chain.** `kWindowsApiOrder` in `d3d11_interop.cpp` is
  `{"vulkan", "d3d11"}` within each renderer tier, so `auto` is
  `vulkan/gpu-next`, `d3d11/gpu-next`, `vulkan/gpu`, `d3d11/gpu`, software.
  Putting D3D11 first is a separate change that only reorders that array.
* **Pickup latency.** The plugin logs
  `mpv_kit: compositor pickup avg/over 120 frames: <avg>ms max=<max>ms
  backend=<wire name>` every 120 frames: the time from the renderer's
  `FrameReady` to the compositor asking for the frame. Measurement only.

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
