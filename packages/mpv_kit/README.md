# mpv_kit

Complete, low-overhead Dart FFI bindings for **libmpv 0.41** (client API
2.5): every exported client API function, `mpv_node` conversion, an
isolate-safe event loop and a typed high-level `Player`. Pure Dart — works
in Flutter apps and in command-line programs.

For video output in Flutter use
[mpv_kit_video](https://pub.dev/packages/mpv_kit_video), which re-exports
this package; to ship libmpv with your app use
[mpv_kit_libs](https://pub.dev/packages/mpv_kit_libs).

## Features

* **`Mpv`** — 1:1 client API: commands (sync/async, abortable),
  properties (typed via `mpv_node`, sync/async), `observeProperty` streams,
  typed `events`, hooks, log messages, sub-clients.
* **`Player`** — typed playback state as `MpvState<T>` (value + change
  stream): position, duration, pause, buffering, tracks, playlist, chapters,
  video params, active hardware decoder, …; commands for open, seek,
  playlist, tracks, subtitles, audio/video adjustments and screenshots.
* **`MpvOptions`** — every option of the bundled libmpv as a typed
  `MpvOption<T>` with choices/ranges, for `Mpv.getOptionValue` /
  `Mpv.setOptionValue`.
* **Catalog** — `mpvProperties`, `mpvCommands`, `mpvOptions` generated
  from mpv's documentation.
* **Custom stream protocols** — `Mpv.registerStreamProtocol` serves
  `myproto://…` URLs from a Dart `MpvStreamSource` that may answer
  asynchronously (requires the mpv_kit libmpv, patch 0006).
* **Secure defaults** — config files, scripts, ytdl, OSC and default key
  bindings are disabled unless enabled explicitly.

## Usage

```dart
import 'package:mpv_kit/mpv_kit.dart';

Future<void> main() async {
  final player = Player(options: {'vo': 'null'}); // audio only, no video
  player.position.stream.listen((p) => print('at $p'));
  player.errors.listen((e) => print('failed: ${e.message}'));
  await player.open('https://example.com/stream.m3u8');
  await Future<void>.delayed(const Duration(seconds: 10));
  await player.dispose();
}
```

Low-level access:

```dart
final mpv = Mpv.create(options: {'vo': 'null'});
mpv.events.where((e) => e is FileLoadedEvent).listen((_) => print('loaded'));
mpv.command(['loadfile', 'video.mkv']);
mpv.observeProperty('time-pos').listen(print);
mpv.setOptionValue(MpvOptions.volume, 50.0);
```

Serving a stream from memory:

```dart
mpv.registerStreamProtocol(
  'mem',
  (uri) => MpvMemoryStreamSource(bytes),
);
mpv.command(['loadfile', 'mem://clip']);
```

## Loading libmpv

`MpvLibrary.open()` resolves libmpv from an explicit `libraryPath`, then
the `MPV_KIT_LIBMPV_PATH` environment variable, then the platform default
names (`libmpv-2.dll`, `libmpv.2.dylib` / the bundled framework,
`libmpv.so.2`). A client API major version other than 2 is rejected.
`MpvLibraryNotFound` lists every attempt.

## Threading

All `Mpv` methods are synchronous FFI calls that libmpv documents as
thread-safe. Events are delivered on the isolate that created the
instance: mpv's wakeup callback posts to a `NativeCallable.listener`, which
drains the event queue without blocking.

## License

MIT. libmpv itself is LGPL-2.1-or-later in the builds distributed by
mpv_kit; see the [repository](https://github.com/TATboy210/mpv_kit).
