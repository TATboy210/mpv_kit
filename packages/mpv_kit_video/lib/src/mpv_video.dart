/// 显示 [MpvVideoController] 纹理的 widget。
library;

import 'dart:async';

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
  });

  final MpvVideoController controller;
  final BoxFit fit;
  final Duration resizeDebounce;

  @override
  State<MpvVideo> createState() => _MpvVideoState();
}

class _MpvVideoState extends State<MpvVideo> {
  Timer? _debounce;
  (int, int)? _requested;

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

  void _requestSize(Size logical, double dpr) {
    final w = (logical.width * dpr).round(), h = (logical.height * dpr).round();
    if (_requested == (w, h)) return;
    final first = _requested == null;
    _requested = (w, h);
    _debounce?.cancel();
    if (first) {
      // Nothing is on screen yet: render the first frame without waiting.
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
    // Follows the window across monitors (refresh rate per display).
    final hz = View.maybeOf(context)?.display.refreshRate;
    if (hz != null) widget.controller.syncDisplayRefreshRate(hz);
    return StreamBuilder<MpvVideoParams?>(
      stream: widget.controller.player.videoParams.stream,
      initialData: widget.controller.player.videoParams.value,
      builder: (context, snapshot) {
        final video = _videoSize(snapshot.data);
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
            _requestSize(shown, dpr);
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
