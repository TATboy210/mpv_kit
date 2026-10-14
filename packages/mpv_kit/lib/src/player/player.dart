/// `Player` — 面向应用的高层播放器，构建在 [Mpv] 之上。
///
/// Every piece of state is a [MpvState]: a current value plus a change stream,
/// backed by one `mpv_observe_property`. For anything not modelled here use
/// [Player.mpv] directly — the full client API stays available.
library;

import 'dart:async';

import '../core/events.dart';
import '../core/mpv.dart';
import 'models.dart';

/// 一个随 mpv 属性同步的值。
final class MpvState<T> {
  MpvState._(this._initial) : _value = _initial;

  final T _initial;
  T _value;
  final _controller = StreamController<T>.broadcast(sync: true);

  /// 当前值。
  T get value => _value;

  /// 值变化流（不重放当前值）。
  Stream<T> get stream => _controller.stream;

  void _set(T v) {
    if (v == _value) return;
    _value = v;
    _controller.add(v);
  }

  void _reset() => _set(_initial);

  Future<void> _close() => _controller.close();
}

/// 高层播放器。
final class Player {
  /// 创建播放器。[options] 在 `mpv_initialize` 前生效（如 `hwdec`、`vo`）。
  ///
  /// Defaults: `vo=libmpv` (rendered by mpv_kit_video), `hwdec=auto-safe`,
  /// `keep-open=yes` (stay on the last frame at EOF), `idle=yes`.
  factory Player({
    Map<String, String> options = const {},
    String? libraryPath,
  }) {
    final mpv = Mpv.create(libraryPath: libraryPath, options: {
      'vo': 'libmpv',
      'hwdec': 'auto-safe',
      'keep-open': 'yes',
      'idle': 'yes',
      'terminal': 'no',
      ...options,
    });
    return Player._(mpv);
  }

  /// 包装一个已存在的 [Mpv]（例如测试中使用 `vo=null`）。
  Player.wrap(Mpv mpv) : this._(mpv);

  Player._(this.mpv) {
    _bind('pause', paused, (v) => v == true);
    _bind('idle-active', idle, (v) => v == true);
    _bind('eof-reached', completed, (v) => v == true);
    _bind('paused-for-cache', buffering, (v) => v == true);
    _bind('time-pos', position, (v) => secondsToDuration(v) ?? Duration.zero);
    _bind('duration', duration, (v) => secondsToDuration(v) ?? Duration.zero);
    _bind('demuxer-cache-duration', bufferedAhead,
        (v) => secondsToDuration(v) ?? Duration.zero);
    _bind('volume', volume, (v) => (v as num?)?.toDouble() ?? 100);
    _bind('mute', muted, (v) => v == true);
    _bind('speed', speed, (v) => (v as num?)?.toDouble() ?? 1);
    _bind('media-title', title, (v) => v as String?);
    _bind('path', path, (v) => v as String?);
    _bind('track-list', tracks, (v) => _maps(v).map(MpvTrack.fromNode).toList());
    _bind('playlist', playlist,
        (v) => _maps(v).map(MpvPlaylistEntry.fromNode).toList());
    _bind('playlist-pos', playlistIndex, (v) => (v as int?) ?? -1);
    _bind('chapter-list', chapters,
        (v) => _maps(v).map(MpvChapter.fromNode).toList());
    _bind('video-params', videoParams,
        (v) => v is Map<String, Object?> ? MpvVideoParams.fromNode(v) : null);
    _bind('hwdec-current', hwdecCurrent, (v) => v as String?);
    _subs.add(mpv.events.listen(_onEvent));
  }

  /// 底层 mpv 客户端：完整 client API（任意属性/命令/选项/hook）。
  final Mpv mpv;

  final _subs = <StreamSubscription<Object?>>[];
  final _states = <MpvState<Object?>>[];
  final _errors = StreamController<EndFileEvent>.broadcast();

  // --- State -------------------------------------------------------------
  final paused = MpvState<bool>._(true);
  final idle = MpvState<bool>._(true);
  final completed = MpvState<bool>._(false);
  final buffering = MpvState<bool>._(false);
  final position = MpvState<Duration>._(Duration.zero);
  final duration = MpvState<Duration>._(Duration.zero);
  final bufferedAhead = MpvState<Duration>._(Duration.zero);
  final volume = MpvState<double>._(100);
  final muted = MpvState<bool>._(false);
  final speed = MpvState<double>._(1);
  final title = MpvState<String?>._(null);
  final path = MpvState<String?>._(null);
  final tracks = MpvState<List<MpvTrack>>._(const []);
  final playlist = MpvState<List<MpvPlaylistEntry>>._(const []);
  final playlistIndex = MpvState<int>._(-1);
  final chapters = MpvState<List<MpvChapter>>._(const []);
  final videoParams = MpvState<MpvVideoParams?>._(null);

  /// 实际生效的硬解后端（如 `vulkan`、`d3d11va`），软解时为 null/`no`。
  final hwdecCurrent = MpvState<String?>._(null);

  /// 播放失败（END_FILE reason=error）事件流。
  Stream<EndFileEvent> get errors => _errors.stream;

  // --- Commands ----------------------------------------------------------

  /// 打开媒体（替换当前播放）。
  Future<void> open(String url, {bool play = true, Duration? start}) async {
    mpv.setProperty('pause', !play);
    await mpv.commandAsync({
      'name': 'loadfile',
      'url': url,
      'flags': 'replace',
      if (start != null) 'options': {'start': '${start.inMicroseconds / 1e6}'},
    }).result;
  }

  /// 追加到播放列表末尾。
  Future<void> add(String url) =>
      mpv.commandAsync(['loadfile', url, 'append']).result;

  void play() => mpv.setProperty('pause', false);
  void pause() => mpv.setProperty('pause', true);
  void playOrPause() => mpv.command(['cycle', 'pause']);
  void stop() => mpv.command(['stop']);

  /// 跳转到绝对位置；[exact] 为 true 时逐帧精确（较慢）。
  Future<void> seek(Duration to, {bool exact = false}) => mpv.commandAsync([
        'seek',
        '${to.inMicroseconds / 1e6}',
        exact ? 'absolute+exact' : 'absolute+keyframes',
      ]).result;

  void next() => mpv.command(['playlist-next']);
  void previous() => mpv.command(['playlist-prev']);
  void jump(int index) => mpv.setProperty('playlist-pos', index);
  void move(int from, int to) => mpv.command(['playlist-move', from, to]);
  void remove(int index) => mpv.command(['playlist-remove', index]);

  void setVolume(double v) => mpv.setProperty('volume', v);
  void setMute(bool m) => mpv.setProperty('mute', m);
  void setSpeed(double s) => mpv.setProperty('speed', s);

  /// 选择轨道；传 null 关闭该类型（`no`）。
  void selectTrack(MpvTrackType type, int? id) => mpv.setProperty(
        switch (type) {
          MpvTrackType.video => 'vid',
          MpvTrackType.audio => 'aid',
          MpvTrackType.sub || MpvTrackType.unknown => 'sid',
        },
        id ?? 'no',
      );

  /// 加载外挂字幕。
  Future<void> addSubtitle(String url, {bool select = true}) =>
      mpv.commandAsync(['sub-add', url, select ? 'select' : 'auto']).result;

  /// 释放 mpv 与全部状态流。
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    mpv.dispose();
    await _errors.close();
    for (final s in _states) {
      await s._close();
    }
  }

  // --- Internals ---------------------------------------------------------

  void _bind<T>(String name, MpvState<T> state, T Function(Object?) parse) {
    _states.add(state);
    _subs.add(mpv.observeProperty(name).listen((v) => state._set(parse(v))));
  }

  void _onEvent(MpvEventData e) {
    if (e case EndFileEvent(reason: EndFileReason.error)) _errors.add(e);
    if (e is ShutdownEvent) {
      for (final s in _states) {
        s._reset();
      }
    }
  }

  static Iterable<Map<String, Object?>> _maps(Object? v) =>
      v is List<Object?> ? v.whereType<Map<String, Object?>>() : const [];
}
