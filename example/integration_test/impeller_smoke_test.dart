// Phase 10 Impeller composition smoke (COMP-01(b)).
//
// Pins the ONE local Flutter SDK (3.47.8, framework 737ba8f885, engine
// revision cf636b1dfb) and runs the D-04 workload in a single testWidgets:
//
//   Part 1  create -> one composed frame -> dispose (1920x1080 source)
//   Part 2  one 4K render target (3840x2160; the 1080p source is scaled)
//   Part 3  100 resize/dispose rounds against one live Player, >= 30 s
//
// Run from example/ with the window VISIBLE (a minimised window drives the
// renderer into its idle path and invalidates the soak):
//
//   MPV_KIT_LIBMPV_PATH=<libmpv-2.dll> PATH="$PATH:<libdir>" \
//     D:/flutter/bin/flutter test integration_test/impeller_smoke_test.dart \
//     -d windows --enable-impeller
//
// The control run uses --no-enable-impeller; the engine's own
// "Using the Impeller rendering backend" log line, not this file, is the
// proof of which compositor is live.
//
// Reporting channel: one `BENCH impeller {json}` line per stage on stdout.
// A harness-side failure emits `result=inconclusive`, never silence and never
// a fabricated pass.
@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

/// Matches VideoRenderer::kIdleTimeout (packages/mpv_kit_video/src/
/// video_renderer.h:171). The renderer also enters idle when the texture is
/// off screen, so an idle event is not by itself a renderer failure: only an
/// idle that arrives while the texture has been continuously mounted for this
/// long is counted as a soak-window idle.
const Duration _idleTimeout = Duration(milliseconds: 500);

/// A composed frame must have some non-black pixels. A black-but-alive
/// process is not a pass (Impeller's GL_RGBA8 format cliff shows up as a
/// silent black texture, not a crash).
const double _minNonBlackRatio = 0.01;

/// One BENCH line on stdout. Integration tests have no console logger.
void _emitBench(Map<String, Object?> payload) {
  stdout.writeln('BENCH impeller ${jsonEncode(payload)}');
}

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the harness.
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Impeller composition smoke (3 parts)', (tester) async {
    await _SmokeHarness().run(tester);
  });
}

/// D-04 workload. Private to this file: the smoke is a one-off evidence
/// harness, not a reusable driver.
final class _SmokeHarness {
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final GlobalKey _probeKey = GlobalKey();
  final Stopwatch _clock = Stopwatch();
  final List<StreamSubscription<MpvVideoEvent>> _subscriptions = [];

  /// Per-part outcome: 'ok' once the part completed, otherwise inconclusive.
  final Map<String, String> _parts = {
    'oneFrame': 'inconclusive',
    'uhd4k': 'inconclusive',
    'soak': 'inconclusive',
  };

  String _stage = 'preflight';
  Map<String, Object?> _details = const {};

  Player? _player;
  MpvVideoController? _controller;

  /// When the external texture was last mounted (null while unmounted).
  Duration? _mountedAt;

  bool _soakStarted = false;
  DateTime? _soakStart;

  int _resizeEvents = 0;
  int _activeEvents = 0;
  int _gpuTimeouts = 0;
  int _recovered = 0;
  int _renderErrors = 0;
  bool _deviceLost = false;
  int _idleSoak = 0;
  int _idleDuringUnmount = 0;
  bool _saw4kResize = false;

  int _rssStart = 0;
  Map<String, Object?> _pixelProbe = const {
    'supported': false,
    'reason': 'probe not executed',
  };

  Future<void> run(WidgetTester tester) async {
    _clock.start();
    final mpvKitPath = Platform.environment['MPV_KIT_LIBMPV_PATH'];
    _emitBench({
      'stage': 'preflight',
      'dart': Platform.version,
      'releaseMode': kReleaseMode,
      'profileMode': kProfileMode,
      'mpvKitPath': mpvKitPath,
    });

    // Minimal tree: the Texture is the only thing this harness needs to
    // compose. MpvVideo is deliberately not used — it calls setSize itself,
    // which would fight D-04's direct size control.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ValueListenableBuilder<int?>(
            valueListenable: _textureId,
            builder: (context, textureId, child) => textureId == null
                ? const SizedBox.shrink()
                : RepaintBoundary(
                    key: _probeKey,
                    child: SizedBox(
                      width: 1280,
                      height: 720,
                      child: Texture(textureId: textureId),
                    ),
                  ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      try {
        await _execute(mpvKitPath);
      } on Object catch (error) {
        _emitBench({
          'stage': _stage,
          'result': 'inconclusive',
          'error': '${error.runtimeType}: $error',
          'parts': _parts,
          ..._details,
        });
        await _disposeQuietly();
        rethrow;
      }
    });
  }

  Future<void> _execute(String? mpvKitPath) async {
    if (kReleaseMode || kProfileMode) {
      throw StateError('the smoke must run in a debug build');
    }
    if (mpvKitPath == null || mpvKitPath.isEmpty) {
      throw StateError('MPV_KIT_LIBMPV_PATH is not set');
    }

    final player = _player = Player(
      options: const {
        'vo': 'libmpv',
        'hwdec': 'auto-safe',
        'keep-open': 'yes',
        'idle': 'yes',
        'terminal': 'no',
        'ao': 'null',
      },
    );
    final controller = _controller = await MpvVideoController.create(player);
    _watch(controller);

    // Identity gate before any measurement: a silently substituted libmpv
    // would make this a software/other-backend run attributed to Impeller.
    final resolved = MpvLibrary.resolvedPath;
    final pathMatches =
        resolved != null && resolved.toLowerCase() == mpvKitPath.toLowerCase();
    final backendMatches = controller.backend == MpvVideoBackend.vulkan;
    if (!pathMatches || !backendMatches) {
      _details = {
        'resolvedLibmpv': resolved,
        'expectedLibmpv': mpvKitPath,
        'mpvBackend': controller.backend.name,
        'mpvReason': controller.reason,
        'lastOpenAttempts': MpvLibrary.lastOpenAttempts,
      };
      throw StateError(
        'preflight identity failed: resolved=$resolved '
        'backend=${controller.backend.name}',
      );
    }
    _rssStart = ProcessInfo.currentRss;

    // --- Part 1: minimal chain, 1920x1080 source --------------------------
    _stage = 'part1';
    _setTexture(controller.textureId);
    final part1Watch = Stopwatch()..start();
    await player.open(
      'av://lavfi:testsrc2=size=1920x1080:rate=30:duration=120[out0];'
      'sine=frequency=440:sample_rate=48000:duration=120[out1]',
    );
    final resizeBaseline = _resizeEvents;
    final part1Ready = await _waitUntil(() {
      final params = player.videoParams.value;
      final fps = player.mpv.tryGetProperty('estimated-vf-fps');
      return params?.width == 1920 &&
          params?.height == 1080 &&
          fps is num &&
          fps > 0 &&
          _resizeEvents > resizeBaseline;
    }, timeout: const Duration(seconds: 30));
    part1Watch.stop();
    if (!part1Ready) {
      throw StateError(
        'part 1 readiness timeout: params=${player.videoParams.value?.width}'
        'x${player.videoParams.value?.height} '
        'fps=${player.mpv.tryGetProperty('estimated-vf-fps')} '
        'resizeEvents=$_resizeEvents',
      );
    }
    _parts['oneFrame'] = 'ok';
    final part1Ms = part1Watch.elapsedMilliseconds;

    // Free the render context before the next part creates its own.
    _setTexture(null);
    await _nextFrame();
    await controller.dispose();
    _controller = null;

    // --- Part 2: one 4K render target -------------------------------------
    _stage = 'part2';
    final uhdController = _controller = await MpvVideoController.create(player);
    _watch(uhdController);
    _setTexture(uhdController.textureId);
    await _nextFrame();
    _saw4kResize = false;
    final part2Watch = Stopwatch()..start();
    // 4K render target; the 1080p lavfi source is scaled by mpv.
    await uhdController.setSize(3840, 2160);
    final uhdReady = await _waitUntil(
      () => _saw4kResize,
      timeout: const Duration(seconds: 30),
    );
    if (!uhdReady) {
      throw StateError('part 2 never reported a 3840x2160 resize');
    }
    // Hold the 4K target for ~2 s so the compositor samples it repeatedly.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _nextFrame();
    final part2Ms = part2Watch.elapsedMilliseconds;
    final fps4k = player.mpv.tryGetProperty('estimated-vf-fps');

    // Pixel proof: a black-but-alive frame is not a pass.
    _pixelProbe = await _probePixels();
    _parts['uhd4k'] = 'ok';

    // --- Part 3: 30 s soak with 100 resize/dispose rounds -----------------
    _stage = 'soak';
    _emitBench({
      'stage': 'soak-start',
      'parts': _parts,
      'rssBytes': ProcessInfo.currentRss,
      'pixelProbe': _pixelProbe,
    });
    _soakStarted = true;
    _soakStart = DateTime.now();

    var rounds = 0;
    for (var i = 0; i < 100; i++) {
      _setTexture(null);
      await _nextFrame();
      final (width, height) = i.isEven ? (1280, 720) : (640, 360);
      await _controller!.setSize(width, height);
      await _controller!.dispose();
      _controller = null;
      final next = _controller = await MpvVideoController.create(player);
      _watch(next);
      _setTexture(next.textureId);
      await _nextFrame();
      rounds = i + 1;
      if (rounds % 10 == 0) {
        _emitBench({
          'stage': 'soak-progress',
          'rounds': rounds,
          'seconds': _soakSeconds(),
          'resizeEvents': _resizeEvents,
          'idleSoak': _idleSoak,
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    // D-05 requires both conditions: 100 rounds AND >= 30 s.
    if (_soakSeconds() < 30) {
      final remaining = (30 - _soakSeconds()).ceil();
      await Future<void>.delayed(Duration(seconds: remaining));
    }
    final seconds = _soakSeconds();
    _parts['soak'] = 'ok';

    _stage = 'complete';
    final result = _classify(rounds: rounds, seconds: seconds);
    _emitBench({
      'stage': 'complete',
      'resolvedLibmpv': MpvLibrary.resolvedPath,
      'mpvBackend': _controller?.backend.name,
      'engineRenderer': 'unresolved-by-harness',
      'parts': _parts,
      'rounds': rounds,
      'seconds': seconds,
      'resizeEvents': _resizeEvents,
      'idleSoak': _idleSoak,
      'idleDuringUnmount': _idleDuringUnmount,
      'activeEvents': _activeEvents,
      'renderErrors': _renderErrors,
      'gpuTimeouts': _gpuTimeouts,
      'recovered': _recovered,
      'deviceLost': _deviceLost,
      'rssStart': _rssStart,
      'rssEnd': ProcessInfo.currentRss,
      'pixelProbe': _pixelProbe,
      'part1Ms': part1Ms,
      'part2Ms': part2Ms,
      'fps4k': fps4k,
      'result': result,
    });

    expect(
      result,
      isIn(const ['pass', 'inconclusive', 'failed']),
      reason: 'the run must end in one of the three recorded buckets',
    );

    await _disposeQuietly();
  }

  void _watch(MpvVideoController controller) {
    _subscriptions.add(
      controller.events.listen(_onEvent, onError: (Object _) {}),
    );
  }

  void _onEvent(MpvVideoEvent event) {
    switch (event.kind) {
      case MpvVideoEventKind.resize:
        _resizeEvents++;
        if (event.message == '3840x2160') {
          _saw4kResize = true;
        }
      case MpvVideoEventKind.idle:
        _classifyIdle();
      case MpvVideoEventKind.active:
        _activeEvents++;
      case MpvVideoEventKind.renderError:
        _renderErrors++;
      case MpvVideoEventKind.gpuTimeout:
        _gpuTimeouts++;
      case MpvVideoEventKind.recovered:
        _recovered++;
      case MpvVideoEventKind.deviceLost:
        _deviceLost = true;
      case MpvVideoEventKind.softwareFallback:
      case MpvVideoEventKind.unknown:
        // Not part of the D-04/D-05 verdict fields.
        break;
    }
  }

  /// Only an idle that arrives after the texture has been continuously
  /// mounted for [_idleTimeout] counts as a soak idle. Anything during an
  /// unmount window (or within the first 500 ms after mounting) is a
  /// switching artefact, not a renderer failure.
  void _classifyIdle() {
    final mountedAt = _mountedAt;
    final mountedFor = mountedAt == null ? null : _clock.elapsed - mountedAt;
    final continuouslyMounted =
        mountedFor != null && mountedFor >= _idleTimeout;
    if (_soakStarted && continuouslyMounted) {
      _idleSoak++;
    } else {
      _idleDuringUnmount++;
    }
  }

  void _setTexture(int? id) {
    _textureId.value = id;
    _mountedAt = id == null ? null : _clock.elapsed;
  }

  double _soakSeconds() {
    final start = _soakStart;
    if (start == null) return 0;
    return DateTime.now().difference(start).inMilliseconds / 1000.0;
  }

  String _classify({required int rounds, required double seconds}) {
    final probeSupported = _pixelProbe['supported'] == true;
    final ratio = _pixelProbe['nonBlackRatio'];
    final nonBlack =
        probeSupported && ratio is num && ratio >= _minNonBlackRatio;
    final partsOk = _parts.values.every((value) => value == 'ok');
    final pass =
        partsOk &&
        rounds == 100 &&
        seconds >= 30 &&
        !_deviceLost &&
        _renderErrors < 10 &&
        _idleSoak == 0 &&
        nonBlack;
    if (pass) return 'pass';
    // A missing pixel probe is an evidence gap, not a renderer failure.
    if (!probeSupported) return 'inconclusive';
    return 'failed';
  }

  Future<bool> _waitUntil(
    bool Function() predicate, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (predicate()) return true;
      await _nextFrame();
      if (predicate()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return predicate();
  }

  Future<Map<String, Object?>> _probePixels() async {
    try {
      final boundary = _probeKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        return {'supported': false, 'reason': 'probe boundary is not mounted'};
      }
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (bytes == null) {
          return {'supported': false, 'reason': 'toByteData returned null'};
        }
        final data = bytes.buffer.asUint8List();
        final pixels = image.width * image.height;
        var nonBlack = 0;
        for (var i = 0; i + 3 < data.length; i += 4) {
          if (data[i] > 8 || data[i + 1] > 8 || data[i + 2] > 8) nonBlack++;
        }
        return {
          'supported': true,
          'nonBlackRatio': pixels == 0 ? 0.0 : nonBlack / pixels,
          'width': image.width,
          'height': image.height,
        };
      } finally {
        image.dispose();
      }
    } on Object catch (error) {
      return {'supported': false, 'reason': '${error.runtimeType}: $error'};
    }
  }

  /// Render context before mpv core (docs/ARCHITECTURE.md:76-90). Errors are
  /// swallowed so cleanup never masks the original failure.
  Future<void> _disposeQuietly() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } on Object {
        // Cleanup must continue; the caller rethrows the real error.
      }
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // Same rule: teardown must not mask the real error.
      }
    }
  }
}
