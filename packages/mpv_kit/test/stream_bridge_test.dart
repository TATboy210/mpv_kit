// Dart-served custom protocols (mpv_kit stream bridge, patch 0006).
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

/// Answers every call after a delay, like a network source.
final class _SlowSource implements MpvStreamSource {
  _SlowSource(this._inner);
  final MpvMemoryStreamSource _inner;
  var reads = 0;

  @override
  int get size => _inner.size;

  @override
  Future<Uint8List> read(int maxBytes) async {
    reads++;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return _inner.read(maxBytes);
  }

  @override
  Future<int> seek(int offset) async => _inner.seek(offset);

  @override
  void close() {}
}

/// Never answers reads.
final class _StuckSource implements MpvStreamSource {
  @override
  int? get size => null;
  @override
  Future<Uint8List> read(int maxBytes) => Completer<Uint8List>().future;
  @override
  int seek(int offset) => throw UnsupportedError('live');
  @override
  void close() {}
}

void main() {
  late Player player;
  late Uint8List png;

  setUpAll(() async {
    // A real media file without fixtures: mpv's own screenshot of lavfi.
    final p = Player(options: const {'vo': 'null', 'ao': 'null'});
    final file = '${Directory.systemTemp.path}/mpv_kit_bridge_test.png';
    await p.open(_lavfi);
    await _until(p.position, (pos) => pos > Duration.zero);
    p.pause();
    await p.screenshotToFile(file);
    png = File(file).readAsBytesSync();
    await p.dispose();
  });

  setUp(() => player = Player(options: const {'vo': 'null', 'ao': 'null'}));
  tearDown(() => player.dispose());

  test('plays media served from memory', () async {
    player.mpv.registerStreamProtocol(
      'mem',
      (uri) => uri == 'mem://shot' ? MpvMemoryStreamSource(png) : null,
    );
    await player.open('mem://shot');
    final vp = await _until(player.videoParams, (v) => v != null);
    expect(vp!.width, 320);
  });

  test('asynchronous sources are awaited', () async {
    final source = _SlowSource(MpvMemoryStreamSource(png));
    player.mpv.registerStreamProtocol('slow', (_) => source);
    await player.open('slow://x');
    await _until(player.videoParams, (v) => v != null);
    expect(source.reads, greaterThan(0));
  });

  test('a rejected URI fails like a missing file', () async {
    player.mpv.registerStreamProtocol('none', (_) => null);
    final err = player.errors.first.timeout(const Duration(seconds: 10));
    await player.open('none://x');
    expect((await err).error, MpvError.loadingFailed);
  });

  test('registering a protocol twice fails', () {
    player.mpv.registerStreamProtocol('dup', (_) => null);
    expect(
      () => player.mpv.registerStreamProtocol('dup', (_) => null),
      throwsA(isA<MpvException>()),
    );
  });

  test('dispose does not hang on a source that never answers', () async {
    final p = Player(options: const {'vo': 'null', 'ao': 'null'});
    p.mpv.registerStreamProtocol('stuck', (_) => _StuckSource());
    unawaited(p.open('stuck://x').catchError((Object _) {}));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await p.dispose().timeout(const Duration(seconds: 10));
  });
}
