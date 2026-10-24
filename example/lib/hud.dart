// Debug HUD (HUD-01/HUD-02): a toggleable overlay showing five property
// groups (sync / cache / decode / render / audio) plus the controller's
// event stream, polled once per second — never on a production hot path.
//
// Composition path (HUD-02): the render line shows backend/reason live;
// the compositor line is a static note until Phase 11 wires the real
// value (the plugin registers via DxgiSharedHandle today).
//
// The data layer is split from the widget so tests can fabricate
// snapshots without a Player.
library;

import 'package:flutter/material.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

/// One polling snapshot of the debug property set.
@immutable
final class HudSnapshot {
  const HudSnapshot({
    required this.sync,
    required this.cache,
    required this.decode,
    required this.render,
    required this.audio,
    this.notice,
  });

  /// avsync family — playback synchronization health.
  final Map<String, Object?> sync;
  /// demuxer cache family.
  final Map<String, Object?> cache;
  /// decoder family.
  final Map<String, Object?> decode;
  /// render/composition family (backend, reason, compositor).
  final Map<String, Object?> render;
  /// audio family.
  final Map<String, Object?> audio;

  /// Transient one-liner (e.g. "ignored non-video file: x.txt").
  final String? notice;

  /// Reads one polling round from [player]/[controller]. Cheap by design:
  /// tryGetProperty + .value getters only; called at 1 Hz.
  static HudSnapshot capture(Player player, MpvVideoController? controller) {
    final m = player.mpv;
    Object? p(String name) {
      try {
        return m.tryGetProperty(name);
      } on Object {
        return null; // disposed mid-poll: the next tick is skipped anyway
      }
    }

    final cacheState = p('demuxer-cache-state');
    final cacheSummary = <String, Object?>{
      if (cacheState is Map) ...{
        for (final k in const [
          'total-bytes',
          'fw-bytes',
          'seekable-ranges',
          'reader-pts',
          'cache-end',
          'buffering',
          'speed',
        ])
          if (cacheState.containsKey(k)) k: cacheState[k],
      },
    };

    final vp = player.videoParams.value;
    return HudSnapshot(
      sync: {
        'avsync': p('avsync'),
        'total-avsync-change': p('total-avsync-change'),
        'dropped': p('frame-drop-count'),
        'dec-drop': p('decoder-frame-drop-count'),
        'delayed': p('vo-delayed-frame-count'),
        'mistimed': p('mistimed-frame-count'),
        'est-vf-fps': p('estimated-vf-fps'),
        'video-sync': p('video-sync'),
        'display-sync': p('display-sync-active'),
      },
      cache: {
        'demuxer-duration': p('demuxer-cache-duration'),
        'buffered-ahead': player.bufferedAhead.value.inMilliseconds,
        ...cacheSummary,
      },
      decode: {
        'hwdec': player.hwdecCurrent.value ?? p('hwdec-current'),
        'codec': p('video-codec'),
        'size': vp == null ? null : '${vp.width}x${vp.height}',
        'pixelformat': vp?.pixelFormat,
        'container-fps': p('container-fps'),
      },
      render: {
        'backend': controller?.backend.name,
        'reason': controller?.reason,
        // Phase 11 replaces this with the live composition path.
        'compositor': 'ANGLE (DxgiSharedHandle)',
      },
      audio: {
        'codec': p('audio-codec'),
        'ao': p('current-ao'),
        'volume': player.volume.value,
        'muted': player.muted.value,
      },
    );
  }

  /// Deterministic snapshot for widget tests — no Player needed.
  factory HudSnapshot.fabricated() => HudSnapshot(
        sync: const {
          'avsync': 0.000012,
          'total-avsync-change': -0.033,
          'dropped': 0,
          'dec-drop': 0,
          'delayed': 0,
          'mistimed': 0,
          'est-vf-fps': 30.0,
          'video-sync': 'audio',
          'display-sync': false,
        },
        cache: const {
          'demuxer-duration': 12.3,
          'buffered-ahead': 12300,
          'total-bytes': 1048576,
          'speed': 2400000.0,
        },
        decode: const {
          'hwdec': 'vulkan',
          'codec': 'h264',
          'size': '1920x1080',
          'pixelformat': 'nv12',
          'container-fps': 30.0,
        },
        render: const {
          'backend': 'vulkan',
          'reason': 'vulkan (gpu-next) on test gpu',
          'compositor': 'ANGLE (DxgiSharedHandle)',
        },
        audio: const {
          'codec': 'aac',
          'ao': 'null',
          'volume': 100.0,
          'muted': false,
        },
      );
}

/// One controller event for the HUD overlay.
@immutable
final class HudEvent {
  const HudEvent(this.time, this.kind, this.message);
  final DateTime time;
  final String kind;
  final String message;

  bool get isError => kind == 'deviceLost' || kind == 'renderError';
}

/// Bounded ring of the most recent controller events.
final class HudEventLog {
  HudEventLog([this.capacity = 8]) : _items = <HudEvent>[];

  final int capacity;
  final List<HudEvent> _items;

  List<HudEvent> get items => List.unmodifiable(_items);

  void add(String kind, [String message = '']) {
    _items.add(HudEvent(DateTime.now(), kind, message));
    if (_items.length > capacity) _items.removeRange(0, _items.length - capacity);
  }
}

/// The overlay panel. Parent controls [visible] and passes the latest
/// [snapshot]/[events]; the widget itself owns nothing but layout.
final class DebugHud extends StatelessWidget {
  const DebugHud({
    super.key,
    required this.visible,
    required this.snapshot,
    required this.events,
  });

  final bool visible;
  final HudSnapshot snapshot;
  final List<HudEvent> events;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.25);
  static const _head = TextStyle(
      fontFamily: 'monospace', fontSize: 11, color: Color(0xFF7EC8E3));

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const Positioned(
        right: 8,
        top: 8,
        child: IgnorePointer(
          child: Text('F9: HUD',
              style: TextStyle(color: Color(0x88FFFFFF), fontSize: 11)),
        ),
      );
    }
    return Positioned(
      left: 8,
      top: 8,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DefaultTextStyle(
            style: _mono.copyWith(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _group('SYNC', snapshot.sync),
                _group('CACHE', snapshot.cache),
                _group('DECODE', snapshot.decode),
                _group('RENDER', snapshot.render),
                _group('AUDIO', snapshot.audio),
                if (snapshot.notice != null)
                  Text(snapshot.notice!,
                      style: _mono.copyWith(color: Color(0xFFFFCC66))),
                if (events.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('EVENTS', style: _head),
                  for (final e in events)
                    Text(
                      '${_hhmmss(e.time)} ${e.kind}'
                      '${e.message.isEmpty ? '' : ' ${e.message}'}',
                      style: _mono.copyWith(
                          color: e.isError
                              ? const Color(0xFFFF6666)
                              : const Color(0xFFAAAAAA)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  Widget _group(String title, Map<String, Object?> props) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _head),
            Text(
              props.entries
                  .map((e) => '${e.key}=${e.value ?? '-'}')
                  .join('  '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}

/// Video-extension allowlist for drag-and-drop (DND-01). Plain paths must
/// end in a known video extension (case-insensitive); av:// and http(s)://
/// URLs pass through for mpv to handle.
bool isVideoPlayable(String path) {
  final p = path.trim().toLowerCase();
  if (p.startsWith('av://') || p.startsWith('http://') || p.startsWith('https://')) {
    return true;
  }
  const exts = {
    '.mp4', '.mkv', '.webm', '.mov', '.avi', '.flv',
    '.ts', '.m2ts', '.m4v', '.mpg', '.mpeg', '.wmv', '.3gp',
  };
  final dot = p.lastIndexOf('.');
  if (dot < 0) return false;
  return exts.contains(p.substring(dot));
}
