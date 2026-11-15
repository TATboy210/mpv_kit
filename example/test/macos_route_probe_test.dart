// Unit tests of the macOS route probe's pure helpers (Phase 13, MAC-02):
// region statistics and the visibility decision table. No plugin and no
// libmpv: the 640x360 RGBA images are built byte by byte.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/macos_route_probe.dart';

const _width = 640;
const _height = 360;

/// Fills [region] (whole pixels) of [rgba] with an opaque colour.
void _fill(Uint8List rgba, Rect region, int r, int g, int b) {
  for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
    for (var x = region.left.toInt(); x < region.right.toInt(); x++) {
      final i = (y * _width + x) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = 255;
    }
  }
}

/// A probe image: everything black, the control patch red and the background
/// region green, plus an optional fill of the texture region.
Uint8List _probeImage({
  (int, int, int)? texture,
  (int, int, int) control = (255, 0, 0),
}) {
  final rgba = Uint8List(_width * _height * 4);
  _fill(rgba, routeControlRegion, control.$1, control.$2, control.$3);
  _fill(rgba, routeBackgroundRegion, 0, 200, 0);
  if (texture != null) {
    _fill(rgba, routeTextureRegion, texture.$1, texture.$2, texture.$3);
  }
  return rgba;
}

/// Classifies [rgba] the way the integration test does (scale 1.0).
String _classify(Uint8List rgba) {
  RouteRegionStats? stats(Rect region) => routeRegionStats(
    rgba,
    width: _width,
    height: _height,
    region: region,
    sx: 1,
    sy: 1,
  );
  return routeVisibility(
    texture: stats(routeTextureRegion),
    control: stats(routeControlRegion),
    background: stats(routeBackgroundRegion),
  );
}

/// A solid-colour bgr0 frame (the padding byte stays 0). [color] is in the
/// screenshot's byte order: (B, G, R).
RouteBgr0Frame _bgr0({
  int width = 16,
  int height = 8,
  (int, int, int) color = (100, 50, 200),
}) {
  final data = List<int>.filled(width * 4 * height, 0);
  for (var i = 0; i < width * height; i++) {
    data[i * 4] = color.$1;
    data[i * 4 + 1] = color.$2;
    data[i * 4 + 2] = color.$3;
  }
  return RouteBgr0Frame(
    width: width,
    height: height,
    stride: width * 4,
    data: data,
  );
}

/// [frame] with only its first [drawnRows] rows kept, the rest black: a
/// readback that returned before the GPU finished drawing.
RouteBgr0Frame _partial(RouteBgr0Frame frame, {required int drawnRows}) {
  final data = List<int>.of(frame.data);
  for (var i = drawnRows * frame.stride; i < data.length; i++) {
    data[i] = 0;
  }
  return RouteBgr0Frame(
    width: frame.width,
    height: frame.height,
    stride: frame.stride,
    data: data,
  );
}

void main() {
  group('route probe visibility', () {
    test('black texture region with visible control is composited-black', () {
      expect(_classify(_probeImage()), 'texture-composited-black');
    });

    test('texture region still background green is not-composited', () {
      expect(
        _classify(_probeImage(texture: (0, 200, 0))),
        'texture-not-composited',
      );
    });

    test('black control patch makes the probe indeterminate', () {
      expect(
        _classify(_probeImage(texture: (200, 100, 50), control: (0, 0, 0))),
        'indeterminate',
      );
    });

    test('coloured texture region is texture-visible', () {
      expect(
        _classify(_probeImage(texture: (200, 100, 50))),
        'texture-visible',
      );
    });
  });

  group('route probe region statistics', () {
    test('region outside the scaled image yields null and indeterminate', () {
      final rgba = _probeImage(texture: (200, 100, 50));
      // A scale of 2 pushes the control patch (right edge 640) to 1280 px,
      // beyond the 640 px wide image.
      final outside = routeRegionStats(
        rgba,
        width: _width,
        height: _height,
        region: routeControlRegion,
        sx: 2,
        sy: 2,
      );
      expect(outside, isNull);
      expect(
        routeVisibility(
          texture: routeRegionStats(
            rgba,
            width: _width,
            height: _height,
            region: routeTextureRegion,
            sx: 1,
            sy: 1,
          ),
          control: outside,
          background: routeRegionStats(
            rgba,
            width: _width,
            height: _height,
            region: routeBackgroundRegion,
            sx: 1,
            sy: 1,
          ),
        ),
        'indeterminate',
      );
    });
  });

  group('route screenshot check', () {
    test('identical frames match', () {
      expect(
        routeScreenshotCheck(
          fellBack: false,
          screenshot: _bgr0(),
          reference: _bgr0(),
        ),
        RouteFrameCheck.match,
      );
    });

    test('black screenshot is a mismatch', () {
      expect(
        routeScreenshotCheck(
          fellBack: false,
          screenshot: _bgr0(color: (0, 0, 0)),
          reference: _bgr0(),
        ),
        RouteFrameCheck.mismatch,
      );
    });

    test('uniform green against a coloured reference is a mismatch', () {
      // The classic wrong-plane import: the whole frame turns green.
      expect(
        routeScreenshotCheck(
          fellBack: false,
          screenshot: _bgr0(color: (0, 135, 0)),
          reference: _bgr0(),
        ),
        RouteFrameCheck.mismatch,
      );
    });

    test('software fallback screenshot is unavailable, not a match', () {
      expect(
        routeScreenshotCheck(
          fellBack: true,
          screenshot: _bgr0(),
          reference: _bgr0(),
        ),
        RouteFrameCheck.unavailable,
      );
    });

    test('different sizes are a mismatch', () {
      expect(
        routeScreenshotCheck(
          fellBack: false,
          screenshot: _bgr0(width: 8, height: 4),
          reference: _bgr0(),
        ),
        RouteFrameCheck.mismatch,
      );
    });

    test('missing screenshot is unavailable', () {
      expect(
        routeScreenshotCheck(
          fellBack: false,
          screenshot: null,
          reference: _bgr0(),
        ),
        RouteFrameCheck.unavailable,
      );
    });

    test('a difference just below the threshold still matches', () {
      // 7 on every channel: mean absolute difference 7.0 <= 8.0.
      expect(
        routeScreenshotCheck(
          fellBack: false,
          screenshot: _bgr0(color: (107, 57, 207)),
          reference: _bgr0(color: (100, 50, 200)),
        ),
        RouteFrameCheck.match,
      );
    });

    test('truncated data has no statistics, it is not a black frame', () {
      expect(routeBgr0Stats(4, 4, 16, List<int>.filled(10, 0)), isNull);
    });
  });

  group('route stable capture', () {
    final good = _bgr0();
    final black = _bgr0(color: (0, 0, 0));
    // A half-drawn readback: the first rows carry the picture, the rest is
    // still black (the 10 / 54 / 129 mean differences seen on macos-15).
    final partial = _partial(good, drawnRows: 2);

    /// Runs [routeStableCapture] over a scripted list of captures and
    /// returns (frame, number of captures taken, discard notes).
    Future<(RouteBgr0Frame?, int, List<String>)> run(
      List<RouteBgr0Frame?> script, {
      int maxCaptures = 5,
    }) async {
      var taken = 0;
      final notes = <String>[];
      final frame = await routeStableCapture(
        () async => script[taken++],
        maxCaptures: maxCaptures,
        gap: Duration.zero,
        note: notes.add,
      );
      return (frame, taken, notes);
    }

    test('two agreeing captures are accepted without a note', () async {
      final (frame, taken, notes) = await run([good, good]);
      expect(frame, same(good));
      expect(taken, 2);
      expect(notes, isEmpty);
    });

    test('an unavailable first capture stays unavailable', () async {
      final (frame, taken, _) = await run([null]);
      expect(frame, isNull);
      expect(taken, 1);
    });

    test('an unavailable second capture keeps the first', () async {
      final (frame, taken, notes) = await run([good, null]);
      expect(frame, same(good));
      expect(taken, 2);
      expect(notes, isEmpty);
    });

    test('a black first capture is discarded for the agreeing pair', () async {
      final (frame, taken, notes) = await run([black, good, good]);
      expect(frame, same(good));
      expect(taken, 3);
      expect(notes, hasLength(1));
    });

    test('a partly drawn capture is discarded for the agreeing pair', () async {
      final (frame, taken, notes) = await run([partial, good, good]);
      expect(frame, same(good));
      expect(taken, 3);
      expect(notes, hasLength(1));
    });

    test('a partly drawn second capture does not confirm the first', () async {
      final (frame, taken, _) = await run([good, partial, good, good]);
      expect(frame, same(good));
      expect(taken, 4);
    });

    test(
      'an agreeing black pair is not accepted while captures remain',
      () async {
        final (frame, taken, notes) = await run([black, black, good, good]);
        expect(frame, same(good));
        expect(taken, 4);
        expect(notes, hasLength(2));
      },
    );

    test('a picture that is black on every capture is still black', () async {
      // The assertions of the caller must still see a persistent failure.
      final (frame, taken, notes) = await run(List.filled(5, black));
      expect(frame, same(black));
      expect(taken, 5, reason: 'bounded by maxCaptures');
      expect(notes, hasLength(4));
    });

    test('captures that never agree return the last one', () async {
      final (frame, taken, notes) = await run([
        good,
        partial,
        black,
        partial,
        good,
      ]);
      expect(frame, same(good));
      expect(taken, 5);
      expect(notes, hasLength(4));
    });

    test('a persistently wrong but stable picture is returned as is', () async {
      // Green against a coloured reference is the zero-copy defect the
      // screenshot check exists for: every capture agrees, none is dropped.
      final green = _bgr0(color: (0, 135, 0));
      final (frame, taken, notes) = await run([green, green]);
      expect(frame, same(green));
      expect(taken, 2);
      expect(notes, isEmpty);
    });

    test('a single capture is taken as is when maxCaptures is 1', () async {
      final (frame, taken, _) = await run([black], maxCaptures: 1);
      expect(frame, same(black));
      expect(taken, 1);
    });
  });

  group('route hwdec outcome', () {
    String classify({
      String requested = 'videotoolbox',
      String? current = 'videotoolbox',
      String? pixelformat = 'videotoolbox',
      String? hwPixelformat = 'nv12',
      RouteFrameCheck screenshot = RouteFrameCheck.match,
      int failures = 0,
      bool referenceValid = true,
    }) => routeHwdecOutcome(
      requested: requested,
      hwdecCurrent: current,
      pixelformat: pixelformat,
      hwPixelformat: hwPixelformat,
      screenshot: screenshot,
      failureEvidence: failures,
      referenceValid: referenceValid,
    );

    test('three markers and a matching screenshot are zero-copy', () {
      expect(classify(), 'zero-copy');
    });

    test('markers with a mismatching screenshot are a bad frame', () {
      expect(
        classify(screenshot: RouteFrameCheck.mismatch),
        'zero-copy-bad-frame',
      );
    });

    test('markers without a usable screenshot are render-unverified', () {
      expect(
        classify(screenshot: RouteFrameCheck.unavailable),
        'zero-copy-render-unverified',
      );
    });

    test('videotoolbox-copy is copy-back', () {
      expect(
        classify(
          current: 'videotoolbox-copy',
          pixelformat: 'nv12',
          hwPixelformat: null,
        ),
        'copy-back',
      );
    });

    test('videotoolbox with a software pixel format is copy-back', () {
      expect(classify(pixelformat: 'nv12', hwPixelformat: null), 'copy-back');
    });

    test('software decode with failure evidence is unavailable', () {
      expect(
        classify(
          current: 'no',
          pixelformat: 'yuv420p',
          hwPixelformat: null,
          failures: 2,
        ),
        'unavailable',
      );
    });

    test('software decode without evidence is unexplained', () {
      expect(
        classify(current: 'no', pixelformat: 'yuv420p', hwPixelformat: null),
        'unavailable-unexplained',
      );
    });

    test('an invalid reference wins over everything', () {
      expect(classify(referenceValid: false), 'reference-invalid');
    });

    test('another hwdec is unexpected', () {
      expect(
        classify(current: 'vaapi', pixelformat: 'vaapi', hwPixelformat: 'nv12'),
        'unexpected',
      );
    });

    test('the allowed set holds exactly the three non-failing outcomes', () {
      expect(routeGatedOutcomesAllowed, {
        'zero-copy',
        'zero-copy-render-unverified',
        'unavailable',
      });
    });

    test('default list: software decoding is software, whatever the log', () {
      for (final failures in [0, 3]) {
        expect(
          classify(
            requested: 'default',
            current: 'no',
            pixelformat: 'yuv420p',
            hwPixelformat: null,
            failures: failures,
          ),
          'software',
        );
      }
    });

    test('default list: zero-copy markers keep the videotoolbox rules', () {
      expect(classify(requested: 'default'), 'zero-copy');
      expect(
        classify(requested: 'default', screenshot: RouteFrameCheck.mismatch),
        'zero-copy-bad-frame',
      );
    });
  });

  group('route flutter texture channel', () {
    test('a reference texture that is not visible is blind', () {
      expect(
        routeFlutterFrame(
          referenceVisibility: 'texture-not-composited',
          visibility: 'texture-visible',
          regionDiff: 0,
          nonBlackRatio: 1,
        ),
        'blind',
      );
    });

    test('a texture that was not composited under test is blind', () {
      for (final visibility in ['texture-not-composited', 'indeterminate']) {
        expect(
          routeFlutterFrame(
            referenceVisibility: 'texture-visible',
            visibility: visibility,
          ),
          'blind',
        );
      }
    });

    test('a black texture region under test is a mismatch', () {
      expect(
        routeFlutterFrame(
          referenceVisibility: 'texture-visible',
          visibility: 'texture-composited-black',
        ),
        'mismatch',
      );
    });

    test('a region far from the reference is a mismatch', () {
      expect(
        routeFlutterFrame(
          referenceVisibility: 'texture-visible',
          visibility: 'texture-visible',
          regionDiff: 40,
          nonBlackRatio: 0.9,
        ),
        'mismatch',
      );
    });

    test('a region close to the reference matches', () {
      expect(
        routeFlutterFrame(
          referenceVisibility: 'texture-visible',
          visibility: 'texture-visible',
          regionDiff: 0.5,
          nonBlackRatio: 0.9,
        ),
        'match',
      );
    });
  });

  group('route rgba region helpers', () {
    test('region bytes are tightly packed and the diff is per channel', () {
      final a = _probeImage(texture: (200, 100, 50));
      final b = _probeImage(texture: (210, 100, 50));
      final regionA = routeRgbaRegion(
        a,
        width: _width,
        height: _height,
        region: routeTextureRegion,
        sx: 1,
        sy: 1,
      );
      final regionB = routeRgbaRegion(
        b,
        width: _width,
        height: _height,
        region: routeTextureRegion,
        sx: 1,
        sy: 1,
      );
      expect(regionA, isNotNull);
      expect(regionA!.length, 320 * 180 * 4);
      // Only R differs, by 10: the mean over three channels is 10 / 3.
      expect(routeRgbaMeanAbsDiff(regionA, regionB!), closeTo(10 / 3, 1e-9));
    });

    test('regions of different sizes have no diff', () {
      expect(routeRgbaMeanAbsDiff(Uint8List(8), Uint8List(16)), isNull);
    });
  });
}
