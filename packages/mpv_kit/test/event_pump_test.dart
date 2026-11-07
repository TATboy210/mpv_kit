// Event pump robustness: bounded drain, reply failure containment and
// batch playlist submission. Real libmpv, headless.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:mpv_kit/src/core/event_decode_hook.dart';
import 'package:test/test.dart';

bool get _libmpvMissing {
  try {
    MpvLibrary.open();
    return false;
  } on Object {
    return true;
  }
}

Mpv _create() => Mpv.create(
  options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes', 'terminal': 'no'},
);

void main() {
  final skip = _libmpvMissing ? 'libmpv not available' : null;

  test(
    'a backlog yields to the event loop before the queue is empty',
    () async {
      final mpv = _create();
      addTearDown(mpv.dispose);
      var count = 0;
      int? timerAt;
      final done = Completer<void>();
      mpv.events.listen((e) {
        if (e is! ClientMessageEvent) return;
        count++;
        if (count == 200) Timer.run(() => timerAt = count);
        if (count >= 600 && !done.isCompleted) done.complete();
      });
      // Queued synchronously, so the drain cannot run between commands: this is
      // the same shape as the queue-overflow test, below the 1000-event limit.
      final self = mpv.clientName;
      for (var i = 0; i < 600; i++) {
        mpv.command(['script-message-to', self, 'flood']);
      }
      await done.future.timeout(const Duration(seconds: 10));
      expect(timerAt, isNotNull);
      expect(
        timerAt,
        lessThan(600),
        reason: 'the drain never yielded to a timer during the backlog',
      );
    },
    skip: skip,
  );

  test('an undecodable reply fails its future instead of hanging', () async {
    final mpv = _create();
    addTearDown(mpv.dispose);
    final cmd = mpv.commandAsync(['expand-text', 'abc']);
    debugEventDecodeFailure = (p) => p.ref.replyUserdata == cmd.id
        ? StateError('injected decode failure')
        : null;
    addTearDown(() => debugEventDecodeFailure = null);
    await expectLater(
      cmd.result,
      throwsA(
        isA<MpvException>().having(
          (e) => e.operation,
          'operation',
          'decode_event',
        ),
      ),
    );
    debugEventDecodeFailure = null;
    // The drain keeps working after the contained failure.
    expect(await mpv.commandAsync(['expand-text', 'abc']).result, isNotNull);
  }, skip: skip);

  test('openPlaylist submits entries before awaiting their replies', () async {
    final player = Player(
      options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes'},
    );
    addTearDown(player.dispose);
    var emissions = 0;
    final sub = player.playlist.stream.listen((_) => emissions++);
    addTearDown(sub.cancel);
    final urls = List<String>.generate(
      32,
      (_) => 'av://lavfi:testsrc2=size=160x90:rate=5:duration=1',
    );
    await player.openPlaylist(urls, play: false);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (player.playlist.value.length != 32 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(player.playlist.value, hasLength(32));
    expect(
      emissions,
      lessThan(16),
      reason: 'the playlist was reparsed once per URL',
    );
  }, skip: skip);
}
