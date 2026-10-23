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

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

Mpv _createMpv() => Mpv.create(
  options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes', 'terminal': 'no'},
);

Player _createPlayer() => Player(
  options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes'},
);

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
  runZonedGuarded<void>(
    () {
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
    },
    (Object error, StackTrace stack) => zoneErrors.add(error),
  );
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
          () =>
              firstSawValue &&
              secondSawValue &&
              _seen(zoneErrors, sentinel),
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
                firstSawValue &&
                secondSawValue &&
                _seen(zoneErrors, sentinel),
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
}
