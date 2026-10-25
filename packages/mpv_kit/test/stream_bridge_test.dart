// Dart-served custom protocols (mpv_kit stream bridge, patch 0006).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mpv_kit/mpv_kit.dart';
import 'package:mpv_kit/src/core/stream_bridge.dart' show StreamBridge;
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

/// Reports a size it cannot compute, like a source whose header is corrupt.
final class _ThrowingSizeSource implements MpvStreamSource {
  var closes = 0;

  @override
  int? get size => throw StateError('size boom');
  @override
  Uint8List read(int maxBytes) => Uint8List(0);
  @override
  int seek(int offset) => throw UnsupportedError('live');
  @override
  void close() => closes++;
}

/// Counts closes of a source that arrives after its open timed out.
final class _LateSource implements MpvStreamSource {
  var closes = 0;

  @override
  int? get size => null;
  @override
  Uint8List read(int maxBytes) => Uint8List(0);
  @override
  int seek(int offset) => throw UnsupportedError('live');
  @override
  void close() => closes++;
}

/// Whether the loaded libmpv exports the mpv_kit stream bridge (patch 0006).
final bool _bridgeAvailable = MpvLibrary.open().library.providesSymbol(
  'mpv_kit_stream_add',
);

/// Skips the current test without the bridge (local stock builds); CI sets
/// MPV_KIT_REQUIRE_LIBMPV and runs the patched build, so it fails there.
bool _skipWithoutBridge() {
  if (_bridgeAvailable) return false;
  if (Platform.environment['MPV_KIT_REQUIRE_LIBMPV'] != null) {
    fail('this libmpv lacks the mpv_kit stream bridge (patch 0006)');
  }
  markTestSkipped('this libmpv has no mpv_kit stream bridge (patch 0006)');
  return true;
}

/// Polls [ok] until it holds, failing after 10 s.
Future<void> _poll(String what, bool Function() ok) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ok()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Whether [e] is the playback-level END_FILE failure (not a source report).
bool _endFileFailure(MpvPlaybackError e) =>
    e.error == MpvError.loadingFailed && !e.message.contains('stream source');

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

  test('a source whose size throws fails the load and is closed', () async {
    if (_skipWithoutBridge()) return;
    final source = _ThrowingSizeSource();
    player.mpv.registerStreamProtocol('badsize', (_) => source);
    final entries = <MpvPlaybackError>[];
    final sub = player.errors.listen(entries.add);
    addTearDown(sub.cancel);
    unawaited(player.open('badsize://x').catchError((Object _) {}));
    await _poll(
      'the size failure to be reported',
      () => entries.any((e) => e.message.contains('size boom')),
    );
    expect(
      entries.firstWhere((e) => e.message.contains('size boom')).message,
      contains('stream source open failed'),
    );
    await _poll('the load to fail', () => entries.any(_endFileFailure));
    await _poll('the source to be closed', () => source.closes > 0);
  });

  group('open timeout', () {
    late Duration saved;
    setUp(() {
      saved = StreamBridge.openTimeout;
      // The real 30 s bound would exceed the 10 s waits of these tests.
      StreamBridge.openTimeout = const Duration(milliseconds: 300);
    });
    tearDown(() => StreamBridge.openTimeout = saved);

    test('an opener that never answers fails the load, the next load plays, '
        'and a late source is closed', () async {
      if (_skipWithoutBridge()) return;
      final pending = Completer<MpvStreamSource?>();
      player.mpv.registerStreamProtocol('hang', (_) => pending.future);
      player.mpv.registerStreamProtocol(
        'mem',
        (_) => MpvMemoryStreamSource(png),
      );
      final entries = <MpvPlaybackError>[];
      final sub = player.errors.listen(entries.add);
      addTearDown(sub.cancel);
      unawaited(player.open('hang://x').catchError((Object _) {}));
      await _poll('the hung open to fail', () => entries.any(_endFileFailure));
      expect(
        entries.any((e) => e.message.contains('TimeoutException')),
        isTrue,
        reason: 'the timeout is reported as an open failure',
      );

      await player.open('mem://shot');
      final vp = await _until(player.videoParams, (v) => v != null);
      expect(vp!.width, 320);

      final late = _LateSource();
      pending.complete(late);
      await _poll('the late source to be closed', () => late.closes > 0);
    });
  });

  // Raw invalid UTF-8 cannot reach the bridge through `loadfile` (the URI is
  // a Dart string, always valid UTF-8 on the way in), so the decoder that
  // `_onRequest` uses for OPEN is tested directly.
  test('URI decoding tolerates invalid UTF-8 and never throws', () {
    // "x://", a lone 0xFF, a truncated 2-byte sequence, "(", NUL.
    const bytes = [0x78, 0x3a, 0x2f, 0x2f, 0xff, 0xc3, 0x28, 0x00];
    final p = calloc<Uint8>(bytes.length);
    addTearDown(() => calloc.free(p));
    p.asTypedList(bytes.length).setAll(0, bytes);
    expect(StreamBridge.decodeUri(p.cast<Utf8>()), 'x://\uFFFD\uFFFD(');
    expect(StreamBridge.decodeUri(nullptr), '');
  });
}
