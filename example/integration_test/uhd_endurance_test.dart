// UHD endurance test (PERF-03): plays a lavfi source at a configurable
// resolution/duration through the real render path and gates on frame
// backlog health. Parameterized by environment:
//
//   MPV_KIT_BENCH_SIZE    WxH      (default 3840x2160)
//   MPV_KIT_BENCH_SECONDS duration (default 1800)
//   MPV_KIT_BENCH_LABEL   run name for the BENCH line (default uhd)
//   MPV_KIT_BENCH_RENDER  1 = mount a Texture and setSize(<source size>),
//                         timing starts after that size's resize event
//   MPV_KIT_BENCH_SOURCE  absolute path of a media file (VER-04, Phase 17).
//                         Plays that file with `loop-file=inf` instead of the
//                         lavfi source, WITHOUT overriding hwdec (the Player's
//                         default list applies), so a hardware-decoded UHD run
//                         is possible. MPV_KIT_BENCH_SIZE must equal the
//                         sample's size. HWDEC lines are printed at the first
//                         frame and at the end and must not be `unexpected`;
//                         MPV_KIT_REQUIRE_HWDEC=<method> (hwdec_probe.dart)
//                         turns a missing zero-copy decode into a failure at
//                         the first frame already. Each per-minute sample gains
//                         `hwdecCurrent` and the BENCH line ends with
//                         `source`, `loopsSeen` (time-pos wrap-arounds) and
//                         `hwdecCurrentFinal`. The loop seam may count towards
//                         drops; that is recorded as data, not filtered.
//                         Unset, everything below is unchanged (lavfi source,
//                         `hwdec: auto-safe`, the 16-05 software assertion).
//
// Unset (the Phase 4 gate command) the test never mounts a Texture and never
// calls setSize, so VideoRenderer::RenderLoop sees `sized == false` and only
// SkipFrame()s: the Phase 4 "4K 30 min PASS" measured decode and VO pacing,
// not one frame rendered into a shared image. It stays the like-for-like
// baseline command. MPV_KIT_BENCH_RENDER=1 is the variant that really renders
// every frame at the source size; its BENCH line carries "rendered": true.
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final size =
      Platform.environment['MPV_KIT_BENCH_SIZE'] ?? '3840x2160';
  final seconds =
      int.parse(Platform.environment['MPV_KIT_BENCH_SECONDS'] ?? '1800');
  final label = Platform.environment['MPV_KIT_BENCH_LABEL'] ?? 'uhd';
  final render = Platform.environment['MPV_KIT_BENCH_RENDER'] == '1';
  // File-source mode (see the header); empty keeps the lavfi source.
  final source = Platform.environment['MPV_KIT_BENCH_SOURCE'] ?? '';
  final requireHwdec = Platform.environment[requireHwdecVariable];

  testWidgets('UHD endurance $size x ${seconds}s', (tester) async {
    // Rendered variant only: the minimal texture tree of
    // impeller_smoke_test.dart, pumped once before runAsync.
    final textureId = render ? ValueNotifier<int?>(null) : null;
    if (textureId != null) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int?>(
            valueListenable: textureId,
            builder: (context, id, child) => id == null
                ? const SizedBox.shrink()
                : SizedBox(
                    width: 1280,
                    height: 720,
                    child: Texture(textureId: id),
                  ),
          ),
        ),
      );
    }
    await tester.runAsync(() async {
      final player = Player(
        options: {
          'vo': 'libmpv',
          // File-source mode leaves hwdec to the Player's default list.
          if (source.isEmpty) 'hwdec': 'auto-safe',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
          'ao': 'null', // paces real time without needing an audio device
        },
      );
      addTearDown(player.dispose);
      final controller = await MpvVideoController.create(player);
      textureId?.value = controller.textureId;

      var renderErrors = 0;
      var deviceLost = false;
      String? lastResize;
      final sub = controller.events.listen((e) {
        if (e.kind == MpvVideoEventKind.renderError) renderErrors++;
        if (e.kind == MpvVideoEventKind.deviceLost) deviceLost = true;
        if (render && e.kind == MpvVideoEventKind.resize) {
          lastResize = e.message;
        }
      }, onError: (Object _) {});

      final (w, h) = switch (size.split('x')) {
        [final a, final b] => (int.parse(a), int.parse(b)),
        _ => throw ArgumentError('MPV_KIT_BENCH_SIZE must be WxH, got $size'),
      };
      // The rendered variant starts timing only after its resize, so its
      // source outlasts the run by the resize wait's 30 s bound: a run
      // window that reaches EOF counts the undisplayed tail as VO drops
      // (12-02 self-check: 8 drops at EOF in a rendered 20 s 1080p run, 0
      // when the source outlasted the run). Unset, the source is unchanged.
      final sourceSeconds = render ? seconds + 30 : seconds;
      if (source.isNotEmpty) {
        expect(
          File(source).existsSync(),
          isTrue,
          reason: 'MPV_KIT_BENCH_SOURCE must name an existing file: $source',
        );
      }
      await player.open(
        source.isNotEmpty
            ? source
            : 'av://lavfi:testsrc2=size=$size:rate=30:duration=$sourceSeconds[out0];'
                  'sine=frequency=440:sample_rate=48000:duration=$sourceSeconds[out1]',
        options: source.isNotEmpty ? const {'loop-file': 'inf'} : null,
      );

      // Wait until the requested resolution is actually being decoded.
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final vp = player.videoParams.value;
        if (vp?.width == w && vp?.height == h) break;
      }
      expect(player.videoParams.value?.width, w,
          reason: 'the source must reach the requested resolution'
              '${source.isEmpty ? '' : ' (MPV_KIT_BENCH_SIZE must equal the sample size)'}');
      expect(player.videoParams.value?.height, h);

      // lavfi is raw video and never reaches a decoder, so HWD-05 asks for a
      // printed and asserted software outcome (16-05 decision A).
      final sampleName = source.isEmpty ? 'lavfi' : _sampleName(source);
      final hwdecRequested = source.isEmpty
          ? 'auto-safe'
          : hwdecOptionText(player.mpv.tryGetProperty('hwdec'));
      final hwdec = await awaitHwdecReport(
        player.mpv.tryGetProperty,
        test: 'uhd_endurance',
        sample: sampleName,
        at: 'first-frame',
        reason: controller.reason,
        requested: hwdecRequested,
      );
      print(hwdec.line);
      if (source.isEmpty) {
        expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
        expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);
      } else {
        // File-source mode: any real outcome is data, `unexpected` is not;
        // a requested zero-copy method fails here, before the long run.
        expect(hwdec.outcome, isNot(HwdecOutcome.unexpected),
            reason: hwdec.line);
        _judgeRequirement(requireHwdec, hwdec);
      }

      // Rendered variant: size the renderer to the source and start timing
      // only once the ring exists at that size (resize is emitted after a
      // successful (re)allocation, video_renderer.cc RenderOnce).
      if (render) {
        await controller.setSize(w, h);
        final sizedBy = DateTime.now().add(const Duration(seconds: 30));
        while (lastResize != '${w}x$h' && DateTime.now().isBefore(sizedBy)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(lastResize, '${w}x$h',
            reason: 'the rendered variant must reach a ${w}x$h ring');
      }

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
      // File-source mode: count time-pos wrap-arounds (loops) at 250 ms, finer
      // than the 10 s sampling so short clips are not undercounted.
      var loopsSeen = 0;
      num? lastPos;
      final loopWatch = source.isEmpty
          ? null
          : Timer.periodic(const Duration(milliseconds: 250), (_) {
              final pos = player.mpv.tryGetProperty('time-pos');
              if (pos is! num) return;
              final last = lastPos;
              if (last != null && pos < last - 0.5) loopsSeen++;
              lastPos = pos;
            });
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
        if (source.isNotEmpty) {
          s['hwdecCurrent'] = player.mpv.tryGetProperty('hwdec-current');
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

      loopWatch?.cancel();
      final finals = <String, Object?>{
        for (final n in names) n: player.mpv.tryGetProperty(n),
      };
      // File-source mode: the end report, judged after the BENCH line.
      final endHwdec = source.isEmpty
          ? null
          : await awaitHwdecReport(
              player.mpv.tryGetProperty,
              test: 'uhd_endurance',
              sample: sampleName,
              at: 'end',
              reason: controller.reason,
              requested: hwdecRequested,
            );
      if (endHwdec != null) print(endHwdec.line);
      final totalAvsync = finals['total-avsync-change'];
      final frameDrops = finals['frame-drop-count'];
      final decoderDrops = finals['decoder-frame-drop-count'];
      final avgDelayed = delayedCount == 0 ? null : delayedSum / delayedCount;

      final result = {
        'label': label,
        'size': size,
        'seconds': seconds,
        'rendered': render,
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
        if (endHwdec != null) ...{
          'source': _fileName(source),
          'loopsSeen': loopsSeen,
          'hwdecCurrentFinal': endHwdec.hwdecCurrent,
        },
      };
      print('BENCH uhd ${jsonEncode(result)}');

      await sub.cancel();
      if (textureId != null) {
        // Unmount before the render context goes away.
        textureId.value = null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await controller.dispose();

      // --- fixed gates ---
      if (endHwdec != null) {
        expect(endHwdec.outcome, isNot(HwdecOutcome.unexpected),
            reason: endHwdec.line);
        _judgeRequirement(requireHwdec, endHwdec);
      }
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

/// File name of [path] (either separator).
String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

/// Sample label of a file-source run: the file name without `.mp4`.
String _sampleName(String path) =>
    _fileName(path).replaceAll(RegExp(r'\.mp4$'), '');

/// Prints the `HWDEC-REQUIRE` line for [report] and fails the test when the
/// requirement [required] (MPV_KIT_REQUIRE_HWDEC) is set and not met.
void _judgeRequirement(String? required, HwdecReport report) {
  if (required == null || required.isEmpty) return;
  final failure = checkHwdecRequirement(required, report);
  print(hwdecRequireLine(required, report, failure));
  if (failure != null) fail(failure);
}
