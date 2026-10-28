/// Pure helpers of the hardware-decode probe (Phase 16, HWD-05).
///
/// Decides whether a playback run decoded on the GPU and handed the frames to
/// the renderer without a CPU round trip (`zero-copy`), downloaded them
/// (`copy-back`) or decoded in software (`software`), and prints the
/// `HWDEC {json}` line the CI gates match. The file depends only on
/// `dart:convert`, never on the plugin, so a unit test and
/// any integration test can share it.
///
/// A run is never called zero-copy from `hwdec-current` alone: the method name
/// is also printed for runs that copy back (Pitfall 1 of the phase research).
library;

import 'dart:convert';

/// How one run decoded.
enum HwdecOutcome {
  /// Hardware decoder, frames stay on the GPU.
  zeroCopy('zero-copy'),

  /// Hardware decoder, frames are downloaded to system memory.
  copyBack('copy-back'),

  /// Software decoder (`hwdec-current` is `no`).
  software('software'),

  /// Nothing conclusive: no decoder yet, or a method this table does not know.
  unexpected('unexpected');

  const HwdecOutcome(this.wire);

  /// Name printed in the `HWDEC` line.
  final String wire;
}

/// The hardware pixel format name `video-params/pixelformat` shows for each
/// non-copy hwdec method.
///
/// `vaapi` and `videotoolbox` are mpv's own names (`img_format.c`).
/// `d3d11`, `vulkan` and `drm_prime` are FFmpeg pix_fmt names; they are
/// ASSUMED here (source level only, not seen in a log: hosted runners do not
/// decode in hardware) and are checked by the RTX 4060 session of 16-06.
const Map<String, String> hwdecZeroCopyFormats = {
  'd3d11va': 'd3d11',
  'vaapi': 'vaapi',
  'vulkan': 'vulkan',
  'videotoolbox': 'videotoolbox',
  'drm': 'drm_prime',
};

/// Suffix mpv appends to the method name when the frames are downloaded.
const String _copySuffix = '-copy';

/// Classifies one run from the three markers.
///
/// - `null` or empty [hwdecCurrent]: [HwdecOutcome.unexpected] (no decoder
///   exists yet; the caller must wait, never skip).
/// - `no`: [HwdecOutcome.software].
/// - a known `<method>-copy`: [HwdecOutcome.copyBack].
/// - a known non-copy method: zero-copy only when [pixelformat] is that
///   method's hardware format AND [hwPixelformat] (the underlying format,
///   e.g. `nv12`) is non-empty. A different non-empty [pixelformat] means the
///   frames were downloaded (copy-back); anything else is unexpected.
///   `d3d11va` keeps its name when `d3d11va-zero-copy=no` and when interop
///   mapping fails, so the name alone proves nothing.
/// - any other method: [HwdecOutcome.unexpected].
HwdecOutcome classifyHwdec({
  String? hwdecCurrent,
  String? pixelformat,
  String? hwPixelformat,
}) {
  if (hwdecCurrent == null || hwdecCurrent.isEmpty) {
    return HwdecOutcome.unexpected;
  }
  if (hwdecCurrent == 'no') return HwdecOutcome.software;
  if (hwdecCurrent.endsWith(_copySuffix)) {
    final base = hwdecCurrent.substring(
      0,
      hwdecCurrent.length - _copySuffix.length,
    );
    return hwdecZeroCopyFormats.containsKey(base)
        ? HwdecOutcome.copyBack
        : HwdecOutcome.unexpected;
  }
  final hardwareFormat = hwdecZeroCopyFormats[hwdecCurrent];
  if (hardwareFormat == null) return HwdecOutcome.unexpected;
  if (pixelformat == hardwareFormat &&
      hwPixelformat != null &&
      hwPixelformat.isNotEmpty) {
    return HwdecOutcome.zeroCopy;
  }
  if (pixelformat != null &&
      pixelformat.isNotEmpty &&
      pixelformat != hardwareFormat) {
    return HwdecOutcome.copyBack;
  }
  return HwdecOutcome.unexpected;
}

/// A property value as option text. mpv's `hwdec` is a string list, and
/// `List.toString()` would print brackets (Phase 13 fed that back as a value
/// and "measured" a software default that never existed).
String hwdecOptionText(Object? value) => switch (value) {
  null => '',
  final List<Object?> list => list.map((e) => '$e').join(','),
  final String text => text,
  _ => '$value',
};

/// The api of a controller `reason`: its first word (ADR 0004).
String reasonApi(String reason) {
  final end = reason.indexOf(' ');
  return end < 0 ? reason : reason.substring(0, end);
}

/// Reads an mpv flag as bool; null when it is neither a bool nor yes/no.
bool? _flag(Object? value) => switch (value) {
  final bool flag => flag,
  'yes' => true,
  'no' => false,
  _ => null,
};

/// Text of an optional property, null when unavailable.
String? _text(Object? value) => value == null ? null : '$value';

/// What one reading of the hwdec properties says.
final class HwdecReport {
  const HwdecReport({
    required this.test,
    required this.sample,
    required this.at,
    required this.api,
    required this.requested,
    required this.hwdecCurrent,
    required this.hwdecInterop,
    required this.pixelformat,
    required this.hwPixelformat,
    required this.d3d11vaZeroCopy,
    required this.outcome,
    required this.reason,
  });

  /// Reads the properties through [property] (e.g. `player.mpv.tryGetProperty`)
  /// and classifies them.
  factory HwdecReport.read(
    Object? Function(String name) property, {
    required String test,
    required String sample,
    required String at,
    required String reason,
    required String requested,
  }) {
    final current = _text(property('hwdec-current'));
    final pixelformat = _text(property('video-params/pixelformat'));
    final hwPixelformat = _text(property('video-params/hw-pixelformat'));
    return HwdecReport(
      test: test,
      sample: sample,
      at: at,
      api: reasonApi(reason),
      requested: requested,
      hwdecCurrent: current,
      hwdecInterop: _text(property('hwdec-interop')),
      pixelformat: pixelformat,
      hwPixelformat: hwPixelformat,
      d3d11vaZeroCopy: _flag(property('options/d3d11va-zero-copy')),
      outcome: classifyHwdec(
        hwdecCurrent: current,
        pixelformat: pixelformat,
        hwPixelformat: hwPixelformat,
      ),
      reason: reason,
    );
  }

  final String test;
  final String sample;

  /// `first-frame` or `end`.
  final String at;

  /// First word of [reason] (ADR 0004).
  final String api;

  /// `no` or the Player's default list as option text.
  final String requested;

  final String? hwdecCurrent;
  final String? hwdecInterop;
  final String? pixelformat;
  final String? hwPixelformat;
  final bool? d3d11vaZeroCopy;
  final HwdecOutcome outcome;

  /// The controller's full reason text.
  final String reason;

  /// Whether the run was classified zero-copy.
  bool get zeroCopy => outcome == HwdecOutcome.zeroCopy;

  /// The `HWDEC {json}` report line; the key order is part of the contract
  /// (CI gates match it as text).
  String get line =>
      'HWDEC ${jsonEncode(<String, Object?>{'schema': 'hwdec-1', 'test': test, 'sample': sample, 'at': at, 'api': api, 'requested': requested, 'hwdecCurrent': hwdecCurrent, 'hwdecInterop': hwdecInterop, 'pixelformat': pixelformat, 'hwPixelformat': hwPixelformat, 'd3d11vaZeroCopy': d3d11vaZeroCopy, 'outcome': outcome.wire, 'zeroCopy': zeroCopy, 'reason': reason})}';
}

/// Polls until `hwdec-current` has a value or [timeout] passes, then reads
/// the report. A timeout yields an `unexpected` report: it is never dropped
/// or skipped.
Future<HwdecReport> awaitHwdecReport(
  Object? Function(String name) property, {
  required String test,
  required String sample,
  required String at,
  required String reason,
  required String requested,
  Duration timeout = const Duration(seconds: 10),
  Duration poll = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final current = property('hwdec-current');
    if (current != null && '$current'.isNotEmpty) break;
    if (!DateTime.now().isBefore(deadline)) break;
    await Future<void>.delayed(poll);
  }
  return HwdecReport.read(
    property,
    test: test,
    sample: sample,
    at: at,
    reason: reason,
    requested: requested,
  );
}
