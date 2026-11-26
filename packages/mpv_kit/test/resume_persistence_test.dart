// Real-libmpv resume-playback tests (headless, vo=null, ao=null).
//
// A position saved when a Player is disposed must be restored when the same
// file is opened by a new Player that uses the same watch-later directory.
// The file is a generated silent WAV, so the test does not depend on any
// media that lives outside the repository.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

/// Upper bound for any wait on a playback state change.
const _timeout = Duration(seconds: 15);

/// Position the first player seeks to before it disposes.
const _savedAt = Duration(seconds: 3);

/// Writes [seconds] of silent 8 kHz mono 16-bit PCM as a WAV file.
///
/// WAV is used because it is seekable with exact timestamps; lavfi sources
/// are not (see player_test.dart).
File _writeSilentWav(String path, {int seconds = 6}) {
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
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * bytesPerSample, Endian.little);
  b.setUint16(32, bytesPerSample, Endian.little);
  b.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return File(path)..writeAsBytesSync(b.buffer.asUint8List());
}

/// Waits until [state] satisfies [ok], or fails after [_timeout].
Future<void> _waitFor(MpvState<Duration> state, bool Function(Duration) ok) {
  if (ok(state.value)) return Future.value();
  return state.stream.firstWhere(ok).timeout(_timeout);
}

/// Builds a headless player with the given resume settings.
Player _player(MpvResumeOptions resume) => Player(
  resume: resume,
  options: const {'vo': 'null', 'ao': 'null'},
);

void main() {
  late Directory tmp;
  late File clip;
  late Directory watchLater;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mpv_kit_resume_');
    clip = _writeSilentWav('${tmp.path}/clip.wav');
    watchLater = Directory('${tmp.path}/watch_later')..createSync();
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('a position saved on dispose is restored on the next open', () async {
    // Arrange
    final resume = MpvResumeOptions(watchLaterDir: watchLater.path);

    // Act: play, seek, and dispose so libmpv writes the position on quit.
    final first = _player(resume);
    await first.open(clip.path);
    await _waitFor(first.duration, (d) => d > Duration.zero);
    await first.seek(_savedAt, exact: true);
    await _waitFor(first.position, (p) => p >= _savedAt);
    await first.dispose();

    // Assert: the save wrote something into the watch-later directory.
    expect(watchLater.listSync(), isNotEmpty);

    // Act: reopen the same file with a new player.
    final second = _player(resume);
    await second.open(clip.path);
    await _waitFor(second.position, (p) => p >= _savedAt);

    // Assert
    expect(second.position.value, greaterThanOrEqualTo(_savedAt));
    await second.dispose();
  });

  test('resume disabled does not restore the saved position', () async {
    // Arrange: save a position with resume on.
    final saving = MpvResumeOptions(watchLaterDir: watchLater.path);
    final first = _player(saving);
    await first.open(clip.path);
    await _waitFor(first.duration, (d) => d > Duration.zero);
    await first.seek(_savedAt, exact: true);
    await _waitFor(first.position, (p) => p >= _savedAt);
    await first.dispose();

    // Act: reopen with resume-playback turned off.
    final disabled = _player(
      MpvResumeOptions(enabled: false, watchLaterDir: watchLater.path),
    );
    await disabled.open(clip.path);
    await _waitFor(disabled.duration, (d) => d > Duration.zero);

    // Assert: playback starts near the beginning, not at the saved position.
    expect(disabled.position.value, lessThan(_savedAt));
    await disabled.dispose();
  });

  test('raw options override typed resume settings', () async {
    // Arrange: typed settings say check-mtime off, the raw option says on.
    final player = Player(
      resume: MpvResumeOptions(
        checkMtime: false,
        watchLaterDir: watchLater.path,
      ),
      options: const {
        'vo': 'null',
        'ao': 'null',
        'resume-playback-check-mtime': 'yes',
      },
    );

    // Assert: the raw value wins; the typed value still applies elsewhere.
    expect(player.mpv.getProperty('resume-playback-check-mtime'), isTrue);
    expect(player.mpv.getProperty('save-position-on-quit'), isTrue);
    expect(player.mpv.getProperty('watch-later-dir'), watchLater.path);
    await player.dispose();
  });
}
