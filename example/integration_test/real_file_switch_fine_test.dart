// Fine-grained real-file switch probe (Windows, real plugin).
//
// The coarse probe in real_file_switch_test.dart samples pixels every ~100 ms,
// which cannot see a mismatch that lasts a few milliseconds. This probe polls
// instead, with no pixel reads: each sample takes the Texture rect in physical
// pixels (what Flutter lays out) and the native `stats` snapshot (the frame
// size the plugin hands to Flutter, and when that size last changed).
//
// A mismatch is a sample where the Texture rect differs from the frame it is
// drawing: the old frame is stretched or squeezed into the new rect. The probe
// reports, per switch:
//   - rectChangeMs: when the Texture rect first changed
//   - shownChangeMs: when the frame Flutter draws first changed size
//   - skewMs: shownChangeMs - rectChangeMs (positive: the rect moved first)
//   - mismatchMs / maxMismatchMs: total and longest time in mismatch
//
//   $env:MPV_KIT_SWITCH_PORTRAIT = 'D:\...\12370391_2160_3840_60fps.mp4'
//   $env:MPV_KIT_SWITCH_LANDSCAPE = 'D:\...\13349743_1920_1080_25fps.mp4'
//   flutter test integration_test/real_file_switch_fine_test.dart -d windows
//
// Printing is the report channel. Timings are mapped from the native steady
// clock to the Dart clock per sample; the mapping error is about half a call
// round trip (roughly 1 ms).
// ignore_for_file: avoid_print
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

/// Logical size of the probed box, a landscape window.
const _boxWidth = 960.0;
const _boxHeight = 540.0;

/// How long each switch is observed after the open call.
const _observeMs = 2000;

/// Physical pixels of tolerance when comparing the rect with the frame size.
const _tolPx = 2;

const _channel = MethodChannel('mpv_kit_video');

/// One poll: the Texture rect and the native frame snapshot, taken together.
final class _Sample {
  const _Sample({
    required this.tMs,
    required this.rectW,
    required this.rectH,
    required this.shownW,
    required this.shownH,
    required this.shownChangeNs,
    required this.nowNs,
  });

  /// Dart-clock time in ms since the switch started, at the middle of the call.
  final double tMs;

  /// Texture rect, in physical pixels.
  final int rectW;
  final int rectH;

  /// Frame Flutter was handed last (physical pixels).
  final int shownW;
  final int shownH;

  /// Native steady-clock ns when that frame size last changed, and the native
  /// clock at this poll. Their difference maps the change onto [tMs].
  final int shownChangeNs;
  final int nowNs;

  /// Whether the rect and the frame Flutter draws are different sizes.
  bool get mismatched =>
      shownW > 0 &&
      ((rectW - shownW).abs() > _tolPx || (rectH - shownH).abs() > _tolPx);

  /// The frame-size change time on the Dart clock, derived from this poll.
  double get shownChangeMs => tMs - (nowNs - shownChangeNs) / 1e6;
}

/// Measurements for one switch.
final class _SwitchFine {
  const _SwitchFine({
    required this.label,
    required this.samples,
    required this.rectChangeMs,
    required this.shownChangeMs,
    required this.mismatchMs,
    required this.maxMismatchMs,
    required this.mismatchRuns,
    required this.settledMatched,
  });

  final String label;
  final int samples;
  final double? rectChangeMs;
  final double? shownChangeMs;
  final double mismatchMs;
  final double maxMismatchMs;
  final int mismatchRuns;

  /// Whether the last sample matches: the picture settled on its frame.
  final bool settledMatched;

  Map<String, Object?> toJson() => {
    'file': label,
    'samples': samples,
    'rectChangeMs': rectChangeMs?.toStringAsFixed(1),
    'shownChangeMs': shownChangeMs?.toStringAsFixed(1),
    'skewMs': (rectChangeMs == null || shownChangeMs == null)
        ? null
        : (shownChangeMs! - rectChangeMs!).toStringAsFixed(1),
    'mismatchMs': mismatchMs.toStringAsFixed(1),
    'maxMismatchMs': maxMismatchMs.toStringAsFixed(1),
    'mismatchRuns': mismatchRuns,
    'settledMatched': settledMatched,
  };
}

/// Pure analysis of one switch's samples. Kept separate from the polling so it
/// can be checked on its own.
_SwitchFine _analyze(String label, List<_Sample> samples) {
  if (samples.isEmpty) {
    return _SwitchFine(
      label: label,
      samples: 0,
      rectChangeMs: null,
      shownChangeMs: null,
      mismatchMs: 0,
      maxMismatchMs: 0,
      mismatchRuns: 0,
      settledMatched: false,
    );
  }

  // The first rect change: the first sample whose rect differs from the first.
  final first = samples.first;
  double? rectChangeMs;
  for (final s in samples) {
    if (s.rectW != first.rectW || s.rectH != first.rectH) {
      rectChangeMs = s.tMs;
      break;
    }
  }

  // The first frame-size change after the switch started, mapped onto the
  // Dart clock from the poll that observed it.
  double? shownChangeMs;
  for (final s in samples) {
    if (s.shownChangeNs != first.shownChangeNs) {
      shownChangeMs = s.shownChangeMs;
      break;
    }
  }

  // Mismatch runs: from a mismatched sample to the next matched one. The run
  // ends at the matched sample's time, so the run length is an upper bound
  // of one poll interval.
  var mismatchMs = 0.0, maxMismatchMs = 0.0, runs = 0;
  double? runStart;
  for (final s in samples) {
    if (s.mismatched) {
      runStart ??= s.tMs;
    } else if (runStart != null) {
      final length = s.tMs - runStart;
      mismatchMs += length;
      if (length > maxMismatchMs) maxMismatchMs = length;
      runs++;
      runStart = null;
    }
  }
  if (runStart != null) {
    // Still mismatched at the end of the window.
    final length = samples.last.tMs - runStart;
    mismatchMs += length;
    if (length > maxMismatchMs) maxMismatchMs = length;
    runs++;
  }

  return _SwitchFine(
    label: label,
    samples: samples.length,
    rectChangeMs: rectChangeMs,
    shownChangeMs: shownChangeMs,
    mismatchMs: mismatchMs,
    maxMismatchMs: maxMismatchMs,
    mismatchRuns: runs,
    settledMatched: !samples.last.mismatched,
  );
}

/// Opens [path] and polls the rect and the native snapshot for [_observeMs].
Future<_SwitchFine> _measureSwitch({
  required WidgetTester tester,
  required GlobalKey key,
  required Player player,
  required MpvVideoController controller,
  required String path,
  required double dpr,
}) async {
  final clock = Stopwatch()..start();
  await player.open(path);

  final samples = <_Sample>[];
  while (clock.elapsedMilliseconds < _observeMs) {
    final t0 = clock.elapsedMicroseconds;
    final stats = await _channel.invokeMapMethod<String, Object?>('stats', {
      'textureId': controller.textureId,
    });
    final t1 = clock.elapsedMicroseconds;
    final texture = find.byType(Texture);
    if (stats != null && texture.evaluate().isNotEmpty) {
      final size = tester.getSize(texture);
      samples.add(
        _Sample(
          tMs: (t0 + t1) / 2000,
          rectW: (size.width * dpr).round(),
          rectH: (size.height * dpr).round(),
          shownW: stats['shownW']! as int,
          shownH: stats['shownH']! as int,
          shownChangeNs: stats['shownChangeNs']! as int,
          nowNs: stats['nowNs']! as int,
        ),
      );
    }
    // Yield so the frame loop runs; each poll is one channel round trip.
    await Future<void>.delayed(Duration.zero);
  }
  return _analyze(path.split(RegExp(r'[\\/]')).last, samples);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final portrait = Platform.environment['MPV_KIT_SWITCH_PORTRAIT'];
  final landscape = Platform.environment['MPV_KIT_SWITCH_LANDSCAPE'];
  final skipReason = (portrait == null || landscape == null)
      ? 'set MPV_KIT_SWITCH_PORTRAIT and MPV_KIT_SWITCH_LANDSCAPE'
      : (!File(portrait).existsSync() || !File(landscape).existsSync())
      ? 'both sample files must exist'
      : null;
  if (skipReason != null) print('SKIP fine switch probe: $skipReason');

  testWidgets(
    'fine probe: texture rect against the frame Flutter draws',
    (tester) async {
      final key = GlobalKey();
      final mounted = ValueNotifier<MpvVideoController?>(null);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<MpvVideoController?>(
              valueListenable: mounted,
              builder: (context, c, child) => RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: _boxWidth,
                  height: _boxHeight,
                  child: c == null ? null : MpvVideo(controller: c),
                ),
              ),
            ),
          ),
        ),
      );

      final player = Player(
        options: const {
          'ao': 'null',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
        },
      );
      final controller = await MpvVideoController.create(player);

      final results = <_SwitchFine>[];
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      await tester.runAsync(() async {
        mounted.value = controller;
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Cold start first, then landscape <-> portrait, as in the coarse probe.
        final order = [portrait!, landscape!, portrait, landscape];
        for (final path in order) {
          results.add(
            await _measureSwitch(
              tester: tester,
              key: key,
              player: player,
              controller: controller,
              path: path,
              dpr: dpr,
            ),
          );
        }
      });

      print(
        'FINE-SWITCH ${jsonEncode({
          'backend': controller.backend.name,
          'dpr': dpr,
          'switches': [for (final r in results) r.toJson()],
        })}',
      );

      await controller.dispose();
      await player.dispose();

      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          r.settledMatched,
          isTrue,
          reason: '${r.label}: the rect never matched the drawn frame',
        );
      }
    },
    skip: skipReason != null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
