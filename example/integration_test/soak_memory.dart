// Pre-registered memory-plateau rule of the backend soak (VER-04, Phase 17).
//
// The rule is written, and unit-tested (example/test/soak_memory_test.dart),
// BEFORE any measured soak run exists. A memory curve read first and judged
// afterwards cannot tell a leak from noise, so after any measurement none of
// the constants or the decision below may change (VER-04 prohibition). An
// insufficient sample set is never flat.
//
// Pure Dart on purpose (dart: imports only): the same file is imported by
// backend_soak_test.dart (RSS curve on hosted runners) and by the RTX
// session's tools/vram_verdict.dart (dedicated GPU memory curve), so the rule
// has exactly one implementation.
library;

/// Checkpoints per soak: round 0 and every 10th of the 100 rounds.
const int soakCheckpointCount = 11;

/// A late growth (checkpoint 10 minus checkpoint 6, i.e. rounds 60..100)
/// above this many MiB is a leak on its own.
///
/// Why 32: 40 rounds each leaking one 640x360 BGRA texture (the smallest soak
/// size, 0.88 MiB) add up to 35 MiB, so a per-round leak of even the smallest
/// frame exceeds it; the 1280x720 size leaks 3.5 MiB per round. Noise of the
/// allocator and driver caches stays far below it (Phase 12 evidence).
const double soakLateGrowthLimitMiB = 32;

/// Each of the last four checkpoint steps (6->7 .. 9->10) must grow by at
/// least this many MiB for the tail to count as steadily increasing.
const double soakTailStepMiB = 1;

/// A steadily increasing tail is a leak only when the late growth also exceeds
/// this many MiB, so a drift of about 1 MiB per checkpoint is not one.
const double soakTailDriftMiB = 8;

/// Outcome of [soakMemoryVerdict]; the enum name is the wire name used in the
/// `SOAK` and `vram` report lines.
enum SoakMemoryVerdict {
  /// Memory reached a plateau.
  flat,

  /// Memory kept growing in the late checkpoints.
  growth,

  /// Fewer than [soakCheckpointCount] checkpoints; no verdict, never flat.
  insufficient,
}

/// The verdict plus the numbers it was derived from.
final class SoakMemoryResult {
  const SoakMemoryResult({
    required this.verdict,
    required this.lateMiB,
    required this.tailIncreasing,
  });

  /// The decision.
  final SoakMemoryVerdict verdict;

  /// Checkpoint 10 minus checkpoint 6 in MiB; null when insufficient.
  final double? lateMiB;

  /// Whether each of the last four steps grew by at least
  /// [soakTailStepMiB]; false when insufficient.
  final bool tailIncreasing;

  @override
  String toString() =>
      'SoakMemoryResult(${verdict.name}, lateMiB: $lateMiB, '
      'tailIncreasing: $tailIncreasing)';
}

/// Decides whether [checkpointsMiB] (memory at round 0, 10, ... 100, in MiB)
/// is a plateau.
///
/// - fewer than [soakCheckpointCount] values: [SoakMemoryVerdict.insufficient];
///   with more, the last [soakCheckpointCount] are judged.
/// - `lateGrowth = c10 - c6`.
/// - growth iff `lateGrowth > soakLateGrowthLimitMiB`, or the tail is steadily
///   increasing and `lateGrowth > soakTailDriftMiB`; otherwise flat.
///
/// Checkpoints 0..5 are deliberately not part of the decision: the first
/// rounds fill caches (warm-up), the plateau is judged on the second half.
SoakMemoryResult soakMemoryVerdict(List<double> checkpointsMiB) {
  if (checkpointsMiB.length < soakCheckpointCount) {
    return const SoakMemoryResult(
      verdict: SoakMemoryVerdict.insufficient,
      lateMiB: null,
      tailIncreasing: false,
    );
  }
  final c = checkpointsMiB.sublist(checkpointsMiB.length - soakCheckpointCount);
  final lateGrowth = c[10] - c[6];
  var tailIncreasing = true;
  for (var i = 7; i <= 10; i++) {
    if (c[i] - c[i - 1] < soakTailStepMiB) tailIncreasing = false;
  }
  final growth =
      lateGrowth > soakLateGrowthLimitMiB ||
      (tailIncreasing && lateGrowth > soakTailDriftMiB);
  return SoakMemoryResult(
    verdict: growth ? SoakMemoryVerdict.growth : SoakMemoryVerdict.flat,
    lateMiB: lateGrowth,
    tailIncreasing: tailIncreasing,
  );
}
