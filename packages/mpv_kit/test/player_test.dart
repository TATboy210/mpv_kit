// High-level Player tests (headless, vo=null).
@TestOn('vm')
library;

import 'dart:async';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

const _lavfi = 'av://lavfi:testsrc2=size=320x240:rate=30:duration=2';

Future<T> _until<T>(MpvState<T> s, bool Function(T) ok) => ok(s.value)
    ? Future.value(s.value)
    : s.stream.firstWhere(ok).timeout(const Duration(seconds: 10));

void main() {
  late Player player;
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
    expect((await err).reason, EndFileReason.error);
  });

  test('seek moves position', () async {
    await player.open(_lavfi, play: false);
    // Wait for the first decoded frame: a seek issued while playback is
    // still initialising can be superseded by mpv's own start-up seek.
    await _until(player.videoParams, (v) => v != null);
    await player.seek(const Duration(milliseconds: 1000), exact: true);
    await _until(player.position,
        (p) => (p.inMilliseconds - 1000).abs() < 100);
  });

  test('catalog is generated from mpv docs', () {
    expect(mpvCommands.map((e) => e.name), contains('loadfile'));
    expect(mpvOptions.map((e) => e.name), containsAll(['hwdec', 'vo']));
    expect(mpvProperties.firstWhere((e) => e.name == 'time-pos').writable,
        isTrue);
  });
}
