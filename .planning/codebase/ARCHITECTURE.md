---
last_mapped_commit: 9f90a45322ab3537941540e6b35a76d978669ef5
last_mapped_at: 2026-10-23
---
<!-- refreshed: 2026-10-23 -->

# Architecture

**Analysis Date:** 2026-10-23

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Application (`example/lib/main.dart`)                                │
│   Player()  +  MpvVideoController.create(player)  +  MpvVideo(...)   │
├───────────────────────────────┬──────────────────────────────────────┤
│ mpv_kit_video (Dart)          │ mpv_kit (pure Dart FFI)              │
│ `lib/src/video_controller.dart`│ `lib/src/core/mpv.dart`              │
│ `lib/src/mpv_video.dart`      │ `lib/src/player/player.dart`         │
│                               │ `lib/src/ffi/bindings.dart`          │
└──────────────┬────────────────┴───────────────┬──────────────────────┘
               │ MethodChannel "mpv_kit_video"   │ dart:ffi (dynamic)
               ▼                                 ▼
┌───────────────────────────────┐   ┌──────────────────────────────────┐
│ Native plugin (per platform)  │   │ libmpv-2.dll / libmpv.so.2 /     │
│ windows/mpv_kit_video_plugin.cpp│  │ mpv.2.framework (loaded once by │
│ linux/mpv_kit_video_plugin.cc │   │ `MpvLibrary`, `ffi/library.dart`)│
│ macos/Classes/MpvKitVideoPlugin.mm│ └──────────────┬───────────────────┘
└──────────────┬────────────────┘                  │
               ▼                                   │
┌───────────────────────────────────────────────┐  │
│ Shared renderer (`src/`)                      │  │
│ `video_renderer.cc` — render thread + ring    │  │
│ `vulkan_backend.cc` — device, queues, images  │  │
│ `windows/d3d11_interop.cpp`, `linux/gl_interop.cc`, │
│ `macos/Classes/metal_interop.mm`              │  │
└──────────────┬────────────────────────────────┘  │
               ▼                                   │
┌───────────────────────────────────────────────┐  │
│ Flutter compositor texture                    │◄─┘ mpv render API
│ D3D11 shared handle / FlTextureGL / IOSurface │   (symbols passed from
│                                               │    Dart, `src/mpv_api.h`)
└───────────────────────────────────────────────┘
```

Build-time supply chain (separate from runtime):

```text
mpv_kit_libs hook/build.dart
  ├─ pinned GitHub release bundle (lib/src/bundles.dart, sha256)
  └─ or user define `libmpv_bundle`
        → code assets (DynamicLoadingBundled) → OS loader resolves default names
native/build/{deps,ffmpeg,build,package}.sh  → produces those bundles
native/mpv (upstream 0.41.0-1113) + native/patches/0001..0007 → patched libmpv
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `Mpv` | 1:1 wrapper over the libmpv client API; owns the handle, event loop, observer streams, pending async replies | `packages/mpv_kit/lib/src/core/mpv.dart` |
| `MpvBindings` | Raw FFI symbol table (54 symbols), memory ownership helpers | `packages/mpv_kit/lib/src/ffi/bindings.dart` |
| `MpvLibrary` | Process-wide single libmpv load + client API major-version check | `packages/mpv_kit/lib/src/ffi/library.dart` |
| Event model | Sealed `MpvEventData` hierarchy decoding `mpv_event*` immediately (pointer lifetime) | `packages/mpv_kit/lib/src/core/events.dart` |
| `node.dart` | Recursive `mpv_node` ↔ Dart values conversion | `packages/mpv_kit/lib/src/core/node.dart` |
| `StreamBridge` | Custom `protocol://` streams served from Dart via `NativeCallable.listener` | `packages/mpv_kit/lib/src/core/stream_bridge.dart` |
| `Player` | High-level API: one `MpvState<T>` per mpv property, typed commands, dispose hooks | `packages/mpv_kit/lib/src/player/player.dart` |
| Models | Typed decode of `track-list`, `video-params`, `audio-params`, playlist, chapters, screenshots | `packages/mpv_kit/lib/src/player/models.dart` |
| Catalog / options | Generated metadata (`mpvProperties`, `mpvCommands`, `mpvOptions`) and typed `MpvOptions` | `packages/mpv_kit/lib/src/generated/` |
| `MpvVideoController` | Dart side of video output: creates the native renderer, owns texture id, routes events, sets size/ICC/display-fps | `packages/mpv_kit_video/lib/src/video_controller.dart` |
| `MpvVideo` | Widget that letterboxes the texture, debounces resizes, follows display refresh rate | `packages/mpv_kit_video/lib/src/mpv_video.dart` |
| `VideoRenderer` (C++) | Render thread, renderer fallback (gpu-next → gpu → software), frame ring, quarantine, backoff, swap reporting | `packages/mpv_kit_video/src/video_renderer.cc` |
| `VulkanContext` (C++) | Vulkan instance/device/queues, timeline semaphore, shared-image ring | `packages/mpv_kit_video/src/vulkan_backend.cc` |
| `Interop` / `VulkanInterop` | Platform abstraction for zero-copy sharing and software pixel order | `packages/mpv_kit_video/src/video_renderer.h`, `src/vulkan_backend.h` |
| Platform plugins | Method channel contract, Flutter texture registration, event marshalling | `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp`, `.../linux/mpv_kit_video_plugin.cc`, `.../macos/Classes/MpvKitVideoPlugin.mm` |
| Build hook | Resolves/verifies/extracts the libmpv bundle and emits code assets | `packages/mpv_kit_libs/hook/build.dart`, `lib/src/bundle.dart` |
| Native test harness | C tests for the Vulkan render backend and stream bridge | `native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c` |

## Pattern Overview

**Overall:** Layered facade over a C library, with a handle-passing Flutter plugin and a callback bridge.

Key characteristics:

- **One library, one handle, one owner per concern.** `MpvLibrary` caches a single `DynamicLibrary`; every `Mpv` wraps an `mpv_handle*`. The video plugin never loads libmpv — Dart passes the handle address and nine render-API symbol addresses across the method channel (`MpvVideoController._symbols` in `packages/mpv_kit_video/lib/src/video_controller.dart`, `MpvApi::Load` in `packages/mpv_kit_video/src/mpv_api.h`).
- **Generated surface, hand-written behavior.** Properties/commands/options tables are generated from mpv's own docs and option table (`tools/gen_catalog.dart`, `tools/gen_options.dart`); all behavior lives in hand-written `core/` and `player/` files.
- **Async at the Dart boundary, synchronous at the C boundary.** FFI calls are synchronous and documented thread-safe; native callbacks (`wakeup`, stream requests) enter Dart through `NativeCallable.listener`, never by upcalling a JIT isolate.
- **Single native render thread per controller.** The compositor, UI and raster threads only request frames; rendering and swap reporting happen on the renderer thread.
- **Fallback-first rendering.** Vulkan gpu-next → Vulkan gpu → software; every failure is reported as a typed event instead of failing the app.

## Layers

**Generated metadata layer:**
- Purpose: expose every mpv property, command and option with docs and types matching the bundled binary.
- Location: `packages/mpv_kit/lib/src/generated/`
- Contains: `catalog.dart` (4346 lines), `catalog_types.dart`, `option_types.dart`, `options.dart` (7617 lines).
- Depends on: nothing but `dart:core`.
- Used by: `Mpv.getOptionValue`/`setOptionValue`, `Player`, application code. Never edited by hand.

**FFI layer:**
- Purpose: declare libmpv symbols and locate/load the library.
- Location: `packages/mpv_kit/lib/src/ffi/`
- Contains: `bindings.dart` (raw symbol table, opaque types, enums), `library.dart` (resolution order, API version gate).
- Depends on: `package:ffi`, `dart:ffi`, `dart:io`.
- Used by: `Mpv`, `StreamBridge`, `MpvVideoController` (symbol lookup for the plugin).

**Core client layer:**
- Purpose: represent libmpv semantics safely in Dart.
- Location: `packages/mpv_kit/lib/src/core/`
- Contains: `mpv.dart`, `events.dart`, `node.dart`, `errors.dart`, `stream_bridge.dart`.
- Depends on: FFI layer, generated option types.
- Used by: `Player`, application code, `mpv_kit_video`.

**High-level player layer:**
- Purpose: ergonomic state and commands for applications.
- Location: `packages/mpv_kit/lib/src/player/`
- Contains: `player.dart`, `models.dart`.
- Depends on: `core/mpv.dart`, `core/events.dart`, `core/errors.dart`.
- Used by: applications and `mpv_kit_video` (controller registers a dispose hook on `Player`).

**Dart video-output layer:**
- Purpose: connect an `Mpv` instance to a Flutter texture and expose diagnostics.
- Location: `packages/mpv_kit_video/lib/src/`
- Contains: `video_controller.dart`, `mpv_video.dart`.
- Depends on: `package:mpv_kit`, Flutter services/widgets.
- Used by: applications that render video.

**Native renderer layer (platform-independent):**
- Purpose: own the mpv render context, render thread, frame ring and Vulkan device.
- Location: `packages/mpv_kit_video/src/`
- Contains: `video_renderer.h/.cc`, `vulkan_backend.h/.cc`, `mpv_api.h`, vendored mpv render headers (`src/include/mpv/`).
- Depends on: vendored Vulkan headers + volk (`third_party/`).
- Used by: every platform plugin.

**Platform interop/plugin layer:**
- Purpose: Flutter texture registration, compositor sharing, event marshalling.
- Location: `packages/mpv_kit_video/windows/`, `linux/`, `macos/`.
- Contains: plugin entry points, `d3d11_interop.*`, `gl_interop.*`, `metal_interop.*`.
- Depends on: native renderer layer, Flutter embedding APIs.
- Used by: Flutter engine.

**Build/packaging layer:**
- Purpose: deliver libmpv and its dependency closure, verify integrity, produce release artifacts.
- Location: `packages/mpv_kit_libs/`, `native/build/`, `tools/`, `.github/workflows/`
- Contains: build hook, tar reader, manifest verification, pinning tool, shell build scripts, ABI audit.
- Depends on: GitHub release assets; no runtime code.

**Vendored upstream layer:**
- Purpose: buildable mpv source plus mpv_kit patches and upstream-tracking notes.
- Location: `native/mpv/`, `native/patches/`, `native/tests/`
- Contains: full mpv tree (963 tracked files), `UPSTREAM.md`, 7 patches, C smoke tests.
- Depends on: nothing at runtime; only the release workflow builds it.

## Data Flow

### Property observation (primary state path)

1. `Player` constructor binds each state: `_bind(name, state, parse)` calls `mpv.observeProperty(name)` (`packages/mpv_kit/lib/src/player/player.dart:641`).
2. `Mpv.observeProperty` allocates a `reply_userdata` id and a sync `StreamController`; on first listen it calls `mpv_observe_property(..., MPV_FORMAT_NODE)` (`packages/mpv_kit/lib/src/core/mpv.dart:392`).
3. mpv fires the wakeup callback on a native thread; the `NativeCallable.listener` posts to the owning isolate (`mpv.dart:25`, `mpv.dart:521`).
4. `_onWakeup` drains `mpv_wait_event(handle, 0)` until `MPV_EVENT_NONE`, decodes each event immediately (`events.dart:19`), and dispatches.
5. `_dispatch` routes `PropertyChangeEvent` to the observer controller by `replyUserdata`, completes async requests, then broadcasts on `Mpv.events` (`mpv.dart:529`).
6. `Player`'s `_bind` parser updates the `MpvState<T>`, whose sync broadcast stream notifies widgets.

`time-pos` is deliberately throttled to 100 ms with a 250 ms jump bypass before updating `position` (`player.dart:120-129`).

### Video frame path

1. `Player` is created with `vo=libmpv` (`player.dart:85`); mpv forwards frames to the render context created by the plugin.
2. `MpvVideoController.create` applies a shader cache dir, reads `player.mpv.handle.address`, resolves the nine render symbols, and invokes `create` on channel `mpv_kit_video` (`video_controller.dart:154-173`).
3. The platform plugin builds an `Interop`, a `VideoRenderer`, calls `Start(choice)`, registers a `TextureVariant` (`GpuSurfaceTexture` for Vulkan, `PixelBufferTexture` for software), and returns `{textureId, backend, reason}` (`windows/mpv_kit_video_plugin.cpp:176-246`).
4. `VideoRenderer::Start` creates the mpv render context (Vulkan gpu-next, Vulkan gpu, then software), sets the update callback, and launches the render thread (`src/video_renderer.cc:42`).
5. mpv's update callback only flags and signals; the render thread calls `mpv_render_context_update` → `mpv_render_context_render` into a ring image (`video_renderer.cc:282`, `:410`).
6. `Interop::FrameReady` marks the Flutter texture dirty (`MarkTextureFrameAvailable` / `textureFrameAvailable` / `g_idle_add` depending on platform).
7. When the compositor pulls the texture, the plugin calls `VideoRenderer::AcquireFront()` under the renderer lock and returns the shared image (`windows/mpv_kit_video_plugin.cpp:273`, `:224`).
8. Swap reporting is deferred to actual presentation (compositor take, or 50 ms timeout), so mpv timing follows Flutter's compositor (`src/video_renderer.h:156-166`).

### Controller resize / display sync

1. `MpvVideo` computes the visible video rect from `player.videoParams`, `BoxFit`, rotation and pixel aspect (`mpv_video.dart:44-93`).
2. Size requests are debounced 80 ms; the first size is sent immediately (`mpv_video.dart:53-67`).
3. `MpvVideoController.setSize` no-ops on unchanged sizes and invokes `setSize` on the channel (`video_controller.dart:340`).
4. `MpvVideo` also calls `syncDisplayRefreshRate` on every build from `View.display.refreshRate`; initial creation asks the native plugin (`getDisplayRefreshRate`) because Flutter reports 0 on Windows (`video_controller.dart:215`, `windows/mpv_kit_video_plugin.cpp:118`).

### Custom stream protocol

1. Application calls `Mpv.registerStreamProtocol(protocol, opener)` (`mpv.dart:462`).
2. `StreamBridge.register` checks for `mpv_kit_stream_add`, creates a `NativeCallable.listener`, and registers the protocol (`stream_bridge.dart:132`).
3. mpv's demuxer thread calls open/read/seek/close; the bridge posts the request and blocks that mpv thread until `mpv_kit_stream_complete` (`stream_bridge.dart:192`).
4. Dart claims the request with `mpv_kit_stream_begin` before touching the buffer, awaits the `MpvStreamSource`, then completes it (`stream_bridge.dart:205-263`).
5. `Mpv.dispose` calls `StreamBridge.shutdown` before `mpv_terminate_destroy` so no mpv thread waits on the disposing isolate (`mpv.dart:168-176`).

### Dispose ordering

1. `MpvVideoController.create` registers `controller.dispose` via `Player.addDisposeHook` (`video_controller.dart:186`).
2. `Player.dispose` awaits all hooks first (`player.dart:620-627`).
3. The controller's hook invokes `dispose` on the channel; the plugin stops the render thread, frees the render context, unregisters the texture, and defers deleting `Instance` until the texture registrar confirms no raster callback is running (`windows/mpv_kit_video_plugin.cpp:159-170`, `:250`).
4. Only then does `Player.dispose` cancel subscriptions and call `mpv.dispose()` (`mpv_terminate_destroy`).

**State Management:** `MpvState<T>` per property in `Player`; `Mpv.events` + per-observer streams at the low level; `MpvVideoController.events` for native diagnostics. No global app state container.

## Key Abstractions

**`Mpv` (client handle):**
- Purpose: exact client-API mirror with safe lifetime and event delivery.
- Examples: `packages/mpv_kit/lib/src/core/mpv.dart`
- Pattern: facade + native callback registration; IDs are monotonic ints used as `reply_userdata`.

**`MpvState<T>`:**
- Purpose: current value + change stream for one observed property.
- Examples: `packages/mpv_kit/lib/src/player/player.dart:16`
- Pattern: value object with sync broadcast controller; deduplicates equal values; resets on `ShutdownEvent`.

**`MpvOption<T>`:**
- Purpose: typed option with declared choices/range validation.
- Examples: `packages/mpv_kit/lib/src/generated/option_types.dart`, `options.dart`
- Pattern: const value object generated from the running library's option table.

**`MpvVideoController`:**
- Purpose: lifetime and identity of one native renderer + Flutter texture.
- Examples: `packages/mpv_kit_video/lib/src/video_controller.dart`
- Pattern: static registry `_live` keyed by `textureId` for event routing; create/dispose returns through the method channel.

**`VideoRenderer` / `Interop` / `VulkanInterop`:**
- Purpose: platform-independent rendering with a narrow platform seam.
- Examples: `packages/mpv_kit_video/src/video_renderer.h`, `src/vulkan_backend.h`
- Pattern: template-method (platform objects implement `CreateImage`, `DestroyImage`, `FrameReady`, `CompositorLatency`) plus a render-thread state machine.

**`MpvStreamSource`:**
- Purpose: host-provided byte stream for custom protocols.
- Examples: `packages/mpv_kit/lib/src/core/stream_bridge.dart:26`, `MpvMemoryStreamSource`
- Pattern: async interface with one in-flight call per stream, enforced by mpv's synchronous reads.

## Entry Points

**Application entry:**
- Location: `example/lib/main.dart`
- Triggers: `flutter run -d windows|linux|macos`
- Responsibilities: create `Player`, create `MpvVideoController`, render `MpvVideo`, display live stats and renderer events.

**Dart package entry:**
- Location: `packages/mpv_kit/lib/mpv_kit.dart`, `packages/mpv_kit_video/lib/mpv_kit_video.dart`, `packages/mpv_kit_libs/lib/mpv_kit_libs.dart`
- Triggers: import by applications.
- Responsibilities: barrel exports; `mpv_kit_video` re-exports all of `mpv_kit`, so apps depend on one package.

**Flutter plugin registration:**
- Location: `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp:304` (`MpvKitVideoPluginCApiRegisterWithRegistrar`), `linux/mpv_kit_video_plugin.cc`, `macos/Classes/MpvKitVideoPlugin.mm:144`
- Triggers: Flutter plugin registrant generated at build time (`example/windows/flutter/generated_plugin_registrant.cc`).
- Responsibilities: install the `mpv_kit_video` method channel, texture registrar, and platform event transport.

**Build hook entry:**
- Location: `packages/mpv_kit_libs/hook/build.dart`
- Triggers: `flutter pub get` / `flutter build` native-assets hook.
- Responsibilities: resolve bundle source, verify hashes, emit `CodeAsset`s.

**Native test executables:**
- Location: `native/tests/meson.build`, `native/tests/render_vk_smoke.c`, `native/tests/stream_bridge_test.c`
- Triggers: `meson test` in `native/tests`.
- Responsibilities: exercise the Vulkan render backend and asynchronous stream bridge against a locally built patched libmpv.

**Tooling entry points:**
- `tools/gen_catalog.dart` — regenerate property/command/option catalog from `native/mpv/DOCS/man`.
- `tools/gen_options.dart` — regenerate typed options by querying a running libmpv.
- `tools/pin_bundles.dart` — update `bundles.dart` from a release's `SHA256SUMS`.
- `tools/rea_abi_audit/pe_audit.py` — verify the Windows DLL export set and GPL-free imports.
- `native/build/build.sh` — full release build (deps → FFmpeg → patched mpv → package).

## Architectural Constraints

- **Single libmpv mapping:** `MpvLibrary._bindings` is a static cache; a later `open(path:)` with a different path is ignored. Changing the library requires a new process (`packages/mpv_kit/lib/src/ffi/library.dart:29-56`).
- **Client API major version 2 only:** `MpvLibrary._checkApiVersion` rejects other majors before any handle is created (`library.dart:75`).
- **Plugin never links or loads libmpv:** all render symbols arrive as addresses over the method channel; `MpvApi::Load` requires exactly nine non-null addresses (`packages/mpv_kit_video/src/mpv_api.h:22`).
- **Rendering is confined to one native thread per controller:** `mpv_render_context_render` must be called from the renderer thread; UI/raster callbacks only publish frames (`packages/mpv_kit_video/src/video_renderer.cc:282`).
- **Render context must die before the mpv core:** enforced by the `Player.addDisposeHook` contract; bypassing it causes libmpv to wait/fail (`docs/ARCHITECTURE.md:76-90`).
- **Frame ring quarantine:** an image the compositor returned stays quarantined for `Interop::CompositorLatency()` acquisitions — Windows 4 (ring 7), others 2 (ring 5); ring = front + in use + quarantine + one free (`packages/mpv_kit_video/src/video_renderer.h:197-230`).
- **No cross-API fences:** correctness relies on the quarantine + Vulkan timeline waits; there is no keyed mutex/fence with ANGLE or Metal (`docs/ARCHITECTURE.md:96-119`).
- **Stream requests block mpv's demuxer thread:** a source that never completes a request stalls playback; every registered protocol is shut down before core destruction (`packages/mpv_kit/lib/src/core/stream_bridge.dart`, `mpv.dart:168`).
- **Platform event marshalling:** native render events must reach the platform thread before the method channel — `PostMessage` (Windows), `g_idle_add` (Linux), `dispatch_async(main)` (macOS).
- **Native asset bundling only:** `mpv_kit_libs` has no runtime Dart code; `mpv_kit` resolves the bundle by default library names via the OS loader (`docs/ARCHITECTURE.md:23-27`).
- **Workspace resolution:** root `pubspec.yaml` lists all packages plus `example` under `workspace:`; each package uses `resolution: workspace` and versions are kept in lockstep (`0.1.0-dev.3`).
- **Dart/Flutter floor differs per package:** `mpv_kit` requires Dart `^3.8.0`; `mpv_kit_video` and `mpv_kit_libs` require Dart `^3.10.0` / Flutter `>=3.38.0` because of native assets (`packages/*/pubspec.yaml`).

## Anti-Patterns

### Loading libmpv from the plugin or a second location

**What happens:** calling `DynamicLibrary.open('libmpv-2.dll')` inside native code, or calling `MpvLibrary.open(path:)` with a new path after the first load.
**Why it's wrong:** creates a second copy of the library, so render symbols and the handle belong to different cores; the cached `MpvLibrary` silently ignores the new path.
**Do this instead:** pass `player.mpv.handle.address` and `library.lookup()` addresses across the channel, as `MpvVideoController.create` does (`packages/mpv_kit_video/lib/src/video_controller.dart:168-173`).

### Disposing the player before the controller

**What happens:** calling `mpv.dispose()`/`Mpv.dispose()` directly while an `MpvVideoController` exists.
**Why it's wrong:** libmpv requires every render context to be freed before `mpv_terminate_destroy`; ordering violations hang or crash.
**Do this instead:** always call `await player.dispose()`; the controller's dispose hook runs first (`packages/mpv_kit/lib/src/player/player.dart:613-631`).

### Editing generated files

**What happens:** hand-editing `catalog.dart`, `options.dart`, `catalog_types.dart` or `option_types.dart`.
**Why it's wrong:** they are regenerated wholesale from mpv docs/option table and will be overwritten; types/ranges must match the bundled binary.
**Do this instead:** change `tools/gen_catalog.dart` / `tools/gen_options.dart` and regenerate.

### Awaiting long work inside a stream source without regard to the demuxer

**What happens:** a `MpvStreamSource` performs a blocking synchronous operation or never completes a read/seek.
**Why it's wrong:** the mpv demuxer thread is blocked for the whole request; playback stalls and `Mpv.dispose` waits on `shutdown`.
**Do this instead:** return promptly (async is fine), keep one request in flight per stream, and honor `close`/shutdown.

### Treating Flutter's display refresh rate as reliable on Windows

**What happens:** relying only on `View.display.refreshRate` to drive `display-fps-override`.
**Why it's wrong:** Flutter reports 0 on Windows (flutter/flutter #158721), silently disabling `video-sync=display-*`.
**Do this instead:** use `MpvVideoController.syncDisplayRefreshRate` and the plugin's `getDisplayRefreshRate` fallback (`video_controller.dart:215-230`).

### Rendering a texture at the widget's logical size

**What happens:** requesting `setSize` with logical pixels.
**Why it's wrong:** mpv would render at half resolution on HiDPI displays, defeating its scalers.
**Do this instead:** multiply by `devicePixelRatio` as `MpvVideo._requestSize` does (`packages/mpv_kit_video/lib/src/mpv_video.dart:53`).

## Error Handling

**Strategy:** errors are typed at each boundary; recoverable rendering problems become events; unrecoverable conditions throw.

**Patterns:**
- libmpv negative return codes → `MpvException` with `MpvError` enum, operation label and `mpv_error_string` text (`packages/mpv_kit/lib/src/core/errors.dart`).
- “Unavailable” reads use `tryGetProperty` returning null for `propertyUnavailable`/`propertyNotFound`, rethrowing everything else (`mpv.dart:322`).
- Unknown option names during `Mpv.create` are tolerated only for `optionNotFound` (feature compiled out), so older builds still work (`mpv.dart:58-76`).
- Async request failures complete their futures with `MpvException`; `Mpv.dispose` completes pending futures with `StateError`.
- Library loading aggregates every attempted path/reason in `MpvLibraryNotFound`.
- Stream bridge maps source failures to mpv error codes (`loadingFailed`, `unsupported`, `generic`) instead of throwing across FFI (`stream_bridge.dart:221-279`).
- Native renderer: failed frames are advanced with `SKIP_RENDERING` and retried with exponential backoff 100 ms → 5 s; device loss stops rendering permanently and emits `device_lost` (`packages/mpv_kit_video/src/video_renderer.h:172-191`).
- Dart controller surfaces `PlatformException` on failed creation and emits `softwareFallback` as an explicit event (`video_controller.dart:174-204`).

## Cross-Cutting Concerns

**Logging:** mpv log messages are opt-in via `Player.setLogLevel`/`Mpv.requestLogMessages`, exposed as `Player.logs` and `Mpv.events`. Renderer diagnostics are emitted as `MpvVideoEvent`s and also written natively (`OutputDebugStringA` + stderr on Windows, plugin logging elsewhere). The resolved backend is printed once with `debugPrint` at create time (`video_controller.dart:188`).

**Validation:** `MpvOption.check` validates choices/range before runtime property writes (`packages/mpv_kit/lib/src/generated/option_types.dart`); `Mpv.command` accepts lists or named maps and converts through `writeNode`; `openPlaylist` uses `RangeError.checkValidIndex`. Dart packages use `strict-casts`, `strict-inference`, `strict-raw-types` and lint sets (`packages/*/analysis_options.yaml`).

**Authentication:** Not applicable — this is a client-side media library with no network service, credentials, or auth layer.

**Language of comments:** Public API docs are English; several newer explanatory comments and doc blocks (notably `Player` defaults and native hardware-decoding notes) are in Chinese. Preserve surrounding language when editing a file.

---

*Architecture analysis: 2026-10-23*
