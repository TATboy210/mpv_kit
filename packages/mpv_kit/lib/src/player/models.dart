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
