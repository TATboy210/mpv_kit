// Failure-path regression tests: throwing listeners, dispose hooks and
// stream sources.
//
// The listener tests pin the behaviour of Dart's synchronous broadcast
// controllers: a throwing listener is reported to the zone's error handler
// while `add` returns normally, so the drain continues and every later
// listener still receives the value. `runZonedGuarded` captures those escaped
// listener errors; failures of the guarded body itself are rethrown so they
// fail the test instead of being mistaken for the injected error.
//
// Requires libmpv: set MPV_KIT_LIBMPV_PATH or have it on the loader path.
@TestOn('vm')
@Tags(['failure-injection'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

/// Whether the loaded libmpv exports the mpv_kit stream bridge (patch 0006).
///
/// Stock builds do not; CI builds the patched libmpv, so the source-I/O tests
/// run there. A missing library still fails loudly — this only guards the
/// missing *patch*, and only with an explicit skip reason.
final bool _streamBridgeAvailable = MpvLibrary.open().library.providesSymbol(
  'mpv_kit_stream_add',
);

/// Skips the current test when the bridge is unavailable; returns true then.
bool _skipWithoutStreamBridge() {
  if (_streamBridgeAvailable) return false;
  if (Platform.environment['MPV_KIT_REQUIRE_LIBMPV'] != null) {
    fail('the stream bridge is required by CI (MPV_KIT_REQUIRE_LIBMPV) but '
        'this libmpv lacks mpv_kit patch 0006 — the wrong library loaded');
  }
  markTestSkipped(
    'MPV_KIT_STREAM_BRIDGE unavailable: this libmpv has no mpv_kit stream '
    'bridge (mpv_kit patch 0006); run against the patched build (CI does)',
  );
  return true;
}

/// A source whose read always throws, with an unknown (live) size.
///
/// [readAttempts] proves the bridge actually called [read] before the test
/// accepts the reported playback error.
final class _ThrowingReadSource implements MpvStreamSource {
  int readAttempts = 0;

  @override
  int? get size => null;

  @override
  FutureOr<Uint8List> read(int maxBytes) {
    readAttempts++;
    throw StateError('read boom');
  }

  @override
  int seek(int offset) => throw UnsupportedError('not seekable');

  @override
  void close() {}
}

/// A source whose seek always throws while serving a seekable in-memory WAV.
///
/// mpv's demuxer has to read real container bytes before it will issue a seek,
/// so the source is backed by a valid WAV rather than an immediate EOF.
/// [readAttempts] and [seekAttempts] prove both bridge handlers ran.
final class _ThrowingSeekSource implements MpvStreamSource {
  _ThrowingSeekSource(this._bytes);

  final Uint8List _bytes;
  int readAttempts = 0;
  int seekAttempts = 0;
  int _position = 0;

  @override
  int? get size => _bytes.length;

  @override
  FutureOr<Uint8List> read(int maxBytes) {
    readAttempts++;
    final remaining = _bytes.length - _position;
    if (remaining <= 0) return Uint8List(0);
    final n = math.min(maxBytes, remaining);
    final chunk = Uint8List.sublistView(_bytes, _position, _position + n);
    _position += n;
    return chunk;
  }

  @override
  FutureOr<int> seek(int offset) {
    seekAttempts++;
    throw StateError('seek boom');
  }

  @override
  void close() {}
}

/// Builds [seconds] of silent 8 kHz mono 16-bit PCM WAV bytes in memory.
///
/// Mirrors `player_test.dart`'s `_writeSilentWav` header shape without touching
/// the filesystem: an exact, index-free source lets the demuxer seek for real.
Uint8List _silentWavBytes({int seconds = 3}) {
  const rate = 8000, bytesPerSample = 2, headerBytes = 44;
  final dataBytes = seconds * rate * bytesPerSample;
  final b = ByteData(headerBytes + dataBytes);
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
  return b.buffer.asUint8List();
}

/// A source whose close always throws, recording how often each call ran.
final class _ThrowingCloseSource implements MpvStreamSource {
  _ThrowingCloseSource({this.blockReads = false});

  /// When true, reads never answer so the stream stays open until shutdown.
  final bool blockReads;
  int readAttempts = 0;
  int closeAttempts = 0;

  @override
  int? get size => null;

  @override
  FutureOr<Uint8List> read(int maxBytes) {
    readAttempts++;
    return blockReads ? Completer<Uint8List>().future : Uint8List(0);
  }

  @override
  int seek(int offset) => throw UnsupportedError('not seekable');

  @override
  FutureOr<void> close() {
    closeAttempts++;
    throw StateError('close boom');
  }
}

Mpv _createMpv() => Mpv.create(
  options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes', 'terminal': 'no'},
);

Player _createPlayer() =>
    Player(options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes'});

/// Runs [body] inside a guarded error zone.
///
/// A listener throwing from a synchronous broadcast controller does not make
/// `controller.add` throw; the error is delivered to the zone's error handler.
/// Those errors are appended to [zoneErrors]. An error from [body] itself (a
/// failed expectation, a timeout) is rethrown to the caller so it fails the
/// test normally.
Future<void> _guarded(
  List<Object> zoneErrors,
  Future<void> Function() body,
) async {
  final done = Completer<void>();
  Object? bodyError;
  StackTrace? bodyStack;
  runZonedGuarded<void>(() {
    body().then<void>(
      (_) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace stack) {
        bodyError = error;
        bodyStack = stack;
        if (!done.isCompleted) done.complete();
      },
    );
  }, (Object error, StackTrace stack) => zoneErrors.add(error));
  await done.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => fail('guarded body did not finish within 20 s'),
  );
  if (bodyError != null) {
    // Outside the guarded zone: a body assertion must fail the test rather
    // than be swallowed by the listener-error collector.
    Error.throwWithStackTrace(bodyError!, bodyStack!);
  }
}

/// Polls [predicate] until it holds, failing after [timeout].
Future<void> _waitFor(
  String what,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

bool _seen(List<Object> zoneErrors, Object sentinel) =>
    zoneErrors.any((error) => identical(error, sentinel));

void main() {
  test('throwing observer listener does not stop another observer', () async {
    final mpv = _createMpv();
    addTearDown(mpv.dispose);
    final sentinel = StateError('observer listener boom');
    final zoneErrors = <Object>[];
    var firstSawValue = false;
    var secondSawValue = false;
    await _guarded(zoneErrors, () async {
      final first = mpv.observeProperty('volume').listen((value) {
        if (value == 33.0) {
          firstSawValue = true;
          throw sentinel;
        }
      });
      final second = mpv.observeProperty('volume').listen((value) {
        if (value == 33.0) secondSawValue = true;
      });
      try {
        mpv.setProperty('volume', 33.0);
        await _waitFor(
          'both volume observers to see 33.0 and the throw to surface',
          () => firstSawValue && secondSawValue && _seen(zoneErrors, sentinel),
        );
      } finally {
        await first.cancel();
        await second.cancel();
      }
    });
    expect(secondSawValue, isTrue, reason: 'the second observer got 33.0');
    expect(zoneErrors, contains(same(sentinel)));
  });

  test('throwing events listener does not stop observers', () async {
    final mpv = _createMpv();
    addTearDown(mpv.dispose);
    final sentinel = StateError('events listener boom');
    final zoneErrors = <Object>[];
    var eventsListenerSawEvent = false;
    var observerSawValue = false;
    await _guarded(zoneErrors, () async {
      final events = mpv.events.listen((event) {
        if (event is PropertyChangeEvent) {
          eventsListenerSawEvent = true;
          throw sentinel;
        }
      });
      final observer = mpv.observeProperty('volume').listen((value) {
        if (value == 44.0) observerSawValue = true;
      });
      try {
        mpv.setProperty('volume', 44.0);
        await _waitFor(
          'the observer to see 44.0 and the events throw to surface',
          () =>
              eventsListenerSawEvent &&
              observerSawValue &&
              _seen(zoneErrors, sentinel),
        );
      } finally {
        await events.cancel();
        await observer.cancel();
      }
    });
    expect(observerSawValue, isTrue, reason: 'the observer got 44.0');
    expect(zoneErrors, contains(same(sentinel)));
  });

  test(
    'throwing Player state listener does not stop other listeners',
    () async {
      final player = _createPlayer();
      addTearDown(player.dispose);
      final sentinel = StateError('state listener boom');
      final zoneErrors = <Object>[];
      var firstSawValue = false;
      var secondSawValue = false;
      await _guarded(zoneErrors, () async {
        final first = player.volume.stream.listen((value) {
          if (value == 55.0) {
            firstSawValue = true;
            throw sentinel;
          }
        });
        final second = player.volume.stream.listen((value) {
          if (value == 55.0) secondSawValue = true;
        });
        try {
          player.setVolume(55);
          await _waitFor(
            'the second volume listener to see 55.0 after the first threw',
            () =>
                firstSawValue && secondSawValue && _seen(zoneErrors, sentinel),
          );
        } finally {
          await first.cancel();
          await second.cancel();
        }
      });
      expect(secondSawValue, isTrue, reason: 'the second listener got 55.0');
      expect(zoneErrors, contains(same(sentinel)));
    },
  );

  test('throwing dispose hook does not skip later hooks or the core', () async {
    final player = _createPlayer();
    addTearDown(player.dispose);
    final sentinel = StateError('dispose hook boom');
    var laterHookRan = false;
    player.addDisposeHook(() async {
      throw sentinel;
    });
    player.addDisposeHook(() async {
      laterHookRan = true;
    });
    await expectLater(player.dispose(), throwsA(same(sentinel)));
    expect(laterHookRan, isTrue, reason: 'the second hook still ran');
    expect(player.mpv.isDisposed, isTrue);
  });

  test('a source whose read throws reports an MpvPlaybackError', () async {
    if (_skipWithoutStreamBridge()) return;
    final player = _createPlayer();
    addTearDown(player.dispose);
    final source = _ThrowingReadSource();
    final zoneErrors = <Object>[];
    await _guarded(zoneErrors, () async {
      player.mpv.registerStreamProtocol(
        'failread',
        (uri) => uri == 'failread://x' ? source : null,
      );
      final entries = <MpvPlaybackError>[];
      final sub = player.errors.listen(entries.add);
      unawaited(player.open('failread://x').catchError((Object _) {}));
      // The demuxer's probe seek also fails on this source (UnsupportedError)
      // and is reported first (OBS-01); wait for the read entry specifically.
      await _waitFor(
        'the read failure to be reported',
        () =>
            entries.any((e) => e.message.contains('stream source read failed')),
      );
      expect(
        source.readAttempts,
        greaterThan(0),
        reason: 'the bridge must have called read before reporting the error',
      );
      // The original exception identity survives (OBS-01): type + message.
      final readEntry = entries
          .firstWhere((e) => e.message.contains('stream source read failed'));
      expect(readEntry.message, contains('StateError'));
      expect(readEntry.message, contains('read boom'));
      expect(readEntry.error, MpvError.generic);
      await player.dispose().timeout(const Duration(seconds: 10));
      await sub.cancel();
    });
    expect(zoneErrors, isEmpty, reason: 'a read throw must stay in the bridge');
  });

  test('a source whose seek throws leaves the open contained', () async {
    if (_skipWithoutStreamBridge()) return;
    final player = _createPlayer();
    addTearDown(player.dispose);
    final source = _ThrowingSeekSource(_silentWavBytes());
    final zoneErrors = <Object>[];
    await _guarded(zoneErrors, () async {
      player.mpv.registerStreamProtocol('failseek', (_) => source);
      // Subscribe before open: mpv's seekability PROBE seek fails on this
      // source and is reported (OBS-01); reports are broadcast without
      // replay, so a later collector would miss it.
      final entries = <MpvPlaybackError>[];
      final sub = player.errors.listen(entries.add);
      // Open without `start`; the seek is issued explicitly after the demuxer
      // has read the WAV, so the bridge's seek handler is provably reached.
      unawaited(player.open('failseek://x').catchError((Object _) {}));
      await _waitFor(
        'the demuxer to read the stream and probe seekability',
        () => source.readAttempts > 0 && source.seekAttempts > 0,
      );
      // Containment is the contract; the error code belongs to Phase 3.
      expect(source.seekAttempts, greaterThan(0));
      // OBS-01: the seek failure itself surfaces with its original identity,
      // while playback continues (no error end-file after the seek entry).
      await _waitFor(
        'the seek failure to be reported',
        () =>
            entries.any((e) => e.message.contains('stream source seek failed')),
      );
      final seekEntry = entries
          .firstWhere((e) => e.message.contains('stream source seek failed'));
      expect(seekEntry.message, contains('StateError'));
      expect(seekEntry.message, contains('seek boom'));
      expect(seekEntry.error, MpvError.generic);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        entries.where((e) => e.error == MpvError.loadingFailed),
        isEmpty,
        reason: 'a failed seek must not end playback',
      );
      await sub.cancel();
      await player.dispose().timeout(const Duration(seconds: 10));
    });
    expect(zoneErrors, isEmpty, reason: 'a seek throw must stay in the bridge');
  });

  test('a close failure during dispose is reported before the stream closes',
      () async {
    if (_skipWithoutStreamBridge()) return;
    final player = _createPlayer();
    addTearDown(player.dispose);
    final source = _ThrowingCloseSource(blockReads: true);
    final zoneErrors = <Object>[];
    await _guarded(zoneErrors, () async {
      player.mpv.registerStreamProtocol('failclosedispose', (_) => source);
      final entries = <MpvPlaybackError>[];
      final done = Completer<void>();
      player.errors.listen(entries.add, onDone: done.complete);
      unawaited(player.open('failclosedispose://x').catchError((Object _) {}));
      await _waitFor(
        'the live source to be read',
        () => source.readAttempts > 0,
      );
      // The shutdown sweep closes the source while Player.errors is still
      // open, so the failure stays observable (OBS-01) before `done`.
      await player.dispose().timeout(const Duration(seconds: 10));
      await done.future.timeout(const Duration(seconds: 5));
      expect(
        entries.any((e) => e.message.contains('stream source close failed')),
        isTrue,
        reason: 'the shutdown-sweep close failure stays observable',
      );
      expect(player.mpv.isDisposed, isTrue);
    });
    expect(zoneErrors, isEmpty);
  });

  test('a source whose open throws surfaces the original error on '
      'Player.errors', () async {
    if (_skipWithoutStreamBridge()) return;
    final player = _createPlayer();
    addTearDown(player.dispose);
    final zoneErrors = <Object>[];
    await _guarded(zoneErrors, () async {
      player.mpv.registerStreamProtocol('failopen', (uri) {
        if (uri == 'failopen://x') throw StateError('open boom');
        return null;
      });
      final entries = <MpvPlaybackError>[];
      final sub = player.errors.listen(entries.add);
      unawaited(player.open('failopen://x').catchError((Object _) {}));
      await _waitFor(
        'the open failure to be reported',
        () =>
            entries.any((e) => e.message.contains('stream source open failed')),
      );
      final sourceLevel = entries
          .firstWhere((e) => e.message.contains('stream source open failed'));
      expect(sourceLevel.error, MpvError.loadingFailed);
      expect(sourceLevel.message, contains('StateError'));
      expect(sourceLevel.message, contains('open boom'));
      // Playback still ends with an explicit error (the END_FILE entry).
      await _waitFor(
        'the playback-level end-file error',
        () => entries.any((e) =>
            e.error == MpvError.loadingFailed &&
            !e.message.contains('stream source')),
      );
      await sub.cancel();
      await player.dispose().timeout(const Duration(seconds: 10));
    });
    expect(zoneErrors, isEmpty, reason: 'an open throw must stay in the bridge');
  });

  test('a source whose close throws is contained on every close path', () async {
    if (_skipWithoutStreamBridge()) return;

    // `_opClose`: mpv releases a stream it has opened.
    final eofSource = _ThrowingCloseSource();
    final player = _createPlayer();
    addTearDown(player.dispose);
    player.mpv.registerStreamProtocol('failcloseeof', (_) => eofSource);
    final firstZoneErrors = <Object>[];
    await _guarded(firstZoneErrors, () async {
      unawaited(player.open('failcloseeof://x').catchError((Object _) {}));
      await _waitFor(
        'the EOF source to be read',
        () => eofSource.readAttempts > 0,
      );
      try {
        player.mpv.command(['stop']);
      } on MpvException {
        // The stream may already have failed and unloaded itself.
      }
      await _waitFor(
        'mpv to close the stream (_opClose)',
        () => eofSource.closeAttempts > 0,
      );

      // `shutdown()` sweep, also reached through `StreamBridge.close()`:
      // a live source still registered when dispose runs.
      final liveSource = _ThrowingCloseSource(blockReads: true);
      player.mpv.registerStreamProtocol('failcloselive', (_) => liveSource);
      unawaited(player.open('failcloselive://x').catchError((Object _) {}));
      await _waitFor(
        'the live source to be read',
        () => liveSource.readAttempts > 0,
      );
      await player.dispose().timeout(const Duration(seconds: 10));
      expect(liveSource.closeAttempts, greaterThan(0));
      expect(player.mpv.isDisposed, isTrue);
    });
    expect(
      firstZoneErrors,
      isEmpty,
      reason: 'a throwing close must never become an uncaught async error',
    );

    // `_handleOpen`'s shutdown branch: the opener is still pending when
    // dispose begins, so the source it later returns is closed after shutdown.
    final pendingPlayer = _createPlayer();
    addTearDown(pendingPlayer.dispose);
    final opener = Completer<MpvStreamSource?>();
    var openerCalled = false;
    pendingPlayer.mpv.registerStreamProtocol('failcloseopen', (_) {
      openerCalled = true;
      return opener.future;
    });
    final secondZoneErrors = <Object>[];
    await _guarded(secondZoneErrors, () async {
      unawaited(
        pendingPlayer.open('failcloseopen://x').catchError((Object _) {}),
      );
      await _waitFor('the pending opener to be called', () => openerCalled);
      await pendingPlayer.dispose().timeout(const Duration(seconds: 10));
      final pendingSource = _ThrowingCloseSource();
      opener.complete(pendingSource);
      await _waitFor(
        'the abandoned open to close its source',
        () => pendingSource.closeAttempts > 0,
      );
    });
    expect(
      secondZoneErrors,
      isEmpty,
      reason: 'the unawaited _handleOpen must contain the throwing close',
    );
  });
}
