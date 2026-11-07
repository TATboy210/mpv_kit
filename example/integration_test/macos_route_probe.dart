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

// --- hwdec section (Phase 13-04, HWD-04) ------------------------------------

/// Largest mean absolute B/G/R difference between the software-decoded
/// reference screenshot and the videotoolbox screenshot of the same sample.
/// H.264/HEVC decoding is bit exact and both screenshots go through the same
/// renderer, so a correct zero-copy import differs by about 0; a green frame
/// or a wrongly imported plane differs by dozens. Fixed before any CI run:
/// do not relax it after seeing a result without recording the observed
/// values and a user decision.
const double routeFrameMaxMeanAbsDiff = 8.0;

/// A raw `screenshot-raw` frame in `bgr0` order (the fourth byte is padding).
final class RouteBgr0Frame {
  const RouteBgr0Frame({
    required this.width,
    required this.height,
    required this.stride,
    required this.data,
  });

  final int width;
  final int height;

  /// Bytes per row; may exceed `width * 4`.
  final int stride;
  final List<int> data;

  /// Whether [data] holds every row the geometry claims.
  bool get isComplete =>
      width > 0 &&
      height > 0 &&
      stride >= width * 4 &&
      data.length >= stride * height;
}

/// Share of non-black pixels of a bgr0 frame.
final class RouteBgr0Stats {
  const RouteBgr0Stats({required this.nonBlackRatio});

  /// Share of pixels with any of B/G/R above [routeNonBlackChannel].
  final double nonBlackRatio;
}

/// Statistics of a bgr0 frame, or null when [data] is shorter than
/// `stride * height` (a truncated read must not look like a black frame).
RouteBgr0Stats? routeBgr0Stats(
  int width,
  int height,
  int stride,
  List<int> data,
) {
  final frame = RouteBgr0Frame(
    width: width,
    height: height,
    stride: stride,
    data: data,
  );
  if (!frame.isComplete) return null;
  var nonBlack = 0;
  for (var y = 0; y < height; y++) {
    final row = y * stride;
    for (var x = 0; x < width; x++) {
      final i = row + x * 4;
      if (data[i] > routeNonBlackChannel ||
          data[i + 1] > routeNonBlackChannel ||
          data[i + 2] > routeNonBlackChannel) {
        nonBlack++;
      }
    }
  }
  return RouteBgr0Stats(nonBlackRatio: nonBlack / (width * height));
}

/// Mean absolute difference over the B, G and R channels of two frames of
/// the same size (the padding byte is ignored), or null when the sizes
/// differ or either frame is truncated.
double? routeBgr0MeanAbsDiff(RouteBgr0Frame a, RouteBgr0Frame b) {
  if (a.width != b.width || a.height != b.height) return null;
  if (!a.isComplete || !b.isComplete) return null;
  var sum = 0;
  for (var y = 0; y < a.height; y++) {
    final rowA = y * a.stride;
    final rowB = y * b.stride;
    for (var x = 0; x < a.width; x++) {
      final ia = rowA + x * 4;
      final ib = rowB + x * 4;
      sum +=
          (a.data[ia] - b.data[ib]).abs() +
          (a.data[ia + 1] - b.data[ib + 1]).abs() +
          (a.data[ia + 2] - b.data[ib + 2]).abs();
    }
  }
  return sum / (a.width * a.height * 3);
}

/// Two captures of the same paused frame agree when their mean absolute
/// B/G/R difference is at most this. A healthy renderer gives 0.0 (the same
/// frame through the same pipeline, observed as `screenshotDiff 0.0`
/// between two software runs); the margin only covers dithering.
const double routeCaptureMaxMeanAbsDiff = 1.0;

/// Takes a screenshot that can be used as evidence of the picture.
///
/// Why a single capture is not evidence: on the hosted macos-15 runners
/// (Apple Paravirtual device behind MoltenVK) mpv's `screenshot-raw` of a
/// paused frame intermittently comes back black or only partly drawn
/// (non-black share 0.0, 0.00003, 0.007; mean difference to the reference
/// 10, 54, 129) while the Flutter texture still matches the reference. It
/// hit the software `hwdec=no` reference as well as the videotoolbox run,
/// with and without the FIFO ready queue (runs 40827789016 on c1cf4a1 and
/// 40884999133 on 9f2b78f fail identically; f644220 and 11b728a have the
/// same sources and differ in outcome).
///
/// A capture is therefore accepted only when the next capture of the same
/// frame agrees with it ([routeCaptureMaxMeanAbsDiff]) and is not black.
/// A truly black or wrong picture is the same on every capture and still
/// fails the caller's assertions; only a capture that differs from its
/// successor is discarded. At most [maxCaptures] are taken, [gap] apart;
/// when none agree the last one is returned so the assertions judge it.
/// Every discarded capture is reported through [note].
///
/// Returns null when the first capture is unavailable (null is data, as in
/// the caller), and the last usable capture when a later one is unavailable.
Future<RouteBgr0Frame?> routeStableCapture(
  Future<RouteBgr0Frame?> Function() capture, {
  int maxCaptures = 5,
  Duration gap = const Duration(milliseconds: 300),
  void Function(String message)? note,
}) async {
  assert(maxCaptures >= 1, 'at least one capture');
  final first = await capture();
  if (first == null) return null;
  // Declared non-null: a promoted `var` loses its promotion in the loop.
  RouteBgr0Frame previous = first;
  for (var taken = 1; taken < maxCaptures; taken++) {
    await Future<void>.delayed(gap);
    final next = await capture();
    if (next == null) return previous;
    final diff = routeBgr0MeanAbsDiff(previous, next);
    final stats = routeBgr0Stats(
      next.width,
      next.height,
      next.stride,
      next.data,
    );
    final black = stats != null && stats.nonBlackRatio < routeMinNonBlackRatio;
    if (diff != null && diff <= routeCaptureMaxMeanAbsDiff && !black) {
      return next;
    }
    note?.call(
      'capture ${taken + 1}/$maxCaptures '
      '${black ? 'is black' : 'differs from the previous capture'} '
      '(mean abs diff ${diff?.toStringAsFixed(4)}); taking another',
    );
    previous = next;
  }
  return previous;
}

/// What the screenshot comparison says about the frame under test.
enum RouteFrameCheck {
  /// Not black and within [routeFrameMaxMeanAbsDiff] of the reference.
  match,

  /// Black, a different size, or too far from the reference.
  mismatch,

  /// No usable comparison: no screenshot, a software fallback screenshot
  /// (which does not exercise the zero-copy render path), or no reference.
  unavailable,
}

/// Compares the screenshot of the sample under test with the software
/// reference. [fellBack] is true when mpv logged `Falling back to software
/// screenshot.`: that screenshot downloads the hardware frame on the CPU and
/// proves nothing about the zero-copy render path.
RouteFrameCheck routeScreenshotCheck({
  required bool fellBack,
  RouteBgr0Frame? screenshot,
  RouteBgr0Frame? reference,
}) {
  if (screenshot == null || fellBack || reference == null) {
    return RouteFrameCheck.unavailable;
  }
  final stats = routeBgr0Stats(
    screenshot.width,
    screenshot.height,
    screenshot.stride,
    screenshot.data,
  );
  if (stats == null) return RouteFrameCheck.unavailable;
  if (screenshot.width != reference.width ||
      screenshot.height != reference.height) {
    return RouteFrameCheck.mismatch;
  }
  if (stats.nonBlackRatio < routeMinNonBlackRatio) {
    return RouteFrameCheck.mismatch;
  }
  final diff = routeBgr0MeanAbsDiff(screenshot, reference);
  if (diff == null) return RouteFrameCheck.unavailable;
  return diff > routeFrameMaxMeanAbsDiff
      ? RouteFrameCheck.mismatch
      : RouteFrameCheck.match;
}

/// Classifies one `hwdec=videotoolbox` run of a sample.
///
/// Zero-copy is only claimed when three independent markers agree:
/// `hwdec-current` is `videotoolbox` (mpv selects the non-copy variant only
/// when the `hwdec_vt_pl` interop loaded), `video-params/pixelformat` is the
/// hardware format `videotoolbox` and `video-params/hw-pixelformat` names
/// the underlying format (`nv12` / `p010`). The screenshot then decides
/// between `zero-copy`, `zero-copy-bad-frame` and
/// `zero-copy-render-unverified`.
///
/// Software decoding is `unavailable` only with at least one failure
/// evidence line that does not come from the screenshot module; without it
/// the outcome is `unavailable-unexplained`, which fails the test: an
/// unreachable hardware path must come with a reason.
String routeHwdecOutcome({
  required String requested,
  String? hwdecCurrent,
  String? pixelformat,
  String? hwPixelformat,
  required RouteFrameCheck screenshot,
  required int failureEvidence,
  required bool referenceValid,
}) {
  if (!referenceValid) return 'reference-invalid';
  final zeroCopyMarkers =
      hwdecCurrent == 'videotoolbox' &&
      pixelformat == 'videotoolbox' &&
      hwPixelformat != null &&
      hwPixelformat.isNotEmpty;
  if (zeroCopyMarkers) {
    return switch (screenshot) {
      RouteFrameCheck.mismatch => 'zero-copy-bad-frame',
      RouteFrameCheck.match => 'zero-copy',
      RouteFrameCheck.unavailable => 'zero-copy-render-unverified',
    };
  }
  if (hwdecCurrent == 'videotoolbox-copy' ||
      (hwdecCurrent == 'videotoolbox' && pixelformat != 'videotoolbox')) {
    return 'copy-back';
  }
  if (hwdecCurrent == null || hwdecCurrent.isEmpty || hwdecCurrent == 'no') {
    // The Player's default list is a record, not a claim: software decoding
    // there is simply what the list ended up with, evidence or not.
    if (requested == 'default') return 'software';
    return failureEvidence > 0 ? 'unavailable' : 'unavailable-unexplained';
  }
  return 'unexpected';
}

/// Outcomes that let the gated hwdec runs pass. The others are product or
/// evidence facts (bad frame, copy-back, an unexplained software fallback,
/// an invalid reference) and fail the test.
const Set<String> routeGatedOutcomesAllowed = {
  'zero-copy',
  'zero-copy-render-unverified',
  'unavailable',
};

/// mpv log lines worth keeping as evidence of what the hwdec path did.
final RegExp routeHwdecLogPattern = RegExp(
  r'videotoolbox|hwdec|hwaccel|hardware|interop|PL_HANDLE_MTL_TEX|'
  r'CVPixelBuffer|screenshot',
  caseSensitive: false,
);

/// Evidence lines that say the hardware path did not work. Lines from the
/// `screenshot` module never count (the screenshot fallback message matches
/// "falling back" but says nothing about decoding).
final RegExp routeHwdecFailurePattern = RegExp(
  r'fail|error|not supported|unsupported|could not|cannot|requires|'
  r'falling back|software decoding|not trying',
  caseSensitive: false,
);

/// Tightly packed RGBA bytes of [region] (logical coordinates) of an RGBA
/// image, or null when the scaled rectangle is empty, falls outside the
/// image, or [rgba] is shorter than the image claims. [sx] / [sy] scale
/// logical to image pixels, exactly like [routeRegionStats].
Uint8List? routeRgbaRegion(
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
  if (rgba.length < width * height * 4) return null;
  final rowBytes = (right - left) * 4;
  final out = Uint8List(rowBytes * (bottom - top));
  for (var y = top; y < bottom; y++) {
    final from = (y * width + left) * 4;
    out.setRange((y - top) * rowBytes, (y - top + 1) * rowBytes, rgba, from);
  }
  return out;
}

/// Mean absolute difference over the R, G and B channels of two tightly
/// packed RGBA regions (alpha is ignored), or null when the lengths differ
/// or are empty.
double? routeRgbaMeanAbsDiff(Uint8List a, Uint8List b) {
  if (a.length != b.length || a.isEmpty) return null;
  var sum = 0;
  for (var i = 0; i < a.length; i += 4) {
    sum +=
        (a[i] - b[i]).abs() +
        (a[i + 1] - b[i + 1]).abs() +
        (a[i + 2] - b[i + 2]).abs();
  }
  return sum / (a.length ~/ 4 * 3);
}

/// What the Flutter texture channel (a `toImage` read of the mounted
/// texture) says about the frame under test, compared with the software
/// reference read in the same way. Recorded, never asserted: whether
/// `toImage` can see a macOS external texture at all is not known in
/// advance.
///
/// - `blind`: the channel cannot tell (the reference texture was not
///   visible, the texture under test was not composited or the read failed,
///   or there is no region diff to compare).
/// - `mismatch`: the texture region under test is black or further than
///   [routeFrameMaxMeanAbsDiff] from the reference.
/// - `match`: otherwise.
String routeFlutterFrame({
  required String referenceVisibility,
  required String visibility,
  double? regionDiff,
  double? nonBlackRatio,
}) {
  if (referenceVisibility != 'texture-visible') return 'blind';
  if (visibility == 'texture-not-composited' || visibility == 'indeterminate') {
    return 'blind';
  }
  if (visibility == 'texture-composited-black') return 'mismatch';
  if (nonBlackRatio != null && nonBlackRatio < routeMinNonBlackRatio) {
    return 'mismatch';
  }
  if (regionDiff == null) return 'blind';
  return regionDiff > routeFrameMaxMeanAbsDiff ? 'mismatch' : 'match';
}
