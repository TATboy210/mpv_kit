// Real-file portrait <-> landscape switch measurement (Windows, real plugin).
//
// Reproduces the user report: switching between a portrait and a landscape
// file in one window makes the picture stall, and the texture grows in steps
// from a small size to the final one. The test runs the real MpvVideo widget
// on real files and records, for every switch:
//   - how long it takes until the texture rect matches the new video's
//     contain-fit size and stays there (settle time)
//   - the sequence of distinct texture sizes (the "small to large" steps)
//   - the native resize events that the renderer emitted during the switch
//   - the largest gap between two frame samples (a stall proxy)
//   - frames where the texture was missing or fully black
//
//   $env:MPV_KIT_SWITCH_PORTRAIT = 'D:\...\12370391_2160_3840_60fps.mp4'
//   $env:MPV_KIT_SWITCH_LANDSCAPE = 'D:\...\13349743_1920_1080_25fps.mp4'
//   $env:MPV_KIT_SWITCH_ROUNDS = '4'   # optional, default 2 (2 switches each)
//   flutter test integration_test/real_file_switch_test.dart -d windows
//
// Each switch also reports the native ring reallocation cost (allocCount,
// allocUs), read from the plugin's `stats` method, to separate the GPU stall
// of a resize from the time spent waiting for the new file.
//
// Skipped when either variable is unset or points at a missing file. The
// hard assertions are only "texture stays mounted" and "each switch settles";
// the timings are printed as one REAL-SWITCH JSON line for comparison between
// builds (the gaps include the sampling cost of this probe itself).
// Printing is the report channel:
// ignore_for_file: avoid_print
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

/// Logical size of the probed box, a landscape window that every file is
/// letterboxed into. Portrait files shrink to a narrow texture inside it.
const _boxWidth = 960.0;
const _boxHeight = 540.0;

/// Pixels with any channel above this are not black.
const _blackLevel = 8;

/// A texture frame with less non-black share than this is treated as black.
const _minNonBlack = 0.05;

/// Consecutive frames the texture must match the expected fit size before a
/// switch counts as settled.
const _stableFrames = 6;

/// Tolerance, in logical pixels, when comparing the texture size to the fit.
const _sizeTolerance = 2.0;

/// Sample every n-th pixel of the texture for the black-frame share.
const _pixelStep = 2;

/// Bound for one switch: a switch that never settles fails the test.
const _settleTimeout = Duration(seconds: 20);

/// Diagnostic channel of the plugin; `stats` returns lifetime frame counters.
const _channel = MethodChannel('mpv_kit_video');

/// Next frame, or a bounded wait when the engine is idle.
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 500)),
]);

/// One read of the Texture rect inside the probe boundary.
final class _Frame {
  const _Frame({
    required this.found,
    required this.size,
    required this.nonBlack,
  });

  /// False when the Texture is not in the tree (a missing frame).
  final bool found;

  /// Logical size of the Texture rect.
  final Size size;

  /// Share of sampled pixels that are not black, in `[0, 1]`.
  final double nonBlack;

  bool get isBlack => found && size.width > 0 && nonBlack < _minNonBlack;
}

/// Reads the boundary and measures the Texture rect only, so the letterbox
/// bars around a portrait picture never count as black.
Future<_Frame> _sampleFrame(WidgetTester tester, GlobalKey key) async {
  const missing = _Frame(found: false, size: Size.zero, nonBlack: 0);
  final texture = find.byType(Texture);
  if (texture.evaluate().isEmpty) return missing;
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return missing;

  final box = tester.getRect(find.byKey(key));
  final rect = tester.getRect(texture);
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw StateError('toByteData returned null');
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    // The boundary is captured at pixelRatio 1, so logical offsets are pixel
    // offsets inside the image.
    final left = (rect.left - box.left).round().clamp(0, image.width);
    final top = (rect.top - box.top).round().clamp(0, image.height);
    final right = (rect.right - box.left).round().clamp(left, image.width);
    final bottom = (rect.bottom - box.top).round().clamp(top, image.height);
    final w = right - left, h = bottom - top;
    if (w <= 0 || h <= 0) {
      return _Frame(found: true, size: rect.size, nonBlack: 0);
    }
    var sampled = 0, nonBlack = 0;
    for (var y = 0; y < h; y += _pixelStep) {
      for (var x = 0; x < w; x += _pixelStep) {
        final i = (((top + y) * image.width) + left + x) * 4;
        sampled++;
        if (data[i] > _blackLevel ||
            data[i + 1] > _blackLevel ||
            data[i + 2] > _blackLevel) {
          nonBlack++;
        }
      }
    }
    return _Frame(
      found: true,
      size: rect.size,
      nonBlack: sampled == 0 ? 0 : nonBlack / sampled,
    );
  } finally {
    image.dispose();
  }
}

/// Contain-fit size of the displayed video inside [box], honouring rotation.
///
/// Returns null while mpv has not reported the geometry yet. This mirrors the
/// fit that [MpvVideo] uses for `BoxFit.contain`, so a settled texture rect
/// must equal it.
Size? _expectedFit(MpvVideoParams? p, Size box) {
  final w = p?.width, h = p?.height;
  if (p == null || w == null || h == null || w == 0 || h == 0) return null;
  final rotated = p.rotate % 180 != 0;
  final vw = (rotated ? h : w).toDouble();
  final vh = (rotated ? w : h).toDouble();
  final scale = min(box.width / vw, box.height / vh);
  return Size(vw * scale, vh * scale);
}

/// Measurements for one switch, serialised into the REAL-SWITCH line.
final class _SwitchResult {
  const _SwitchResult({
    required this.label,
    required this.settled,
    required this.settleMs,
    required this.frames,
    required this.missing,
    required this.black,
    required this.maxGapMs,
    required this.sizes,
    required this.resizes,
    required this.params,
    required this.allocCount,
    required this.allocUs,
  });

  final String label;
  final bool settled;

  /// Time from the switch request until the size was stable, or the timeout.
  final int settleMs;
  final int frames;
  final int missing;

  /// Frames whose texture share of non-black pixels was below the threshold.
  final int black;

  /// Largest interval between two consecutive frame samples.
  final int maxGapMs;

  /// Distinct texture sizes in order, each with the time it appeared.
  final List<String> sizes;

  /// Native `resize` events emitted during this switch, as `WxH@ms`.
  final List<String> resizes;

  /// `video-params` geometry reports during this switch, as `WxH@ms`. These
  /// are the Dart-side trigger of the texture size change.
  final List<String> params;

  /// Ring reallocations the renderer performed during this switch, and the
  /// time they cost on the render thread (from the native `stats` counters).
  final int allocCount;
  final int allocUs;

  Map<String, Object?> toJson() => {
    'file': label,
    'settled': settled,
    'settleMs': settleMs,
    'frames': frames,
    'missing': missing,
    'black': black,
    'maxGapMs': maxGapMs,
    'sizes': sizes,
    'params': params,
    'resizes': resizes,
    'allocCount': allocCount,
    'allocUs': allocUs,
  };
}

/// Switches [player] to [path] and samples the texture until it has settled
/// at the new video's fit size, or until [_settleTimeout].
Future<_SwitchResult> _switchTo({
  required WidgetTester tester,
  required GlobalKey key,
  required Player player,
  required String path,
  required List<String> resizeLog,
  required List<String> paramsLog,
  required void Function(Stopwatch? clock) setClock,
  required int textureId,
}) async {
  // Record the resize events and geometry reports that belong to this switch.
  final resizeStart = resizeLog.length;
  final paramsStart = paramsLog.length;
  final before = await _allocStats(textureId);
  final clock = Stopwatch()..start();
  setClock(clock);

  await player.open(path);

  final sizes = <String>[];
  var frames = 0, missing = 0, black = 0, maxGapMs = 0, stable = 0;
  var settled = false;
  var settleMs = _settleTimeout.inMilliseconds;
  var lastMs = clock.elapsedMilliseconds;

  while (!settled && clock.elapsed < _settleTimeout) {
    await _nextFrame();
    final nowMs = clock.elapsedMilliseconds;
    maxGapMs = nowMs - lastMs > maxGapMs ? nowMs - lastMs : maxGapMs;
    lastMs = nowMs;

    final frame = await _sampleFrame(tester, key);
    frames++;
    if (!frame.found) {
      missing++;
      stable = 0;
      continue;
    }
    if (frame.isBlack) black++;

    final label = '${frame.size.width.round()}x${frame.size.height.round()}';
    if (sizes.isEmpty || sizes.last.split('@').first != label) {
      sizes.add('$label@${nowMs}ms');
    }

    // Fixed render target (contain): the texture is the whole box.
    final expected = const Size(_boxWidth, _boxHeight);
    final matches =
        expected != null &&
        (frame.size.width - expected.width).abs() <= _sizeTolerance &&
        (frame.size.height - expected.height).abs() <= _sizeTolerance &&
        !frame.isBlack;
    stable = matches ? stable + 1 : 0;
    if (stable >= _stableFrames) {
      settled = true;
      settleMs = nowMs;
    }
  }

  setClock(null);
  final after = await _allocStats(textureId);
  return _SwitchResult(
    label: path.split(RegExp(r'[\\/]')).last,
    settled: settled,
    settleMs: settleMs,
    frames: frames,
    missing: missing,
    black: black,
    maxGapMs: maxGapMs,
    sizes: sizes,
    resizes: resizeLog.sublist(resizeStart),
    params: paramsLog.sublist(paramsStart),
    allocCount: after.count - before.count,
    allocUs: after.totalUs - before.totalUs,
  );
}

/// Number of landscape/portrait rounds, from MPV_KIT_SWITCH_ROUNDS (default 2).
/// Invalid or non-positive values fall back to the default.
int _roundsFromEnv() {
  final parsed = int.tryParse(
    Platform.environment['MPV_KIT_SWITCH_ROUNDS'] ?? '',
  );
  return (parsed == null || parsed < 1) ? 2 : parsed;
}

/// Reallocation counters of the native renderer, read through the plugin's
/// diagnostic `stats` method. Zeros when the method is unavailable.
Future<({int count, int totalUs})> _allocStats(int textureId) async {
  final stats = await _channel.invokeMapMethod<String, Object?>('stats', {
    'textureId': textureId,
  });
  return (
    count: (stats?['allocCount'] as int?) ?? 0,
    totalUs: (stats?['allocTotalUs'] as int?) ?? 0,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final portrait = Platform.environment['MPV_KIT_SWITCH_PORTRAIT'];
  final landscape = Platform.environment['MPV_KIT_SWITCH_LANDSCAPE'];
  final skipReason = (portrait == null || landscape == null)
      ? 'set MPV_KIT_SWITCH_PORTRAIT and MPV_KIT_SWITCH_LANDSCAPE'
      : (!File(portrait).existsSync() || !File(landscape).existsSync())
      ? 'both sample files must exist'
      : null;
  if (skipReason != null) print('SKIP real-file switch: $skipReason');

  testWidgets(
    'real portrait <-> landscape switches stay mounted and settle',
    (tester) async {
      final key = GlobalKey();
      final mounted = ValueNotifier<MpvVideoController?>(null);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ValueListenableBuilder<MpvVideoController?>(
              valueListenable: mounted,
              builder: (context, c, child) => RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: _boxWidth,
                  height: _boxHeight,
                  child: c == null ? null : MpvVideo(controller: c),
                ),
              ),
            ),
          ),
        ),
      );

      // Default hwdec on purpose: the user's report is about real playback,
      // not about a software-decode probe.
      final player = Player(
        options: const {
          'ao': 'null',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
        },
      );
      final controller = await MpvVideoController.create(player);

      final resizeLog = <String>[];
      final paramsLog = <String>[];
      Stopwatch? clock;
      final sub = controller.events.listen((e) {
        if (e.kind == MpvVideoEventKind.resize) {
          resizeLog.add('${e.message}@${clock?.elapsedMilliseconds ?? -1}ms');
        }
      });
      final paramsSub = player.videoParams.stream.listen((p) {
        final w = p?.width, h = p?.height;
        if (w == null || h == null) return;
        paramsLog.add('${w}x$h@${clock?.elapsedMilliseconds ?? -1}ms');
      });

      final results = <_SwitchResult>[];
      final rounds = _roundsFromEnv();
      // Non-null here: the test is skipped when either variable is missing.
      final landscapePath = landscape!;
      final portraitPath = portrait!;
      late _SwitchResult warmup;
      await tester.runAsync(() async {
        mounted.value = controller;
        await _nextFrame();

        // The first load is a cold start: MpvVideo shows no Texture until mpv
        // reports the geometry. It is measured for the report but not asserted.
        warmup = await _switchTo(
          tester: tester,
          key: key,
          player: player,
          path: portraitPath,
          resizeLog: resizeLog,
          paramsLog: paramsLog,
          setClock: (c) => clock = c,
          textureId: controller.textureId,
        );

        // Each round switches landscape -> portrait, the direction in which
        // the step-wise growth was reported. Rounds repeat the same sequence
        // so that a single noisy switch does not decide the result.
        for (var round = 0; round < rounds; round++) {
          for (final path in <String>[landscapePath, portraitPath]) {
            results.add(
              await _switchTo(
                tester: tester,
                key: key,
                player: player,
                path: path,
                resizeLog: resizeLog,
                paramsLog: paramsLog,
                setClock: (c) => clock = c,
                textureId: controller.textureId,
              ),
            );
          }
        }
      });

      // Lifetime compositor counters: a null descriptor after a frame was ever
      // shown means the picture was lost during the switches.
      final stats = await _channel.invokeMapMethod<String, Object?>('stats', {
        'textureId': controller.textureId,
      });

      final summary = {
        'backend': controller.backend.name,
        'reason': controller.reason,
        'warmup': warmup.toJson(),
        'switches': [for (final r in results) r.toJson()],
        'stats': stats,
      };
      print('REAL-SWITCH ${jsonEncode(summary)}');

      await sub.cancel();
      await paramsSub.cancel();
      await controller.dispose();
      await player.dispose();

      for (final r in results) {
        expect(
          r.missing,
          0,
          reason: '${r.label}: texture removed during the switch',
        );
        expect(
          r.settled,
          isTrue,
          reason: '${r.label}: size did not settle within $_settleTimeout',
        );
      }
    },
    skip: skipReason != null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
