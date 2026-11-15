// Unit tests of the pre-registered soak memory rule (VER-04, Phase 17).
// Written before any measured run; the thresholds must not change afterwards.
library;

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/soak_memory.dart';

/// 11 checkpoints, the value at each index given by [at].
List<double> _series(double Function(int i) at) => [
  for (var i = 0; i < soakCheckpointCount; i++) at(i),
];

void main() {
  group('soakMemoryVerdict', () {
    test('plateau within +-2 MiB is flat', () {
      final result = soakMemoryVerdict(
        _series((i) => 500 + (i.isEven ? 2 : -2)),
      );
      expect(result.verdict, SoakMemoryVerdict.flat);
    });

    test('warm-up in the first five checkpoints then plateau is flat', () {
      final result = soakMemoryVerdict(
        _series((i) => i < 5 ? 400 + i * 20 : 480),
      );
      expect(result.verdict, SoakMemoryVerdict.flat);
      expect(result.lateMiB, 0);
    });

    test('a 1 MiB per round leak (+10 per checkpoint) is growth', () {
      final result = soakMemoryVerdict(_series((i) => 400 + i * 10));
      expect(result.verdict, SoakMemoryVerdict.growth);
      expect(result.lateMiB, 40);
    });

    test('a 0.5 MiB per round leak (+5 per checkpoint) is growth', () {
      final result = soakMemoryVerdict(_series((i) => 400 + i * 5));
      expect(result.verdict, SoakMemoryVerdict.growth);
      expect(result.lateMiB, 20);
      expect(result.tailIncreasing, isTrue);
    });

    test('alternating +-10 MiB noise is flat', () {
      final result = soakMemoryVerdict(
        _series((i) => 500 + (i.isEven ? 10 : -10)),
      );
      expect(result.verdict, SoakMemoryVerdict.flat);
      expect(result.tailIncreasing, isFalse);
    });

    test('a small drift of 1 MiB per checkpoint is flat', () {
      final result = soakMemoryVerdict(_series((i) => 500 + i * 1));
      expect(result.verdict, SoakMemoryVerdict.flat);
      expect(result.lateMiB, 4);
      expect(result.tailIncreasing, isTrue);
    });

    test('ten checkpoints are insufficient, never flat', () {
      final result = soakMemoryVerdict([
        for (var i = 0; i < soakCheckpointCount - 1; i++) 500.0,
      ]);
      expect(result.verdict, SoakMemoryVerdict.insufficient);
      expect(result.lateMiB, isNull);
    });

    test('an empty list is insufficient', () {
      expect(
        soakMemoryVerdict(const []).verdict,
        SoakMemoryVerdict.insufficient,
      );
    });

    test('a late growth just above 32 MiB without a steady tail is growth', () {
      // c6 = 500, c10 = 532.5; the middle steps are flat, so only the
      // absolute limit can fire.
      final values = _series((i) => i == 10 ? 532.5 : 500);
      final result = soakMemoryVerdict(values);
      expect(result.verdict, SoakMemoryVerdict.growth);
      expect(result.tailIncreasing, isFalse);
    });

    test('a late growth of exactly 32 MiB without a steady tail is flat', () {
      final values = _series((i) => i == 10 ? 532 : 500);
      expect(soakMemoryVerdict(values).verdict, SoakMemoryVerdict.flat);
    });

    test('a steady tail of exactly 8 MiB is flat, 8.5 MiB is growth', () {
      // Steps of 2 MiB: late = 8 (not above the drift limit).
      expect(
        soakMemoryVerdict(
          _series((i) => i < 6 ? 500 : 500 + (i - 6) * 2),
        ).verdict,
        SoakMemoryVerdict.flat,
      );
      // Steps of 2.125 MiB: late = 8.5.
      expect(
        soakMemoryVerdict(
          _series((i) => i < 6 ? 500 : 500 + (i - 6) * 2.125),
        ).verdict,
        SoakMemoryVerdict.growth,
      );
    });

    test('with more than 11 values the last 11 are judged', () {
      final leaking = [for (var i = 0; i < 11; i++) 400.0 + i * 10];
      final result = soakMemoryVerdict([9999, ...leaking]);
      expect(result.verdict, SoakMemoryVerdict.growth);
      expect(result.lateMiB, 40);
    });
  });

  test('the registered constants', () {
    // Pre-registered values; a change after a measured run is forbidden.
    expect(soakCheckpointCount, 11);
    expect(soakLateGrowthLimitMiB, 32);
    expect(soakTailStepMiB, 1);
    expect(soakTailDriftMiB, 8);
  });
}
