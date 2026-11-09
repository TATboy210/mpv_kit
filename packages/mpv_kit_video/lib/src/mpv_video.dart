/// 显示 [MpvVideoController] 纹理的 widget。
library;

import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/widgets.dart';
import 'package:mpv_kit/mpv_kit.dart';

import 'video_controller.dart';

/// Displays the video of [controller], letterboxed according to [fit].
///
/// mpv renders at the exact physical pixel size of the visible video rect,
/// so scaling uses mpv's high-quality scalers instead of texture filtering.
/// Resizes are debounced by [resizeDebounce] to avoid reallocating render
/// targets on every frame of a window drag.
class MpvVideo extends StatefulWidget {
  const MpvVideo({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.resizeDebounce = const Duration(milliseconds: 80),
    this.capRenderSize = true,
  });

  final MpvVideoController controller;
  final BoxFit fit;
  final Duration resizeDebounce;

  /// Never render above the video's own pixel size (dev.9).
  ///
  /// A 1080p video in a 4K window would otherwise allocate a 4K shared-image
  /// ring and pay 4x the fill rate for an upscale Flutter discards anyway.
  /// With this on, the requested size is uniformly shrunk to the source
  /// size; the texture is then stretched by the compositor (same quality as
  /// any other upscale of an already-rendered frame, but cheaper).
  final bool capRenderSize;

  @override
  State<MpvVideo> createState() => _MpvVideoState();
}

class _MpvVideoState extends State<MpvVideo> {
  Timer? _debounce;
  (int, int)? _requested;

  /// Last non-null video geometry.
  ///
  /// Switching files makes mpv report `video-params` as unavailable for a
  /// moment. Without this cache the widget would unmount its [Texture] and
  /// show nothing (a black flash) even though the native renderer still
  /// holds the last frame. The cache is not cleared on idle/stop: keeping
  /// the last frame there is deliberate (it matches `keep-open=yes`), and
  /// clearing it would bring the black switch flash back.
  Size? _lastVideoSize;

  /// True while the file switch passed through a null `video-params` and the
  /// new geometry has not been applied yet. The next non-null build requests
  /// the new size at once instead of through the 80 ms resize debounce: the
  /// debounce exists for window drags, but a switch would otherwise keep the
  /// previous size's ring on screen (mpv letterboxes the new frame into it).
  bool _switchPending = false;

  @override
  void didUpdateWidget(covariant MpvVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new controller owns a new native renderer with no size yet. The
    // computed size may be identical, so only resetting the request makes
    // the build below send its initial setSize.
    if (!identical(oldWidget.controller, widget.controller)) {
      _debounce?.cancel();
      _debounce = null;
      _requested = null;
      _lastVideoSize = null;
      _switchPending = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Video display size honouring rotation and pixel aspect.
  static Size? _videoSize(MpvVideoParams? p) {
    final w = p?.width, h = p?.height;
    if (p == null || w == null || h == null || w == 0 || h == 0) return null;
    final aspect = p.aspect ?? w / h;
    final rotated = p.rotate % 180 != 0;
    final size = Size(h * aspect, h.toDouble());
    return rotated ? size.flipped : size;
  }

  void _requestSize(
    Size logical,
    double dpr, {
    bool immediate = false,
    Size? source,
  }) {
    var w = (logical.width * dpr).round();
    var h = (logical.height * dpr).round();
    if (source != null && source.width > 0 && source.height > 0) {
      // Uniform shrink to the source's pixel size, applied before the
      // `_requested` cache so the cached pair is the capped one.
      final scale = min(
        1.0,
        min(
          source.width / (logical.width * dpr),
          source.height / (logical.height * dpr),
        ),
      );
      if (scale < 1.0) {
        w = (logical.width * dpr * scale).round();
        h = (logical.height * dpr * scale).round();
      }
    }
    if (_requested == (w, h)) return;
    final first = _requested == null;
    _requested = (w, h);
    _debounce?.cancel();
    if (first || immediate) {
      // Nothing is on screen yet, or a file switch just changed the source:
      // render at the new size without waiting.
      unawaited(widget.controller.setSize(w, h));
      return;
    }
    _debounce = Timer(widget.resizeDebounce, () {
      unawaited(widget.controller.setSize(w, h));
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Follows the window across monitors (refresh rate per display). The
    // controller guards on an unchanged rate, so steady-state rebuilds do no
    // FFI work at all; only a real display change reaches mpv.
    final hz = View.maybeOf(context)?.display.refreshRate;
    if (hz != null) widget.controller.syncDisplayRefreshRate(hz);
    return StreamBuilder<MpvVideoParams?>(
      stream: widget.controller.player.videoParams.stream,
      initialData: widget.controller.player.videoParams.value,
      builder: (context, snapshot) {
        // Transiently null params (file switch) keep the last geometry and
        // the Texture mounted.
        final measured = _videoSize(snapshot.data);
        if (measured != null) {
          _lastVideoSize = measured;
        } else if (_lastVideoSize != null) {
          _switchPending = true;
        }
        final video = measured ?? _lastVideoSize;
        final immediate = _switchPending && measured != null;
        if (immediate) _switchPending = false;
        return LayoutBuilder(
          builder: (context, constraints) {
            final box = constraints.biggest;
            if (video == null || !box.isFinite || box.isEmpty) {
              return const SizedBox.expand();
            }
            // applyBoxFit may crop the source (cover); scale the *whole* video
            // by the same factors so every BoxFit keeps the right geometry.
            final fs = applyBoxFit(widget.fit, video, box);
            final shown = Size(
              video.width * fs.destination.width / fs.source.width,
              video.height * fs.destination.height / fs.source.height,
            );
            _requestSize(
              shown,
              dpr,
              immediate: immediate,
              source: widget.capRenderSize ? video : null,
            );
            return ClipRect(
              // Tight on both ends: the parent may pass tight constraints that
              // are smaller (cover) or larger (contain) than the video rect.
              child: OverflowBox(
                minWidth: shown.width,
                maxWidth: shown.width,
                minHeight: shown.height,
                maxHeight: shown.height,
                child: SizedBox.fromSize(
                  size: shown,
                  child: Texture(
                    textureId: widget.controller.textureId,
                    // Rendered at display resolution; only transient sizes
                    // during a debounced resize are resampled.
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
