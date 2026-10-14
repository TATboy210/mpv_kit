/// 将一个 mpv 实例的视频输出连接到 Flutter 纹理。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

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
    // Read by the render context at creation, so it must come first.
    _applyShaderCacheDir(player);
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

  /// Compiling the renderer's shaders on first use costs a few frames at
  /// every start. libmpv (config=no) has no cache directory of its own, so
  /// point `gpu-shader-cache-dir` at a per-user cache unless the app chose
  /// one. Keys include the driver, so one directory serves every GPU.
  static void _applyShaderCacheDir(Player player) {
    final current = player.mpv.tryGetProperty('gpu-shader-cache-dir');
    if (current is String && current.isNotEmpty) return;
    final dir = defaultShaderCacheDir();
    if (dir == null) return;
    player.mpv.setProperty('gpu-shader-cache-dir', dir);
  }

  /// Per-user cache location for compiled shaders, or null if the
  /// environment does not provide one.
  @visibleForTesting
  static String? defaultShaderCacheDir({
    String? os,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final system = os ?? Platform.operatingSystem;
    final base = switch (system) {
      'windows' => _nonEmpty(env['LOCALAPPDATA']),
      'macos' => _join(env['HOME'], 'Library/Caches'),
      _ => _nonEmpty(env['XDG_CACHE_HOME']) ?? _join(env['HOME'], '.cache'),
    };
    if (base == null) return null;
    // Forward slashes on Windows too: mpv creates the missing parent
    // directories (mp_mkdirp) by splitting on '/' only.
    return '$base/mpv_kit/shader-cache';
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  static String? _join(String? base, String child) =>
      _nonEmpty(base) == null ? null : '$base/$child';

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
