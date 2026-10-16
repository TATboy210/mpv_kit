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
