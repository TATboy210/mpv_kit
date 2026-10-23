/// `Player` — 面向应用的高层播放器，构建在 [Mpv] 之上。
///
/// Every piece of state is a [MpvState]: a current value plus a change stream,
/// backed by one `mpv_observe_property`. For anything not modelled here use
/// [Player.mpv] directly — the full client API stays available.
library;

import 'dart:async';

import '../core/errors.dart';
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
///
/// Commands fall in two groups: playback (open, seek, playlist) and
/// rendering/audio adjustments (delays, filters, image adjustments). Both
/// are thin, documented wrappers over mpv properties and commands, so the
/// behaviour is mpv's own (see `mpv(1)` for each property).
final class Player {
  /// 创建播放器。[options] 在 `mpv_initialize` 前生效（如 `hwdec`、`vo`）。
  ///
  /// Defaults: `vo=libmpv` (rendered by mpv_kit_video), `hwdec=vulkan,auto-safe`,
  /// `keep-open=yes` (stay on the last frame at EOF), `idle=yes`.
  ///
  /// `hwdec` 首选 `vulkan`（Vulkan Video 零拷贝解码，4K 60fps 无每帧
  /// GPU→CPU 拷贝）；驱动不支持 Vulkan Video 时按逗号列表自动落到
  /// `auto-safe` 的保守列表（其 copy 变体有每帧 ~12MB 的系统内存往返，
  /// 4K 下约 700MB/s，仅在无零拷贝路径可用时作为回退）。
  ///
  /// 其余默认项面向 4K/8K 满帧播放（各项含义见行内注释），全部可被
  /// [options] 覆盖：
  /// - `video-sync=display-desync`：按显示节拍调度帧（render API 无
  ///   swapchain，靠 MpvVideoController 的 display-fps-override 提供节拍）。
  ///   不用 `display-resample` 是因为 Flutter raster 的推送节拍抖动比
  ///   音频时钟大，重采样音频反而引入音调波动；音频自行跟时钟即可。
  /// - `video-timing-offset=0.02`：audio 同步模式的兜底保障——默认
  ///   0.05 会让 render API 客户端被限到 ~20fps（mpv 文档明说）。
  /// - 缓存组：100Mbps（≈12.5MB/s）4K 源默认 150MB 缓冲只有 12 秒，
  ///   放大到 400MB/100MB 回看；`hysteresis-bytes` 治高码率的读停-读停
  ///   抖动；`stream-buffer-size` 从 128KB 提到 4M 减少 IO 粒度。
  /// - `hwdec-extra-frames=6`：auto 恒等于 6（不开插帧时），显式固定
  ///   免受 req_frames 推导影响，4K HEVC/AV1 池稳定。
  /// - `dither=no` / `hdr-compute-peak=no`：目标固定是 SDR 8bit 纹理，
  ///   8bit 蓝噪声抖动视觉无损、HDR peak 检测 pass 无意义（HDR→SDR
  ///   tone-map 仍照做，只是省掉逐帧峰值统计）。
  factory Player({
    Map<String, String> options = const {},
    String? libraryPath,
  }) {
    final mpv = Mpv.create(
      libraryPath: libraryPath,
      options: {
        'vo': 'libmpv',
        'hwdec': 'vulkan,auto-safe',
        'keep-open': 'yes',
        'idle': 'yes',
        'terminal': 'no',
        // --- 4K/8K 满帧参数包（见上方 doc 注释） ---
        'video-sync': 'display-desync',
        'video-timing-offset': '0.02',
        'demuxer-max-bytes': '400MiB',
        'demuxer-max-back-bytes': '100MiB',
        'demuxer-hysteresis-bytes': '32MiB',
        'stream-buffer-size': '4MiB',
        'hwdec-extra-frames': '6',
        'dither': 'no',
        'hdr-compute-peak': 'no',
        'deband': 'no',
        ...options,
      },
    );
    return Player._(mpv);
  }

  /// 包装一个已存在的 [Mpv]（例如测试中使用 `vo=null`）。
  Player.wrap(Mpv mpv) : this._(mpv);

  Player._(this.mpv) {
    _bind('pause', paused, (v) => v == true);
    _bind('idle-active', idle, (v) => v == true);
    _bind('eof-reached', completed, (v) => v == true);
    _bind('paused-for-cache', buffering, (v) => v == true);
    _bind('cache-buffering-state', bufferingPercent, (v) => nodeInt(v) ?? 0);
    _bind('seeking', seeking, (v) => v == true);
    // `time-pos` 按渲染帧粒度通知（60Hz 片源即 60 事件/秒），每个事件
    // 都要 node 解码 + broadcast；UI 进度条不需要帧级精度——100ms 节流，
    // 位移 >250ms（seek/拖动）时直通保持跟手。其余 state 保持即时。
    var lastPosEmitMs = 0;
    _subs.add(mpv.observeProperty('time-pos').listen((v) {
      final d = secondsToDuration(v) ?? Duration.zero;
      final ms = DateTime.now().millisecondsSinceEpoch;
      final jumped =
          (d - position._value).abs() > const Duration(milliseconds: 250);
      if (!jumped && ms - lastPosEmitMs < 100) return;
      lastPosEmitMs = ms;
      position._set(d);
    }));
    _bind('duration', duration, (v) => secondsToDuration(v) ?? Duration.zero);
    _bind(
      'demuxer-cache-duration',
      bufferedAhead,
      (v) => secondsToDuration(v) ?? Duration.zero,
    );
    _bind('volume', volume, (v) => (v as num?)?.toDouble() ?? 100);
    _bind('mute', muted, (v) => v == true);
    _bind('speed', speed, (v) => (v as num?)?.toDouble() ?? 1);
    _bind('media-title', title, (v) => v as String?);
    _bind('path', path, (v) => v as String?);
    _bind(
      'track-list',
      tracks,
      (v) => _maps(v).map(MpvTrack.fromNode).toList(),
    );
    _bind('vid', videoTrack, _trackId);
    _bind('aid', audioTrack, _trackId);
    _bind('sid', subtitleTrack, _trackId);
    _bind('sub-text', subtitleText, (v) => v as String? ?? '');
    _bind('sub-visibility', subtitlesVisible, (v) => v != false);
    _bind(
      'sub-delay',
      subtitleDelay,
      (v) => secondsToDuration(v) ?? Duration.zero,
    );
    _bind(
      'audio-delay',
      audioDelay,
      (v) => secondsToDuration(v) ?? Duration.zero,
    );
    _bind(
      'playlist',
      playlist,
      (v) => _maps(v).map(MpvPlaylistEntry.fromNode).toList(),
    );
    _bind('playlist-pos', playlistIndex, (v) => (v as int?) ?? -1);
    // `inf` / a count / `no` (false): any value but `no` loops.
    _bind('loop-file', loopFile, (v) => v != false && v != 'no');
    _bind('loop-playlist', loopPlaylist, (v) => v != false && v != 'no');
    _bind(
      'chapter-list',
      chapters,
      (v) => _maps(v).map(MpvChapter.fromNode).toList(),
    );
    _bind('chapter', chapter, (v) => nodeInt(v) ?? -1);
    _bind(
      'video-params',
      videoParams,
      (v) => v is Map<String, Object?> ? MpvVideoParams.fromNode(v) : null,
    );
    _bind('hwdec-current', hwdecCurrent, (v) => v as String?);
    _bind(
      'demuxer-cache-time',
      bufferedPosition,
      (v) => secondsToDuration(v) ?? Duration.zero,
    );
    _bind('metadata', metadata, _stringMap);
    _bind(
      'audio-params',
      audioParams,
      (v) => v is Map<String, Object?> ? MpvAudioParams.fromNode(v) : null,
    );
    _bind('audio-device', audioDevice, (v) => v as String? ?? 'auto');
    // 两个来源任一变化都要重算告警（新文件装载/硬解建立/失败回退）。
    _subs.add(videoParams.stream.listen((_) => _updateDecodeWarning()));
    _subs.add(hwdecCurrent.stream.listen((_) => _updateDecodeWarning()));
    _subs.add(mpv.events.listen(_onEvent));
  }

  /// 底层 mpv 客户端：完整 client API（任意属性/命令/选项/hook）。
  final Mpv mpv;

  final _subs = <StreamSubscription<Object?>>[];
  final _states = <MpvState<Object?>>[];
  final _errors = StreamController<MpvPlaybackError>.broadcast();
  final _logs = StreamController<LogMessageEvent>.broadcast();
  final _disposeHooks = <Future<void> Function()>[];
  var _disposed = false;

  // --- Playback state ----------------------------------------------------
  /// Whether playback is paused (`pause`).
  final paused = MpvState<bool>._(true);

  /// Whether no file is loaded (`idle-active`).
  final idle = MpvState<bool>._(true);

  /// Whether the end of the file was reached (`eof-reached`; stays
  /// on the last frame with the default `keep-open=yes`).
  final completed = MpvState<bool>._(false);

  /// Playback waits for the network cache (`paused-for-cache`).
  final buffering = MpvState<bool>._(false);

  /// Cache fill while [buffering], 0–100 (`cache-buffering-state`).
  final bufferingPercent = MpvState<int>._(0);

  /// A seek is in progress (`seeking`).
  final seeking = MpvState<bool>._(false);

  /// Current playback position (`time-pos`).
  final position = MpvState<Duration>._(Duration.zero);

  /// Duration of the current file (`duration`), zero if unknown.
  final duration = MpvState<Duration>._(Duration.zero);

  /// Demuxer cache ahead of the playback position
  /// (`demuxer-cache-duration`).
  final bufferedAhead = MpvState<Duration>._(Duration.zero);

  /// Volume in percent (`volume`), 100 is unchanged.
  final volume = MpvState<double>._(100);

  /// Whether audio is muted (`mute`).
  final muted = MpvState<bool>._(false);

  /// Playback speed factor (`speed`).
  final speed = MpvState<double>._(1);

  /// Title of the current file (`media-title`).
  final title = MpvState<String?>._(null);

  /// Path or URL of the current file (`path`).
  final path = MpvState<String?>._(null);

  // --- Tracks and subtitles ----------------------------------------------
  /// Every track of the current file (`track-list`).
  final tracks = MpvState<List<MpvTrack>>._(const []);

  /// Selected track ids (`vid`/`aid`/`sid`), null when disabled.
  final videoTrack = MpvState<int?>._(null);

  /// Selected audio track id (`aid`), null when disabled.
  final audioTrack = MpvState<int?>._(null);

  /// Selected subtitle track id (`sid`), null when disabled.
  final subtitleTrack = MpvState<int?>._(null);

  /// Text of the current subtitle line (`sub-text`), empty between lines.
  final subtitleText = MpvState<String>._('');

  /// Whether subtitles are shown (`sub-visibility`).
  final subtitlesVisible = MpvState<bool>._(true);

  /// Subtitle delay (`sub-delay`); positive shows them later.
  final subtitleDelay = MpvState<Duration>._(Duration.zero);

  /// Audio delay (`audio-delay`); positive delays audio.
  final audioDelay = MpvState<Duration>._(Duration.zero);

  // --- Playlist and chapters ---------------------------------------------
  /// Playlist entries (`playlist`).
  final playlist = MpvState<List<MpvPlaylistEntry>>._(const []);

  /// Index of the current playlist entry (`playlist-pos`), -1 if none.
  final playlistIndex = MpvState<int>._(-1);

  /// Whether the current file repeats (`loop-file`).
  final loopFile = MpvState<bool>._(false);

  /// Whether the playlist repeats (`loop-playlist`).
  final loopPlaylist = MpvState<bool>._(false);

  /// Chapters of the current file (`chapter-list`).
  final chapters = MpvState<List<MpvChapter>>._(const []);

  /// Current chapter index, -1 before the first chapter / without chapters.
  final chapter = MpvState<int>._(-1);

  // --- Video -------------------------------------------------------------
  /// Parameters of the decoded video (`video-params`), null without
  /// video.
  final videoParams = MpvState<MpvVideoParams?>._(null);

  /// 实际生效的硬解后端（如 `vulkan`、`d3d11va`），软解时为 null/`no`。
  final hwdecCurrent = MpvState<String?>._(null);

  /// 静默软解告警：>1080p 的视频却没走硬件解码时给出一条人话说明，
  /// 否则 null。Vulkan render context 只能消费 Vulkan hwdec 的帧，
  /// `auto-safe` 尾巴（d3d11va/vaapi…）与它 interop 不匹配时 mpv 初始化
  /// hwdec 失败会**静默**回退软解——4K 吃力、8K 无解，默认只在 mpv 日志
  /// 里可见；这条状态把它变成可观察的。
  final decodeWarning = MpvState<String?>._(null);

  /// Absolute position up to which the demuxer has cached data
  /// (`demuxer-cache-time`); zero when nothing is cached.
  final bufferedPosition = MpvState<Duration>._(Duration.zero);

  // --- Audio -------------------------------------------------------------
  /// 当前文件/流的元数据标签（`metadata`），键名保持文件原样（如
  /// `title`、`artist`、`album`；不同容器的大小写不同，例如 ID3 为
  /// `ARTIST`）。网络电台的 ICY 标题也在这里更新（`icy-title`）。
  final metadata = MpvState<Map<String, String>>._(const {});

  /// Decoded audio format (`audio-params`), null without audio.
  final audioParams = MpvState<MpvAudioParams?>._(null);

  /// Audio output devices of the active audio driver
  /// (`audio-device-list`).
  ///
  /// Observed from the first access only: listing devices starts the audio
  /// drivers' hotplug monitoring, which players that never show a device
  /// picker should not pay for.
  late final MpvState<List<MpvAudioDevice>> audioDevices = () {
    final state = MpvState<List<MpvAudioDevice>>._(const []);
    if (_disposed) return state;
    _bind(
      'audio-device-list',
      state,
      (v) => _maps(v).map(MpvAudioDevice.fromNode).toList(),
    );
    return state;
  }();

  /// Selected audio output device (`audio-device`), `auto` by default.
  final audioDevice = MpvState<String>._('auto');

  /// Files that failed to load (`end-file` with reason `error`).
  Stream<MpvPlaybackError> get errors => _errors.stream;

  /// mpv log messages at or above the level set with [setLogLevel].
  Stream<LogMessageEvent> get logs => _logs.stream;

  // --- Opening -----------------------------------------------------------

  /// 打开媒体（替换当前播放）。[options] are per-file options (e.g.
  /// `{'sub-file': path}`), [start] the initial position.
  Future<void> open(
    String url, {
    bool play = true,
    Duration? start,
    Map<String, String>? options,
  }) async {
    mpv.setProperty('pause', !play);
    await mpv.commandAsync({
      'name': 'loadfile',
      'url': url,
      'flags': 'replace',
      if (start != null || options != null)
        'options': {...?options, if (start != null) 'start': _seconds(start)},
    }).result;
  }

  /// Replaces the playlist with [urls] and starts playing [startIndex].
  Future<void> openPlaylist(
    List<String> urls, {
    int startIndex = 0,
    bool play = true,
  }) async {
    if (urls.isEmpty) {
      stop();
      return;
    }
    RangeError.checkValidIndex(startIndex, urls, 'startIndex');
    mpv.setProperty('pause', !play);
    // `stop` clears the playlist; appended entries do not start playback
    // on their own, so the chosen entry is started explicitly.
    mpv.command(['stop']);
    for (final url in urls) {
      await mpv.commandAsync(['loadfile', url, 'append']).result;
    }
    mpv.command(['playlist-play-index', startIndex]);
  }

  /// 追加到播放列表末尾。
  Future<void> add(String url) =>
      mpv.commandAsync(['loadfile', url, 'append']).result;

  // --- Transport ---------------------------------------------------------
  /// Resumes playback.
  void play() => mpv.setProperty('pause', false);

  /// Pauses playback.
  void pause() => mpv.setProperty('pause', true);

  /// Toggles pause.
  void playOrPause() => mpv.command(['cycle', 'pause']);

  /// Stops playback and clears the playlist (`stop`).
  void stop() => mpv.command(['stop']);

  /// 跳转到绝对位置；[exact] 为 true 时逐帧精确（较慢）。
  Future<void> seek(Duration to, {bool exact = false}) => mpv.commandAsync([
    'seek',
    _seconds(to),
    exact ? 'absolute+exact' : 'absolute+keyframes',
  ]).result;

  /// Seeks by [delta] relative to the current position.
  Future<void> seekRelative(Duration delta, {bool exact = false}) =>
      mpv.commandAsync([
        'seek',
        _seconds(delta),
        exact ? 'relative+exact' : 'relative',
      ]).result;

  /// Steps one frame forward (pauses), or backward with [backward].
  void frameStep({bool backward = false}) =>
      mpv.command([backward ? 'frame-back-step' : 'frame-step']);

  /// Loops between [a] and [b] (`ab-loop-a`/`ab-loop-b`); null clears a
  /// point.
  void setAbLoop(Duration? a, Duration? b) {
    mpv.setProperty('ab-loop-a', a == null ? 'no' : _seconds(a));
    mpv.setProperty('ab-loop-b', b == null ? 'no' : _seconds(b));
  }

  // --- Playlist ----------------------------------------------------------
  /// Plays the next playlist entry.
  void next() => mpv.command(['playlist-next']);

  /// Plays the previous playlist entry.
  void previous() => mpv.command(['playlist-prev']);

  /// Plays playlist entry [index].
  void jump(int index) => mpv.command(['playlist-play-index', index]);

  /// Moves playlist entry [from] to position [to] (`playlist-move`).
  void move(int from, int to) => mpv.command(['playlist-move', from, to]);

  /// Removes playlist entry [index].
  void remove(int index) => mpv.command(['playlist-remove', index]);

  /// Removes every entry except the one playing.
  void clearPlaylist() => mpv.command(['playlist-clear']);

  /// Shuffles the playlist (`playlist-shuffle`); [unshufflePlaylist]
  /// restores the original order.
  void shufflePlaylist() => mpv.command(['playlist-shuffle']);

  /// Restores the order from before [shufflePlaylist].
  void unshufflePlaylist() => mpv.command(['playlist-unshuffle']);

  /// Repeats the current file.
  void setLoopFile(bool loop) =>
      mpv.setProperty('loop-file', loop ? 'inf' : 'no');

  /// Sets [loopFile] / [loopPlaylist] at once (media_kit's PlaylistMode).
  void setLoopMode(MpvLoopMode mode) {
    setLoopFile(mode == MpvLoopMode.file);
    setLoopPlaylist(mode == MpvLoopMode.playlist);
  }

  /// Current loop mode, derived from [loopFile] and [loopPlaylist]
  /// (a looping file takes precedence).
  MpvLoopMode get loopMode => loopFile.value
      ? MpvLoopMode.file
      : loopPlaylist.value
      ? MpvLoopMode.playlist
      : MpvLoopMode.none;

  /// Repeats the whole playlist.
  void setLoopPlaylist(bool loop) =>
      mpv.setProperty('loop-playlist', loop ? 'inf' : 'no');

  /// Seeks to chapter [index].
  void setChapter(int index) => mpv.setProperty('chapter', index);

  // --- Audio -------------------------------------------------------------
  /// Sets the volume in percent (100 is unchanged).
  void setVolume(double v) => mpv.setProperty('volume', v);

  /// Mutes or unmutes audio.
  void setMute(bool m) => mpv.setProperty('mute', m);

  /// Sets the playback speed factor.
  void setSpeed(double s) => mpv.setProperty('speed', s);

  /// Positive values delay audio relative to video.
  void setAudioDelay(Duration d) => mpv.setProperty('audio-delay', _sec(d));

  /// Sends audio to [device], a name from [audioDevices] (`auto` follows
  /// the system default). Takes effect immediately.
  void setAudioDevice(String device) =>
      mpv.setPropertyString('audio-device', device);

  /// Applies ReplayGain tags of the file (`replaygain`).
  void setReplayGain(MpvReplayGain mode) =>
      mpv.setPropertyString('replaygain', mode.value);

  /// Audio filter chain in mpv `--af` syntax (e.g. an equalizer
  /// `lavfi=[superequalizer=...]`); null or empty removes all filters.
  void setAudioFilters(String? filters) =>
      mpv.setPropertyString('af', filters ?? '');

  // --- Tracks and subtitles ----------------------------------------------

  /// 选择轨道；传 null 关闭该类型（`no`）。
  void selectTrack(MpvTrackType type, int? id) =>
      mpv.setProperty(switch (type) {
        MpvTrackType.video => 'vid',
        MpvTrackType.audio => 'aid',
        MpvTrackType.sub || MpvTrackType.unknown => 'sid',
      }, id ?? 'no');

  /// 加载外挂字幕。
  Future<void> addSubtitle(String url, {bool select = true}) =>
      mpv.commandAsync(['sub-add', url, select ? 'select' : 'auto']).result;

  /// Shows or hides subtitles without deselecting the track.
  void setSubtitlesVisible(bool visible) =>
      mpv.setProperty('sub-visibility', visible);

  /// Positive values show subtitles later.
  void setSubtitleDelay(Duration d) => mpv.setProperty('sub-delay', _sec(d));

  // --- Video -------------------------------------------------------------

  /// Sets an image adjustment to [value] in -100..100.
  void setVideoAdjustment(MpvVideoAdjustment adjustment, int value) =>
      mpv.setProperty(adjustment.property, value.clamp(-100, 100));

  /// Rotation in degrees (multiples of 90), on top of the file's own.
  void setRotation(int degrees) =>
      mpv.setProperty('video-rotate', degrees % 360);

  /// Display aspect ratio override (e.g. 16 / 9); null restores the file's.
  void setAspectRatio(double? ratio) =>
      mpv.setProperty('video-aspect-override', ratio ?? -1.0);

  /// Deinterlacing (`deinterlace`): true forces it on, false off.
  void setDeinterlace(bool enable) => mpv.setProperty('deinterlace', enable);

  /// Hardware decoding mode, e.g. `auto-safe`, `vulkan`, `no`. Takes effect
  /// for the next decoder (mpv reinitialises the current one).
  void setHardwareDecoding(String mode) => mpv.setPropertyString('hwdec', mode);

  /// Current frame as raw pixels (`screenshot-raw`). With
  /// [includeSubtitles] the subtitles are drawn in (video resolution).
  Future<MpvScreenshot?> screenshot({bool includeSubtitles = false}) async {
    final node = await mpv.commandAsync([
      'screenshot-raw',
      includeSubtitles ? 'subtitles' : 'video',
    ]).result;
    return MpvScreenshot.fromNode(node);
  }

  /// Writes the current frame to [file]; the extension picks the format
  /// (`.png`, `.jpg`, `.webp`).
  Future<void> screenshotToFile(String file, {bool includeSubtitles = false}) =>
      mpv.commandAsync([
        'screenshot-to-file',
        file,
        includeSubtitles ? 'subtitles' : 'video',
      ]).result;

  /// Codec and stream facts of the current file.
  MpvMediaInfo mediaInfo() {
    Object? p(String name) => mpv.tryGetProperty(name);
    final vp = videoParams.value;
    return MpvMediaInfo(
      path: p('path') as String?,
      fileFormat: p('file-format') as String?,
      fileSize: nodeInt(p('file-size')),
      duration: secondsToDuration(p('duration')),
      videoCodec: p('video-codec') as String?,
      width: vp?.width,
      height: vp?.height,
      fps: (p('container-fps') as num?)?.toDouble(),
      videoBitrate: nodeInt(p('video-bitrate')),
      pixelFormat: vp?.pixelFormat,
      hwdec: switch (p('hwdec-current')) {
        final String s when s != 'no' && s.isNotEmpty => s,
        _ => null,
      },
      audioCodec: p('audio-codec') as String?,
      audioSampleRate: nodeInt(p('audio-params/samplerate')),
      audioChannels: nodeInt(p('audio-params/channel-count')),
      audioBitrate: nodeInt(p('audio-bitrate')),
    );
  }

  // --- Diagnostics -------------------------------------------------------

  /// Enables [logs] at [level] (`no`, `fatal`, `error`, `warn`, `info`,
  /// `v`, `debug`, `trace`).
  void setLogLevel(String level) => mpv.requestLogMessages(level);

  // --- Lifetime ----------------------------------------------------------

  /// Runs [hook] at the start of [dispose], before the mpv core is
  /// destroyed. Render contexts (mpv_kit_video) use this: libmpv requires
  /// them to be freed first.
  void addDisposeHook(Future<void> Function() hook) => _disposeHooks.add(hook);

  /// Undoes [addDisposeHook].
  void removeDisposeHook(Future<void> Function() hook) =>
      _disposeHooks.remove(hook);

  /// 释放 mpv 与全部状态流。Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Copy: hooks remove themselves while running.
    for (final hook in List.of(_disposeHooks)) {
      await hook();
    }
    _disposeHooks.clear();
    for (final s in _subs) {
      await s.cancel();
    }
    mpv.dispose();
    await _errors.close();
    await _logs.close();
    for (final s in _states) {
      await s._close();
    }
  }

  // --- Internals ---------------------------------------------------------

  void _bind<T>(String name, MpvState<T> state, T Function(Object?) parse) {
    _states.add(state);
    _subs.add(mpv.observeProperty(name).listen((v) => state._set(parse(v))));
  }

  /// 按当前 video-params 与 hwdec-current 重算 [decodeWarning]。
  ///
  /// 阈值取 1920×1088（1080p 按 16 对齐后的宏块高度）：软解兜得住的
  /// 上限；超过且没走硬解（`hwdec-current` 为 null/`no`）才告警。
  /// 无视频时清空告警（音频-only 文件不算异常）。
  void _updateDecodeWarning() {
    final params = videoParams.value;
    if (params == null ||
        (params.width ?? 0) * (params.height ?? 0) <= 1920 * 1088) {
      decodeWarning._set(null);
      return;
    }
    final hz = hwdecCurrent.value;
    if (hz != null && hz != 'no') {
      decodeWarning._set(null);
      return;
    }
    decodeWarning._set(
      '${params.width}×${params.height} 软解播放（hwdec=${hz ?? 'no'}）：'
      '该驱动未建立 Vulkan Video 硬解，4K 可能掉帧、8K 无法满帧',
    );
  }

  void _onEvent(MpvEventData e) {
    switch (e) {
      case EndFileEvent(reason: EndFileReason.error):
        _errors.add(
          MpvPlaybackError(
            error: MpvError.fromCode(e.fileError),
            message: mpv.errorString(e.fileError),
            playlistEntryId: e.playlistEntryId,
          ),
        );
      case LogMessageEvent():
        if (!_logs.isClosed) _logs.add(e);
      case ShutdownEvent():
        for (final s in _states) {
          s._reset();
        }
      default:
        break;
    }
  }

  /// `vid`/`aid`/`sid`: a track id, or `no`/false when disabled.
  static int? _trackId(Object? v) => v is bool ? null : nodeInt(v);

  static String _seconds(Duration d) => '${d.inMicroseconds / 1e6}';

  static double _sec(Duration d) => d.inMicroseconds / 1e6;

  static Map<String, String> _stringMap(Object? v) => v is Map<String, Object?>
      ? Map.unmodifiable({
          for (final MapEntry(:key, :value) in v.entries)
            if (value != null) key: '$value',
        })
      : const {};

  static Iterable<Map<String, Object?>> _maps(Object? v) =>
      v is List<Object?> ? v.whereType<Map<String, Object?>>() : const [];
}
