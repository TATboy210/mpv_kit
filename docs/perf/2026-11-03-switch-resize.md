# Windows Switching / Rapid Resize — Black-Frame Fix (dev.7)

**Date:** 2026-11-03 · **Machine:** Windows 11 x64, RTX 4060 Laptop, 16-thread CPU ·
**libmpv:** pinned `v0.1.0-dev.6` bundle · **Flutter:** 3.47.9.

## Symptom

Switching to another video file showed a black flash (and, when the aspect
changed, a frame of letterboxed content). Rapid window resizes during a
switch could keep the window black until the next size rendered.

## Root causes (verified)

1. **Dart, every switch:** `MpvVideo` returned `SizedBox.expand()` whenever
   `videoParams` became null. mpv reports `video-params` as unavailable while
   the new file loads, so the `Texture` widget was unmounted and the last
   frame disappeared (`mpv_video.dart`, `player.dart` `_bind('video-params')`).
   A widget test reproduced it before the fix: after `stop()` no `Texture`
   remained in the tree.
2. **Dart, controller replacement:** `_requested`/`_debounce` were never
   reset when a different `MpvVideoController` was mounted at the same size,
   so the new native renderer never received its first `setSize` and skipped
   every frame.
3. **Dart, switch timing:** a new file's size request went through the 80 ms
   window-resize debounce; with a changed aspect ratio, mpv published the
   new frame into the previous ring letterboxed for the debounce window.
4. **Native, resize after resize without a frame:** `RenderOnce` cleared
   `retired_front_` at the start of every size change. If the first new-size
   render failed (or the publish gate timed out) and another `SetSize`
   arrived, the backend had already freed the survivor; `AcquireFront` then
   returned an empty frame and `Describe` returned `nullptr` — Flutter draws
   nothing. The `*_retire_twice` goldens encoded this behavior.

Flutter's `ExternalTextureD3d` binds the shared handle through ANGLE and
calls the release callback immediately, with no fence or keyed mutex
(verified earlier from the Windows embedder). Producer-side
`quarantine=4` + the pre-publish GPU wait remain the only sync, so this
release keeps zero-copy and does not adopt a copy-to-texture model.

## Fix

- `MpvVideo` caches the last non-null video `Size`, keeps the `Texture`
  mounted while params are transiently null, requests the new size at once
  after a switch (no debounce) and resets all size state in
  `didUpdateWidget` when the controller changes.
- Internal `RenderBackend` contract gains `kKeepRetiredFront` plus
  `keeps_retired_front()`. Vulkan, D3D11 and software advertise it and keep
  their retired survivor across a resize that arrives before any new-size
  frame; `FreeRetired()` still releases it after the first new-size publish
  and the quarantine. OpenGL and test fakes keep the old behavior (default
  false).
- Windows plugin gains a test-only `stats` method
  (`describes`, `nullDescribes`, `pixels`, `nullPixels`) so a lost frame can
  be proven absent; no Dart public API was added.

## Measurements

`example/integration_test/switch_resize_test.dart` runs the real plugin with
the real `MpvVideo` widget and `RepaintBoundary.toImage()` probes:
playing switch, aspect switch, paused switch, 20 rapid `setSize` calls and a
paused double resize. A frame is "black" below 5 % non-black pixels.

| Backend | Playing switch (40 samples) | Aspect switch | Paused switch | `nullDescribes` / `nullPixels` |
|---|---|---|---|---|
| Vulkan (default) | missing 0, black 0, worst non-black 0.996 | missing 0 | missing 0, black 0, worst 0.996 | 0 |
| `MPV_KIT_VIDEO_API=d3d11` | missing 0, black 0, worst non-black 0.996 | missing 0 | missing 0, black 0, worst 0.996 | 0 |
| `MPV_KIT_VIDEO_API=software` | missing 0, black 0, worst non-black 0.996 | missing 0 | missing 0, black 0, worst 0.427 | 0 |

The 0.427 paused-switch sample is the single transitional frame after an
aspect change: the first new-file frame is published into the previous
ring (mpv letterboxes it) before `setSize` reaches the renderer. It is not a
black frame and corrects on the next frame.

Regression runs: `d3d11_backend_test` (single resize, non-black 1.0),
`real_plugin_test` (30 resize events, 10 cycles, 0 errors) and
`backend_soak_test` 100 rounds on d3d11 (42.7 s, 0 errors) and Vulkan
(52.8 s, 0 errors) all pass.

Native goldens: `vk_retire_twice` and `sw_retire_twice` now expect the
survivor to stay alive and be handed to the compositor (`acquire index=-2 …
serial=1`) and to be released after quarantine; the frozen `sw`, `vk` and
`vk_fallback` goldens are unchanged and still pass.

## Verdict

The reported black screen on video switching was the unmounted `Texture`
(root cause 1), fixed in Dart and now covered by a deterministic widget test
plus the real-plugin switch test on both GPU backends and the software path.
The native adopt-retired change closes the remaining black window when a
resize follows an unpublished resize (render failure or publish timeout).
