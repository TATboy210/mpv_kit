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
// Soak (RBE-06, deferred release with a compositor attached): a minimal
// tree shows the controller's texture, so the compositor keeps taking
// frames. Before the controller is disposed, it is resized 10 rounds
// between 640x360 and 320x180 while its texture is mounted (each resize
// retires a front the compositor holds). After it is disposed, 10 fresh
// controllers on the same player each go through create, mount,
// setSize(320, 180), unmount and dispose. One INTEGRATION-SOAK {json} line
// reports resize events, cycles, render errors and device losses; the test
// requires >= 20 resize events, no device loss and < 10 render errors.
//
// Printing is the report channel:
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';

/// Resize rounds of the first controller, and create/dispose cycles after it.
const _soakRounds = 10;
const _soakCycles = 10;

/// Upper bound for the renderer to report a requested size: a resize only
/// needs one render call, so this is generous even for a software runner.
const _resizeTimeout = Duration(seconds: 5);

/// Time each size stays on screen during the resize rounds, so the
/// compositor takes several frames of every generation.
const _settle = Duration(milliseconds: 300);

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the test (same helper as impeller_smoke_test.dart).
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

/// Asks [controller] for [width]x[height] and waits for its resize event.
/// The listener is attached before the request, so the event cannot be
/// missed.
Future<void> _resizeTo(
  MpvVideoController controller,
  int width,
  int height,
) async {
  final resized = controller.events
      .firstWhere(
        (e) =>
            e.kind == MpvVideoEventKind.resize &&
            e.message == '${width}x$height',
      )
      .timeout(_resizeTimeout);
  await controller.setSize(width, height);
  await resized;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('real plugin: create, render a frame, dispose', (tester) async {
    // The texture the compositor samples during the soak; null shows
    // nothing. Pumped before runAsync: a tree pumped inside it is not
    // reliably composed.
    final texture = ValueNotifier<int?>(null);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int?>(
          valueListenable: texture,
          builder: (context, id, child) => SizedBox(
            width: 640,
            height: 360,
            child: id == null ? null : Texture(textureId: id),
          ),
        ),
      ),
    );
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

      // lavfi is raw video and never reaches a decoder, so HWD-05 asks for a
      // printed and asserted software outcome (16-05 decision A).
      final hwdec = await awaitHwdecReport(
        player.mpv.tryGetProperty,
        test: 'real_plugin',
        sample: 'lavfi',
        at: 'first-frame',
        reason: controller.reason,
        requested: 'auto-safe',
      );
      print(hwdec.line);
      expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
      expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);

      // Which libmpv is this? Both the branch build and, since v0.1.0-dev.4,
      // the pinned bundle report client API 2.6 (patch 0010), so
      // MPV_KIT_EXPECT_LIBMPV_API only guards against an older libmpv; the
      // strict MPV_KIT_LIBMPV_PATH handling is what prevents a silent
      // fall-back to the bundled copy.
      final (apiMajor, apiMinor) = MpvLibrary.apiVersion(player.mpv.bindings);
      final libmpvApi = '$apiMajor.$apiMinor';
      final expectedApi = Platform.environment['MPV_KIT_EXPECT_LIBMPV_API'];
      if (expectedApi != null && expectedApi.isNotEmpty) {
        expect(libmpvApi, expectedApi,
            reason: 'the loaded libmpv is not the expected build');
      }

      print('INTEGRATION ${jsonEncode({
            'libmpvApi': libmpvApi,
            'mpvVersion': player.mpv.tryGetProperty('mpv-version'),
            'backend': controller.backend.name,
            'reason': controller.reason,
            'elapsedMs': elapsedMs,
            'fps': fps,
            'events': events.toSet().map((k) => k.name).toList()..sort(),
          })}');

      // Soak (a): resize a controller that has a front while the compositor
      // takes frames from it. The first 640x360 creates the front; every
      // later resize retires the front the compositor holds.
      texture.value = controller.textureId;
      for (var round = 0; round < _soakRounds; round++) {
        await _resizeTo(controller, 640, 360);
        await Future<void>.delayed(_settle);
        await _resizeTo(controller, 320, 180);
        await Future<void>.delayed(_settle);
      }
      texture.value = null;
      await _nextFrame();

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

      // Soak (b): independent create/mount/setSize/unmount/dispose cycles.
      // The first controller's render context is gone, so the handle has
      // at most one render context at any time.
      final cycleEvents = <MpvVideoEventKind>[];
      for (var cycle = 0; cycle < _soakCycles; cycle++) {
        final c = await MpvVideoController.create(player);
        final cycleSub = c.events
            .listen((e) => cycleEvents.add(e.kind), onError: (Object _) {});
        texture.value = c.textureId;
        await _resizeTo(c, 320, 180);
        texture.value = null;
        await _nextFrame();
        await c.dispose();
        await cycleSub.cancel();
      }
      final all = [...events, ...cycleEvents];
      int count(MpvVideoEventKind kind) => all.where((k) => k == kind).length;
      final resizeEvents = count(MpvVideoEventKind.resize);
      final renderErrors = count(MpvVideoEventKind.renderError);
      final deviceLost = count(MpvVideoEventKind.deviceLost);
      print('INTEGRATION-SOAK ${jsonEncode({
            'resizeEvents': resizeEvents,
            'cycles': _soakCycles,
            'renderErrors': renderErrors,
            'deviceLost': deviceLost,
          })}');
      expect(resizeEvents, greaterThanOrEqualTo(2 * _soakRounds),
          reason: 'every soak resize must reach the renderer');
      expect(deviceLost, 0, reason: 'no device loss during the soak');
      expect(renderErrors, lessThan(10),
          reason: 'a renderError storm means the render path is unhealthy');

      await player.dispose();
      await sub.cancel();
    });
  });
}
