## 0.1.0-dev.4

- Fixed: a failed render no longer causes a false `gpuTimeout` on the next
  frame (the unsignalled timeline value is rolled back).
- Fixed: shared images use the external queue family from the first frame,
  pairing every Vulkan ownership transfer.
- Fixed: a host ICC profile set on the controller survives option changes
  with the gpu-next renderer.

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
