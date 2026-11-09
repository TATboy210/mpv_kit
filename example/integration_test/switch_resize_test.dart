// Real-plugin Windows test: switching files, rapid resizes and pause/resume
// must never unmount the texture or leave a fully black frame. Covers the
// default Vulkan zero-copy chain, the native D3D11 backend
// (MPV_KIT_VIDEO_API=d3d11) and the software pixel path.
//
//   flutter test integration_test/switch_resize_test.dart -d windows
//   MPV_KIT_VIDEO_API=d3d11 flutter test integration_test/switch_resize_test.dart -d windows
//   MPV_KIT_VIDEO_API=software flutter test integration_test/switch_resize_test.dart -d windows
//
// The widget tree is the real MpvVideo; RepaintBoundary.toImage() sees the
// external texture. Samples are cropped to the Texture rect so letterbox
// bars of a changed aspect ratio never count as black frames.
//
// A switch may show one or two transitional frames while the renderer
// moves to the new size (mpv can publish the first new-file frame into the
// previous ring before the setSize lands, letterboxed). Those frames are
// not black; the test requires the texture to stay mounted, no frame to be
// fully black, and the settled picture to be correct.
//
// Printing is the report channel:
// ignore_for_file: avoid_print
@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

/// Logical size of the probed box.
const _boxWidth = 400.0;
const _boxHeight = 300.0;

/// A channel above this value is not black.
const _blackLevel = 8;

/// Share of the probed pixels that must be fully black to fail a switch.
const _minNonBlack = 0.05;

/// "Red", "lime" and "blue": one channel above, the other two below.
const _high = 192;
const _low = 64;

/// Pixels skipped around the frame edge and the colour seam.
const _edgeMargin = 2;
const _seamMargin = 10;

/// Share of the probed pixels that must have the expected colour.
const _minColorRatio = 0.9;

const _nextFrameTimeout = Duration(milliseconds: 500);
const _settleTimeout = Duration(seconds: 10);
const _flowTimeout = Duration(seconds: 30);

const _channel = MethodChannel('mpv_kit_video');

String _source({
  required String top,
  required String bottom,
  required int w,
  required int h,
}) =>
    'av://lavfi:color=c=$top:s=${w}x${h ~/ 2}:r=30:d=120[top];'
    'color=c=$bottom:s=${w}x${h ~/ 2}:r=30:d=120[bottom];'
    '[top][bottom]vstack[out0]';

Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(_nextFrameTimeout),
]);

/// One read of the Texture rect inside the probe boundary.
final class _Sample {
  const _Sample({
    required this.found,
    required this.nonBlack,
    required this.top,
    required this.bottom,
    required this.width,
    required this.height,
  });

  /// False when the Texture was not in the tree (the old black-switch bug).
  final bool found;
  final double nonBlack;
  final double top;
  final double bottom;
  final int width;
  final int height;

  bool isColor(String color) => switch (color) {
    'red' || 'green' => top >= _minColorRatio && bottom >= _minColorRatio,
    _ => false,
  };

  @override
  String toString() =>
      'found=$found ${width}x$height nonBlack=${nonBlack.toStringAsFixed(3)} '
      'top=${top.toStringAsFixed(3)} bottom=${bottom.toStringAsFixed(3)}';
}

bool _isRed(int r, int g, int b) => r > _high && g < _low && b < _low;
bool _isGreen(int r, int g, int b) => g > _high && r < _low && b < _low;
bool _isBlue(int r, int g, int b) => b > _high && r < _low && g < _low;

/// Reads the boundary and classifies the Texture rect only.
Future<_Sample> _sample(WidgetTester tester, GlobalKey key) async {
  final texture = find.byType(Texture);
  if (texture.evaluate().isEmpty) {
    return const _Sample(
      found: false,
      nonBlack: 0,
      top: 0,
      bottom: 0,
      width: 0,
      height: 0,
    );
  }
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary;
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
    final left = (rect.left - box.left).round().clamp(0, image.width);
    final top = (rect.top - box.top).round().clamp(0, image.height);
    final right = (rect.right - box.left).round().clamp(left, image.width);
    final bottom = (rect.bottom - box.top).round().clamp(top, image.height);
    final w = right - left, h = bottom - top;
    if (w <= 0 || h <= 0) {
      return const _Sample(
        found: true,
        nonBlack: 0,
        top: 0,
        bottom: 0,
        width: 0,
        height: 0,
      );
    }
    final mid = h ~/ 2;
    var nonBlack = 0, topHit = 0, topTotal = 0, bottomHit = 0, bottomTotal = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (((top + y) * image.width) + left + x) * 4;
        final r = data[i], g = data[i + 1], b = data[i + 2];
        if (r > _blackLevel || g > _blackLevel || b > _blackLevel) nonBlack++;
        final inside =
            x >= _edgeMargin &&
            x < w - _edgeMargin &&
            y >= _edgeMargin &&
            y < h - _edgeMargin;
        if (!inside) continue;
        if (y < mid - _seamMargin) {
          topTotal++;
          if (_isRed(r, g, b) || _isGreen(r, g, b)) topHit++;
        } else if (y >= mid + _seamMargin) {
          bottomTotal++;
          if (_isBlue(r, g, b)) bottomHit++;
        }
      }
    }
    return _Sample(
      found: true,
      nonBlack: nonBlack / (w * h),
      top: topTotal == 0 ? 0 : topHit / topTotal,
      bottom: bottomTotal == 0 ? 0 : bottomHit / bottomTotal,
      width: w,
      height: h,
    );
  } finally {
    image.dispose();
  }
}

/// Waits until the frame shows [color] over blue, bounded.
Future<_Sample> _settleColor(
  WidgetTester tester,
  GlobalKey key,
  String color,
) async {
  final deadline = DateTime.now().add(_settleTimeout);
  var last = await _sample(tester, key);
  while (!(last.found && last.isColor(color)) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _nextFrame();
    last = await _sample(tester, key);
  }
  return last;
}

/// Waits until the Texture shows a non-black picture, bounded.
Future<_Sample> _settlePicture(WidgetTester tester, GlobalKey key) async {
  final deadline = DateTime.now().add(_settleTimeout);
  var last = await _sample(tester, key);
  while (!(last.found && last.nonBlack >= _minColorRatio) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _nextFrame();
    last = await _sample(tester, key);
  }
  return last;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('switch, rapid resize and pause/resume never blank', (
    tester,
  ) async {
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

    final kinds = <MpvVideoEventKind>[];
    final player = Player(
      options: const {
        'vo': 'libmpv',
        'hwdec': 'no', // the render path is the subject, not the decoder
        'keep-open': 'yes',
        'idle': 'yes',
        'terminal': 'no',
        'ao': 'null',
      },
    );
    final controller = await MpvVideoController.create(player);
    final sub = controller.events.listen((e) => kinds.add(e.kind));
    await tester.runAsync(() async {
      mounted.value = controller;
      await _nextFrame();
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      expect(boundary, isNotNull);

      Future<_Sample> openAndSettle(String url, String color) async {
        await player.open(url);
        final s = await _settleColor(tester, key, color);
        expect(s.found, isTrue, reason: 'Texture must stay mounted');
        expect(s.isColor(color), isTrue,
            reason: 'expected $color over blue after settling: $s');
        return s;
      }

      /// Switches to [url] while sampling every frame; returns the number of
      /// samples, the missing-Texture count and the worst non-black share.
      Future<({int samples, int missing, int black, double worst})> switchTo(
        String url, {
        required bool play,
        int minSamples = 40,
      }) async {
        final done = player.open(url, play: play);
        var finished = false;
        unawaited(done.whenComplete(() => finished = true));
        var samples = 0, missing = 0, black = 0;
        var worst = 1.0;
        while (!finished || samples < minSamples) {
          await _nextFrame();
          final s = await _sample(tester, key);
          samples++;
          if (!s.found) missing++;
          if (s.nonBlack < _minNonBlack) black++;
          if (s.nonBlack < worst) worst = s.nonBlack;
          if (samples > 600) break; // bounded
        }
        return (samples: samples, missing: missing, black: black, worst: worst);
      }

      // First frames before any switch: the probe must be able to see them.
      await openAndSettle(
        _source(top: 'red', bottom: 'blue', w: 320, h: 180),
        'red',
      );
      final deadline = DateTime.now().add(_flowTimeout);
      while (player.mpv.tryGetProperty('estimated-vf-fps') == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(player.mpv.tryGetProperty('estimated-vf-fps'), isNotNull);

      // (a) Switch while playing to another 16:9 source, sampling every
      // frame of the transition.
      final a = await switchTo(
        _source(top: 'lime', bottom: 'blue', w: 640, h: 360),
        play: true,
      );
      expect(a.missing, 0, reason: 'Texture removed during the switch');
      expect(a.black, 0, reason: 'fully black frame during the switch');
      final switched = await _settleColor(tester, key, 'green');
      expect(switched.isColor('green'), isTrue, reason: '$switched');

      // (a2) Switch to a different aspect: the Texture rect changes, so the
      // per-frame colour probe is not meaningful; mounting and the settled
      // picture are.
      final a2 = await switchTo(
        _source(top: 'lime', bottom: 'blue', w: 240, h: 320),
        play: true,
      );
      expect(a2.missing, 0, reason: 'Texture removed during aspect switch');
      final portrait = await _settleColor(tester, key, 'green');
      expect(portrait.isColor('green'), isTrue, reason: '$portrait');

      // (b) Switch while paused: the old or the new frame may be shown, but
      // never nothing and never a fully black frame.
      player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final b = await switchTo(
        _source(top: 'red', bottom: 'blue', w: 320, h: 180),
        play: false,
      );
      expect(b.missing, 0, reason: 'Texture removed while paused');
      expect(b.black, 0, reason: 'fully black frame while paused');
      player.play();
      final resumed = await _settleColor(tester, key, 'red');
      expect(resumed.isColor('red'), isTrue, reason: '$resumed');

      // (c) Rapid resize: 20 requests without waiting for any of them.
      const sizes = [
        (640, 360),
        (320, 180),
        (800, 450),
        (400, 225),
        (960, 540),
        (480, 270),
      ];
      for (var i = 0; i < 20; i++) {
        final s = sizes[i % sizes.length];
        unawaited(controller.setSize(s.$1, s.$2));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final afterRapid = await _settlePicture(tester, key);
      expect(afterRapid.found, isTrue);
      expect(afterRapid.nonBlack, greaterThanOrEqualTo(_minColorRatio),
          reason: 'black frame after rapid resizes: $afterRapid');
      final rapidColor = await _settleColor(tester, key, 'red');
      expect(rapidColor.isColor('red'), isTrue, reason: '$rapidColor');

      // (d) Pause, resize twice back to back, resume.
      player.pause();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      unawaited(controller.setSize(640, 360));
      unawaited(controller.setSize(320, 180));
      final pausedResize = await _settlePicture(tester, key);
      expect(pausedResize.found, isTrue);
      expect(pausedResize.nonBlack, greaterThanOrEqualTo(_minColorRatio),
          reason: 'black frame after resize while paused: $pausedResize');
      player.play();
      final afterResume = await _settleColor(tester, key, 'red');
      expect(afterResume.isColor('red'), isTrue, reason: '$afterResume');

      // The native side never lost a frame after one existed.
      final stats = await _channel.invokeMapMethod<String, Object?>('stats', {
        'textureId': controller.textureId,
      });
      print(
        'SWITCH-RESIZE ${jsonEncode({
          'backend': controller.backend.name,
          'reason': controller.reason,
          'textureId': controller.textureId,
          'switch': {
            'samples': a.samples,
            'missing': a.missing,
            'black': a.black,
            'worstNonBlack': a.worst,
          },
          'aspectSwitch': {'samples': a2.samples, 'missing': a2.missing},
          'pausedSwitch': {
            'samples': b.samples,
            'missing': b.missing,
            'black': b.black,
            'worstNonBlack': b.worst,
          },
          'stats': stats,
          'events': kinds.toSet().map((k) => k.name).toList()..sort(),
        })}',
      );
      if (controller.backend == MpvVideoBackend.vulkan) {
        expect(
          stats?['nullDescribes'],
          0,
          reason: 'the compositor lost its frame after one was shown',
        );
      } else {
        expect(
          stats?['nullPixels'],
          0,
          reason: 'the software path lost its frame after one was shown',
        );
      }
      expect(
        kinds,
        isNot(contains(MpvVideoEventKind.deviceLost)),
        reason: 'device lost',
      );
      expect(
        kinds.where((k) => k == MpvVideoEventKind.renderError).length,
        lessThan(10),
      );

      await sub.cancel();
      await controller.dispose();
      await player.dispose();
    });
  });
}
