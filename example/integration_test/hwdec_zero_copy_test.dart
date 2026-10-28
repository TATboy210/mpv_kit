// Hardware-decode probe on real encoded samples (Phase 16, HWD-05).
//
// Nearly every other integration test plays lavfi raw video, which can only
// ever report `hwdec-current=no`. This one opens real H.264 / HEVC files so
// the Player's default hwdec list, the decoder and the renderer all have
// something to decide about, and prints what happened:
//
//   HWDEC-IDENTITY {"libmpv","attempts","backend","reason","defaultHwdec"}
//   HWDEC {json}      one line per run and moment (`first-frame`), the
//                     format of hwdec_probe.dart (`hwdec-1`)
//   HWDEC-RUN {json}  one line per run: `firstFrameMs` (loadfile until the
//                     VO reports a frame rate)
//
// Every sample runs twice on the one Player and controller: first with the
// per-file option `hwdec=no` (the software reference), then with the
// Player's own default list. The reference must classify as software; the
// default run may be anything but `unexpected`. A missing sample is a
// failure, not a skip, and an unavailable `hwdec-current` is `unexpected`.
//
// Samples come from the app assets (`integration_test/route_samples/`, made
// by tools/make_hwdec_samples.sh and downloaded from the hwdec-samples
// artifact of native-verify). `MPV_KIT_HWDEC_SAMPLES` (a comma separated file
// name list, read from --dart-define or the environment) overrides the
// default list.
//
// ONE controller per process (todo 2026-10-27-diagnose-second-controller-
// first-frame-stall-in-resize-front), and one testWidgets per file (a second
// one hangs, Phase 4).
//
// Printing is the report channel:
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';

/// Sample list override, from --dart-define.
const _samplesDefine = String.fromEnvironment('MPV_KIT_HWDEC_SAMPLES');

/// Samples of a default run (all three 640x360 files of the hwdec-samples
/// artifact).
const _defaultSamples = 'h264-8bit.mp4,hevc-8bit.mp4,hevc-10bit.mp4';

/// Asset directory the samples are bundled under (see pubspec.yaml).
const _sampleAssetDir = 'integration_test/route_samples/';

/// Bound of every "wait until X" in the test.
const _readyTimeout = Duration(seconds: 15);

/// Bound of one resize round trip.
const _resizeTimeout = Duration(seconds: 5);

/// Size of the controller's texture; equal to the samples.
const _width = 640;
const _height = 360;

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the test (same helper as real_plugin_test.dart).
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

/// The sample file names of this run.
List<String> _sampleNames() {
  final text = _samplesDefine.isNotEmpty
      ? _samplesDefine
      : (Platform.environment['MPV_KIT_HWDEC_SAMPLES'] ?? _defaultSamples);
  return text
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
}

/// Asks [controller] for [width]x[height] and waits for its resize event.
/// The listener is attached before the request, so the event cannot be missed.
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

/// Copies the sample assets into a temp directory (the example app may be
/// sandboxed and cannot read the workspace) and returns name -> path. A
/// missing asset fails the test: a skipped sample would read as a pass.
Future<Map<String, String>> _stageSamples(
  List<String> names,
  Directory temp,
) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest.listAssets().toSet();
  final paths = <String, String>{};
  for (final name in names) {
    final key = '$_sampleAssetDir$name';
    if (!assets.contains(key)) {
      fail(
        'asset $key is missing; the hwdec-samples job of native-verify.yml '
        '(tools/make_hwdec_samples.sh) creates it before the build',
      );
    }
    final bytes = await rootBundle.load(key);
    final file = File('${temp.path}/$name')
      ..writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    paths[name] = file.path;
  }
  return paths;
}

/// Opens [path] (with `hwdec=no` when [requested] is `no`, otherwise with the
/// Player's default list) and returns the milliseconds until the VO reports a
/// frame rate. Fails when the decoder or the VO is not ready in
/// [_readyTimeout].
Future<int> _openAndWaitForFrame(
  Player player,
  String path,
  String requested,
) async {
  final watch = Stopwatch()..start();
  await player.open(
    path,
    options: requested == 'no' ? const {'hwdec': 'no'} : null,
  );
  final deadline = DateTime.now().add(_readyTimeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final params = player.videoParams.value;
    if (params?.width == _width &&
        params?.height == _height &&
        player.mpv.tryGetProperty('estimated-vf-fps') != null) {
      return watch.elapsedMilliseconds;
    }
  }
  fail(
    '$path (requested=$requested): no decoded and rendered frame within '
    '$_readyTimeout',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('hwdec zero-copy probe on real samples', (tester) async {
    final names = _sampleNames();
    // The texture the compositor samples; pumped before runAsync (a tree
    // pumped inside it is not reliably composed).
    final texture = ValueNotifier<int?>(null);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int?>(
          valueListenable: texture,
          builder: (context, id, child) => SizedBox(
            width: _width.toDouble(),
            height: _height.toDouble(),
            child: id == null ? null : Texture(textureId: id),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('mpv_kit_hwdec_');
      // `hwdec` is not overridden: the Player's default list is under test.
      final player = Player(options: const {'ao': 'null'});
      MpvVideoController? controller;
      StreamSubscription<MpvVideoEvent>? eventSub;
      try {
        // Read before any file is loaded, as option text (the property is a
        // list; List.toString would print brackets).
        final defaultHwdec = hwdecOptionText(
          player.mpv.tryGetProperty('hwdec'),
        );
        final samples = await _stageSamples(names, temp);
        controller = await MpvVideoController.create(player);
        final events = <MpvVideoEventKind>[];
        eventSub = controller.events.listen(
          (e) => events.add(e.kind),
          onError: (Object _) {},
        );
        print(
          'HWDEC-IDENTITY ${jsonEncode({'libmpv': MpvLibrary.resolvedPath, 'attempts': MpvLibrary.lastOpenAttempts, 'backend': controller.backend.name, 'reason': controller.reason, 'defaultHwdec': defaultHwdec})}',
        );

        texture.value = controller.textureId;
        await _nextFrame();
        await _resizeTo(controller, _width, _height);

        for (final MapEntry(key: name, value: path) in samples.entries) {
          final sample = name.replaceAll('.mp4', '');
          // Reference first (software), then the default list.
          for (final requested in ['no', defaultHwdec]) {
            final firstFrameMs = await _openAndWaitForFrame(
              player,
              path,
              requested,
            );
            final report = await awaitHwdecReport(
              player.mpv.tryGetProperty,
              test: 'hwdec_zero_copy',
              sample: sample,
              at: 'first-frame',
              reason: controller.reason,
              requested: requested,
            );
            print(report.line);
            print(
              'HWDEC-RUN ${jsonEncode({'schema': 'hwdec-run-1', 'sample': sample, 'api': report.api, 'requested': requested, 'firstFrameMs': firstFrameMs})}',
            );
            if (requested == 'no') {
              expect(
                report.outcome,
                HwdecOutcome.software,
                reason: 'hwdec=no must decode in software: ${report.line}',
              );
              expect(report.zeroCopy, isFalse);
            } else {
              expect(
                report.outcome,
                isNot(HwdecOutcome.unexpected),
                reason:
                    'the default list gave no conclusive outcome: '
                    '${report.line}',
              );
            }
          }
        }
        expect(events, isNot(contains(MpvVideoEventKind.deviceLost)));
      } finally {
        // Unmount, then controller before player (dispose-order rule).
        texture.value = null;
        await _nextFrame();
        await eventSub?.cancel();
        await controller?.dispose();
        await player.dispose();
        temp.deleteSync(recursive: true);
      }
    });
  });
}
