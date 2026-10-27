---
last_mapped_commit: cd47d6761925b8ccb49e153864bf9789dc3f5039
last_mapped_at: 2026-10-27
---
<!-- refreshed: 2026-10-27 -->
# Architecture

**Analysis Date:** 2026-10-27

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         Application (Flutter)                       │
│   `example/lib/main.dart`, `example/lib/hud.dart`                   │
└───────────────┬───────────────────────────────┬─────────────────────┘
                │                               │
                ▼                               ▼
┌──────────────────────────────┐  ┌─────────────────────────────────────┐
│ mpv_kit (pure Dart FFI)      │  │ mpv_kit_video (Flutter plugin, Dart)│
│ player/ -> core/ -> ffi/     │◄─┤ `lib/src/video_controller.dart`     │
│ `packages/mpv_kit/lib/src/`  │  │ `lib/src/mpv_video.dart`            │
└──────────────┬───────────────┘  └──────────────┬──────────────────────┘
               │ dart:ffi                        │ MethodChannel('mpv_kit_video')
               │                                 │ (handle + 9 render symbol addrs)
               ▼                                 ▼
┌──────────────────────────────┐  ┌─────────────────────────────────────┐
│ libmpv (patched, LGPL)       │◄─┤ Platform plugins                    │
│ delivered by mpv_kit_libs    │  │ windows/ linux/ macos/ (+ interop)  │
│ `packages/mpv_kit_libs/hook/`│  ├─────────────────────────────────────┤
│ built from `native/`         │  │ Shared C++ engine `src/`            │
└──────────────────────────────┘  │ VideoRenderer -> RenderBackend      │
                                  │ (SoftwareBackend, VulkanRenderBackend)│
                                  └─────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `MpvLibrary` | Process-wide single libmpv load, client API major 2 gate | `packages/mpv_kit/lib/src/ffi/library.dart` |
| `MpvBindings` | Hand-written FFI symbol table | `packages/mpv_kit/lib/src/ffi/bindings.dart` |
| `Mpv` | 1:1 client API wrapper: handle, event loop, observers, async replies | `packages/mpv_kit/lib/src/core/mpv.dart` |
| Events / node / errors | Sealed `MpvEventData`, `mpv_node` conversion, `MpvException` | `packages/mpv_kit/lib/src/core/events.dart`, `node.dart`, `errors.dart` |
| `StreamBridge` | Custom `protocol://` sources served from Dart (patch 0006) | `packages/mpv_kit/lib/src/core/stream_bridge.dart` |
| `Player` | High-level `MpvState<T>` per property, typed commands, dispose hooks | `packages/mpv_kit/lib/src/player/player.dart`, `models.dart` |
| Generated catalog/options | Property/command/option metadata, typed `MpvOptions` | `packages/mpv_kit/lib/src/generated/` |
| `MpvVideoController` | Creates native renderer, texture id, event routing, strict `backend` wire-name validation | `packages/mpv_kit_video/lib/src/video_controller.dart` |
| `MpvVideo` | Widget: letterbox, debounced resize, display refresh follow | `packages/mpv_kit_video/lib/src/mpv_video.dart` |
| `VideoRenderer` | API-independent engine: render thread, candidate chain, ring/quarantine, publish gate, backoff, swap reporting, idle, events | `packages/mpv_kit_video/src/video_renderer.h`, `video_renderer.cc` |
| `RenderBackend` | Graphics-API seam: device, render context, render targets | `packages/mpv_kit_video/src/render_backend.h` |
| `SoftwareBackend` | `MPV_RENDER_API_TYPE_SW` backend | `packages/mpv_kit_video/src/video_renderer.cc` |
| `VulkanRenderBackend` / `VulkanContext` | Vulkan device, timeline semaphore, shared-image ring | `packages/mpv_kit_video/src/vulkan_backend.h`, `vulkan_backend.cc` |
| `MpvApi` | Nine render-API function pointers received from Dart | `packages/mpv_kit_video/src/mpv_api.h` |
| `Interop` / `VulkanInterop` | Platform seam: `FrameReady`, `RetainFrame`, `CompositorLatency`, `BackendCandidates`, `CreateBackend`, shared image creation | `packages/mpv_kit_video/src/video_renderer.h`, `vulkan_backend.h` |
| Platform plugins | Method channel, texture registration, event marshalling | `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp` + `d3d11_interop.cpp`, `linux/mpv_kit_video_plugin.cc` + `gl_interop.cc`, `macos/Classes/MpvKitVideoPlugin.mm` + `metal_interop.mm` |
| Bundle hook | Resolve, sha256-verify, extract libmpv bundle, emit code assets | `packages/mpv_kit_libs/hook/build.dart`, `lib/src/bundle.dart`, `bundles.dart`, `tar.dart` |
| Native build | deps -> FFmpeg -> patched mpv -> package | `native/build/*.sh`, `native/patches/`, `native/deps/libplacebo/` |
| Native tests | Render smoke, stream bridge, renderer golden traces, affinity, API override | `native/tests/` |

## Pattern Overview

**Overall:** Layered FFI binding + Flutter plugin with a native engine/backend seam (template method + strategy).

**Key Characteristics:**
- One libmpv mapping per process; the plugin never loads libmpv — Dart passes the handle and render symbol addresses over the method channel.
- Generated surface (catalog/options), hand-written behaviour.
- Synchronous C boundary; native callbacks enter Dart only via `NativeCallable.listener`.
- One native render thread per controller owns every post-`Start` `mpv_render_*` call.
- Fallback-first rendering as data: an ordered `BackendCandidate` chain, every failure becomes a reason trail or typed event.
- Public API frozen (`packages/mpv_kit/test/api_freeze_test.dart`, `api_surface_test.dart`); new backends map onto existing `MpvVideoBackend { vulkan, software }` (ADR 0004).

## Layers

**Generated:**
- Purpose: mpv properties/commands/options with docs and types
- Location: `packages/mpv_kit/lib/src/generated/`
- Contains: `catalog.dart`, `catalog_types.dart`, `options.dart`, `option_types.dart`
- Depends on: `dart:core` only
- Used by: `Mpv`, `Player`, apps. Regenerate via `tools/gen_catalog.dart`, `tools/gen_options.dart`

**FFI:**
- Purpose: symbol declarations and library resolution
- Location: `packages/mpv_kit/lib/src/ffi/`
- Depends on: `dart:ffi`, `package:ffi`
- Used by: `core/`, `MpvVideoController` (symbol lookup)

**Core:**
- Purpose: safe libmpv semantics in Dart
- Location: `packages/mpv_kit/lib/src/core/`
- Depends on: `ffi/`, `generated/`
- Used by: `player/`, `mpv_kit_video`

**Player:**
- Purpose: ergonomic state and commands
- Location: `packages/mpv_kit/lib/src/player/`
- Depends on: `core/`
- Used by: apps, `mpv_kit_video`

**Video Dart:**
- Purpose: Flutter texture + diagnostics
- Location: `packages/mpv_kit_video/lib/src/`
- Depends on: `package:mpv_kit`, Flutter services/widgets
- Used by: apps (barrel re-exports `mpv_kit`)

**Native engine:**
- Purpose: render context, render thread, frame ring, backends
- Location: `packages/mpv_kit_video/src/`
- Depends on: `src/include/mpv/` (vendored render headers), `third_party/` (Vulkan-Headers, volk)
- Used by: all platform plugins (macOS compiles it via `macos/Classes/shared_sources.cpp`, `volk_unity.c`)

**Platform plugins:**
- Purpose: Flutter texture registrar, compositor sharing, event marshalling
- Location: `packages/mpv_kit_video/{windows,linux,macos}/`
- Depends on: native engine, Flutter embedder APIs

**Distribution/tooling:**
- Location: `packages/mpv_kit_libs/`, `native/build/`, `tools/`, `.github/workflows/`
- No runtime Dart code in `mpv_kit_libs`

**Vendored upstream:**
- `native/mpv/`: full upstream mpv source tree (963 tracked files, version in `native/mpv/MPV_VERSION`), third-party, never edited directly; downstream changes live as patches in `native/patches/` (0001–0004, 0006–0009) tracked in `native/patches/UPSTREAM.md`, checked by `tools/check_patches.sh`. libplacebo backports in `native/deps/libplacebo/` with `SHA256SUMS`.

## Data Flow

### Property observation

1. `Player` registers observers through `Mpv.observeProperty` (`packages/mpv_kit/lib/src/core/mpv.dart`)
2. libmpv wakeup callback -> `NativeCallable.listener` -> `Mpv` drains `mpv_wait_event`, decodes immediately into `MpvEventData` (`core/events.dart`, `core/node.dart`)
3. Property-change events update `MpvState<T>` (sync broadcast, deduplicated) (`player/player.dart`)

### Video frame path

1. `MpvVideoController.create` sends handle + render symbol addresses to the plugin (`video_controller.dart`); `MpvApi::Load` requires all nine (`src/mpv_api.h`)
2. `VideoRenderer::Start` builds candidates (`Interop::BackendCandidates`, default `DefaultCandidates(choice)`), applies `MPV_KIT_VIDEO_API` filter, per api creates one backend (`Interop::CreateBackend` or built-in), calls `RenderBackend::Create` per renderer; `_create`/`_get_info` run on the caller thread (`src/video_renderer.cc`)
3. Render thread: `BindThread`, update callback signals CV, reports due swaps, `mpv_render_context_update`, `RenderBackend::Render` into a free slot, `Wait` if `pipelined()`, publish, `Interop::FrameReady`
4. Compositor/raster thread calls `AcquireFront()` under the renderer lock: returns front `Frame` (via `FrameFor`), counts a due swap (`swaps_to_report_`), wakes render thread — makes no libmpv call
5. Render thread calls `mpv_render_context_report_swap` for each counted swap before next update (`video_renderer.cc:533`)
6. On destroy: platform sets quit and joins; render thread removes update callback, `RenderBackend::Release` (`render_context_free`), `UnbindThread`, exits; backend destroyed afterwards (device last)

### Resize / reallocation

1. `MpvVideo` debounces size, controller sends physical size
2. Render thread calls `AllocTargets(count, w, h, keep_slot)`; old generation retires (Vulkan keeps only `keep_slot`; software keeps old + previous generation)
3. `FreeRetired` after first new-size frame published and compositor took quarantine+1 frames

### Reason / backend reporting (ADR 0004)

1. Winner's `wire_name` (`vulkan`, `software`; reserved `d3d11`, `opengl`) returned as `backend`; Dart matches exactly or throws `PlatformException('render_init')`
2. `reason` = winner head + trails of earlier candidates, e.g. `software (sw) on cpu; vulkan/gpu-next unavailable: ...`

### Custom stream protocol

1. `Mpv.registerStreamProtocol` -> `StreamBridge` registers native callbacks (patch 0006)
2. mpv demuxer thread requests -> `NativeCallable.listener` -> `MpvStreamSource` async -> completion back to native; failures mapped to mpv error codes

**State Management:**
- Mutable state concentrated in `MpvState<T>`, `Mpv`, `Player`, `MpvVideoController` (static `_live` registry keyed by texture id), and `VideoRenderer` (under renderer lock).

## Key Abstractions

**RenderBackend:**
- Purpose: one graphics API behind a `VideoRenderer`
- Examples: `packages/mpv_kit_video/src/render_backend.h`, `SoftwareBackend` in `video_renderer.cc`, `VulkanRenderBackend` in `vulkan_backend.cc`
- Pattern: strategy interface (`wire_name`, `frame_kind`, `pipelined`, `BindThread/UnbindThread`, `Create`, `device_failed`, `device_name`, `RendererName`, `AllocTargets`, `FreeRetired`, `FrameFor`, `Render`, `Wait`, `Release`) with a documented deferred-release contract

**BackendCandidate / DefaultCandidates:**
- Purpose: ordered `{api, renderer}` chain; `auto` = vulkan/gpu-next, vulkan/gpu, software/sw
- Examples: `render_backend.h`, `video_renderer.cc:253`
- Pattern: data-driven fallback; renderer quality first, API second (ADR 0004 Decision 5)

**Interop:**
- Purpose: platform seam (texture dirty, retain, compositor latency, candidate override, platform backend factory)
- Examples: `video_renderer.h:54`, `windows/d3d11_interop.*`, `linux/gl_interop.*`, `macos/Classes/metal_interop.*`

**Mpv / Player / MpvState<T>:**
- Purpose: client-API mirror and high-level state
- Examples: `packages/mpv_kit/lib/src/core/mpv.dart`, `packages/mpv_kit/lib/src/player/player.dart`

**MpvStreamSource:**
- Purpose: host-provided byte streams
- Examples: `packages/mpv_kit/lib/src/core/stream_bridge.dart`

## Entry Points

**Package barrels:**
- Location: `packages/mpv_kit/lib/mpv_kit.dart`, `packages/mpv_kit_video/lib/mpv_kit_video.dart`, `packages/mpv_kit_libs/lib/mpv_kit_libs.dart`
- Responsibilities: public API exports

**Plugin registration:**
- Location: `packages/mpv_kit_video/windows/mpv_kit_video_plugin.cpp` (`MpvKitVideoPluginCApiRegisterWithRegistrar`), `linux/mpv_kit_video_plugin.cc`, `macos/Classes/MpvKitVideoPlugin.mm`
- Triggers: generated plugin registrant

**Build hook:** `packages/mpv_kit_libs/hook/build.dart` (native-assets build)

**Example app:** `example/lib/main.dart`; integration tests in `example/integration_test/`

**Native tests:** `native/tests/meson.build`

**Tools:** `tools/gen_catalog.dart`, `tools/gen_options.dart`, `tools/pin_bundles.dart`, `tools/check_consistency.dart`, `tools/check_patches.sh`, `tools/bench_decode.dart`, `tools/rea_abi_audit/pe_audit.py`, `native/build/build.sh`

## Architectural Constraints

- **Threading:** Dart single isolate event loop; native callbacks via `NativeCallable.listener`. Native: after `Start`, every `mpv_render_*` call (update, render, set_parameter, report_swap, final set_update_callback(nullptr), render_context_free) runs on the controller's render thread; only `_create`/`_get_info`/first update callback run on the `Start` caller. Debug asserts plus `native/tests/video_renderer_affinity_test.cc` enforce this. Required for a future OpenGL backend.
- **Global state:** `MpvLibrary` static binding cache (`library.dart`); `MpvVideoController._live` registry (`video_controller.dart`).
- **Single libmpv mapping:** later `open(path:)` with a different path is ignored.
- **Dispose order:** render context must be freed before the mpv core — enforced by `Player.addDisposeHook`.
- **Frame ring quarantine:** compositor-returned image stays quarantined for `CompositorLatency()` acquisitions (Windows 4, ring 7; others 2, ring 5) (`video_renderer.h`); no cross-API fences.
- **`MPV_KIT_VIDEO_API`:** read once per `Start`, `^[a-z0-9-]{1,16}$`, strict — no fallback; mismatch -> `render_init` (`video_renderer.cc:53`).
- **Frozen public API:** `MpvVideoBackend` stays `{vulkan, software}`; wire names private, exact match.
- **Golden freeze:** `native/tests/golden/*.txt` and existing golden test files are frozen; new tests go in new files.
- **Circular imports:** none; dependencies point inward (`player/` -> `core/` -> `ffi/`, `generated/`).

## Anti-Patterns

### Calling libmpv render API off the render thread

**What happens:** Adding `mpv_render_context_*` calls in `AcquireFront`, platform callbacks or the destructor.
**Why it's wrong:** Breaks render.h threading rules and the affinity test; impossible for OpenGL.
**Do this instead:** Count work under the lock and wake the render thread, as swap reporting does in `packages/mpv_kit_video/src/video_renderer.cc`.

### Adding a backend via control flow or public enum

**What happens:** Branching in `VideoRenderer` per API, or adding an `MpvVideoBackend` value.
**Why it's wrong:** Violates the API freeze and ADR 0004.
**Do this instead:** Implement `RenderBackend`, add a `BackendCandidate` via `Interop::BackendCandidates`/`CreateBackend`, add wire name to Dart's exact-match set first.

### Loading libmpv from the plugin / disposing player before controller / editing generated files

**Do this instead:** Pass symbols over the channel (`mpv_api.h`); rely on dispose hooks; regenerate with `tools/gen_*.dart`.

## Error Handling

**Strategy:** Typed exceptions in Dart, typed events and reason trails in native.

**Patterns:**
- Negative libmpv codes -> `MpvException` (`core/errors.dart`); `tryGetProperty` returns null for unavailable.
- Stream bridge maps source failures to mpv error codes, never throws across FFI.
- Renderer: failed frames -> `SKIP_RENDERING` + backoff 100 ms -> 5 s; device loss stops rendering, emits `device_lost`.
- Creation failure -> `PlatformException('render_init')` with trails; unknown wire name also `render_init`.

## Cross-Cutting Concerns

**Logging:** One line per controller creation in `video_controller.dart`; diagnostics as `MpvVideoEvent` / `Player.logs`; native `log_` callback in `VideoRenderer`.
**Validation:** Boundary checks (`MpvOption.check`, `MpvApi::Load`, `MPV_KIT_VIDEO_API` charset, strict wire names, bundle sha256).
**Authentication:** Not applicable.

Further reading: `docs/ARCHITECTURE.md`, `docs/ARCHITECTURE-diagrams.md`, `docs/adr/0001`–`0004`.

---

*Architecture analysis: 2026-10-27*
