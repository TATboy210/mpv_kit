/// 将一个 mpv 实例的视频输出连接到 Flutter 纹理。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mpv_kit/mpv_kit.dart';

import 'backend_api.dart';

/// 实际生效的渲染后端。
///
/// [vulkan] 表示 GPU 零拷贝后端：Vulkan，或平台原生图形 API（如 D3D11、
/// OpenGL），真实 API 是 [MpvVideoController.reason] 的第一个 token；
/// [software] 表示 CPU 渲染。公共 API 冻结，本枚举不增减值（ADR 0004，
/// docs/adr/0004-render-backend-reporting.md）。
enum MpvVideoBackend { vulkan, software }

/// Renderer to request from [MpvVideoController.create].
///
/// Vulkan renderers fall back to [software] when the GPU or the platform
/// interop cannot be used; [MpvVideoController.reason] says what happened.
enum MpvVideoRenderer {
  /// gpu-next, then gpu, then software (default).
  auto('auto'),

  /// libplacebo's renderer (`--vo=gpu-next`): best HDR tone mapping and
  /// color management.
  gpuNext('gpu-next'),

  /// mpv's older gl_video renderer (`--vo=gpu`).
  gpu('gpu'),

  /// CPU rendering into a pixel buffer. Slow; for diagnostics and machines
  /// without a usable Vulkan driver.
  software('software');

  const MpvVideoRenderer(this.wireName);

  /// Name used on the method channel and in `MPV_KIT_VIDEO_RENDERER`.
  final String wireName;

  /// Parses [wireName]; null if unknown.
  static MpvVideoRenderer? tryParse(String? name) {
    for (final r in values) {
      if (r.wireName == name) return r;
    }
    return null;
  }
}

/// Kinds of [MpvVideoEvent].
enum MpvVideoEventKind {
  /// Render targets were reallocated; message is `WxH` in pixels.
  resize,

  /// The texture is not being displayed (hidden or minimised window):
  /// frames are advanced without rendering.
  idle,

  /// The texture is displayed again after [idle].
  active,

  /// A frame failed to render. Rendering is retried with a growing delay.
  renderError,

  /// The GPU did not finish a frame within one second (retried).
  gpuTimeout,

  /// Rendering works again after [renderError] / [gpuTimeout].
  recovered,

  /// The GPU device was lost (the API is the first token of the controller's
  /// reason): this controller renders nothing anymore. Dispose it and create
  /// a new one (for example with [MpvVideoRenderer.software]).
  deviceLost,

  /// Dart-side warning: rendering fell back to software ([reason] says
  /// why). Every frame is a full CPU render plus buffer copies — 4K+ is
  /// not viable on this path. Not produced by the native plugin; produced
  /// once while creating the controller, when the backend resolved to
  /// software, and delivered to the first listener of
  /// [MpvVideoController.events] (the one that subscribes after create
  /// returned; later listeners do not get it).
  softwareFallback,

  /// A kind this version does not know (newer plugin).
  unknown;

  static MpvVideoEventKind _parse(String? wire) => switch (wire) {
    'resize' => resize,
    'idle' => idle,
    'active' => active,
    'render_error' => renderError,
    'gpu_timeout' => gpuTimeout,
    'recovered' => recovered,
    'device_lost' => deviceLost,
    _ => unknown,
  };
}

/// A diagnostic event from the native renderer.
@immutable
final class MpvVideoEvent {
  const MpvVideoEvent(this.kind, this.message);

  final MpvVideoEventKind kind;

  /// Details, e.g. `3840x2160` for [MpvVideoEventKind.resize] or the error
  /// for [MpvVideoEventKind.renderError]. May be empty.
  final String message;

  @override
  String toString() => message.isEmpty
      ? 'MpvVideoEvent(${kind.name})'
      : 'MpvVideoEvent(${kind.name}: $message)';
}

/// Owns the Flutter texture that shows [player]'s video.
///
/// The mpv instance must be created with `vo=libmpv` (the [Player] default).
/// Rendering runs on a native thread; the UI thread only receives
/// "frame available" notifications.
///
/// Lifetime: libmpv requires the render context to be freed before the mpv
/// core is destroyed. The controller registers itself with
/// [Player.addDisposeHook], so `player.dispose()` disposes it first; calling
/// [dispose] earlier is fine too.
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
    'mpv_render_context_get_info',
    'mpv_render_context_set_parameter',
  ];

  /// Live controllers by texture id, for routing native events.
  static final _live = <int, MpvVideoController>{};
  static var _handlerInstalled = false;

  /// Private plugin wire names of the GPU zero-copy backends, all reported
  /// as [MpvVideoBackend.vulkan]; the real graphics API is the first token
  /// of [reason] (ADR 0004). Matched exactly — no case folding, no prefix
  /// match — so any other value stays a protocol break (STAB-04).
  static const _gpuWireNames = {'d3d11', 'opengl', 'vulkan'};

  /// Environment variable that overrides the requested renderer (`auto`,
  /// `gpu-next`, `gpu`, `software`): a way to diagnose driver problems in a
  /// shipped app without code changes.
  static const rendererOverrideVariable = 'MPV_KIT_VIDEO_RENDERER';

  /// Creates the render context and texture.
  ///
  /// [renderer] selects the renderer; `MPV_KIT_VIDEO_RENDERER` in the
  /// environment takes precedence. Throws [PlatformException] when no
  /// backend can be initialised.
  static Future<MpvVideoController> create(
    Player player, {
    MpvVideoRenderer renderer = MpvVideoRenderer.auto,
    @Deprecated('Use renderer: MpvVideoRenderer.software')
    bool forceSoftware = false,
  }) async {
    _installHandler();
    final requested =
        MpvVideoRenderer.tryParse(
          Platform.environment[rendererOverrideVariable],
        ) ??
        (forceSoftware ? MpvVideoRenderer.software : renderer);
    // Read by the render context at creation, so it must come first.
    _applyShaderCacheDir(player);
    final lib = player.mpv.bindings.library;
    final result = await _channel.invokeMapMethod<String, Object?>('create', {
      'handle': player.mpv.handle.address,
      'symbols': [for (final s in _symbols) lib.lookup<Void>(s).address],
      'renderer': requested.wireName,
    });
    final textureId = result?['textureId'];
    final backendName = result?['backend'];
    final reason = result?['reason'];
    // Validate before trusting the response: a malformed or newer plugin
    // response must surface as PlatformException (STAB-04), never as a
    // TypeError — and a garbage `backend` is a protocol break, not a reason
    // to silently downgrade to software.
    if (textureId is! int ||
        backendName is! String ||
        (!_gpuWireNames.contains(backendName) &&
            backendName != 'software') ||
        (reason != null && reason is! String)) {
      // The native context already exists. Release it when the response
      // named a texture; without a usable textureId there is no handle to
      // free it with, so it lives until process exit (protocol break).
      if (textureId is int) await _release(textureId);
      throw PlatformException(
        code: 'render_init',
        message: 'malformed create result',
        details: 'textureId: ${textureId.runtimeType}, '
            'backend: ${backendName.runtimeType}, '
            'reason: ${reason.runtimeType}',
      );
    }
    final controller = MpvVideoController._(
      player,
      textureId,
      backendName == 'software'
          ? MpvVideoBackend.software
          : MpvVideoBackend.vulkan,
      reason is String ? reason : '',
    );
    try {
      _live[textureId] = controller;
      player.addDisposeHook(controller.dispose);
      await controller._syncInitialRefreshRate();
      // The enum reports d3d11/opengl as `vulkan`; print the real API.
      final api = backendApiName(controller.reason, controller.backend.name);
      debugPrint('mpv_kit_video: $api (${controller.reason})');
      // 4K 下 software 回退是灾难性的（每帧 CPU 全量渲染 + 缓冲三重拷贝
      // ≈6GB/s 内存流量），release 构建连 debugPrint 都看不到——把它变成
      // 显式事件，让应用层有机会提示用户或拒绝大分辨率。
      if (controller.backend == MpvVideoBackend.software) {
        // Held for the first `events` listener: no listener can exist before
        // create returns (see [_events]).
        controller._pendingFallback = MpvVideoEvent(
          MpvVideoEventKind.softwareFallback,
          controller.reason.isEmpty
              ? 'rendering in software'
              : 'rendering in software: ${controller.reason}',
        );
      }
      return controller;
    } on Object {
      await controller._rollback();
      rethrow;
    }
  }

  /// Releases the native context for [textureId] after create already made
  /// the native side allocate it. Best effort: a broken channel or an id the
  /// native side does not know (`no_texture`) leaves nothing more to do.
  static Future<void> _release(int textureId) async {
    try {
      await _channel.invokeMethod<void>('dispose', {'textureId': textureId});
    } on Object {
      // Swallowed on purpose: rollback must not mask the original error.
    }
  }

  /// 初次同步显示刷新率。
  ///
  /// Windows 上 Flutter 的 `Display.refreshRate` 长期返回 0
  /// (flutter/flutter #158721),而 0 会被 [syncDisplayRefreshRate] 丢弃
  /// → `display-fps-override` 从未被设置 → 一切 `video-sync=display-*`
  /// 模式失效。因此优先问插件原生层(按视频窗口所在显示器取
  /// `EnumDisplaySettings`),拿不到再退回 Flutter 的 displays 列表。
  Future<void> _syncInitialRefreshRate() async {
    double hz = 0;
    try {
      final native = await _channel.invokeMethod<double>(
        'getDisplayRefreshRate',
      );
      hz = (native ?? 0).toDouble();
    } on PlatformException {
      // Fall through to the Flutter-provided rate.
    }
    if (hz <= 0) {
      final displays = PlatformDispatcher.instance.displays;
      hz = displays.isEmpty ? 0 : displays.first.refreshRate;
    }
    syncDisplayRefreshRate(hz);
  }

  /// Undoes everything [create] installed after the native context existed:
  /// the routing entry, the player dispose hook, then the native context
  /// itself. The original error is rethrown by the caller.
  Future<void> _rollback() async {
    _live.remove(textureId);
    player.removeDisposeHook(dispose);
    await _release(textureId);
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final args = call.arguments;
      if (args is! Map) return;
      final id = args['textureId'];
      final controller = id is int ? _live[id] : null;
      controller?._onEvent(
        MpvVideoEvent(
          MpvVideoEventKind._parse(args['kind'] as String?),
          args['message'] as String? ?? '',
        ),
      );
    });
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
    try {
      player.mpv.setProperty('gpu-shader-cache-dir', dir);
    } on MpvException catch (e) {
      // An optional diagnostic setting must not fail create on a reduced
      // libmpv build (OBS-04); every other error stays loud.
      if (e.error != MpvError.propertyNotFound) rethrow;
      debugPrint(
        'mpv_kit_video: gpu-shader-cache-dir unsupported by this libmpv '
        'build; ignored',
      );
    }
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

  /// Backend description in the ADR 0004 grammar:
  /// `head *( "; " trail )`, where the head is `api (renderer) on device`
  /// and every trail is `api/renderer unavailable: why` for a candidate that
  /// was tried before the winner. The first token is the real graphics API,
  /// for example `vulkan (gpu-next) on <device>` or
  /// `software (sw) on cpu; vulkan/gpu-next unavailable: <why>`.
  final String reason;

  // A broadcast stream drops events added while it has no listener, and
  // create cannot return a controller that already has one, so the create-time
  // softwareFallback event used to be lost every time. It is kept in
  // [_pendingFallback] and handed to the first listener from onListen (this
  // library has no internal listener, so that is the application's). `late`
  // because onListen refers to this instance.
  late final _events = StreamController<MpvVideoEvent>.broadcast(
    onListen: _deliverPending,
  );

  /// The create-time [MpvVideoEventKind.softwareFallback] event until the
  /// first listener of [events] takes it; null otherwise.
  MpvVideoEvent? _pendingFallback;

  void _deliverPending() {
    final pending = _pendingFallback;
    if (pending == null) return;
    _pendingFallback = null;
    if (!_events.isClosed) _events.add(pending);
  }

  /// `display-fps-override` value this controller set, null if none.
  double? _autoDisplayFps;
  var _disposed = false;
  (int, int)? _size;

  /// Diagnostic events from the native renderer (resizes, idle/active,
  /// render errors, device loss).
  Stream<MpvVideoEvent> get events => _events.stream;

  /// Whether rendering stopped for good ([MpvVideoEventKind.deviceLost]).
  bool get isBroken => _broken;
  var _broken = false;

  void _onEvent(MpvVideoEvent e) {
    if (e.kind == MpvVideoEventKind.deviceLost) _broken = true;
    if (!_events.isClosed) _events.add(e);
  }

  /// Tells mpv the refresh rate of the display showing the video.
  ///
  /// The render API has no vsync source, so mpv would only estimate the
  /// rate from swap timing; `video-sync=display-*` and interpolation depend
  /// on it. [MpvVideo] calls this with its view's display whenever that
  /// changes (e.g. the window moved to a 144 Hz monitor). An explicit user
  /// setting of `display-fps-override` is left alone. Non-positive rates
  /// are ignored.
  void syncDisplayRefreshRate(double hz) {
    if (_disposed || hz <= 0 || hz == _autoDisplayFps) return;
    final current = player.mpv.tryGetProperty('display-fps-override');
    final userSet = current is num && current > 0 && current != _autoDisplayFps;
    if (userSet) return;
    player.mpv.setProperty('display-fps-override', hz);
    _autoDisplayFps = hz;
  }

  /// Sets the render resolution in physical pixels (usually the widget size
  /// times devicePixelRatio, capped at the video size). Cheap to call often:
  /// unchanged sizes are ignored.
  Future<void> setSize(int width, int height) async {
    if (_disposed || width <= 0 || height <= 0) return;
    if (_size == (width, height)) return;
    _size = (width, height);
    try {
      await _channel.invokeMethod<void>('setSize', {
        'textureId': textureId,
        'width': width,
        'height': height,
      });
    } on Object {
      // dispose won the race while this call was in flight: the plugin is
      // gone and nobody can consume the failure (MpvVideo issues resize
      // through unawaited). While the controller is live, rethrow — real
      // errors must reach the caller.
      if (_disposed) return;
      rethrow;
    }
  }

  /// Color-manages output for the display described by [profile] (the raw
  /// ICC file contents), or turns color management off when null/empty.
  ///
  /// Sets mpv's `icc-profile-auto` accordingly (the render API only uses
  /// the profile with that option enabled). Not supported by the software
  /// renderer. A file path can also be used via
  /// `player.mpv.setProperty('icc-profile', path)`.
  Future<void> setIccProfile(Uint8List? profile) async {
    if (_disposed) return;
    final enable = profile != null && profile.isNotEmpty;
    player.mpv.setProperty('icc-profile-auto', enable);
    try {
      await _channel.invokeMethod<void>('setIccProfile', {
        'textureId': textureId,
        'profile': enable ? profile : Uint8List(0),
      });
    } on Object {
      // Same dispose-won-the-race rule as [setSize].
      if (_disposed) return;
      rethrow;
    }
  }

  /// Releases the texture and render context (the [player] stays alive).
  /// Idempotent.
  ///
  /// The events stream closes even when the native call throws — a listener
  /// must always observe `done` — and the channel error is still surfaced to
  /// the caller.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // A never-delivered fallback event is dropped with the stream.
    _pendingFallback = null;
    _live.remove(textureId);
    player.removeDisposeHook(dispose);
    try {
      await _channel.invokeMethod<void>('dispose', {'textureId': textureId});
    } finally {
      _closeEvents();
    }
  }

  /// Closes [_events] unless already closed, retrying once in a microtask if
  /// a dispatch was still unwinding (mirrors Mpv's `_closeIfOpen`; dispose
  /// is re-enterable from a synchronous events listener).
  void _closeEvents() {
    if (_events.isClosed) return;
    try {
      unawaited(_events.close());
    } on StateError {
      scheduleMicrotask(() {
        if (!_events.isClosed) unawaited(_events.close());
      });
    }
  }
}
