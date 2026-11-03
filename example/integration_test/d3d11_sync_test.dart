// Real-plugin test of the D3D11 completion/device-loss paths added in dev.8.
// One mode per run (debug plugin build; the injection exists only without
// NDEBUG), always with the native D3D11 backend forced:
//
//   MPV_KIT_VIDEO_API=d3d11 MPV_KIT_D3D11_INJECT=<mode> \
//     flutter test integration_test/d3d11_sync_test.dart -d windows
//
// modes: device-removed:alloc | device-removed:render:<n> | signal-fail:<n> |
//        query-getdata-fail (also set MPV_KIT_D3D11_SYNC=query) |
//        create-no-11-1
//
// Printing is the report channel:
// ignore_for_file: avoid_print
@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

const _channel = MethodChannel('mpv_kit_video');
const _source = 'av://lavfi:testsrc2=size=640x360:rate=30:duration=120';
const _flowTimeout = Duration(seconds: 30);
const _lostTimeout = Duration(seconds: 25);
const _quiet = Duration(seconds: 2);

Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('d3d11 completion and device-loss injection', (tester) async {
    final mode = Platform.environment['MPV_KIT_D3D11_INJECT'] ?? '';
    expect(
      mode,
      isNotEmpty,
      reason: 'set MPV_KIT_D3D11_INJECT=<mode> (see the file header)',
    );
    final texture = ValueNotifier<int?>(null);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<int?>(
            valueListenable: texture,
            builder: (context, id, child) => SizedBox(
              width: 320,
              height: 180,
              child: id == null ? null : Texture(textureId: id),
            ),
          ),
        ),
      ),
    );

    final kinds = <MpvVideoEventKind>[];
    final player = Player(
      options: const {
        'vo': 'libmpv',
        'hwdec': 'no',
        'keep-open': 'yes',
        'idle': 'yes',
        'terminal': 'no',
        'ao': 'null',
      },
    );
    final controller = await MpvVideoController.create(player);
    final sub = controller.events.listen((e) => kinds.add(e.kind));
    texture.value = controller.textureId;
    await tester.runAsync(() async {
      expect(
        controller.reason,
        startsWith('d3d11'),
        reason: 'MPV_KIT_VIDEO_API=d3d11 must select the native backend',
      );
      await player.open(_source);
      final deadline = DateTime.now().add(_flowTimeout);
      while (player.mpv.tryGetProperty('estimated-vf-fps') == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(player.mpv.tryGetProperty('estimated-vf-fps'), isNotNull);
      // Allocate the ring: without a setSize the renderer only skips frames,
      // so no render/Signal/query path is exercised.
      await controller.setSize(640, 360);

      var lost = false;
      var framesAfter = 0;
      if (mode.startsWith('device-removed:alloc')) {
        unawaited(controller.setSize(960, 540));
      } else if (mode.startsWith('device-removed:render')) {
        // The injection fires on its own after the configured render.
      } else if (mode.startsWith('signal-fail')) {
        final stats = await _channel.invokeMapMethod<String, Object?>('stats', {
          'textureId': controller.textureId,
        });
        expect(
          stats?['sync'],
          'fence',
          reason: 'fence path not active: $stats',
        );
        final fpsBefore =
            player.mpv.tryGetProperty('estimated-vf-fps') as num? ?? 0;
        for (var i = 0; i < 40; i++) {
          await _nextFrame();
        }
        final fpsAfter =
            player.mpv.tryGetProperty('estimated-vf-fps') as num? ?? 0;
        framesAfter = fpsAfter > 0 && fpsBefore > 0 ? 1 : 0;
        expect(framesAfter, 1, reason: 'frames stopped after the fallback');
        expect(kinds, isNot(contains(MpvVideoEventKind.gpuTimeout)));
        expect(kinds, isNot(contains(MpvVideoEventKind.renderError)));
        expect(kinds, isNot(contains(MpvVideoEventKind.deviceLost)));
      } else if (mode == 'create-no-11-1') {
        for (var i = 0; i < 40; i++) {
          await _nextFrame();
        }
        expect(kinds, isNot(contains(MpvVideoEventKind.deviceLost)));
        framesAfter = 1;
      } else {
        // query-getdata-fail: escalates to one device_lost.
      }

      if (mode.startsWith('device-removed') || mode == 'query-getdata-fail') {
        final lostDeadline = DateTime.now().add(_lostTimeout);
        while (!kinds.contains(MpvVideoEventKind.deviceLost) &&
            DateTime.now().isBefore(lostDeadline)) {
          await _nextFrame();
        }
        lost = kinds.contains(MpvVideoEventKind.deviceLost);
        expect(lost, isTrue, reason: 'no deviceLost for $mode');
        expect(controller.isBroken, isTrue);
        final count = kinds
            .where((k) => k == MpvVideoEventKind.deviceLost)
            .length;
        expect(count, 1, reason: 'deviceLost reported $count times');
        await Future<void>.delayed(_quiet);
        final after = kinds
            .skip(kinds.indexOf(MpvVideoEventKind.deviceLost))
            .where((k) => k == MpvVideoEventKind.renderError)
            .length;
        expect(after, 0, reason: 'renderError after deviceLost');
      }

      print(
        'D3D11-SYNC ${jsonEncode({'mode': mode, 'reason': controller.reason, 'deviceLost': lost, 'isBroken': controller.isBroken, 'framesAfter': framesAfter, 'events': kinds.toSet().map((k) => k.name).toList()..sort()})}',
      );
      await sub.cancel();
      await controller.dispose();
      await player.dispose();
    });
  });
}
