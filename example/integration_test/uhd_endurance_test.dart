// UHD endurance test (PERF-03): plays a lavfi source at a configurable
// resolution/duration through the real render path and gates on frame
// backlog health. Parameterized by environment:
//
//   MPV_KIT_BENCH_SIZE    WxH      (default 3840x2160)
//   MPV_KIT_BENCH_SECONDS duration (default 1800)
//   MPV_KIT_BENCH_LABEL   run name for the BENCH line (default uhd)
//
// Run from example/ (window must stay visible the whole time — minimizing
// triggers the renderer's idle path):
//
//   MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 \
//   MPV_KIT_LIBMPV_PATH=<libmpv> PATH="$PATH:<libdir>" \
//   flutter test integration_test/uhd_endurance_test.dart -d windows
//
// Gates (fixed; a failure is recorded data, never relaxed):
//   frame-drop-count == 0 && decoder-frame-drop-count == 0
//   |total-avsync-change| < 1.0 s
//   average vo-delayed-frame-count < 1  (display-sync-mode metric; the
//   Player default is video-sync=audio — recorded with that caveat)
//   no renderError storm (> 10 events fails; transient retries tolerated)
@TestOn('windows')
library;

// Printing is the report channel:
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final size =
      Platform.environment['MPV_KIT_BENCH_SIZE'] ?? '3840x2160';
  final seconds =
      int.parse(Platform.environment['MPV_KIT_BENCH_SECONDS'] ?? '1800');
  final label = Platform.environment['MPV_KIT_BENCH_LABEL'] ?? 'uhd';

  testWidgets('UHD endurance $size x ${seconds}s', (tester) async {
    await tester.runAsync(() async {
      final player = Player(
        options: const {
          'vo': 'libmpv',
          'hwdec': 'auto-safe',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
          'ao': 'null', // paces real time without needing an audio device
        },
      );
      addTearDown(player.dispose);
      final controller = await MpvVideoController.create(player);

      var renderErrors = 0;
      var deviceLost = false;
      final sub = controller.events.listen((e) {
        if (e.kind == MpvVideoEventKind.renderError) renderErrors++;
        if (e.kind == MpvVideoEventKind.deviceLost) deviceLost = true;
      }, onError: (Object _) {});

      final (w, h) = switch (size.split('x')) {
        [final a, final b] => (int.parse(a), int.parse(b)),
        _ => throw ArgumentError('MPV_KIT_BENCH_SIZE must be WxH, got $size'),
      };
      await player.open(
        'av://lavfi:testsrc2=size=$size:rate=30:duration=$seconds[out0];'
        'sine=frequency=440:sample_rate=48000:duration=$seconds[out1]',
      );

      // Wait until the requested resolution is actually being decoded.
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final vp = player.videoParams.value;
        if (vp?.width == w && vp?.height == h) break;
      }
      expect(player.videoParams.value?.width, w,
          reason: 'the source must reach the requested resolution');
      expect(player.videoParams.value?.height, h);

      // Sample every 10 s; keep one compact sample per minute.
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
      var delayedSum = 0;
      var delayedCount = 0;
      num? delayedMax;
      num? avsyncPeak;
      final runDeadline = DateTime.now().add(Duration(seconds: seconds));
      var sampleIndex = 0;
      while (DateTime.now().isBefore(runDeadline)) {
        await Future<void>.delayed(const Duration(seconds: 10));
        final s = <String, Object?>{
          't': (seconds - runDeadline.difference(DateTime.now()).inSeconds)
              .toString(),
        };
        for (final n in names) {
          s[n] = player.mpv.tryGetProperty(n);
        }
        final delayed = s['vo-delayed-frame-count'];
        if (delayed is num) {
          delayedSum += delayed.round();
          delayedCount++;
          if (delayedMax == null || delayed > delayedMax) {
            delayedMax = delayed;
          }
        }
        final av = s['avsync'];
        if (av is num) {
          if (avsyncPeak == null || av.abs() > avsyncPeak.abs()) {
            avsyncPeak = av.abs();
          }
        }
        if (sampleIndex % 6 == 0) samples.add(s);
        sampleIndex++;
      }

      final finals = <String, Object?>{
        for (final n in names) n: player.mpv.tryGetProperty(n),
      };
      final totalAvsync = finals['total-avsync-change'];
      final frameDrops = finals['frame-drop-count'];
      final decoderDrops = finals['decoder-frame-drop-count'];
      final avgDelayed = delayedCount == 0 ? null : delayedSum / delayedCount;

      final result = {
        'label': label,
        'size': size,
        'seconds': seconds,
        'renderErrors': renderErrors,
        'deviceLost': deviceLost,
        'frameDropCountFinal': frameDrops,
        'decoderFrameDropCountFinal': decoderDrops,
        'avsyncPeakAbs': avsyncPeak,
        'totalAvsyncChangeFinal': totalAvsync,
        'voDelayedFrameCountAvg': avgDelayed,
        'voDelayedFrameCountMax': delayedMax,
        'displaySyncActive': finals['display-sync-active'],
        'estimatedVfFpsFinal': finals['estimated-vf-fps'],
        'rssBytes': ProcessInfo.currentRss,
        'samplesPerMinute': samples,
      };
      print('BENCH uhd ${jsonEncode(result)}');

      await sub.cancel();
      await controller.dispose();

      // --- fixed gates ---
      expect(deviceLost, isFalse, reason: 'the Vulkan device must survive');
      expect(renderErrors, lessThan(10),
          reason: 'a renderError storm means the render path is unhealthy');
      expect(frameDrops, 0, reason: 'VO drops must stay at zero');
      expect(decoderDrops, 0, reason: 'decoder drops must stay at zero');
      expect(
        (totalAvsync as num?)?.abs() ?? 0,
        lessThan(1.0),
        reason: 'cumulative A/V drift must stay bounded over the run',
      );
      expect(
        avgDelayed ?? 0,
        lessThan(1),
        reason: 'vo-delayed is a display-sync metric under video-sync=audio; '
            'an average >= 1 would still indicate backlog',
      );
    });
  });
}
