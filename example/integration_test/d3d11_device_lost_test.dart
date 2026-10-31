// Real-plugin test of the D3D11 failure paths (Phase 14, D3D-07).
//
// Run only by Windows CI and locally, in a debug plugin build (the injection
// seam exists only without NDEBUG, `flutter test` builds debug), once per
// mode, without MPV_KIT_VIDEO_API:
//   MPV_KIT_D3D11_INJECT=device-removed:30 flutter test integration_test/d3d11_device_lost_test.dart -d windows
//   MPV_KIT_D3D11_INJECT=create-fail       flutter test integration_test/d3d11_device_lost_test.dart -d windows
// with MPV_KIT_LIBMPV_PATH pointing at a libmpv that has the D3D11 render API
// (patch 0010) and the gpu-next D3D11 branch (patch 0004). MpvLibrary.open is
// strict about that path: a libmpv that fails to load throws
// MpvLibraryNotFound with the loader's reason instead of falling back to the
// bundled copy. native-verify runs this test on the staged branch libmpv
// through MPV_KIT_LIBMPV_PATH (strict, never falls back); flutter-plugin runs
// d3d11_backend_test on the pinned bundle alone (Phase 17.1).
//
// The injection replaces only the HRESULT source of the plugin's device
// removal check (and the device creation result); the mapping to device_lost
// is the real one. A real TDR is not induced (see d3d11_backend.cpp).
//
//   device-removed:<n>  the controller (auto chain; on a runner without
//       Vulkan this is d3d11) gets exactly one deviceLost after frame <n>,
//       isBroken is true, nothing else is reported for 2 s, dispose finishes,
//       the Player still answers property reads, and a software controller
//       on the same Player renders frames.
//   create-fail         the d3d11 device cannot be created: the chain moves
//       on and the reason keeps a `d3d11/<renderer> unavailable: ... (injected)`
//       trail for both renderers; without Vulkan the winner is software.
//
// One testWidgets (a second one would start a new window and plugin
// instance, as in real_plugin_test.dart). One D3D11-INJECT {json} line
// reports the result.
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

/// Upper bound for the injected device removal to reach Dart.
const _lostTimeout = Duration(seconds: 20);

/// Quiet period after the device_lost event: the engine must not report
/// further render errors once rendering stopped for good.
const _quietPeriod = Duration(seconds: 2);

/// Upper bound for frames to flow.
const _flowTimeout = Duration(seconds: 30);

/// Upper bound for the event stream to end after dispose.
const _disposeTimeout = Duration(seconds: 5);

/// Upper bound for the create-time softwareFallback event to reach the first
/// listener (it is handed over when that listener subscribes, so this only
/// covers the microtask hop).
const _fallbackTimeout = Duration(seconds: 2);

/// Why every d3d11 candidate fails under `create-fail`
/// (DXGI_ERROR_UNSUPPORTED, marked as injected).
const _injectedWhy = 'd3d11 device creation failed: 0x887A0004 (injected)';

/// A 320x180 red-over-blue lavfi source, long enough for any section.
const _source =
    'av://lavfi:color=c=red:s=320x90:r=30:d=120[top];'
    'color=c=blue:s=320x90:r=30:d=120[bottom];'
    '[top][bottom]vstack[out0]';

/// Waits until the VO reports a frame rate (frames flow), bounded.
Future<void> _waitForFrames(Player player, String what) async {
  final deadline = DateTime.now().add(_flowTimeout);
  while (DateTime.now().isBefore(deadline) &&
      player.mpv.tryGetProperty('estimated-vf-fps') == null) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  expect(
    player.mpv.tryGetProperty('estimated-vf-fps'),
    isNotNull,
    reason: 'frames must flow: $what',
  );
}

/// Waits for [controller]'s event stream to end (after dispose), bounded.
Future<void> _disposeAndWait(MpvVideoController controller) async {
  final done = Completer<void>();
  controller.events.listen((_) {}, onDone: done.complete);
  await controller.dispose();
  await done.future.timeout(_disposeTimeout);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('d3d11 failure injection: device lost and create failure', (
    tester,
  ) async {
    final mode = Platform.environment['MPV_KIT_D3D11_INJECT'] ?? '';
    if (mode != 'create-fail' && !mode.startsWith('device-removed:')) {
      fail(
        'set MPV_KIT_D3D11_INJECT=device-removed:<n> or create-fail '
        '(debug plugin build only), got "$mode"',
      );
    }
    final texture = ValueNotifier<int?>(null);
    // Pumped before runAsync: a tree pumped inside it is not reliably
    // composed (same as real_plugin_test.dart).
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
    await tester.runAsync(() async {
      final player = Player(
        options: const {
          'vo': 'libmpv',
          // The hosted tier only proves the render path, not hardware decode.
          'hwdec': 'no',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
          'ao': 'null',
        },
      );
      final controller = await MpvVideoController.create(player);
      final events = <MpvVideoEventKind>[];
      // The first listener, attached right after create, is the one that gets
      // the create-time softwareFallback event (VER-01).
      final fallback = Completer<String>();
      controller.events.listen((e) {
        events.add(e.kind);
        if (e.kind == MpvVideoEventKind.softwareFallback &&
            !fallback.isCompleted) {
          fallback.complete(e.message);
        }
      }, onError: (Object _) {});
      final report = <String, Object?>{
        'mode': mode,
        'reason': controller.reason,
        'backend': controller.backend.name,
      };

      if (mode == 'create-fail') {
        await _createFail(player, controller, texture, fallback, report);
      } else {
        await _deviceRemoved(player, controller, texture, events, report);
      }
      report['events'] = (events.map((k) => k.name).toSet().toList()..sort());
      print('D3D11-INJECT ${jsonEncode(report)}');
      await player.dispose();
    });
  });
}

/// Prints and asserts the software decode of the lavfi source (HWD-05).
///
/// lavfi is raw video and never reaches a decoder, so the asserted outcome is
/// software (16-05 decision A). Called at the first frame of each mode.
Future<void> _expectSoftwareDecode(
  Player player,
  MpvVideoController controller,
) async {
  final hwdec = await awaitHwdecReport(
    player.mpv.tryGetProperty,
    test: 'd3d11_device_lost',
    sample: 'lavfi',
    at: 'first-frame',
    reason: controller.reason,
    requested: 'no',
  );
  print(hwdec.line);
  expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
  expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);
}

/// create-fail: the reason carries the injected trail of both d3d11
/// candidates; the winner is software (no Vulkan on the runner) or Vulkan.
Future<void> _createFail(
  Player player,
  MpvVideoController controller,
  ValueNotifier<int?> texture,
  Completer<String> fallback,
  Map<String, Object?> report,
) async {
  final reason = controller.reason;
  final softwareWon = reason.startsWith('software (sw) on cpu');
  expect(
    softwareWon || reason.startsWith('vulkan ('),
    isTrue,
    reason: 'the chain must continue past d3d11: $reason',
  );
  // With Vulkan present the pre-switch chain tries it before d3d11, so no
  // d3d11 trail exists; the RTX 4060 case is covered by 14-11.
  report['trailsChecked'] = softwareWon;
  // VER-01: landing on software must emit softwareFallback with the whole
  // fallback chain as its reason (null in the report when Vulkan won).
  report['softwareFallback'] = null;
  if (softwareWon) {
    final message = await fallback.future.timeout(
      _fallbackTimeout,
      onTimeout: () => '<no softwareFallback event within $_fallbackTimeout>',
    );
    expect(
      message,
      'rendering in software: $reason',
      reason: 'the softwareFallback event carries the full reason',
    );
    report['softwareFallback'] = message;
    for (final renderer in const ['gpu-next', 'gpu']) {
      expect(
        reason,
        contains('d3d11/$renderer unavailable: $_injectedWhy'),
        reason: 'every d3d11 candidate keeps its injected trail',
      );
    }
  }
  texture.value = controller.textureId;
  await controller.setSize(320, 180);
  await player.open(_source);
  await _waitForFrames(player, 'after the d3d11 create failure ($reason)');
  await _expectSoftwareDecode(player, controller);
  texture.value = null;
  await _disposeAndWait(controller);
}

/// `device-removed:<n>`: one deviceLost, a broken controller, a clean dispose
/// and a working software controller on the same Player.
Future<void> _deviceRemoved(
  Player player,
  MpvVideoController controller,
  ValueNotifier<int?> texture,
  List<MpvVideoEventKind> events,
  Map<String, Object?> report,
) async {
  expect(
    controller.reason,
    startsWith('d3d11 (gpu-next) on '),
    reason: 'the pre-switch auto chain must land on d3d11 on this runner',
  );
  final lost = controller.events
      .firstWhere((e) => e.kind == MpvVideoEventKind.deviceLost)
      .timeout(_lostTimeout);
  texture.value = controller.textureId;
  await controller.setSize(320, 180);
  await player.open(_source);
  // Decoder state does not depend on the renderer, so this is the first-frame
  // point before the injected device loss is awaited.
  await _expectSoftwareDecode(player, controller);
  await lost;
  expect(controller.isBroken, isTrue, reason: 'device_lost breaks it');
  // Rendering stopped for good: no render_error follows.
  final before = events.length;
  await Future<void>.delayed(_quietPeriod);
  expect(
    events.skip(before).where((k) => k == MpvVideoEventKind.renderError),
    isEmpty,
    reason: 'no render_error after device_lost',
  );
  expect(
    events.where((k) => k == MpvVideoEventKind.deviceLost).length,
    1,
    reason: 'exactly one deviceLost',
  );
  report['isBroken'] = controller.isBroken;

  // The process survives: dispose finishes, the Player still answers.
  texture.value = null;
  await _disposeAndWait(controller);
  expect(player.mpv.getProperty('pause'), isNotNull);

  // Recovery: a software controller on the same Player renders frames.
  final software = await MpvVideoController.create(
    player,
    renderer: MpvVideoRenderer.software,
  );
  expect(software.reason, startsWith('software (sw) on cpu'));
  texture.value = software.textureId;
  await software.setSize(320, 180);
  await player.open(_source);
  await _waitForFrames(player, 'on the software controller after device loss');
  report['recoveredWithSoftware'] = true;
  texture.value = null;
  await _disposeAndWait(software);
}
