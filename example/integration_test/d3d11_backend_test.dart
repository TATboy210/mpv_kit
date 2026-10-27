// Real-plugin test of the native Windows D3D11 backend (Phase 14, D3D-06).
//
// Run only by Windows CI and locally, always with MPV_KIT_VIDEO_API=d3d11
// (the controller must come up on the d3d11 backend, with no fallback):
//   MPV_KIT_VIDEO_API=d3d11 flutter test integration_test/d3d11_backend_test.dart -d windows
// with MPV_KIT_LIBMPV_PATH pointing at a libmpv that has the D3D11 render API
// (patch 0010) and the gpu-next D3D11 branch (patch 0004). A debug plugin
// build also honours MPV_KIT_D3D11_SYNC=query, which forces the
// D3D11_QUERY_EVENT completion path instead of the ID3D11Fence path; the
// value is echoed in the report line.
//
// One testWidgets with several sections: every extra testWidgets would
// start a new window and a new plugin instance (same reason as
// real_plugin_test.dart).
//
// Source: a 320x180 picture, red upper half and blue lower half, shown in a
// RepaintBoundary whose toImage() is the pixel probe. Sections:
//   (a) the controller reports the GPU zero-copy backend and a reason that
//       starts with MPV_KIT_EXPECT_REASON_PREFIX (default "d3d11 (gpu-next) on ");
//   (b) after the first frames the upper half is red and the lower half
//       blue (>= 95% of the probed pixels each);
//   (c) resize 640x360, 320x180: the texture id never changes, the first
//       read after each resize event is not black (>= 99% non-black: no
//       flicker through a black frame), and red/blue hold at every size;
//   (d) no device_lost, render_error or gpu_timeout event; dispose ends the
//       event stream.
// One D3D11-BACKEND {json} line reports the measurements.
//
// Printing is the report channel:
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

/// Logical size of the probed box. The texture is stretched into it whatever
/// size the renderer was asked for, so the probe image is always this size.
const _boxWidth = 320.0;
const _boxHeight = 180.0;

/// Share of the probed pixels that must have the expected colour.
const _minColorRatio = 0.95;

/// Share of the pixels that must not be black right after a resize event.
const _minNonBlackRatio = 0.99;

/// A channel above this value is not black.
const _blackLevel = 8;

/// "Red": R above, G and B below. "Blue" mirrors it. The picture is YUV
/// converted, so the channels are close to, not exactly, 255 and 0.
const _high = 192;
const _low = 64;

/// Pixels skipped at the box edge and around the red/blue seam, where
/// filtering blends the two colours.
const _edgeMargin = 4;
const _seamMargin = 12;

/// Upper bound for the renderer to report a requested size.
const _resizeTimeout = Duration(seconds: 10);

/// Upper bound for frames to flow, and for a colour read to settle after a
/// resize (new-size frames take a few render rounds to reach the front).
const _flowTimeout = Duration(seconds: 30);
const _settleTimeout = Duration(seconds: 10);

/// Reason head the test expects; the CI runner and the RTX 4060 differ in the
/// adapter name only.
String get _expectedReasonPrefix =>
    Platform.environment['MPV_KIT_EXPECT_REASON_PREFIX'] ??
    'd3d11 (gpu-next) on ';

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the test.
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

/// Colour shares of one toImage() read.
final class _Probe {
  const _Probe(this.redTop, this.blueBottom, this.nonBlack);

  /// Share of upper-half pixels that are red.
  final double redTop;

  /// Share of lower-half pixels that are blue.
  final double blueBottom;

  /// Share of all pixels with any channel above [_blackLevel].
  final double nonBlack;

  bool get isRedOverBlue =>
      redTop >= _minColorRatio && blueBottom >= _minColorRatio;

  Map<String, double> toJson() => {
    'redTop': redTop,
    'blueBottom': blueBottom,
    'nonBlack': nonBlack,
  };

  @override
  String toString() =>
      'redTop=${redTop.toStringAsFixed(3)} '
      'blueBottom=${blueBottom.toStringAsFixed(3)} '
      'nonBlack=${nonBlack.toStringAsFixed(3)}';

  /// Classifies the RGBA pixels of a [width]x[height] image.
  factory _Probe.fromRgba(List<int> rgba, int width, int height) {
    final mid = height ~/ 2;
    var red = 0, redTotal = 0, blue = 0, blueTotal = 0, nonBlack = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
        if (r > _blackLevel || g > _blackLevel || b > _blackLevel) nonBlack++;
        final inside =
            x >= _edgeMargin &&
            x < width - _edgeMargin &&
            y >= _edgeMargin &&
            y < height - _edgeMargin;
        if (!inside) continue;
        if (y < mid - _seamMargin) {
          redTotal++;
          if (r > _high && g < _low && b < _low) red++;
        } else if (y >= mid + _seamMargin) {
          blueTotal++;
          if (b > _high && r < _low && g < _low) blue++;
        }
      }
    }
    return _Probe(
      redTotal == 0 ? 0 : red / redTotal,
      blueTotal == 0 ? 0 : blue / blueTotal,
      nonBlack / (width * height),
    );
  }
}

/// Reads the probed box through RepaintBoundary.toImage, the channel that
/// sees external textures (12-02).
Future<_Probe> _readProbe(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('the probe boundary is not mounted');
  }
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw StateError('toByteData returned null');
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    return _Probe.fromRgba(data, image.width, image.height);
  } finally {
    image.dispose();
  }
}

/// Reads until red over blue holds (or [_settleTimeout] passes), then asserts
/// it. Only waits for frames to arrive: the thresholds are fixed.
Future<_Probe> _expectRedOverBlue(GlobalKey key, String label) async {
  var probe = await _readProbe(key);
  final deadline = DateTime.now().add(_settleTimeout);
  while (!probe.isRedOverBlue && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _nextFrame();
    probe = await _readProbe(key);
  }
  expect(
    probe.redTop,
    greaterThanOrEqualTo(_minColorRatio),
    reason: '$label: upper half must be red ($probe)',
  );
  expect(
    probe.blueBottom,
    greaterThanOrEqualTo(_minColorRatio),
    reason: '$label: lower half must be blue ($probe)',
  );
  return probe;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('d3d11 backend: pixels, resize without flicker, no errors', (
    tester,
  ) async {
    final key = GlobalKey();
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
            builder: (context, id, child) => RepaintBoundary(
              key: key,
              child: SizedBox(
                width: _boxWidth,
                height: _boxHeight,
                child: id == null ? null : Texture(textureId: id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final kinds = <MpvVideoEventKind>[];
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
      final sub = controller.events.listen(
        (e) => kinds.add(e.kind),
        onError: (Object _) {},
      );
      final done = Completer<void>();
      controller.events.listen((_) {}, onDone: done.complete);
      final textureId = controller.textureId;

      // (a) the backend and its reason.
      expect(
        controller.backend,
        MpvVideoBackend.vulkan,
        reason: 'd3d11 is a GPU zero-copy backend (ADR 0004)',
      );
      expect(
        controller.reason,
        startsWith(_expectedReasonPrefix),
        reason: 'MPV_KIT_VIDEO_API=d3d11 must select the d3d11 backend',
      );

      await player.open(
        'av://lavfi:color=c=red:s=320x90:r=30:d=60[top];'
        'color=c=blue:s=320x90:r=30:d=60[bottom];'
        '[top][bottom]vstack[out0]',
      );
      texture.value = textureId;
      await _resizeTo(controller, 320, 180);

      // (b) frames flow, then the picture is red over blue.
      final deadline = DateTime.now().add(_flowTimeout);
      while (DateTime.now().isBefore(deadline) &&
          player.mpv.tryGetProperty('estimated-vf-fps') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(
        player.mpv.tryGetProperty('estimated-vf-fps'),
        isNotNull,
        reason: 'the VO must produce frames on the d3d11 backend',
      );
      for (var i = 0; i < 5; i++) {
        await _nextFrame();
      }
      final probe = await _expectRedOverBlue(key, '320x180');

      // (c) resize: same texture id, no black frame, colours at every size.
      final resizeProbes = <String, _Probe>{};
      for (final (w, h) in const [(640, 360), (320, 180)]) {
        await _resizeTo(controller, w, h);
        // Immediately after the resize event: the front of the retired
        // generation must still be on screen, never a black frame.
        final first = await _readProbe(key);
        expect(
          first.nonBlack,
          greaterThanOrEqualTo(_minNonBlackRatio),
          reason: 'no black flash right after the resize to ${w}x$h ($first)',
        );
        expect(controller.textureId, textureId);
        resizeProbes['${w}x$h'] = await _expectRedOverBlue(key, '${w}x$h');
        expect(controller.textureId, textureId);
      }

      print(
        'D3D11-BACKEND ${jsonEncode({'backend': controller.backend.name, 'reason': controller.reason, 'textureId': textureId, 'probe': probe.toJson(), 'resizeProbe': resizeProbes.map((k, v) => MapEntry(k, v.toJson())), 'events': kinds.toSet().map((k) => k.name).toList()..sort(), 'syncEnv': Platform.environment['MPV_KIT_D3D11_SYNC'] ?? 'default'})}',
      );

      // (d) clean shutdown, no device or render trouble.
      texture.value = null;
      await _nextFrame();
      await controller.dispose();
      await done.future.timeout(const Duration(seconds: 5));
      for (final bad in [
        MpvVideoEventKind.deviceLost,
        MpvVideoEventKind.renderError,
        MpvVideoEventKind.gpuTimeout,
      ]) {
        expect(kinds, isNot(contains(bad)), reason: '${bad.name} event seen');
      }
      await player.dispose();
      await sub.cancel();
    });
  });
}
