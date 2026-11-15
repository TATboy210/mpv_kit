// Seek-recovery regression (REBASE-02, mpv#17258 class): seeks that move
// the position must each recover — frames keep flowing, no renderError
// storm, no deviceLost.
//
// Source semantics (empirically pinned, see docs/perf/2026-10-24-vendor-
// advance-regression.md): the default av://lavfi generator supports
// FORWARD and near-end seeks only (backward/to-zero are no-ops — a
// source property, not a bridge regression). For both-direction coverage
// set MPV_KIT_SEEK_MEDIA to a real seekable video file; the test then
// also exercises backward and to-start seeks.
//
// Run from example/ against a real libmpv build:
//   MPV_KIT_LIBMPV_PATH=<dll> PATH="$PATH:<libdir>" \
//   flutter test integration_test/seek_recovery_test.dart -d windows
//
// Printing is the report channel:
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final media = Platform.environment['MPV_KIT_SEEK_MEDIA'];
  final source = media ??
      'av://lavfi:testsrc2=size=640x360:rate=30:duration=60[out0];'
          'sine=frequency=440:sample_rate=48000:duration=60[out1]';

  testWidgets('seeks that move position each recover (frames keep flowing)',
      (tester) async {
    await tester.runAsync(() async {
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
      final events = <MpvVideoEventKind>[];
      final sub = controller.events
          .listen((e) => events.add(e.kind), onError: (Object _) {});

      await player.open(source);

      // Readiness: params known AND frames flowing.
      final initialDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(initialDeadline) &&
          (player.videoParams.value?.width == null ||
              player.mpv.tryGetProperty('estimated-vf-fps') == null)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(player.videoParams.value?.width, isNotNull,
          reason: 'playback must start');
      expect(player.mpv.tryGetProperty('estimated-vf-fps'), isNotNull);

      // lavfi is raw video and never reaches a decoder, so HWD-05 asks for a
      // printed and asserted software outcome (16-05 decision A).
      final hwdec = await awaitHwdecReport(
        player.mpv.tryGetProperty,
        test: 'seek_recovery',
        sample: media == null ? 'lavfi' : 'media',
        at: 'first-frame',
        reason: controller.reason,
        requested: 'auto-safe',
      );
      print(hwdec.line);
      // MPV_KIT_SEEK_MEDIA (manual runs only) swaps the lavfi source for a real
      // file whose decode may be hardware; the line is still printed and the
      // outcome must be conclusive, software is asserted for lavfi.
      if (media == null) {
        expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
        expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);
      } else {
        expect(
          hwdec.outcome,
          isNot(HwdecOutcome.unexpected),
          reason: hwdec.line,
        );
      }

      // lavfi: fixed 60 s; real media: read the reported duration.
      final total = media == null
          ? const Duration(seconds: 60)
          : player.duration.value;
      expect(total, greaterThan(Duration.zero), reason: 'duration must be known');

      // After a seek that lands at [target], playback continues: the
      // position settles in [target, target + 10s] and frames flow.
      Future<void> seekAndRecover(Duration target, String label) async {
        final errorsBefore =
            events.where((k) => k == MpvVideoEventKind.renderError).length;
        await player.seek(target, exact: true);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        var recovered = false;
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final pos = player.position.value;
          final fps = player.mpv.tryGetProperty('estimated-vf-fps');
          if (fps != null &&
              pos >= target &&
              pos <= target + const Duration(seconds: 10)) {
            recovered = true;
            break;
          }
        }
        print('SEEK $label target=$target recovered=$recovered '
            'pos=${player.position.value}');
        expect(recovered, isTrue,
            reason: 'seek to $target ($label) must recover within 10 s '
                '(position in window, frames flowing)');
        expect(
          events.where((k) => k == MpvVideoEventKind.renderError).length -
              errorsBefore,
          lessThan(5),
          reason: 'no renderError storm after seek ($label)',
        );
      }

      await seekAndRecover(total * 0.5, 'forward-mid');
      // Rapid double seek (both forward): fire the second before the
      // first settles. Near-end runs LAST — on the lavfi generator every
      // later target would be a backward no-op.
      unawaited(player.seek(total * 0.6, exact: true));
      await seekAndRecover(total * 0.8, 'rapid-followup');
      await seekAndRecover(total * 0.95, 'near-end');
      if (media != null) {
        // Real media: backward and to-start are meaningful.
        await seekAndRecover(total * 0.2, 'backward');
        await seekAndRecover(Duration.zero, 'to-start');
      }

      expect(events, isNot(contains(MpvVideoEventKind.deviceLost)));
      print('SEEK-RECOVERY OK media=${media ?? "lavfi"} events='
          '${events.toSet().map((k) => k.name).toList()..sort()}');

      await sub.cancel();
      await controller.dispose();
      await player.dispose();
    });
  });
}
