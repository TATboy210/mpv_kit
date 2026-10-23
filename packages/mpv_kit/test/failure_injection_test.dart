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
  markTestSkipped(
    'MPV_KIT_STREAM_BRIDGE unavailable: this libmpv has no mpv_kit stream '
    'bridge (mpv_kit patch 0006); run against the patched build (CI does)',
  );
  return true;
}

/// A source whose read always throws, with an unknown (live) size.
final class _ThrowingReadSource implements MpvStreamSource {
  @override
  int? get size => null;

  @override
  FutureOr<Uint8List> read(int maxBytes) => throw StateError('read boom');

  @override
  int seek(int offset) => throw UnsupportedError('not seekable');

  @override
  void close() {}
}

/// A source whose seek always throws; reads report end of stream.
final class _ThrowingSeekSource implements MpvStreamSource {
  @override
  int? get size => null;

  @override
  FutureOr<Uint8List> read(int maxBytes) => Uint8List(0);

  @override
  FutureOr<int> seek(int offset) => throw StateError('seek boom');

  @override
  void close() {}
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
    final zoneErrors = <Object>[];
    await _guarded(zoneErrors, () async {
      player.mpv.registerStreamProtocol(
        'failread',
        (uri) => uri == 'failread://x' ? _ThrowingReadSource() : null,
      );
      final error = player.errors.first.timeout(const Duration(seconds: 10));
      unawaited(player.open('failread://x').catchError((Object _) {}));
      final playbackError = await error;
      expect(playbackError.message, isNotEmpty);
      await player.dispose().timeout(const Duration(seconds: 10));
    });
    expect(zoneErrors, isEmpty, reason: 'a read throw must stay in the bridge');
  });

  test('a source whose seek throws leaves the open contained', () async {
    if (_skipWithoutStreamBridge()) return;
    final player = _createPlayer();
    addTearDown(player.dispose);
    final zoneErrors = <Object>[];
    await _guarded(zoneErrors, () async {
      player.mpv.registerStreamProtocol(
        'failseek',
        (_) => _ThrowingSeekSource(),
      );
      // `start` makes mpv seek during the open, which calls source.seek.
      try {
        await player
            .open('failseek://x', start: const Duration(seconds: 1))
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        rethrow;
      } on Object {
        // Failing the open cleanly is acceptable; seek-error reporting is
        // Phase 3 (OBS-01), so no playback error is asserted here.
      }
      // Provoke another seek in case the opening one was short-circuited.
      try {
        await player
            .seek(const Duration(seconds: 2))
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        rethrow;
      } on Object {
        // Containment is the contract, not the error code.
      }
      await player.dispose().timeout(const Duration(seconds: 10));
    });
    expect(zoneErrors, isEmpty, reason: 'a seek throw must stay in the bridge');
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
