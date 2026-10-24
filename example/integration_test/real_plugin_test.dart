// Real-plugin integration test (VERIFY-01): exercises the actual native
// plugin path — no method-channel mocks. Runs on CI via
// native-verify.yml's integration-test job on Linux/Windows/macOS runners
// with the verify-tier libmpv artifacts, and locally via
//   flutter test integration_test/real_plugin_test.dart -d <target>
// with MPV_KIT_LIBMPV_PATH set (see README "Local libmpv for tests").
//
// Contract: create a controller (native render context), open a lavfi
// source, wait until the decoder reports video params AND the VO has
// produced frames (estimated-vf-fps non-null — software backend is
// acceptable on GPU-less runners), then dispose exactly once with no
// device loss. One INTEGRATION {json} line reports backend/timings.
//
// Printing is the report channel:
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('real plugin: create, render a frame, dispose', (tester) async {
    await tester.runAsync(() async {
      final events = <MpvVideoEventKind>[];
      final player = Player(
        options: const {
          'vo': 'libmpv',
          'hwdec': 'auto-safe',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
          'ao': 'null',
        },
      );
      final controller = await MpvVideoController.create(player);
      final sub = controller.events
          .listen((e) => events.add(e.kind), onError: (Object _) {});
      final done = Completer<void>();
      // A late listener replacing the collector still sees done:
      controller.events.listen((_) {}, onDone: done.complete);

      final sw = Stopwatch()..start();
      await player.open(
        'av://lavfi:testsrc2=size=640x360:rate=30:duration=30[out0];'
        'sine=frequency=440:sample_rate=48000:duration=30[out1]',
      );

      // Readiness 1: the decoder reports the requested size.
      var paramsReady = false;
      // Readiness 2: the VO produced frames (fps estimate exists) — this is
      // the "rendered a frame" proof; it requires the render context to
      // actually consume and present decoded frames.
      var framesFlowing = false;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline) &&
          !(paramsReady && framesFlowing)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final vp = player.videoParams.value;
        if (vp?.width == 640 && vp?.height == 360) paramsReady = true;
        if (player.mpv.tryGetProperty('estimated-vf-fps') != null) {
          framesFlowing = true;
        }
      }
      final elapsedMs = sw.elapsedMilliseconds;
      final fps = player.mpv.tryGetProperty('estimated-vf-fps');

      expect(paramsReady, isTrue,
          reason: 'the decoder must report the requested video size');
      expect(framesFlowing, isTrue,
          reason: 'the VO must produce frames (estimated-vf-fps stays null '
              'until the render loop presents)');
      expect(fps, isA<num>());

      print('INTEGRATION ${jsonEncode({
            'backend': controller.backend.name,
            'reason': controller.reason,
            'elapsedMs': elapsedMs,
            'fps': fps,
            'events': events.toSet().map((k) => k.name).toList()..sort(),
          })}');

      await controller.dispose();
      await done.future.timeout(const Duration(seconds: 5));
      // Second dispose: idempotent no-op.
      await controller.dispose();
      expect(events, isNot(contains(MpvVideoEventKind.deviceLost)));
      expect(
        events.where((k) => k == MpvVideoEventKind.renderError).length,
        lessThan(10),
        reason: 'a renderError storm means the render path is unhealthy',
      );
      await player.dispose();
      await sub.cancel();
    });
  });
}
