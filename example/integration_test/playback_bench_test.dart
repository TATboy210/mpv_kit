// Real-machine playback benchmark (PERF-02): exercises the actual plugin +
// GPU render path through a visible window. Run from example/:
//
//   flutter test integration_test -d windows
//
// with MPV_KIT_LIBMPV_PATH pointing at a real libmpv and its dependency
// directory on PATH. The window must stay visible for the whole run —
// minimizing triggers the renderer's idle path and invalidates the numbers.
//
// Output is one `BENCH <name> {json}` line per section for the baseline
// record. All sections share one testWidgets: sequential integration tests
// in one file leave the binding in a state where later tests hang ("did not
// complete").
//
// Printing is the report channel (integration tests have no console logger):
// ignore_for_file: avoid_print
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';

// Multi-stream lavfi graph: [out0]=video, [out1]=audio (ffmpeg lavfi device
// labeling). Audio makes avsync/total-avsync-change meaningful; ao=null
// paces real time.
String lavfiSource(String size, int seconds) =>
    'av://lavfi:testsrc2=size=$size:rate=30:duration=$seconds[out0];'
    'sine=frequency=440:sample_rate=48000:duration=$seconds[out1]';

const _lavfi =
    'av://lavfi:testsrc2=size=1920x1080:rate=30:duration=25[out0];'
    'sine=frequency=440:sample_rate=48000:duration=25[out1]';

Player _createPlayer() => Player(
      options: const {
        'vo': 'libmpv',
        'hwdec': 'auto-safe',
        'keep-open': 'yes',
        'idle': 'yes',
        'terminal': 'no',
        'ao': 'null', // paces real time without needing an audio device
      },
    );

/// Samples the sync/drop metric family and returns finals/peaks plus the
/// sample list.
Future<Map<String, Object?>> _sample(
  Player player, {
  required Duration duration,
  Duration every = const Duration(milliseconds: 500),
}) async {
  const names = [
    'avsync',
    'total-avsync-change',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'estimated-vf-fps',
    'vo-delayed-frame-count',
    'display-sync-active',
  ];
  final samples = <Map<String, Object?>>[];
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(every);
    final s = <String, Object?>{'t': DateTime.now().toUtc().toIso8601String()};
    for (final n in names) {
      s[n] = player.mpv.tryGetProperty(n);
    }
    samples.add(s);
  }
  num? peakAbs(String n) {
    final vals = samples.map((s) => s[n]).whereType<num>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a.abs() > b.abs() ? a : b).abs();
  }

  num? max(String n) {
    final vals = samples.map((s) => s[n]).whereType<num>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a > b ? a : b);
  }

  return {
    'samples': samples,
    'frameDropCountFinal': samples.last['frame-drop-count'],
    'decoderFrameDropCountFinal': samples.last['decoder-frame-drop-count'],
    'avsyncPeakAbs': peakAbs('avsync'),
    'totalAvsyncChangeFinal': samples.last['total-avsync-change'],
    'estimatedVfFpsMax': max('estimated-vf-fps'),
    'voDelayedFrameCountMax': max('vo-delayed-frame-count'),
    'displaySyncActive': samples.last['display-sync-active'],
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real-time pacing: never wait for a frame before advancing.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('playback, cycle and resize benchmarks', (tester) async {
    await tester.runAsync(() async {
      // --- playback metrics ---
      final player = _createPlayer();
      final controller = await MpvVideoController.create(player);
      await player.open(_lavfi);
      await Future<void>.delayed(const Duration(seconds: 2)); // settle
      // lavfi is raw video and never reaches a decoder, so HWD-05 asks for a
      // printed and asserted software outcome (16-05 decision A).
      final hwdec = await awaitHwdecReport(
        player.mpv.tryGetProperty,
        test: 'playback_bench',
        sample: 'lavfi',
        at: 'first-frame',
        reason: controller.reason,
        requested: 'auto-safe',
      );
      print(hwdec.line);
      expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
      expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);
      final r = await _sample(player, duration: const Duration(seconds: 20));
      expect(r['estimatedVfFpsMax'], greaterThan(0));
      print('BENCH playback ${jsonEncode({
            'metrics': r,
            'videoSize':
                '${player.videoParams.value?.width}x${player.videoParams.value?.height}',
          })}');
      // --- resize sweep while playing (the real workload: ring
      // reallocation with frames flowing; a stopped-but-rendered state would
      // block the render thread's reallocation on unconsumed retired
      // images) ---
      final events = <MpvVideoEventKind>[];
      final sub = controller.events
          .listen((e) => events.add(e.kind), onError: (Object _) {});
      final resizeBaseline = ProcessInfo.currentRss;
      for (var i = 0; i < 50; i++) {
        await controller.setSize(1280, 720);
        await controller.setSize(640, 360);
        if (i % 10 == 0) print('RESIZE progress $i');
      }
      final resizeGrowth = ProcessInfo.currentRss - resizeBaseline;
      expect(events, contains(MpvVideoEventKind.resize));
      print('BENCH resize ${jsonEncode({
            'resizes': 100,
            'resizeEvents':
                events.where((k) => k == MpvVideoEventKind.resize).length,
            'rssGrowthBytes': resizeGrowth,
          })}');
      await sub.cancel();

      player.stop();
      // One render context per mpv handle: free it before the cycles create
      // their own controllers.
      await controller.dispose();

      // --- create/dispose cycles (the Phase 2-hardened controller path) ---
      for (var i = 0; i < 5; i++) {
        final c = await MpvVideoController.create(player);
        await c.dispose();
      }
      final cycleBaseline = ProcessInfo.currentRss;
      for (var i = 0; i < 50; i++) {
        final c = await MpvVideoController.create(player);
        await c.dispose();
      }
      final cycleGrowth = ProcessInfo.currentRss - cycleBaseline;
      expect(
        cycleGrowth,
        lessThan(64 * 1024 * 1024),
        reason: 'RSS grew ${(cycleGrowth / (1024 * 1024)).toStringAsFixed(1)} '
            'MiB over 50 controller create/dispose cycles (bound: 64 MiB)',
      );
      print('BENCH cycles ${jsonEncode({
            'cycles': 50,
            'rssGrowthBytes': cycleGrowth,
          })}');

    });
  });
}
