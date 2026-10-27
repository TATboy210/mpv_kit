/// Pure helpers of the macOS route probe (Phase 13, MAC-02).
///
/// Region statistics, the visibility decision table and the probe geometry
/// used by `macos_route_test.dart`. The file is self-contained on purpose:
/// it depends only on `dart:typed_data` and `package:flutter/painting.dart`,
/// not on the plugin, so the same file also compiles inside the
/// pre-Phase-12 tree (3a5f450), which has no `impeller_smoke_modes.dart`.
///
/// The method is the Phase 12 probe-control design (green background, red
/// control patch, texture region, one `RepaintBoundary.toImage` channel).
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Logical size of the probe tree (width x height).
const Size routeProbeSize = Size(640, 360);

/// Where the Flutter texture is mounted (logical coordinates of the
/// 640x360 tree). Same rectangle as 12-02's probe control.
const Rect routeTextureRegion = Rect.fromLTRB(0, 0, 320, 180);

/// The red control patch: proves the probe reads non-texture content at all.
const Rect routeControlRegion = Rect.fromLTRB(576, 296, 640, 360);

/// A background-only region that overlaps neither the texture nor the patch.
const Rect routeBackgroundRegion = Rect.fromLTRB(400, 200, 560, 340);

/// Probe background, (0, 200, 0). Fills every pixel of the tree that is not
/// covered by the texture or the control patch.
const Color routeProbeBackground = Color(0xFF00C800);

/// Probe control patch colour (pure red).
const Color routeProbeControl = Color(0xFFFF0000);

/// A region counts as "visible" when at least this share of its pixels is
/// non-black (Phase 10 `_probePixels` rule, 10-08 decision table).
const double routeMinNonBlackRatio = 0.01;

/// Share the control and background regions must reach before the texture
/// region may be judged at all (12-02 probe control).
const double routeControlVisibleRatio = 0.9;

/// A texture region at least this green shows the background through it:
/// the texture was not composited into the probe image (12-02).
const double routeTextureOccludedRatio = 0.5;

/// A pixel is "background green" when every channel is within this distance
/// of (0, 200, 0) (12-02 probe control).
const int routeGreenTolerance = 24;

/// Any channel above this value makes a pixel "non-black" (Phase 10 rule).
const int routeNonBlackChannel = 8;

/// The libmpv the hook bundle puts into the app. The macOS default library
/// name list starts with it, so a different resolved path means the probe
/// measured some other libmpv.
const String routeBundleLibrary = '@rpath/mpv.2.framework/mpv.2';

/// Pixel statistics for one rectangle of the probe image.
final class RouteRegionStats {
  const RouteRegionStats({
    required this.nonBlackRatio,
    required this.greenFraction,
    required this.meanR,
    required this.meanG,
    required this.meanB,
  });

  /// Share of pixels with any channel > [routeNonBlackChannel].
  final double nonBlackRatio;

  /// Share of pixels within [routeGreenTolerance] of (0, 200, 0).
  final double greenFraction;

  final double meanR;
  final double meanG;
  final double meanB;

  /// Evidence form: every number is rounded to 4 decimals so the printed
  /// lines stay short and byte-stable between the two trees.
  Map<String, Object?> toJson() => {
    'nonBlackRatio': _round4(nonBlackRatio),
    'greenFraction': _round4(greenFraction),
    'meanR': _round4(meanR),
    'meanG': _round4(meanG),
    'meanB': _round4(meanB),
  };
}

double _round4(double value) => double.parse(value.toStringAsFixed(4));

/// Statistics for [region] (logical coordinates) of an RGBA image of
/// [width] x [height] pixels, or null when the scaled rectangle is empty or
/// falls outside the image. [sx] / [sy] scale logical to image pixels.
RouteRegionStats? routeRegionStats(
  Uint8List rgba, {
  required int width,
  required int height,
  required Rect region,
  required double sx,
  required double sy,
}) {
  final left = (region.left * sx).round();
  final top = (region.top * sy).round();
  final right = (region.right * sx).round();
  final bottom = (region.bottom * sy).round();
  if (left < 0 || top < 0 || right > width || bottom > height) return null;
  if (right <= left || bottom <= top) return null;
  var nonBlack = 0;
  var green = 0;
  var sumR = 0;
  var sumG = 0;
  var sumB = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      if (r > routeNonBlackChannel ||
          g > routeNonBlackChannel ||
          b > routeNonBlackChannel) {
        nonBlack++;
      }
      if (r <= routeGreenTolerance &&
          (g - 200).abs() <= routeGreenTolerance &&
          b <= routeGreenTolerance) {
        green++;
      }
      sumR += r;
      sumG += g;
      sumB += b;
    }
  }
  final pixels = (right - left) * (bottom - top);
  return RouteRegionStats(
    nonBlackRatio: nonBlack / pixels,
    greenFraction: green / pixels,
    meanR: sumR / pixels,
    meanG: sumG / pixels,
    meanB: sumB / pixels,
  );
}

/// The 10-08 / 12-02 decision table, in the same order:
/// any region missing, or the control / background not visible ->
/// `indeterminate` (the probe channel itself failed); texture still green ->
/// `texture-not-composited`; texture black -> `texture-composited-black`;
/// otherwise `texture-visible`.
String routeVisibility({
  RouteRegionStats? texture,
  RouteRegionStats? control,
  RouteRegionStats? background,
}) {
  if (texture == null || control == null || background == null) {
    return 'indeterminate';
  }
  if (control.nonBlackRatio < routeControlVisibleRatio ||
      background.greenFraction < routeControlVisibleRatio) {
    return 'indeterminate';
  }
  if (texture.greenFraction >= routeTextureOccludedRatio) {
    return 'texture-not-composited';
  }
  if (texture.nonBlackRatio < routeMinNonBlackRatio) {
    return 'texture-composited-black';
  }
  return 'texture-visible';
}
