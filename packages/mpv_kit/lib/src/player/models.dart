/// Player 高层的强类型数据模型（由 mpv node 解析，宽松容错）。
library;

import '../core/errors.dart';

/// `track-list` 中的轨道类型。
enum MpvTrackType {
  /// Video track.
  video,

  /// Audio track.
  audio,

  /// Subtitle track.
  sub,

  /// A type this binding does not know.
  unknown,
}

/// 一条音/视/字幕轨道（`track-list/N`）。
final class MpvTrack {
  /// Creates a track description.
  const MpvTrack({
    required this.id,
    required this.type,
    this.title,
    this.lang,
    this.codec,
    this.selected = false,
    this.isDefault = false,
    this.external = false,
    this.width,
    this.height,
    this.channels,
    this.isAlbumArt = false,
    this.raw = const {},
  });

  /// 解析一条 track-list 节点。
  factory MpvTrack.fromNode(Map<String, Object?> m) => MpvTrack(
    id: _int(m['id']) ?? -1,
    type: switch (m['type']) {
      'video' => MpvTrackType.video,
      'audio' => MpvTrackType.audio,
      'sub' => MpvTrackType.sub,
      _ => MpvTrackType.unknown,
    },
    title: m['title'] as String?,
    lang: m['lang'] as String?,
    codec: m['codec'] as String?,
    selected: m['selected'] == true,
    isDefault: m['default'] == true,
    external: m['external'] == true,
    width: _int(m['demux-w']),
    height: _int(m['demux-h']),
    channels: _int(m['demux-channel-count']),
    isAlbumArt: m['albumart'] == true,
    raw: m,
  );

  /// Track id, as used by `vid`/`aid`/`sid`.
  final int id;

  /// Kind of track.
  final MpvTrackType type;

  /// Title, if the file or entry provides one.
  final String? title;

  /// Language tag (e.g. `eng`), if known.
  final String? lang;

  /// Codec name (e.g. `h264`, `aac`).
  final String? codec;

  /// Whether the track is currently selected.
  final bool selected;

  /// Whether the file marks the track as default.
  final bool isDefault;

  /// Whether the track comes from an external file.
  final bool external;

  /// Width in pixels, if known.
  final int? width;

  /// Height in pixels, if known.
  final int? height;

  /// Audio channel count, if known.
  final int? channels;

  /// 视频轨实为音频文件内嵌的封面图（`albumart`）。音乐播放时 mpv 默认把
  /// 封面当作一帧静止画面显示（`audio-display=embedded-first`）。
  final bool isAlbumArt;

  /// 完整原始字段（mpv 提供的所有键）。
  final Map<String, Object?> raw;
}

/// `playlist/N`。
final class MpvPlaylistEntry {
  /// Creates a playlist entry.
  const MpvPlaylistEntry({
    required this.filename,
    this.title,
    this.current = false,
    this.id,
  });

  /// Parses one `playlist` node.
  factory MpvPlaylistEntry.fromNode(Map<String, Object?> m) => MpvPlaylistEntry(
    filename: m['filename'] as String? ?? '',
    title: m['title'] as String?,
    current: m['current'] == true,
    id: _int(m['id']),
  );

  /// File name or URL as added to the playlist.
  final String filename;

  /// Title, if the file or entry provides one.
  final String? title;

  /// Whether this entry is the one being played.
  final bool current;

  /// Stable playlist entry id (`playlist/N/id`).
  final int? id;
}

/// `chapter-list/N`。
final class MpvChapter {
  /// Creates a chapter.
  const MpvChapter({required this.time, this.title});

  /// Parses one `chapter-list` node.
  factory MpvChapter.fromNode(Map<String, Object?> m) => MpvChapter(
    time: _duration(m['time']) ?? Duration.zero,
    title: m['title'] as String?,
  );

  /// Start time of the chapter.
  final Duration time;

  /// Title, if the file or entry provides one.
  final String? title;
}

/// `video-params`：解码后视频的几何与色彩参数。
final class MpvVideoParams {
  /// Creates video parameters.
  const MpvVideoParams({
    this.width,
    this.height,
    this.pixelFormat,
    this.primaries,
    this.gamma,
    this.rotate = 0,
    this.aspect,
    this.raw = const {},
  });

  /// Parses the `video-params` node.
  factory MpvVideoParams.fromNode(Map<String, Object?> m) => MpvVideoParams(
    width: _int(m['w']),
    height: _int(m['h']),
    pixelFormat: m['pixelformat'] as String?,
    primaries: m['primaries'] as String?,
    gamma: m['gamma'] as String?,
    rotate: _int(m['rotate']) ?? 0,
    aspect: (m['aspect'] as num?)?.toDouble(),
    raw: m,
  );

  /// Width in pixels, if known.
  final int? width;

  /// Height in pixels, if known.
  final int? height;

  /// Pixel format (e.g. `yuv420p`, `nv12`).
  final String? pixelFormat;

  /// Color primaries (e.g. `bt.709`, `bt.2020`).
  final String? primaries;

  /// 传输特性，例如 `pq`（HDR10）、`hlg`、`bt.1886`。
  final String? gamma;

  /// Rotation in degrees from the file's metadata.
  final int rotate;

  /// Display aspect ratio (width / height), if known.
  final double? aspect;

  /// All raw fields of the mpv node.
  final Map<String, Object?> raw;
}

/// `audio-params`：解码后（滤镜前）的音频格式。
final class MpvAudioParams {
  /// Creates audio parameters.
  const MpvAudioParams({
    this.format,
    this.sampleRate,
    this.channels,
    this.channelCount,
    this.raw = const {},
  });

  /// Parses the `audio-params` node.
  factory MpvAudioParams.fromNode(Map<String, Object?> m) => MpvAudioParams(
    format: m['format'] as String?,
    sampleRate: _int(m['samplerate']),
    channels: m['channels'] as String?,
    channelCount: _int(m['channel-count']),
    raw: m,
  );

  /// Sample format (e.g. `floatp`, `s16`, `s32`).
  final String? format;

  /// Sample rate in Hz.
  final int? sampleRate;

  /// Channel layout (e.g. `stereo`, `5.1`).
  final String? channels;

  /// Number of channels.
  final int? channelCount;

  /// All raw fields of the mpv node.
  final Map<String, Object?> raw;
}

/// 一个音频输出设备（`audio-device-list/N`）。
final class MpvAudioDevice {
  /// Creates a device description.
  const MpvAudioDevice({required this.name, required this.description});

  /// Parses an `audio-device-list` entry.
  factory MpvAudioDevice.fromNode(Map<String, Object?> m) => MpvAudioDevice(
    name: m['name'] as String? ?? '',
    description: m['description'] as String? ?? '',
  );

  /// Value for `audio-device` (e.g. `auto`, `wasapi/{guid}`).
  final String name;

  /// Human-readable name shown by the system.
  final String description;

  @override
  bool operator ==(Object other) =>
      other is MpvAudioDevice &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, description);

  @override
  String toString() => 'MpvAudioDevice($name: $description)';
}

/// One seekable range of the demuxer cache (a `seekable-ranges` entry of
/// `demuxer-cache-state`): seeking inside it needs no new read from the
/// source.
final class MpvSeekableRange {
  /// Creates a range from [start] to [end].
  const MpvSeekableRange({required this.start, required this.end});

  /// Start of the cached range.
  final Duration start;

  /// End of the cached range.
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is MpvSeekableRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'MpvSeekableRange($start..$end)';
}

/// Demuxer cache state (`demuxer-cache-state`): how much is buffered ahead,
/// how many bytes the packet queue holds and which ranges are seekable.
///
/// Optional fields are null when mpv leaves the key out (no value yet, or
/// not applicable such as [fileCacheBytes] without `cache-on-disk`).
final class MpvDemuxerCacheState {
  /// Creates a cache state; [seekableRanges] defaults to none.
  const MpvDemuxerCacheState({
    this.cacheEnd,
    this.readerPts,
    this.cacheDuration,
    this.forwardBytes = 0,
    this.totalBytes = 0,
    this.fileCacheBytes,
    this.rawInputRate,
    this.eof = false,
    this.underrun = false,
    this.idle = false,
    this.bofCached = false,
    this.eofCached = false,
    this.seekableRanges = const [],
  });

  /// mpv itself caps `seekable-ranges` at 10 (`MAX_SEEK_RANGES`); the node
  /// is still external input, so keep at most this many.
  static const maxSeekableRanges = 64;

  /// Parses a `demuxer-cache-state` node; null for anything but a map
  /// (the property is unavailable while no file is loaded).
  ///
  /// Never throws: missing keys, wrong types, negative byte counts and
  /// non-finite times become null/0, and inverted ranges are dropped.
  static MpvDemuxerCacheState? fromNode(Object? v) {
    // Any map: readNode yields Map<String, Object?>, hand-built ones may not.
    if (v is! Map<Object?, Object?>) return null;
    final ranges = <MpvSeekableRange>[
      if (v['seekable-ranges'] case final List<Object?> list)
        for (final r in list.take(maxSeekableRanges))
          if (r case {'start': final Object? s, 'end': final Object? e})
            if ((_finiteDuration(s), _finiteDuration(e)) case (
              final start?,
              final end?,
            ) when end >= start)
              MpvSeekableRange(start: start, end: end),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return MpvDemuxerCacheState(
      cacheEnd: _finiteDuration(v['cache-end']),
      readerPts: _finiteDuration(v['reader-pts']),
      cacheDuration: _finiteDuration(v['cache-duration']),
      forwardBytes: _nonNegativeInt(v['fw-bytes']) ?? 0,
      totalBytes: _nonNegativeInt(v['total-bytes']) ?? 0,
      fileCacheBytes: _nonNegativeInt(v['file-cache-bytes']),
      rawInputRate: _nonNegativeInt(v['raw-input-rate']),
      eof: v['eof'] == true,
      underrun: v['underrun'] == true,
      idle: v['idle'] == true,
      bofCached: v['bof-cached'] == true,
      eofCached: v['eof-cached'] == true,
      seekableRanges: List.unmodifiable(ranges),
    );
  }

  /// Timestamp of the end of the cached data (`cache-end`).
  final Duration? cacheEnd;

  /// Timestamp the decoder has read up to (`reader-pts`).
  final Duration? readerPts;

  /// Buffered duration ahead of [readerPts] (`cache-duration`).
  final Duration? cacheDuration;

  /// Bytes of packets queued ahead of the reader (`fw-bytes`).
  final int forwardBytes;

  /// Bytes held by the packet queue, forward and back (`total-bytes`).
  final int totalBytes;

  /// Bytes written to the disk cache (`file-cache-bytes`), when enabled.
  final int? fileCacheBytes;

  /// Estimated source read rate in bytes per second (`raw-input-rate`).
  final int? rawInputRate;

  /// Whether the demuxer reached the end of the file (`eof`).
  final bool eof;

  /// Whether the reader ran out of data (`underrun`).
  final bool underrun;

  /// Whether the demuxer is not reading ahead right now (`idle`).
  final bool idle;

  /// Whether the start of the file is cached (`bof-cached`).
  final bool bofCached;

  /// Whether the end of the file is cached (`eof-cached`).
  final bool eofCached;

  /// Seekable cached ranges, sorted by start (`seekable-ranges`).
  final List<MpvSeekableRange> seekableRanges;

  @override
  bool operator ==(Object other) =>
      other is MpvDemuxerCacheState &&
      other.cacheEnd == cacheEnd &&
      other.readerPts == readerPts &&
      other.cacheDuration == cacheDuration &&
      other.forwardBytes == forwardBytes &&
      other.totalBytes == totalBytes &&
      other.fileCacheBytes == fileCacheBytes &&
      other.rawInputRate == rawInputRate &&
      other.eof == eof &&
      other.underrun == underrun &&
      other.idle == idle &&
      other.bofCached == bofCached &&
      other.eofCached == eofCached &&
      _sameRanges(other.seekableRanges, seekableRanges);

  @override
  int get hashCode => Object.hash(
    cacheEnd,
    readerPts,
    cacheDuration,
    forwardBytes,
    totalBytes,
    fileCacheBytes,
    rawInputRate,
    eof,
    underrun,
    idle,
    bofCached,
    eofCached,
    Object.hashAll(seekableRanges),
  );

  @override
  String toString() =>
      'MpvDemuxerCacheState(ahead: $cacheDuration, '
      'fw: $forwardBytes B, total: $totalBytes B, '
      'ranges: ${seekableRanges.length})';

  static bool _sameRanges(List<MpvSeekableRange> a, List<MpvSeekableRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 循环方式：`loop-file` / `loop-playlist` 的组合（对应 media_kit 的
/// `PlaylistMode.single` / `loop` / `none`）。
enum MpvLoopMode {
  /// Play the playlist once.
  none,

  /// Repeat the current file (`loop-file=inf`).
  file,

  /// Repeat the whole playlist (`loop-playlist=inf`).
  playlist,
}

/// 响度均衡（`replaygain`）：使用文件中的 ReplayGain 标签。
enum MpvReplayGain {
  /// Ignore ReplayGain tags.
  off('no'),

  /// Per-track gain.
  track('track'),

  /// Per-album gain (consistent loudness within an album).
  album('album');

  const MpvReplayGain(this.value);

  /// mpv value of `replaygain`.
  final String value;
}

int? _int(Object? v) => switch (v) {
  final int i => i,
  final double d => d.round(),
  _ => null,
};

/// 秒（double）→ Duration。
Duration? _duration(Object? v) => switch (v) {
  final num n => Duration(microseconds: (n * 1e6).round()),
  _ => null,
};

/// 有限秒数 → Duration；NaN/inf（`round()` 会抛错）返回 null。
Duration? _finiteDuration(Object? v) =>
    v is num && v.isFinite ? _duration(v) : null;

/// 非负整数；负数（只可能来自损坏的 node）与 NaN/inf 返回 null。
int? _nonNegativeInt(Object? v) => switch (v) {
  final int i when i >= 0 => i,
  final double d when d.isFinite && d >= 0 => d.round(),
  _ => null,
};

/// 供 Player 使用的公开转换函数。
Duration? secondsToDuration(Object? v) => _duration(v);

/// A failed or aborted load (`end-file` with reason `error`).
final class MpvPlaybackError {
  /// Creates an error for a failed playlist entry.
  const MpvPlaybackError({
    required this.error,
    required this.message,
    required this.playlistEntryId,
  });

  /// Typed mpv error, e.g. [MpvError.loadingFailed].
  final MpvError error;

  /// `mpv_error_string` of the error.
  final String message;

  /// Playlist entry that failed (`playlist-entry-id`).
  final int playlistEntryId;

  @override
  String toString() => 'MpvPlaybackError(${error.name}: $message)';
}

/// Image adjustments of the `brightness`/`contrast`/... properties, each an
/// integer in -100..100 (0 = unchanged).
enum MpvVideoAdjustment {
  /// Brightness (`brightness`).
  brightness('brightness'),

  /// Contrast (`contrast`).
  contrast('contrast'),

  /// Saturation (`saturation`).
  saturation('saturation'),

  /// Gamma (`gamma`).
  gamma('gamma'),

  /// Hue (`hue`).
  hue('hue');

  /// Creates an adjustment bound to its mpv [property].
  const MpvVideoAdjustment(this.property);

  /// mpv property name.
  final String property;
}

/// Uncompressed screenshot from `screenshot-raw`.
final class MpvScreenshot {
  /// Creates a screenshot from raw pixel data.
  const MpvScreenshot({
    required this.width,
    required this.height,
    required this.stride,
    required this.format,
    required this.data,
  });

  /// Parses the node returned by `screenshot-raw`; null if malformed.
  static MpvScreenshot? fromNode(Object? node) {
    if (node is! Map<String, Object?>) return null;
    final w = _int(node['w']), h = _int(node['h']), s = _int(node['stride']);
    final data = node['data'];
    if (w == null || h == null || s == null || data is! List<int>) return null;
    return MpvScreenshot(
      width: w,
      height: h,
      stride: s,
      format: node['format'] as String? ?? 'bgr0',
      data: data,
    );
  }

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Bytes per row (may exceed `width * 4`).
  final int stride;

  /// Pixel format: `bgr0` (8-bit BGRX) or `rgba64` (16-bit RGBA, little
  /// endian), as requested.
  final String format;

  /// Pixel rows, `stride * height` bytes.
  final List<int> data;
}

/// Snapshot of codec and stream facts for the current file (as shown in a
/// "media info" dialog). Fields are null when mpv does not know them.
final class MpvMediaInfo {
  /// Creates a media info snapshot.
  const MpvMediaInfo({
    this.path,
    this.fileFormat,
    this.fileSize,
    this.duration,
    this.videoCodec,
    this.width,
    this.height,
    this.fps,
    this.videoBitrate,
    this.pixelFormat,
    this.hwdec,
    this.audioCodec,
    this.audioSampleRate,
    this.audioChannels,
    this.audioBitrate,
  });

  /// Path or URL of the file.
  final String? path;

  /// Container format (`file-format`).
  final String? fileFormat;

  /// File size in bytes.
  final int? fileSize;

  /// Duration of the file.
  final Duration? duration;

  /// Video codec description (`video-codec`).
  final String? videoCodec;

  /// Width in pixels, if known.
  final int? width;

  /// Height in pixels, if known.
  final int? height;

  /// Container frame rate.
  final double? fps;

  /// Bits per second.
  final int? videoBitrate;

  /// Pixel format (e.g. `yuv420p`, `nv12`).
  final String? pixelFormat;

  /// Active hardware decoder, null for software decoding.
  final String? hwdec;

  /// Audio codec description (`audio-codec`).
  final String? audioCodec;

  /// Audio sample rate in Hz.
  final int? audioSampleRate;

  /// Audio channel count.
  final int? audioChannels;

  /// Bits per second.
  final int? audioBitrate;
}

/// Reads an int-ish mpv value.
int? nodeInt(Object? v) => _int(v);
