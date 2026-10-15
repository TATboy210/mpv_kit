// Format matrix: plays every sample of tools/make_format_samples.sh and
// checks that the expected decoders run. Skipped unless
// MPV_KIT_FORMAT_SAMPLES points at the generated directory (CI generates
// it for the release bundles, whose FFmpeg build is trimmed).
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

Future<T> _until<T>(MpvState<T> s, bool Function(T) ok) => ok(s.value)
    ? Future.value(s.value)
    : s.stream.firstWhere(ok).timeout(const Duration(seconds: 15));

void main() {
  final dir = Platform.environment['MPV_KIT_FORMAT_SAMPLES'];
  final manifest = dir == null ? null : File('$dir/expect.tsv');
  if (manifest == null || !manifest.existsSync()) {
    test('format matrix', () {}, skip: 'MPV_KIT_FORMAT_SAMPLES not set');
    return;
  }
  final rows = manifest
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => l.split('\t'));

  late Player player;
  setUp(() => player = Player(options: const {'vo': 'null', 'ao': 'null'}));
  tearDown(() => player.dispose());

  for (final [name, video, audio, sub] in rows) {
    test(name, () async {
      final errors = <MpvPlaybackError>[];
      final errSub = player.errors.listen(errors.add);
      player.setSpeed(4);
      await player.open('$dir/$name');
      final tracks = await _until(player.tracks, (t) => t.isNotEmpty);
      String? codec(MpvTrackType type) =>
          tracks.where((t) => t.type == type).firstOrNull?.codec;

      if (video != '-') expect(codec(MpvTrackType.video), video, reason: name);
      if (audio != '-') expect(codec(MpvTrackType.audio), audio, reason: name);
      if (sub != '-') expect(codec(MpvTrackType.sub), sub, reason: name);
      if (audio != '-') {
        // Decoding started: the decoder produced a format.
        final ap = await _until(player.audioParams, (p) => p != null);
        expect(ap!.sampleRate, greaterThan(0), reason: name);
      }
      if (video != '-' && !tracks.any((t) => t.isAlbumArt)) {
        final vp = await _until(player.videoParams, (p) => p != null);
        expect(vp!.width, greaterThan(0), reason: name);
      }
      // Playback progresses (or the short sample already ended).
      await _until(
        player.position,
        (p) => p > const Duration(milliseconds: 300),
      ).catchError(
        (_) => _until(player.completed, (c) => c).then((_) => Duration.zero),
      );
      expect(errors, isEmpty, reason: name);
      await errSub.cancel();
    });
  }

  test('music tags and cover art', () async {
    final tagged = rows.where((r) => r[0] == 'tagged.mp3');
    if (tagged.isEmpty) return markTestSkipped('tagged.mp3 not generated');
    await player.open('$dir/tagged.mp3');
    final meta = await _until(player.metadata, (m) => m.isNotEmpty);
    final lower = {for (final e in meta.entries) e.key.toLowerCase(): e.value};
    expect(lower['artist'], 'Test Artist');
    expect(lower['album'], 'Test Album');
    final tracks = await _until(player.tracks, (t) => t.length == 2);
    expect(tracks.where((t) => t.isAlbumArt), hasLength(1));
  });
}
