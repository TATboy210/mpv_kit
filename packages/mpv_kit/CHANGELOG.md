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
