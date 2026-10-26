part of 'impeller_smoke_test.dart';

// Evidence-only modes of the Impeller composition smoke
// (impeller_smoke_test.dart). The main file keeps the measured D-05 workload
// (part 1 -> part 2 -> part 3) and the mode dispatch; everything selected by
// MPV_KIT_SMOKE_DIAG / MPV_KIT_SMOKE_MODE lives here:
//
//   MPV_KIT_SMOKE_DIAG=soak | soak-after-4k
//       10-07 soak-abort reproducer: part-1 replay, optional 4K prelude, then
//       the shared soak rounds, trace only.
//   MPV_KIT_SMOKE_DIAG=probe
//       12-02 probe control (WR-03): a green background, a red control patch
//       and a texture region read through the same RepaintBoundary.toImage
//       channel part 2 uses, so a black texture read can be told apart from
//       "the probe never sees external textures".
//
// None of these modes calls _classify or emits a `"stage":"complete"` line:
// they cannot be mistaken for a D-05 measurement.
//
// Printing is the report channel:
// ignore_for_file: avoid_print

/// Probe-control background, (0, 200, 0). Fills every pixel of the control
/// tree that is not covered by the texture or the red patch.
const Color _probeBackground = Color(0xFF00C800);

/// Probe-control patch: proves the probe reads non-texture content at all.
const Color _probeControl = Color(0xFFFF0000);

/// Logical regions of the 640x360 control tree. The background region is
/// chosen to overlap neither the texture nor the control patch.
const Rect _textureRegion = Rect.fromLTRB(0, 0, 320, 180);
const Rect _controlRegion = Rect.fromLTRB(576, 296, 640, 360);
const Rect _backgroundRegion = Rect.fromLTRB(400, 200, 560, 340);

/// A pixel counts as background green when every channel is within this
/// distance of (0, 200, 0).
const int _greenTolerance = 24;

/// Region ratios the control and background must reach before the texture
/// region may be judged at all.
const double _controlVisibleRatio = 0.9;

/// A texture region at least this green shows the background through it: the
/// texture was not composited into the probe image.
const double _textureOccludedRatio = 0.5;

/// Pixel statistics for one rectangle of the probe image.
final class _RegionStats {
  const _RegionStats({
    required this.nonBlackRatio,
    required this.greenFraction,
    required this.meanR,
    required this.meanG,
    required this.meanB,
  });

  /// Share of pixels with any channel > 8 (the `_probePixels` rule).
  final double nonBlackRatio;

  /// Share of pixels within [_greenTolerance] of (0, 200, 0).
  final double greenFraction;

  final double meanR;
  final double meanG;
  final double meanB;

  Map<String, Object?> toJson() => {
    'nonBlackRatio': nonBlackRatio,
    'greenFraction': greenFraction,
    'meanR': meanR,
    'meanG': meanG,
    'meanB': meanB,
  };
}

/// One read of the control tree: the three regions plus the surface facts
/// that explain which image the probe actually captured.
final class _ProbeRead {
  const _ProbeRead.unsupported(this.reason)
    : texture = null,
      control = null,
      background = null,
      viewSize = null,
      surface = const {};

  const _ProbeRead({
    required _RegionStats this.texture,
    required _RegionStats this.control,
    required _RegionStats this.background,
    required this.viewSize,
    required this.surface,
  }) : reason = null;

  final String? reason;
  final _RegionStats? texture;
  final _RegionStats? control;
  final _RegionStats? background;

  /// Logical size of the view the probe tree was laid out in.
  final Size? viewSize;

  /// probeSurface / boundarySize / viewSize / dpr /
  /// probeSurfaceMatchesBoundary.
  final Map<String, Object?> surface;

  /// The 10-08 decision table. Purely descriptive: never a D-05 input.
  String get visibility {
    final texture = this.texture;
    final control = this.control;
    final background = this.background;
    if (texture == null || control == null || background == null) {
      return 'indeterminate';
    }
    if (control.nonBlackRatio < _controlVisibleRatio ||
        background.greenFraction < _controlVisibleRatio) {
      return 'indeterminate';
    }
    if (texture.greenFraction >= _textureOccludedRatio) {
      return 'texture-not-composited';
    }
    if (texture.nonBlackRatio < _minNonBlackRatio) {
      return 'texture-composited-black';
    }
    return 'texture-visible';
  }

  Map<String, Object?> toJson() => {
    'supported': reason == null,
    'reason': ?reason,
    'visibility': visibility,
    'texture': texture?.toJson(),
    'control': control?.toJson(),
    'background': background?.toJson(),
    ...surface,
  };
}

/// `640.0` -> `640`, `683.5` -> `683.50`: integral sizes print as integers so
/// the evidence keys stay greppable as `WxH`.
String _fmt(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _fmtSize(Size size) => '${_fmt(size.width)}x${_fmt(size.height)}';

/// Statistics for [region] (logical coordinates) of an RGBA image, or null
/// when the scaled rectangle falls outside the image.
_RegionStats? _regionStats(
  Uint8List data, {
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
      final r = data[i];
      final g = data[i + 1];
      final b = data[i + 2];
      if (r > 8 || g > 8 || b > 8) nonBlack++;
      if (r <= _greenTolerance &&
          (g - 200).abs() <= _greenTolerance &&
          b <= _greenTolerance) {
        green++;
      }
      sumR += r;
      sumG += g;
      sumB += b;
    }
  }
  final pixels = (right - left) * (bottom - top);
  return _RegionStats(
    nonBlackRatio: nonBlack / pixels,
    greenFraction: green / pixels,
    meanR: sumR / pixels,
    meanG: sumG / pixels,
    meanB: sumB / pixels,
  );
}

extension _SmokeModes on _SmokeHarness {
  /// The probe-control tree (10-08 Task 1). Built only when
  /// MPV_KIT_SMOKE_DIAG=probe; the production tree never contains a colour.
  ///
  /// Align is required: StackFit.expand hands tight constraints to
  /// non-positioned children, which would stretch both boxes to 640x360.
  Widget _probeControlTree(int textureId) => RepaintBoundary(
    key: _probeKey,
    child: SizedBox(
      width: 640,
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _probeBackground),
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 180,
              child: Texture(textureId: textureId),
            ),
          ),
          const Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 64,
              height: 64,
              child: ColoredBox(color: _probeControl),
            ),
          ),
        ],
      ),
    ),
  );

  /// Reads the three control regions through the same
  /// RenderRepaintBoundary.toImage channel `_probePixels` uses. Diag only.
  Future<_ProbeRead> _probeRegions() async {
    try {
      final context = _probeKey.currentContext;
      final boundary = context?.findRenderObject();
      if (context == null || boundary is! RenderRepaintBoundary) {
        return const _ProbeRead.unsupported('probe boundary is not mounted');
      }
      // Read the view before the await: the context must not be used across
      // an asynchronous gap.
      final view = View.maybeOf(context);
      final dpr = view?.devicePixelRatio ?? 1.0;
      final viewSize = view == null ? null : view.physicalSize / dpr;
      final boundarySize = boundary.size;
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (bytes == null) {
          return const _ProbeRead.unsupported('toByteData returned null');
        }
        // Same view slicing as _probePixels (WR-02).
        final data = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        if (data.length < image.width * image.height * 4) {
          return const _ProbeRead.unsupported('short pixel buffer');
        }
        final sx = image.width / boundarySize.width;
        final sy = image.height / boundarySize.height;
        _RegionStats? stats(Rect region) => _regionStats(
          data,
          width: image.width,
          height: image.height,
          region: region,
          sx: sx,
          sy: sy,
        );
        final texture = stats(_textureRegion);
        final control = stats(_controlRegion);
        final background = stats(_backgroundRegion);
        if (texture == null || control == null || background == null) {
          return _ProbeRead.unsupported(
            'region outside the ${image.width}x${image.height} probe image',
          );
        }
        // toImage() defaults to pixelRatio 1.0: a matching surface is the
        // boundary's logical size, within rounding.
        final matches =
            (image.width - boundarySize.width).abs() < 1 &&
            (image.height - boundarySize.height).abs() < 1;
        return _ProbeRead(
          texture: texture,
          control: control,
          background: background,
          viewSize: viewSize,
          surface: {
            'probeSurface': '${image.width}x${image.height}',
            'boundarySize': _fmtSize(boundarySize),
            'viewSize': viewSize == null ? null : _fmtSize(viewSize),
            'dpr': dpr,
            'probeSurfaceMatchesBoundary': matches,
          },
        );
      } finally {
        image.dispose();
      }
    } on Object catch (error) {
      return _ProbeRead.unsupported('${error.runtimeType}: $error');
    }
  }

  /// Readiness gate shared by the probe diag and part 2: the VO reports a
  /// non-zero fps AND playback time advances by >= 0.2 s between two samples
  /// taken >= 200 ms apart (400 ms here). fps alone was shown in 10-04 not
  /// to be render evidence.
  Future<Map<String, Object?>> _firstFrameGate(Player player) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    Object? fps;
    var delta = 0.0;
    while (DateTime.now().isBefore(deadline)) {
      fps = player.mpv.tryGetProperty('estimated-vf-fps');
      final before = player.mpv.tryGetProperty('time-pos');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _nextFrame();
      final after = player.mpv.tryGetProperty('time-pos');
      if (fps is num && fps > 0 && before is num && after is num) {
        delta = (after - before).toDouble();
        if (delta >= 0.2) {
          return {
            'probeTiming': 'after-first-frame',
            'fpsAtProbe': fps,
            'timePosDelta': delta,
          };
        }
      }
    }
    return {
      'probeTiming': 'before-first-frame',
      'fpsAtProbe': fps,
      'timePosDelta': delta,
    };
  }

  /// MPV_KIT_SMOKE_DIAG=probe: mount the control tree, wait for the first
  /// presented frame, read the regions twice 1 s apart and print one
  /// `DIAG probe {json}` line. Never reaches _classify.
  Future<void> _runProbe(Player player) async {
    _stage = 'diag-probe';
    final controller = _controller;
    if (controller == null) {
      throw StateError('probe diag requires the preflight controller');
    }
    _setTexture(controller.textureId);
    await _nextFrame();
    await player.open(_lavfiSource);
    final paramsReady = await _waitUntil(() {
      final params = player.videoParams.value;
      return params?.width == 1920 && params?.height == 1080;
    }, timeout: const Duration(seconds: 30));
    if (!paramsReady) {
      throw StateError('probe diag: video params timeout');
    }
    final resizeBaseline = _resizeEvents;
    await controller.setSize(1280, 720);
    final resized = await _waitUntil(
      () => _resizeEvents > resizeBaseline,
      timeout: const Duration(seconds: 30),
    );
    if (!resized) {
      throw StateError('probe diag: no resize after setSize(1280, 720)');
    }
    final timing = await _firstFrameGate(player);

    final first = await _probeRegions();
    await Future<void>.delayed(const Duration(seconds: 1));
    await _nextFrame();
    final second = await _probeRegions();

    // Two reads of the same tree must agree; disagreement is indeterminate.
    final stable = first.visibility == second.visibility;
    // The production boundary asks for 1280x720; a smaller view clamps it
    // (Center passes loose constraints bounded by the view), which is the
    // candidate explanation of 10-05's 1266x683 surface.
    final viewSize = first.viewSize;
    final priorExplained =
        viewSize != null && (viewSize.width < 1280 || viewSize.height < 720);
    final report = <String, Object?>{
      'probeVisibility': stable ? first.visibility : 'indeterminate',
      'probeStable': stable,
      ...timing,
      'priorSurfaceExplained': priorExplained,
      'read1': first.toJson(),
      'read2': second.toJson(),
    };
    print('DIAG probe ${jsonEncode(report)}');

    _setTexture(null);
    await _nextFrame();
    await _disposeQuietly();
  }

  /// Evidence-only reproducer: replays the measured part-1 lifecycle, applies
  /// the mode prelude, then runs [rounds] soak rounds through the same
  /// [_SmokeHarness._runSoakRounds].
  ///
  /// It never calls _classify, never emits a `stage: complete` payload and
  /// never writes the classification evidence file, so no diag run can be
  /// mistaken for a D-05 measurement.
  Future<void> _runDiag(Player player, String mode, int rounds) async {
    _stage = 'diag-$mode';

    // --- part 1 replay: the prelude 10-05 actually executed ---------------
    final controller = _controller;
    if (controller == null) {
      throw StateError('diag requires the preflight controller');
    }
    _trace.mark('mount-begin', round: 0);
    _setTexture(controller.textureId);
    _trace.mark('mount-done', round: 0);

    await player.open(_lavfiSource);
    final paramsReady = await _waitUntil(() {
      final params = player.videoParams.value;
      return params?.width == 1920 && params?.height == 1080;
    }, timeout: const Duration(seconds: 30));
    if (!paramsReady) {
      throw StateError('diag part-1 replay: video params timeout');
    }
    final resizeBaseline = _resizeEvents;
    _trace.mark('set-size-begin', round: 0);
    await controller.setSize(1920, 1080);
    _trace.mark('set-size-done', round: 0);
    final part1Ready = await _waitUntil(() {
      final fps = player.mpv.tryGetProperty('estimated-vf-fps');
      return fps is num && fps > 0 && _resizeEvents > resizeBaseline;
    }, timeout: const Duration(seconds: 30));
    if (!part1Ready) {
      throw StateError('diag part-1 replay: readiness timeout');
    }

    _trace.mark('unmount-begin', round: 0);
    _setTexture(null);
    _trace.mark('unmount-done', round: 0);
    _trace.mark('frame-after-unmount-begin', round: 0);
    await _nextFrame();
    _trace.mark('frame-after-unmount-done', round: 0);
    _trace.mark('dispose-begin', round: 0);
    await controller.dispose();
    _trace.mark('dispose-done', round: 0);
    _controller = null;

    _trace.mark('create-begin', round: 0);
    final remounted = _controller = await MpvVideoController.create(player);
    _controllersCreated++;
    _trace.mark('create-done', round: 0);
    _watch(remounted);
    _trace.mark('mount-begin', round: 0);
    _setTexture(remounted.textureId);
    _trace.mark('mount-done', round: 0);
    _trace.mark('frame-after-mount-begin', round: 0);
    await _nextFrame();
    _trace.mark('frame-after-mount-done', round: 0);
    print('DIAG soak part1_replay yes');

    // --- mode prelude ------------------------------------------------------
    if (mode == 'soak-after-4k') {
      final uhdBaseline = _resizeEvents;
      _saw4kResize = false;
      _trace.mark('set-size-begin', round: 0);
      await remounted.setSize(3840, 2160);
      _trace.mark('set-size-done', round: 0);
      final uhdReady = await _waitUntil(
        () => _saw4kResize && _resizeEvents > uhdBaseline,
        timeout: const Duration(seconds: 30),
      );
      if (!uhdReady) {
        throw StateError('diag prelude: no 3840x2160 resize');
      }
      // Hold the 4K target so the compositor samples it repeatedly, exactly
      // like part 2.
      await Future<void>.delayed(const Duration(seconds: 2));
      await _remountCycle(round: 0);
    } else {
      final loopBaseline = _resizeEvents;
      _trace.mark('set-size-begin', round: 0);
      await remounted.setSize(1280, 720);
      _trace.mark('set-size-done', round: 0);
      await _waitUntil(
        () => _resizeEvents > loopBaseline,
        timeout: const Duration(seconds: 30),
      );
    }

    // --- measured soak rounds, trace only ---------------------------------
    _soakStarted = true;
    _soakStart = DateTime.now();
    await _runSoakRounds(rounds, emitDiag: true);
    print('DIAG soak complete ${jsonEncode({
          'rounds': rounds,
          'mode': mode,
        })}');
  }
}
