// 1000 create/dispose cycles: every Player stream closes and RSS stays bounded.
//
// `ProcessInfo.currentRss` is process-wide, so this soak is only meaningful
// when no other suite shares the process. `dart_test.yaml` skips the
// `lifecycle` tag by default, which keeps plain `dart test` and the coverage
// step from running it alongside another suite; it runs alone, explicitly:
//
//   dart test -t lifecycle --run-skipped
//
// Requires libmpv: set MPV_KIT_LIBMPV_PATH or have it on the loader path.
@TestOn('vm')
@Tags(['lifecycle'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

/// One create/dispose cycle that proves every owned stream reaches `done`.
Future<void> _cycle() async {
  final player = Player(
    options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes'},
  );
  final done = <Completer<void>>[];
  void track(Stream<Object?> stream) {
    final completer = Completer<void>();
    done.add(completer);
    stream.listen(
      null,
      onError: (Object error, StackTrace stack) {},
      onDone: completer.complete,
    );
  }

  for (final stream in player.stateStreamsForTesting) {
    track(stream);
  }
  track(player.errors);
  track(player.logs);

  await player.dispose();
  expect(player.mpv.isDisposed, isTrue);
  // Every tracked controller must emit `done`; the dispose call closes them,
  // so this is a closure check rather than a timeout in the normal case.
  await Future.wait(
    done.map((completer) => completer.future),
  ).timeout(const Duration(seconds: 5));
}

void main() {
  test(
    '1000 create/dispose cycles close every stream and keep RSS bounded',
    () async {
      // Warm up so the baseline is past one-time JIT and allocator growth; the
      // measured delta then reflects only the repeated lifecycle itself.
      for (var i = 0; i < 20; i++) {
        await _cycle();
      }
      final baseline = ProcessInfo.currentRss;
      for (var i = 0; i < 1000; i++) {
        await _cycle();
      }
      final growth = ProcessInfo.currentRss - baseline;
      expect(
        growth,
        lessThan(64 * 1024 * 1024),
        reason:
            'RSS grew by ${(growth / (1024 * 1024)).toStringAsFixed(1)} MiB '
            'over 1000 create/dispose cycles (bound: 64 MiB)',
      );
    },
  );
}
