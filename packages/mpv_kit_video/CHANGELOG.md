## 0.1.0-dev.8

- Fixed: a D3D11 device loss detected while allocating a new ring (resize) or
  returning a render error now emits `deviceLost` once and stops rendering,
  instead of backing off forever while Dart's `isBroken` stayed false.
- Fixed: `ID3D11Fence::Signal` failures are checked; that slot falls back to
  its `D3D11_QUERY_EVENT` completion instead of waiting for a value that was
  never signalled. Three consecutive unusable query completions report
  `deviceLost` instead of a 1 s timeout per frame.
- Fixed: device creation retries with feature level 11_0 when the runtime
  rejects 11_1 with `E_INVALIDARG` (backend and interop devices).
- Fixed: the Windows plugin no longer dereferences the platform texture
  struct after `AcquireFront` released the renderer lock (`RetainFrame` now
  fills `Frame.handle`/`Frame.release_context` under the lock), defers
  `Instance` deletion in the plugin destructor through `UnregisterTexture`,
  and reports a failed texture registration instead of `textureId: -1`.
- Added (test-only, Windows): injection modes `create-no-11-1`,
  `device-removed:alloc`, `device-removed:render:<n>`, `signal-fail:<n>`,
  `query-getdata-fail`, and `stats.sync`.

## 0.1.0-dev.7

- Fixed: switching to another file no longer shows a black frame. `MpvVideo`
  keeps the last frame's geometry and the texture mounted while mpv reports
  `video-params` as unavailable, requests the new size at once after a switch
  instead of after the window-resize debounce, and resets its size state when
  a different controller is mounted at the same size.
- Fixed: a resize that arrives before the previous resize published a frame
  (render failure or GPU timeout) no longer drops the only picture. The
  Vulkan, D3D11 and software backends keep their retired survivor until the
  first new-size frame and the compositor quarantine; backends that do not
  advertise the capability (OpenGL) keep the old behaviour.
- Added (test-only, Windows plugin): a `stats` method with lifetime
  `describes`/`nullDescribes`/`pixels`/`nullPixels` counters. No Dart public
  API change.

## 0.1.0-dev.6

- Depends on mpv_kit 0.1.0-dev.6 (8K software-decode thread cap). No changes
  to the renderer or the platform graphics backends.

## 0.1.0-dev.5

- Depends on mpv_kit / mpv_kit_libs 0.1.0-dev.5 (lower software-decode
  memory, demuxer cache state API, smaller bundles). No changes to the
  renderer or the platform graphics backends.

## 0.1.0-dev.4

- Fixed: a failed render no longer causes a false `gpuTimeout` on the next
  frame (the unsignalled timeline value is rolled back).
- Fixed: shared images use the external queue family from the first frame,
  pairing every Vulkan ownership transfer.
- Fixed: a host ICC profile set on the controller survives option changes
  with the gpu-next renderer.
- Fixed: `MpvVideoEventKind.softwareFallback` was emitted before any listener
  could subscribe and so was always lost; it is now delivered to the first
  listener of `MpvVideoController.events`.
- Windows: new native Direct3D 11 backend (mpv's D3D11 render API on
  Flutter's adapter). `auto` tries `vulkan/gpu-next`, `d3d11/gpu-next`,
  `vulkan/gpu`, `d3d11/gpu`, then software, and `MPV_KIT_VIDEO_API=d3d11`
  forces it. It needs a libmpv built with the D3D11 render API (mpv_kit
  patch 0010).
- Linux: new native OpenGL backend (mpv's OpenGL render API on Flutter's
  `EGLDisplay`) that serves mpv's `gpu` renderer. `auto` tries
  `vulkan/gpu-next`, `opengl/gpu`, `vulkan/gpu`, then software, and
  `MPV_KIT_VIDEO_API=opengl` forces it. It needs a libmpv built with GL/EGL.
- `MpvVideoController.reason` names the API that won and lists one
  `unavailable` entry per candidate tried before it; `backend` still reports
  only `vulkan` or `software` (ADR 0004). No public API changed.

## 0.1.0-dev.3

- Requires mpv_kit / mpv_kit_libs 0.1.0-dev.3: zero-copy Vulkan rendering
  works with the bundled libmpv on Windows (dev.1/dev.2 always used the
  software fallback there).

## 0.1.0-dev.2

- Requires mpv_kit / mpv_kit_libs 0.1.0-dev.2: macOS apps build again
  (the 0.1.0-dev.1 libraries could not be repackaged by Flutter) and listing
  audio devices no longer crashes on machines without audio output.

## 0.1.0-dev.1

- `MpvVideoController` / `MpvVideo`: mpv's Vulkan render backend with
  zero-copy sharing on Windows (D3D11 shared textures), Linux (GL memory
  objects) and macOS (IOSurface via MoltenVK), software fallback
  everywhere.
- Renderer choice `MpvVideoRenderer` (`auto`, `gpuNext`, `gpu`,
  `software`) with the fallback chain gpu-next → gpu → software, the
  active path reported by `backend` / `reason`, and the
  `MPV_KIT_VIDEO_RENDERER` environment override.
- Dedicated native render thread with a quarantined frame ring, idle
  detection for hidden windows, and failure backoff.
- `events` stream of `MpvVideoEvent` diagnostics (resize, idle/active,
  render errors, GPU timeouts, recovery, device loss) and `isBroken`.
- `setIccProfile` for display color management.
- Persistent shader cache in a per-user directory by default;
  `display-fps-override` set from Flutter's display refresh rate.
- Render context disposed before the mpv core via
  `Player.addDisposeHook`.
- Re-exports `package:mpv_kit` and depends on `mpv_kit_libs`.
