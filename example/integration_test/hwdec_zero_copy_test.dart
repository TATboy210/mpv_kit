// Hardware-decode probe on real encoded samples (Phase 16, HWD-05).
//
// Nearly every other integration test plays lavfi raw video, which can only
// ever report `hwdec-current=no`. This one opens real H.264 / HEVC files so
// the Player's default hwdec list, the decoder and the renderer all have
// something to decide about, and prints what happened:
//
//   HWDEC-IDENTITY {"libmpv","attempts","backend","reason","defaultHwdec"}
//   HWDEC {json}      two lines per run (`first-frame`, `end`), the format of
//                     hwdec_probe.dart (`hwdec-1`)
//   HWDEC-RUN {json}  one line per run, keys in this order: schema, sample,
//                     api, requested, firstFrameMs, frameChecks (three
//                     `{"t","screenshot","diff"}`), flutterFrame, playedToEnd,
//                     hwdecStable, hwdecSeen, frameDrops, decoderDrops,
//                     voDelayed, renderErrors, deviceLost
//
// Every sample runs twice on the one Player and controller: first with the
// per-file option `hwdec=no` (the software reference), then with the
// Player's own default list. Each run
//  1. waits for a decoded and rendered frame (`firstFrameMs`),
//  2. pauses, seeks to the start and reads the Flutter texture channel
//     (`flutterFrame`: a toImage read of the mounted texture, compared with
//     the reference; `blind` where toImage cannot see an external texture),
//  3. seeks exactly to 0, duration/3 and 2*duration/3 and takes a VO
//     screenshot at each (`frameChecks`; the screenshot goes through the
//     renderer and the hwdec mapping, so it is the main "the picture is
//     right" channel; a software screenshot fallback is reported as
//     `software-fallback`, never as proof),
//  4. plays to the end, sampling `hwdec-current` once a second.
//
// Assertions: `hwdec=no` classifies as software (first frame and end), plays
// to the end and its screenshots, where available, are not black; the default
// run is never `unexpected`, plays to the end, and when any of its lines is
// zero-copy none of its three screenshot checks is a `mismatch` (a bad
// zero-copy frame is a product defect). No run may lose the device. A missing
// sample is a failure, not a skip; an unavailable `hwdec-current` is
// `unexpected`.
//
// Samples come from the app assets (`integration_test/route_samples/`, made
// by tools/make_hwdec_samples.sh and downloaded from the hwdec-samples
// artifact of native-verify). `MPV_KIT_HWDEC_SAMPLES` (a comma separated file
// name list) overrides the default list; `MPV_KIT_HWDEC_ZERO_COPY=yes` sets
// the Player option `d3d11va-zero-copy=yes` (16-06 comparison runs; the HWDEC
// line records the value). Both are read from --dart-define or the
// environment.
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
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';
import 'macos_route_probe.dart';

/// Sample list override, from --dart-define.
const _samplesDefine = String.fromEnvironment('MPV_KIT_HWDEC_SAMPLES');

/// `yes` sets `d3d11va-zero-copy=yes` on the Player, from --dart-define.
const _zeroCopyDefine = String.fromEnvironment('MPV_KIT_HWDEC_ZERO_COPY');

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

/// Time the compositor keeps pulling frames after a seek before a pixel is
/// read.
const _settle = Duration(milliseconds: 300);

/// Time for the last log events to arrive after a screenshot.
const _logSettle = Duration(milliseconds: 200);

/// Bound of one `screenshot-raw`; a timeout counts as "no screenshot".
const _screenshotTimeout = Duration(seconds: 10);

/// Extra time to play to the end beyond the sample's duration.
const _playMargin = Duration(seconds: 15);

/// Duration used when mpv does not report one (the samples are 4 s).
const _fallbackSeconds = 4.0;

/// Seek targets of the frame checks, as fractions of the duration.
const _seekFractions = [0.0, 1 / 3, 2 / 3];

/// Evidence line of mpv's software screenshot fallback.
const _fallbackLog = 'Falling back to software screenshot';

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the test (same helper as real_plugin_test.dart).
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

/// Pulls frames for [duration] so the compositor takes several of them.
Future<void> _settleFor(Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await _nextFrame();
  }
}

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

/// Whether the d3d11va zero-copy option is switched on for this run.
bool _zeroCopyRequested() =>
    (_zeroCopyDefine.isNotEmpty
        ? _zeroCopyDefine
        : Platform.environment['MPV_KIT_HWDEC_ZERO_COPY']) ==
    'yes';

/// Rounds an optional double to 4 decimals for the report.
double? _round4(double? value) =>
    value == null ? null : double.parse(value.toStringAsFixed(4));

/// Whether the property [name] is the bool `true`.
bool _isTrue(Player player, String name) =>
    player.mpv.tryGetProperty(name) == true;

/// An integer property, null when unavailable.
int? _intProperty(Player player, String name) {
  final value = player.mpv.tryGetProperty(name);
  return value is int ? value : null;
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

// --- Flutter texture channel (a copy of macos_route_test.dart's probe) ------

/// The probe tree: green background, the texture region, the red patch, all
/// inside one RepaintBoundary of the logical probe size. Positioned children
/// avoid the StackFit.expand pitfall of 12-02.
Widget _probeTree(GlobalKey key, ValueNotifier<int?> texture) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: routeProbeSize.width,
      height: routeProbeSize.height,
      child: RepaintBoundary(
        key: key,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: routeProbeBackground),
            ),
            Positioned.fromRect(
              rect: routeTextureRegion,
              child: ValueListenableBuilder<int?>(
                valueListenable: texture,
                builder: (context, id, child) => id == null
                    ? const SizedBox.shrink()
                    : Texture(textureId: id),
              ),
            ),
            Positioned.fromRect(
              rect: routeControlRegion,
              child: const ColoredBox(color: routeProbeControl),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// One toImage read of the probe tree: the visibility verdict and the texture
/// region's RGBA bytes (null when the read failed).
final class _PixelRead {
  const _PixelRead({
    required this.visibility,
    this.textureBytes,
    this.nonBlackRatio,
  });

  final String visibility;
  final Uint8List? textureBytes;
  final double? nonBlackRatio;
}

/// Reads the probe boundary through RenderRepaintBoundary.toImage. Any failure
/// yields an `indeterminate` read, which classifies as `blind`.
Future<_PixelRead> _readPixels(GlobalKey key) async {
  const failed = _PixelRead(visibility: 'indeterminate');
  try {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return failed;
    final logical = boundary.size;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return failed;
      // The ByteData may be an offset view (same slicing as 12-02).
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (data.length < image.width * image.height * 4) return failed;
      final sx = image.width / logical.width;
      final sy = image.height / logical.height;
      RouteRegionStats? stats(ui.Rect region) => routeRegionStats(
        data,
        width: image.width,
        height: image.height,
        region: region,
        sx: sx,
        sy: sy,
      );
      final texture = stats(routeTextureRegion);
      return _PixelRead(
        visibility: routeVisibility(
          texture: texture,
          control: stats(routeControlRegion),
          background: stats(routeBackgroundRegion),
        ),
        nonBlackRatio: texture?.nonBlackRatio,
        textureBytes: routeRgbaRegion(
          data,
          width: image.width,
          height: image.height,
          region: routeTextureRegion,
          sx: sx,
          sy: sy,
        ),
      );
    } finally {
      image.dispose();
    }
  } on Object catch (error) {
    // A failed read is data: it prints as blind.
    print('HWDEC-NOTE toImage read failed: ${error.runtimeType}: $error');
    return failed;
  }
}

/// The `flutterFrame` verdict of [run] against the software [reference].
String _flutterFrame(_PixelRead reference, _PixelRead run) {
  final refBytes = reference.textureBytes;
  final runBytes = run.textureBytes;
  return routeFlutterFrame(
    referenceVisibility: reference.visibility,
    visibility: run.visibility,
    regionDiff: refBytes == null || runBytes == null
        ? null
        : routeRgbaMeanAbsDiff(refBytes, runBytes),
    nonBlackRatio: run.nonBlackRatio,
  );
}

// --- VO screenshot channel ----------------------------------------------------

/// Whether mpv logged its software screenshot fallback since the last reset;
/// such a screenshot downloads the hardware frame on the CPU and proves
/// nothing about the render path.
final class _FallbackWatch {
  bool seen = false;

  void onLog(LogMessageEvent event) {
    if (event.text.contains(_fallbackLog)) seen = true;
  }
}

/// One frame check: the seek target, the verdict and the mean difference
/// against the reference frame of the same target.
final class _FrameCheck {
  const _FrameCheck(this.seconds, this.screenshot, this.diff);

  final double seconds;

  /// `match`, `mismatch`, `unavailable`, `software-fallback`, or `reference`
  /// for the software reference run itself.
  final String screenshot;
  final double? diff;

  Map<String, Object?> toJson() => {
    't': _round4(seconds),
    'screenshot': screenshot,
    'diff': _round4(diff),
  };
}

/// What one run produced. The reference run's frames and pixels are kept for
/// the default run's comparison.
final class _RunResult {
  const _RunResult({
    required this.frames,
    required this.checks,
    required this.pixel,
    required this.firstReport,
    required this.endReport,
    required this.playedToEnd,
    required this.deviceLost,
    required this.line,
  });

  final List<RouteBgr0Frame?> frames;
  final List<_FrameCheck> checks;
  final _PixelRead pixel;
  final HwdecReport firstReport;
  final HwdecReport endReport;
  final bool playedToEnd;

  /// Device losses during this run.
  final int deviceLost;

  /// The printed `HWDEC-RUN` line, for assertion messages.
  final String line;

  bool get anyZeroCopy => firstReport.zeroCopy || endReport.zeroCopy;
}

/// Seeks exactly to [seconds] and waits for the restart event plus a settle
/// period, so the new frame has reached the compositor.
Future<void> _seekExact(Player player, double seconds) async {
  final restarted = Completer<void>();
  final sub = player.mpv.events.listen((event) {
    if (event is PlaybackRestartEvent && !restarted.isCompleted) {
      restarted.complete();
    }
  });
  try {
    await player.seek(
      Duration(milliseconds: (seconds * 1000).round()),
      exact: true,
    );
    await restarted.future.timeout(_readyTimeout);
  } on TimeoutException {
    fail('no playback restart after seeking to ${seconds}s in $_readyTimeout');
  } finally {
    await sub.cancel();
  }
  await _settleFor(_settle);
}

/// Takes a `screenshot-raw` and returns it as a bgr0 frame; null when the
/// screenshot is unavailable (a timeout or an error is data, not a failure).
Future<RouteBgr0Frame?> _screenshot(Player player) async {
  try {
    final shot = await player.screenshot().timeout(_screenshotTimeout);
    if (shot == null || shot.format != 'bgr0') return null;
    return RouteBgr0Frame(
      width: shot.width,
      height: shot.height,
      stride: shot.stride,
      data: shot.data,
    );
  } on MpvException catch (error) {
    print('HWDEC-NOTE screenshot failed: $error');
  } on TimeoutException {
    print('HWDEC-NOTE screenshot timed out after $_screenshotTimeout');
  }
  return null;
}

/// Opens [path] (with `hwdec=no` when [requested] is `no`, otherwise with the
/// Player's default list) and returns the milliseconds until the VO reports a
/// frame rate. Fails when the decoder or the VO is not ready in
/// [_readyTimeout].
///
/// Readiness is any decoded size, not the 640x360 texture size: the 4K
/// sample (hevc-10bit-2160p) never reports 640x360, and waiting for it made
/// the first RTX 4060 run fail after 15 s (16-06 run A).
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
    if ((params?.width ?? 0) > 0 &&
        (params?.height ?? 0) > 0 &&
        player.mpv.tryGetProperty('estimated-vf-fps') != null) {
      return watch.elapsedMilliseconds;
    }
  }
  fail(
    '$path (requested=$requested): no decoded and rendered frame within '
    '$_readyTimeout',
  );
}

/// Plays from the start to the end of the file, sampling `hwdec-current` once
/// a second. Returns whether `eof-reached` came within the bound, and the
/// distinct values seen in order.
Future<(bool, List<String>)> _playToEnd(Player player, double seconds) async {
  final seen = <String>[];
  void sample() {
    final current = player.mpv.tryGetProperty('hwdec-current');
    if (current != null && !seen.contains('$current')) seen.add('$current');
  }

  await _seekExact(player, 0);
  player.play();
  final deadline = DateTime.now().add(
    Duration(milliseconds: (seconds * 1000).round()) + _playMargin,
  );
  while (DateTime.now().isBefore(deadline)) {
    sample();
    if (_isTrue(player, 'eof-reached')) return (true, seen);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  sample();
  return (_isTrue(player, 'eof-reached'), seen);
}

/// One run of [sample] with [requested] (`no` or the default list): first
/// frame, Flutter channel, three screenshot checks, play to the end. Prints
/// the HWDEC and HWDEC-RUN lines. [reference] is the software run of the same
/// sample, null for that run itself.
Future<_RunResult> _runOne({
  required Player player,
  required MpvVideoController controller,
  required GlobalKey boundaryKey,
  required List<MpvVideoEventKind> events,
  required _FallbackWatch watch,
  required String sample,
  required String path,
  required String requested,
  required _RunResult? reference,
}) async {
  int count(MpvVideoEventKind kind) => events.where((e) => e == kind).length;
  final errorsBefore = count(MpvVideoEventKind.renderError);
  final lostBefore = count(MpvVideoEventKind.deviceLost);

  final firstFrameMs = await _openAndWaitForFrame(player, path, requested);
  final first = await awaitHwdecReport(
    player.mpv.tryGetProperty,
    test: 'hwdec_zero_copy',
    sample: sample,
    at: 'first-frame',
    reason: controller.reason,
    requested: requested,
  );
  print(first.line);

  // Pause on a deterministic frame (the first one) for the pixel channels;
  // the frame a free-running play happens to stop on would differ between
  // the two runs.
  final durationValue = player.mpv.tryGetProperty('duration');
  final seconds = durationValue is num
      ? durationValue.toDouble()
      : _fallbackSeconds;
  player.pause();
  await _seekExact(player, 0);
  final pixel = await _readPixels(boundaryKey);
  final flutterFrame = reference == null
      ? 'reference'
      : _flutterFrame(reference.pixel, pixel);

  final frames = <RouteBgr0Frame?>[];
  final checks = <_FrameCheck>[];
  for (var i = 0; i < _seekFractions.length; i++) {
    final at = seconds * _seekFractions[i];
    if (i > 0) await _seekExact(player, at);
    watch.seen = false;
    final frame = await _screenshot(player);
    await Future<void>.delayed(_logSettle);
    frames.add(frame);
    final refFrame = reference?.frames[i];
    if (reference == null) {
      checks.add(_FrameCheck(at, 'reference', null));
    } else {
      final check = routeScreenshotCheck(
        fellBack: watch.seen,
        screenshot: frame,
        reference: refFrame,
      );
      checks.add(
        _FrameCheck(
          at,
          watch.seen ? 'software-fallback' : check.name,
          frame == null || refFrame == null
              ? null
              : routeBgr0MeanAbsDiff(frame, refFrame),
        ),
      );
    }
  }

  final (playedToEnd, seen) = await _playToEnd(player, seconds);
  final end = await awaitHwdecReport(
    player.mpv.tryGetProperty,
    test: 'hwdec_zero_copy',
    sample: sample,
    at: 'end',
    reason: controller.reason,
    requested: requested,
  );
  print(end.line);

  final deviceLost = count(MpvVideoEventKind.deviceLost) - lostBefore;
  final line =
      'HWDEC-RUN ${jsonEncode({
        'schema': 'hwdec-run-1',
        'sample': sample,
        'api': end.api,
        'requested': requested,
        'firstFrameMs': firstFrameMs,
        'frameChecks': [for (final c in checks) c.toJson()],
        'flutterFrame': flutterFrame,
        'playedToEnd': playedToEnd,
        'hwdecStable': seen.length <= 1,
        'hwdecSeen': seen,
        'frameDrops': _intProperty(player, 'frame-drop-count'),
        'decoderDrops': _intProperty(player, 'decoder-frame-drop-count'),
        'voDelayed': _intProperty(player, 'vo-delayed-frame-count'),
        'renderErrors': count(MpvVideoEventKind.renderError) - errorsBefore,
        'deviceLost': deviceLost,
      })}';
  print(line);
  return _RunResult(
    frames: frames,
    checks: checks,
    pixel: pixel,
    firstReport: first,
    endReport: end,
    playedToEnd: playedToEnd,
    deviceLost: deviceLost,
    line: line,
  );
}

/// The assertions of the software reference run.
void _expectReference(_RunResult run) {
  for (final report in [run.firstReport, run.endReport]) {
    expect(
      report.outcome,
      HwdecOutcome.software,
      reason: 'hwdec=no must decode in software: ${report.line}',
    );
    expect(report.zeroCopy, isFalse, reason: report.line);
  }
  expect(run.playedToEnd, isTrue, reason: run.line);
  expect(run.deviceLost, 0, reason: run.line);
  // A reference screenshot that exists must show a picture; one that could
  // not be taken is recorded in the line (the frame itself is proven by the
  // VO frame rate the first-frame wait requires).
  for (final frame in run.frames.nonNulls) {
    final stats = routeBgr0Stats(
      frame.width,
      frame.height,
      frame.stride,
      frame.data,
    );
    expect(
      stats?.nonBlackRatio ?? 0,
      greaterThanOrEqualTo(routeMinNonBlackRatio),
      reason: 'black reference screenshot: ${run.line}',
    );
  }
}

/// The assertions of a run with the Player's default hwdec list.
void _expectDefault(_RunResult run) {
  for (final report in [run.firstReport, run.endReport]) {
    expect(
      report.outcome,
      isNot(HwdecOutcome.unexpected),
      reason: 'the default list gave no conclusive outcome: ${report.line}',
    );
  }
  expect(run.playedToEnd, isTrue, reason: run.line);
  expect(run.deviceLost, 0, reason: run.line);
  if (run.anyZeroCopy) {
    // A zero-copy run with a wrong picture is a product defect.
    for (final check in run.checks) {
      expect(check.screenshot, isNot('mismatch'), reason: run.line);
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('hwdec zero-copy probe on real samples', (tester) async {
    final names = _sampleNames();
    // The texture the compositor samples; pumped before runAsync (a tree
    // pumped inside it is not reliably composed).
    final texture = ValueNotifier<int?>(null);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(_probeTree(boundaryKey, texture));

    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('mpv_kit_hwdec_');
      // `hwdec` is not overridden: the Player's default list is under test.
      final player = Player(
        options: {
          'ao': 'null',
          if (_zeroCopyRequested()) 'd3d11va-zero-copy': 'yes',
        },
      );
      MpvVideoController? controller;
      StreamSubscription<MpvVideoEvent>? eventSub;
      StreamSubscription<LogMessageEvent>? logSub;
      try {
        // Read before any file is loaded, as option text (the property is a
        // list; List.toString would print brackets).
        final defaultHwdec = hwdecOptionText(
          player.mpv.tryGetProperty('hwdec'),
        );
        final samples = await _stageSamples(names, temp);
        final created = await MpvVideoController.create(player);
        controller = created;
        final events = <MpvVideoEventKind>[];
        eventSub = created.events.listen(
          (e) => events.add(e.kind),
          onError: (Object _) {},
        );
        // The fallback evidence line is a verbose-level message.
        final watch = _FallbackWatch();
        logSub = player.logs.listen(watch.onLog);
        player.setLogLevel('v');
        print(
          'HWDEC-IDENTITY ${jsonEncode({'libmpv': MpvLibrary.resolvedPath, 'attempts': MpvLibrary.lastOpenAttempts, 'backend': created.backend.name, 'reason': created.reason, 'defaultHwdec': defaultHwdec})}',
        );

        texture.value = created.textureId;
        await _nextFrame();
        await _resizeTo(created, _width, _height);

        for (final MapEntry(key: name, value: path) in samples.entries) {
          final sample = name.replaceAll('.mp4', '');
          Future<_RunResult> run(String requested, _RunResult? reference) =>
              _runOne(
                player: player,
                controller: created,
                boundaryKey: boundaryKey,
                events: events,
                watch: watch,
                sample: sample,
                path: path,
                requested: requested,
                reference: reference,
              );
          // Reference first (software), then the default list.
          final reference = await run('no', null);
          _expectReference(reference);
          _expectDefault(await run(defaultHwdec, reference));
        }
        expect(events, isNot(contains(MpvVideoEventKind.deviceLost)));
      } finally {
        // Unmount, then controller before player (dispose-order rule).
        texture.value = null;
        await _nextFrame();
        await logSub?.cancel();
        await eventSub?.cancel();
        await controller?.dispose();
        await player.dispose();
        temp.deleteSync(recursive: true);
      }
    });
  });
}
