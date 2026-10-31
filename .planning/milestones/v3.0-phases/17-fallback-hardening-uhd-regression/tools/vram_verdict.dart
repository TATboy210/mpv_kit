// Dedicated-GPU-memory verdict of one RTX soak run (VER-04, Phase 17).
//
//   dart vram_verdict.dart <vram.csv> <run.log> <run>
//   dart vram_verdict.dart --self-test
//
// Joins the SOAK-CHECKPOINT lines of backend_soak_test.dart (round, utc) with
// the 1 s samples of vram_sample.ps1: for each checkpoint the nearest sample
// that has a pid (the example process existed) within 2 s supplies the
// process' dedicated memory in MiB. The decision itself is NOT implemented
// here: soakMemoryVerdict from example/integration_test/soak_memory.dart (the
// rule registered before any measured run) is imported, so RSS on hosted
// runners and VRAM on the RTX share one implementation.
//
// Output (one line):
//   vram run=<run> checkpoints=<c0,...,cN> late_mib=<x|n/a>
//        tail_increasing=<yes|no> verdict=<flat|growth|insufficient>
//        adapter_first_mib=<x|n/a> adapter_last_mib=<x|n/a>
// Exit codes: 0 flat, 1 growth, 2 insufficient (also unreadable inputs).
//
// Read-only: nothing is written or deleted.
import 'dart:convert';
import 'dart:io';

import '../../../../example/integration_test/soak_memory.dart';

/// Largest distance between a checkpoint and the sample that stands for it.
const Duration _maxSampleGap = Duration(seconds: 2);

/// One row of the sampler CSV.
final class _Sample {
  const _Sample({
    required this.utc,
    required this.pid,
    required this.processMib,
    required this.adapterMib,
  });

  final DateTime utc;

  /// Empty when the example process did not exist at that moment.
  final String pid;

  /// Null without a pid.
  final double? processMib;

  final double? adapterMib;
}

/// One SOAK-CHECKPOINT line.
final class _Checkpoint {
  const _Checkpoint({required this.round, required this.utc});

  final int round;
  final DateTime utc;
}

/// Rows of [csv] (header skipped, malformed rows ignored).
List<_Sample> parseCsv(String csv) {
  final samples = <_Sample>[];
  for (final line in const LineSplitter().convert(csv).skip(1)) {
    final f = line.split(',');
    if (f.length < 4) continue;
    final utc = DateTime.tryParse(f[0]);
    if (utc == null) continue;
    samples.add(
      _Sample(
        utc: utc.toUtc(),
        pid: f[1],
        processMib: double.tryParse(f[2]),
        adapterMib: double.tryParse(f[3]),
      ),
    );
  }
  return samples;
}

/// SOAK-CHECKPOINT lines of [log] (a line may carry a leading timestamp).
List<_Checkpoint> parseCheckpoints(String log) {
  final pattern = RegExp(r'SOAK-CHECKPOINT (\{.*\})');
  final checkpoints = <_Checkpoint>[];
  for (final line in const LineSplitter().convert(log)) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    final json = jsonDecode(match.group(1)!);
    if (json is! Map<String, Object?>) continue;
    final round = json['round'];
    final utc = DateTime.tryParse('${json['utc']}');
    if (round is int && utc != null) {
      checkpoints.add(_Checkpoint(round: round, utc: utc.toUtc()));
    }
  }
  return checkpoints;
}

/// Process memory at each checkpoint; a checkpoint without a sample with a pid
/// within [_maxSampleGap] is dropped (and so leads to `insufficient`).
List<double> checkpointValues(
  List<_Checkpoint> checkpoints,
  List<_Sample> samples,
) {
  final usable = samples
      .where((s) => s.pid.isNotEmpty && s.processMib != null)
      .toList();
  final values = <double>[];
  for (final checkpoint in checkpoints) {
    _Sample? nearest;
    var best = _maxSampleGap + const Duration(milliseconds: 1);
    for (final sample in usable) {
      final gap = sample.utc.difference(checkpoint.utc).abs();
      if (gap < best) {
        best = gap;
        nearest = sample;
      }
    }
    if (nearest != null && best <= _maxSampleGap) {
      values.add(nearest.processMib!);
    }
  }
  return values;
}

String _mib(double? value) => value == null ? 'n/a' : value.toStringAsFixed(1);

/// The report line and the verdict for one run.
(String, SoakMemoryVerdict) report(String run, String csv, String log) {
  final samples = parseCsv(csv);
  final values = checkpointValues(parseCheckpoints(log), samples);
  final result = soakMemoryVerdict(values);
  final line =
      'vram run=$run checkpoints=${values.map(_mib).join(',')} '
      'late_mib=${_mib(result.lateMiB)} '
      'tail_increasing=${result.tailIncreasing ? 'yes' : 'no'} '
      'verdict=${result.verdict.name} '
      'adapter_first_mib=${_mib(samples.isEmpty ? null : samples.first.adapterMib)} '
      'adapter_last_mib=${_mib(samples.isEmpty ? null : samples.last.adapterMib)}';
  return (line, result.verdict);
}

int _exitFor(SoakMemoryVerdict verdict) => switch (verdict) {
  SoakMemoryVerdict.flat => 0,
  SoakMemoryVerdict.growth => 1,
  SoakMemoryVerdict.insufficient => 2,
};

// --- self-test ---------------------------------------------------------------

/// Synthetic run: 11 checkpoints 5 s apart, 1 s samples around them whose
/// process memory at checkpoint index i is [at] (i).
(String csv, String log) _synthetic(
  double Function(int i) at, {
  int sampled = soakCheckpointCount,
}) {
  final base = DateTime.utc(2026, 1, 1, 12);
  final csv = StringBuffer(
    'utc,pid,process_dedicated_mib,adapter_dedicated_mib,foreground\n',
  );
  final log = StringBuffer();
  for (var i = 0; i < soakCheckpointCount; i++) {
    final when = base.add(Duration(seconds: 5 * i));
    log.writeln(
      '${when.toIso8601String()} SOAK-CHECKPOINT '
      '${jsonEncode({'schema': 'soak-1', 'round': i * 10, 'utc': when.toIso8601String()})}',
    );
    // A sample a second before and one a second after: the nearer wins, both
    // carry the same value so the pick is unambiguous. Checkpoints from
    // [sampled] on get no sample (the sampler died).
    if (i >= sampled) continue;
    for (final offset in [-1, 1]) {
      final t = when.add(Duration(seconds: offset));
      csv.writeln('${t.toIso8601String()},4242,${at(i)},900.0,mpv_kit_example');
    }
  }
  return (csv.toString(), log.toString());
}

int _selfTest() {
  var failed = false;
  void expectVerdict(
    String name,
    (String, String) data,
    SoakMemoryVerdict want,
  ) {
    final (_, verdict) = report(name, data.$1, data.$2);
    if (verdict != want) {
      stderr.writeln('self-test $name: want ${want.name}, got ${verdict.name}');
      failed = true;
    }
  }

  expectVerdict(
    'flat',
    _synthetic((i) => 800.0 + (i.isEven ? 2 : -2)),
    SoakMemoryVerdict.flat,
  );
  expectVerdict(
    'leak',
    _synthetic((i) => 800.0 + i * 10),
    SoakMemoryVerdict.growth,
  );
  // Sampler died before the last checkpoints: no sample with a pid near them.
  final (csv, log) = _synthetic((i) => 800.0);
  final cut = csv
      .split('\n')
      .where(
        (l) =>
            !l.startsWith('2026-01-01T12:00:4') &&
            !l.startsWith('2026-01-01T12:00:5'),
      )
      .join('\n');
  expectVerdict('insufficient', (cut, log), SoakMemoryVerdict.insufficient);
  if (failed) return 1;
  print('VRAM-VERDICT self-test ok');
  return 0;
}

void main(List<String> args) => exit(_run(args));

/// Runs the tool and returns the process exit code.
int _run(List<String> args) {
  if (args.length == 1 && args.first == '--self-test') return _selfTest();
  if (args.length != 3) {
    stderr.writeln('usage: vram_verdict.dart <csv> <log> <run> | --self-test');
    return 2;
  }
  final String csv;
  final String log;
  try {
    csv = File(args[0]).readAsStringSync();
    log = File(args[1]).readAsStringSync();
  } on FileSystemException catch (e) {
    stderr.writeln('vram_verdict: cannot read input: ${e.message} ${e.path}');
    return 2;
  }
  final (line, verdict) = report(args[2], csv, log);
  print(line);
  return _exitFor(verdict);
}
