// High-level Player tests (headless, vo=null).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

const _lavfi = 'av://lavfi:testsrc2=size=320x240:rate=30:duration=2';

Future<T> _until<T>(MpvState<T> s, bool Function(T) ok) => ok(s.value)
    ? Future.value(s.value)
    : s.stream.firstWhere(ok).timeout(const Duration(seconds: 10));

/// Writes [seconds] of silent 8 kHz mono 16-bit PCM as a WAV file.
///
/// Seek tests need a source with exact, index-free seeking: lavfi sources
/// are not seekable in mpv's demuxer cache (`seekable-ranges` stays empty)
/// and their low-level seeks land on arbitrary frames, which made a lavfi
/// seek test pass only when it caught a transient position.
File _writeSilentWav(String path, {int seconds = 3}) {
  const rate = 8000, bytesPerSample = 2;
  final dataBytes = seconds * rate * bytesPerSample;
  final b = ByteData(44 + dataBytes);
  void tag(int offset, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // fmt chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * bytesPerSample, Endian.little); // byte rate
  b.setUint16(32, bytesPerSample, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return File(path)..writeAsBytesSync(b.buffer.asUint8List());
}

void main() {
  late Player player;
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('mpv_kit_test'));
  tearDownAll(() => tmp.deleteSync(recursive: true));
  setUp(() => player = Player(options: const {'vo': 'null', 'ao': 'null'}));
  tearDown(() => player.dispose());

  test('open exposes tracks, video params and position', () async {
    await player.open(_lavfi);
    final tracks = await _until(player.tracks, (t) => t.isNotEmpty);
    expect(tracks.single.type, MpvTrackType.video);
    expect(tracks.single.width, 320);
    final vp = await _until(player.videoParams, (v) => v != null);
    expect(vp!.width, 320);
    await _until(player.position, (p) => p > Duration.zero);
    expect(player.paused.value, isFalse);
  });

  test('pause / volume / speed / mute round-trip', () async {
    await player.open(_lavfi, play: false);
    await _until(player.paused, (p) => p);
    player.setVolume(30);
    player.setSpeed(2);
    player.setMute(true);
    await _until(player.volume, (v) => v == 30);
    await _until(player.speed, (v) => v == 2);
    await _until(player.muted, (v) => v);
  });

  test('playlist add / jump', () async {
    await player.open(_lavfi);
    await player.add(_lavfi);
    final list = await _until(player.playlist, (l) => l.length == 2);
    expect(list.first.current, isTrue);
    player.jump(1);
    await _until(player.playlistIndex, (i) => i == 1);
  });

  test('keep-open reports completion at EOF', () async {
    await player.open(_lavfi);
    await _until(player.completed, (c) => c);
  });

  test('errors stream reports unplayable input', () async {
    final err = player.errors.first.timeout(const Duration(seconds: 10));
    await player.open('/definitely/not/a/file.mkv');
    expect((await err).error, MpvError.loadingFailed);
  });

  test('seek moves position', () async {
    final wav = _writeSilentWav('${tmp.path}${Platform.pathSeparator}seek.wav');
    await player.open(wav.path, play: false);
    await _until(player.duration, (d) => d > Duration.zero);
    // Exact seeks in PCM are sample-accurate; every target, in any order.
    for (final ms in const [1000, 300, 2500]) {
      await player.seek(Duration(milliseconds: ms), exact: true);
      final pos = await _until(
        player.position,
        (p) => (p.inMilliseconds - ms).abs() < 50,
      );
      expect(pos.inMilliseconds, closeTo(ms, 50));
    }
  });

  test('openPlaylist starts at the requested entry', () async {
    await player.openPlaylist([_lavfi, _lavfi, _lavfi], startIndex: 2);
    await _until(player.playlist, (l) => l.length == 3);
    await _until(player.playlistIndex, (i) => i == 2);
  });

  test('delays, loops and adjustments round-trip', () async {
    await player.open(_lavfi, play: false);
    player.setSubtitleDelay(const Duration(milliseconds: 500));
    player.setAudioDelay(const Duration(milliseconds: -250));
    player.setLoopFile(true);
    player.setLoopPlaylist(true);
    player.setSubtitlesVisible(false);
    player.setVideoAdjustment(MpvVideoAdjustment.contrast, 150);
    await _until(
      player.subtitleDelay,
      (d) => d == const Duration(milliseconds: 500),
    );
    await _until(
      player.audioDelay,
      (d) => d == const Duration(milliseconds: -250),
    );
    await _until(player.loopFile, (v) => v);
    await _until(player.loopPlaylist, (v) => v);
    await _until(player.subtitlesVisible, (v) => !v);
    // Clamped to mpv's -100..100 range.
    expect(player.mpv.getProperty('contrast'), 100);
    player.setAbLoop(const Duration(milliseconds: 200), null);
    expect(player.mpv.getProperty('ab-loop-a'), closeTo(0.2, 1e-6));
    expect(player.mpv.getPropertyString('ab-loop-b'), 'no');
  });

  test('audio-only media exposes audio params and no video', () async {
    await player.open(
      'av://lavfi:sine=frequency=440:sample_rate=48000:duration=2',
    );
    final ap = await _until(player.audioParams, (p) => p != null);
    expect(ap!.sampleRate, 48000);
    expect(ap.channelCount, greaterThan(0));
    final tracks = await _until(player.tracks, (t) => t.isNotEmpty);
    expect(tracks.single.type, MpvTrackType.audio);
    expect(tracks.single.isAlbumArt, isFalse);
    expect(player.videoParams.value, isNull);
    await _until(player.position, (p) => p > Duration.zero);
  });

  test('loop mode, replay gain and audio device', () async {
    await player.open(_lavfi, play: false);
    player.setLoopMode(MpvLoopMode.file);
    await _until(player.loopFile, (v) => v);
    expect(player.loopMode, MpvLoopMode.file);
    player.setLoopMode(MpvLoopMode.playlist);
    await _until(player.loopPlaylist, (v) => v);
    await _until(player.loopFile, (v) => !v);
    expect(player.loopMode, MpvLoopMode.playlist);
    player.setLoopMode(MpvLoopMode.none);
    await _until(player.loopPlaylist, (v) => !v);
    expect(player.loopMode, MpvLoopMode.none);
    player.setReplayGain(MpvReplayGain.album);
    expect(player.mpv.getPropertyString('replaygain'), 'album');
    player.setAudioDevice('auto');
    expect(player.audioDevice.value, 'auto');
    expect(player.metadata.value, isA<Map<String, String>>());
    expect(player.bufferedPosition.value, isA<Duration>());
  });

  test('selected track ids follow vid/aid/sid', () async {
    await player.open(_lavfi);
    await _until(player.videoTrack, (id) => id == 1);
    player.selectTrack(MpvTrackType.video, null);
    await _until(player.videoTrack, (id) => id == null);
  });

  test('screenshot returns raw pixels of the current frame', () async {
    // video-params can precede the first displayed frame on slow runners;
    // a frame exists once playback time advances.
    await player.open(_lavfi);
    await _until(player.position, (p) => p > Duration.zero);
    player.pause();
    final shot = await player.screenshot();
    expect(shot, isNotNull);
    expect(shot!.width, 320);
    expect(shot.height, 240);
    expect(shot.data.length, shot.stride * shot.height);
  });

  test('mediaInfo snapshots codec facts', () async {
    await player.open(_lavfi, play: false);
    await _until(player.videoParams, (v) => v != null);
    final info = player.mediaInfo();
    expect(info.width, 320);
    expect(info.videoCodec, isNotNull);
  });

  test('logs stream delivers messages at the requested level', () async {
    player.setLogLevel('v');
    final first = player.logs.first.timeout(const Duration(seconds: 10));
    await player.open(_lavfi);
    expect((await first).text, isNotEmpty);
  });

  test('dispose runs hooks before destroying the core', () async {
    final p = Player(options: const {'vo': 'null', 'ao': 'null'});
    final order = <String>[];
    Future<void> hook() async {
      // The core must still be alive here.
      expect(p.mpv.isDisposed, isFalse);
      order.add('hook');
    }

    p.addDisposeHook(hook);
    p.addDisposeHook(() async {
      p.removeDisposeHook(hook); // removing during dispose is harmless
      order.add('second');
    });
    await p.dispose();
    expect(order, ['hook', 'second']);
    expect(p.mpv.isDisposed, isTrue);
    await p.dispose(); // idempotent
  });

  test('throwing dispose hook still destroys the core and closes all '
      'streams', () async {
    final p = Player(options: const {'vo': 'null', 'ao': 'null'});
    // A failing assertion must not leak the native core — and with it the
    // wakeup listener that keeps the isolate alive — for the rest of the run.
    addTearDown(() {
      if (!p.mpv.isDisposed) p.mpv.dispose();
    });
    final sentinel = StateError('dispose hook exploded');
    Future<void> hook() async => throw sentinel;
    final positionDone = Completer<void>();
    final decodeWarningDone = Completer<void>();
    p.position.stream.listen((_) {}, onDone: positionDone.complete);
    p.decodeWarning.stream.listen((_) {}, onDone: decodeWarningDone.complete);
    p.addDisposeHook(hook);
    // The hook error is surfaced unchanged...
    await expectLater(p.dispose(), throwsA(same(sentinel)));
    // ...but every teardown step still ran.
    expect(p.mpv.isDisposed, isTrue);
    await positionDone.future.timeout(const Duration(seconds: 5));
    await decodeWarningDone.future.timeout(const Duration(seconds: 5));
    await p.dispose(); // a second dispose is harmless
  });

  test('audioDevices first read after dispose is already closed', () async {
    final trackedStreams = player.stateStreamsForTesting.length;
    await player.dispose();
    final devices = player.audioDevices;
    final done = Completer<void>();
    devices.stream.listen((_) {}, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 5));
    expect(devices.value, isEmpty);
    expect(player.mpv.isDisposed, isTrue);
    // The lazy state must stay outside _states: a first post-dispose read
    // must not register a new stream or start audio-device hotplug monitoring.
    expect(player.stateStreamsForTesting.length, trackedStreams);
  });

  test('catalog is generated from mpv docs', () {
    expect(mpvCommands.map((e) => e.name), contains('loadfile'));
    expect(mpvOptions.map((e) => e.name), containsAll(['hwdec', 'vo']));
    expect(
      mpvProperties.firstWhere((e) => e.name == 'time-pos').writable,
      isTrue,
    );
  });
}
