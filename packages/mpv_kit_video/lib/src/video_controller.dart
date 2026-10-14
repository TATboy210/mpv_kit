/// 将一个 mpv 实例的视频输出连接到 Flutter 纹理。
library;

import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mpv_kit/mpv_kit.dart';

/// 实际生效的渲染后端。
enum MpvVideoBackend { vulkan, software }

/// Owns the Flutter texture that shows [player]'s video.
///
/// The mpv instance must be created with `vo=libmpv` (the [Player] default).
/// Rendering runs on a native thread; the UI thread only receives
/// "frame available" notifications.
final class MpvVideoController {
  MpvVideoController._(this.player, this.textureId, this.backend, this.reason);

  static const _channel = MethodChannel('mpv_kit_video');

  /// Symbol order shared with native `MpvApi::Load` (src/mpv_api.h).
  static const _symbols = [
    'mpv_render_context_create',
    'mpv_render_context_set_update_callback',
    'mpv_render_context_update',
    'mpv_render_context_render',
    'mpv_render_context_report_swap',
    'mpv_render_context_free',
    'mpv_error_string',
  ];

  /// Creates the render context and texture.
  ///
  /// [forceSoftware] skips Vulkan (diagnostics / broken drivers). Throws
  /// [PlatformException] when no backend can be initialised.
  static Future<MpvVideoController> create(
    Player player, {
    bool forceSoftware = false,
  }) async {
    final lib = player.mpv.bindings.library;
    final result = await _channel.invokeMapMethod<String, Object?>('create', {
      'handle': player.mpv.handle.address,
      'symbols': [for (final s in _symbols) lib.lookup<Void>(s).address],
      'forceSoftware': forceSoftware,
    });
    if (result == null) {
      throw PlatformException(code: 'render_init', message: 'no result');
    }
    final controller = MpvVideoController._(
      player,
      result['textureId']! as int,
      result['backend'] == 'vulkan'
          ? MpvVideoBackend.vulkan
          : MpvVideoBackend.software,
      result['reason'] as String? ?? '',
    );
    _applyDisplayRate(player);
    debugPrint(
      'mpv_kit_video: ${controller.backend.name} '
      '(${controller.reason})',
    );
    return controller;
  }

  /// The render API has no vsync source, so mpv would only estimate the
  /// refresh rate from swap timing. Tell it the display's real rate, which
  /// `video-sync=display-*` and interpolation depend on. Leaves an explicit
  /// user setting alone.
  static void _applyDisplayRate(Player player) {
    final displays = PlatformDispatcher.instance.displays;
    final hz = displays.isEmpty ? 0.0 : displays.first.refreshRate;
    if (hz <= 0) return;
    final current = player.mpv.tryGetProperty('display-fps-override');
    if (current is num && current > 0) return;
    player.mpv.setProperty('display-fps-override', hz);
  }

  /// 播放器。
  final Player player;

  /// Flutter 纹理 id，交给 [Texture] widget。
  final int textureId;

  /// 生效的后端。
  final MpvVideoBackend backend;

  /// 后端选择说明（例如设备名或回退原因）。
  final String reason;

  var _disposed = false;
  (int, int)? _size;

  /// Sets the render resolution in physical pixels (usually the widget size
  /// times devicePixelRatio, capped at the video size). Cheap to call often:
  /// unchanged sizes are ignored.
  Future<void> setSize(int width, int height) async {
    if (_disposed || width <= 0 || height <= 0) return;
    if (_size == (width, height)) return;
    _size = (width, height);
    await _channel.invokeMethod<void>('setSize', {
      'textureId': textureId,
      'width': width,
      'height': height,
    });
  }

  /// Releases the texture and render context (the [player] stays alive).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _channel.invokeMethod<void>('dispose', {'textureId': textureId});
  }
}
