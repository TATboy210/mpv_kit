## 0.1.0-dev.4

- Changed: `MpvLibrary.open` (and so `Mpv.create`/`Player` with `libraryPath`)
  is strict about explicitly named libraries. An explicit `path`, else a
  non-empty `MPV_KIT_LIBMPV_PATH`, is tried alone; if it fails to load
  (missing file, unresolved dependency, incompatible client API) it throws
  `MpvLibraryNotFound` carrying the loader's reason instead of silently
  falling back to the next candidate (which ran the wrong libmpv). The
  platform default names are only tried when neither is given. Signatures are
  unchanged.
- Fixed: disposing an `Mpv` while clients created from it were still alive
  hung forever; `dispose()` now disposes those clients first.
- Fixed: custom stream protocols always answer a claimed request: a source
  whose `size` getter throws, or a URI that is not valid UTF-8, fails the
  load instead of freezing it, and an opener that does not complete within
  30 s fails with `loadingFailed` (a source arriving later is closed).
- Changed: `Player` no longer hardware-decodes FFV1 by default
  (`hwdec-codecs` excludes `ffv1`, mpv #18255); override it through
  `options`.
- Changed (behavior): `Player` now defaults `hwdec` to a per-platform,
  zero-copy-first list instead of one shared list: Windows
  `vulkan,d3d11va,d3d11va-copy,auto-safe`, Linux `vulkan,vaapi,auto-safe`,
  macOS `videotoolbox,auto-safe`, other `auto-safe` (was
  `vulkan,d3d11va-copy,auto-safe` everywhere). An explicit `hwdec` in `options`
  still wins. See ADR 0006.

## 0.1.0-dev.3

- No API changes; released together with mpv_kit_libs 0.1.0-dev.3.

## 0.1.0-dev.2

- Fixed: reading `audioDevices` no longer crashes on machines without an
  audio output device (fixed in libmpv, see mpv_kit_libs). The device
  tests now run on every CI target.

## 0.1.0-dev.1

- Music and audio state for drop-in replacement of media_kit: `metadata`
  (tags, ICY titles), `audioParams`, `audioDevices` / `setAudioDevice`,
  `bufferedPosition`, `setLoopMode` / `loopMode` (`MpvLoopMode`),
  `setReplayGain`, `MpvTrack.isAlbumArt`. See
  `docs/MIGRATING_FROM_MEDIA_KIT.md`.
- Known issue: reading `audioDevices` on a machine without any audio
  output device (e.g. headless CI VMs) crashes inside mpv's CoreAudio /
  WASAPI device enumeration. Device listing is lazy, so playback never
  triggers it; machines with an audio device are unaffected.
- `Mpv`: bindings for the full libmpv 0.41 client API (client API 2.5):
  commands (sync, async, abortable), properties via `mpv_node`, property
  observers as streams, typed events, hooks, log messages, sub-clients.
- Isolate-safe event loop driven by mpv's wakeup callback through
  `NativeCallable.listener`.
- Secure defaults (`Mpv.secureDefaultOptions`): config files, scripts,
  ytdl, OSC and default key bindings disabled unless requested.
- `Player`: typed high-level player with `MpvState<T>` state streams,
  playlist, track, subtitle, audio/video adjustment and screenshot commands,
  `errors` and `logs` streams, and `addDisposeHook` for render contexts.
- `MpvOptions`: typed `MpvOption<T>` for every option of the bundled
  libmpv, with `Mpv.getOptionValue` / `Mpv.setOptionValue`.
- `mpvProperties`, `mpvCommands`, `mpvOptions`: catalog generated from
  mpv's documentation.
- Custom stream protocols served from Dart (`Mpv.registerStreamProtocol`,
  `MpvStreamSource`, `MpvMemoryStreamSource`) on libmpv builds with the
  mpv_kit stream bridge (patch 0006).
- `MpvLibrary`: libmpv lookup via explicit path, `MPV_KIT_LIBMPV_PATH` or
  platform default names, with a client API version check.
