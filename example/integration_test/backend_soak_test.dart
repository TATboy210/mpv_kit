// Platform-independent resize/dispose soak, one backend per run (VER-04,
// Phase 17).
//
// Why a new soak and not impeller_smoke_test part 3: ROADMAP success
// criterion 4 asks for the SAME soak on d3d11 / vulkan / software (RTX 4060)
// and on opengl (ubuntu), but impeller_smoke_test is `@TestOn('windows')` and
// its D-05 verdict is entangled with part 2's pixel probe (the second
// controller's first frame, an open finding: todo
// 2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front).
// This file therefore copies the rounds of D-05 part 3 step by step and adds
// NO "every round must present a frame" wait, so that open finding cannot leak
// into the soak verdict. Whether the last controller presents is only
// recorded (`lastControllerFrame`).
//
// Step-by-step correspondence with impeller_smoke_test.dart part 3:
//   `_runSoakRounds`  -> `_runRounds`    100 rounds, 250 ms between rounds,
//                                        sizes alternate 1280x720 / 640x360,
//                                        >= 30 s padding as in D-05
//   `_remountCycle`   -> `_remountCycle` unmount, one frame, setSize,
//                                        dispose, create, mount, one frame
//   `_nextFrame`      -> `_nextFrame`    same bounded wait
//   `_classifyIdle`   -> `_onEvent`      an idle after >= 500 ms of continuous
//                                        mount, inside the soak, is idleSoak
//   `_classify`       -> final asserts   rounds == 100, seconds >= 30,
//                                        deviceLost == 0, renderErrors < 10,
//                                        idleSoak == 0
//   Player options and the 1920x1080 lavfi source are D-05's.
// The one intentional difference: mount and unmount go through a Navigator
// (push and pop of a route that holds only the Texture, zero transition time
// so the cadence of a round is unchanged), the route push/pop texture-leak
// scenario of flutter/flutter#154716, instead of D-05's ValueNotifier subtree
// swap.
//
// Environment:
//   MPV_KIT_VIDEO_API=<api>      REQUIRED (d3d11, vulkan, opengl, software).
//       Forces the backend; the first token of every controller's reason must
//       equal it. Unset fails the test.
//   MPV_KIT_SOAK_MEMORY=rss      asserts that the process RSS curve is flat
//       under the pre-registered rule (soak_memory.dart). Unset only records
//       it; any other value fails. On hosted llvmpipe the GL/Vulkan textures
//       live in process memory, so RSS is the memory record there; dedicated
//       GPU memory is sampled outside this test (17-04, vram_verdict.dart).
// The round count is a constant (100) and is deliberately not configurable.
//
// Report lines (printing is the report channel), keys in this order:
//   SOAK-CHECKPOINT {schema, round, utc, rssBytes, controllers, resizeEvents,
//                    renderErrors, deviceLost}    rounds 0, 10, ... 100
//   SOAK {schema, api, reason, rounds, seconds, renderErrors, deviceLost,
//         idleSoak, apiMismatches, rssMiB, rssVerdict, rssLateMiB,
//         lastControllerFrame}
//   HWDEC {...}   first frame, software outcome asserted (HWD-05)
//
// Run with the window visible (a minimised window drives the renderer to its
// idle path). Only one testWidgets per file (a second one hangs the live
// binding, STATE.md).
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';
import 'soak_memory.dart';

/// Fixed number of resize/dispose rounds (D-05); never read from the
/// environment and never shortened (VER-04 prohibition).
const int _soakRounds = 100;

/// A checkpoint is taken at round 0 and after every this many rounds, which
/// yields [soakCheckpointCount] checkpoints for 100 rounds.
const int _checkpointEvery = 10;

/// Minimum soak duration (D-05 requires 100 rounds AND >= 30 s).
const double _minSoakSeconds = 30;

/// Pause between rounds (D-05 `_runSoakRounds`).
const Duration _roundGap = Duration(milliseconds: 250);

/// Matches VideoRenderer::kIdleTimeout: an idle event only counts as a soak
/// idle after the texture has been mounted continuously for this long (the
/// renderer also idles while the texture is off screen).
const Duration _idleTimeout = Duration(milliseconds: 500);

/// Upper bound for a presented frame; generous for software runners.
const Duration _presentTimeout = Duration(seconds: 30);

/// The D-04/D-05 source (1920x1080 raw video, never reaches a decoder).
const _lavfiSource =
    'av://lavfi:testsrc2=size=1920x1080:rate=30:duration=120[out0];'
    'sine=frequency=440:sample_rate=48000:duration=120[out1]';

/// Size of the mounted texture box and of the first controller's target.
const (int, int) _largeSize = (1280, 720);

/// The alternate, smaller target size (D-05).
const (int, int) _smallSize = (640, 360);

const int _bytesPerMiB = 1024 * 1024;

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the harness (same rule as D-05 and texture_probe).
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

/// Waits until a frame has been presented: fps estimate > 0 and time-pos
/// advanced by >= 0.2 s over one 400 ms window (texture_probe `_presented`).
/// Returns false on timeout.
Future<bool> _presented(Player player) async {
  final deadline = DateTime.now().add(_presentTimeout);
  while (DateTime.now().isBefore(deadline)) {
    final fps = player.mpv.tryGetProperty('estimated-vf-fps');
    final before = player.mpv.tryGetProperty('time-pos');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _nextFrame();
    final after = player.mpv.tryGetProperty('time-pos');
    if (fps is num &&
        fps > 0 &&
        before is num &&
        after is num &&
        after - before >= 0.2) {
      return true;
    }
  }
  return false;
}

/// UTC time with millisecond precision (`...T12:00:00.123Z`), the join key
/// between SOAK-CHECKPOINT lines and the 1 s VRAM samples (utc column).
String _utcMillis() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

/// [value] rounded to one decimal, for the human-readable SOAK line.
double _round1(double value) => (value * 10).roundToDouble() / 10;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('backend soak: 100 resize/dispose rounds', (tester) async {
    final api = Platform.environment['MPV_KIT_VIDEO_API'] ?? '';
    if (api.isEmpty) {
      fail(
        'MPV_KIT_VIDEO_API=<api> is required: the soak runs one forced '
        'backend per run',
      );
    }
    final memoryMode = Platform.environment['MPV_KIT_SOAK_MEMORY'] ?? '';
    if (memoryMode.isNotEmpty && memoryMode != 'rss') {
      fail('MPV_KIT_SOAK_MEMORY must be unset or "rss", got "$memoryMode"');
    }
    final harness = _SoakHarness(api: api, assertRss: memoryMode == 'rss');
    // Pumped before runAsync: a tree pumped inside it is not reliably
    // composed.
    await tester.pumpWidget(harness.tree());
    await tester.runAsync(() async {
      try {
        await harness.execute();
      } finally {
        await harness.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// State and steps of one soak run.
final class _SoakHarness {
  _SoakHarness({required this.api, required this.assertRss});

  /// The forced backend (first token of every controller reason).
  final String api;

  /// Whether the RSS plateau is a hard assertion.
  final bool assertRss;

  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  final Stopwatch _clock = Stopwatch()..start();
  final List<StreamSubscription<MpvVideoEvent>> _subscriptions = [];
  final List<int> _rssBytes = [];

  Player? _player;
  MpvVideoController? _controller;
  Route<void>? _route;
  Duration? _mountedAt;
  DateTime? _soakStart;
  bool _soakActive = false;

  int _controllers = 0;
  int _resizeEvents = 0;
  int _renderErrors = 0;
  int _deviceLost = 0;
  int _idleSoak = 0;
  int _apiMismatches = 0;
  int _rounds = 0;

  /// The widget tree: a bare Navigator whose home route is empty. Mounting a
  /// texture pushes a route, unmounting pops it.
  Widget tree() => Directionality(
    textDirection: TextDirection.ltr,
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );

  Future<void> execute() async {
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
    final first = await _create();
    final reason = first.reason;
    expect(
      reasonApi(reason),
      api,
      reason: 'MPV_KIT_VIDEO_API=$api must win; reported "$reason"',
    );

    await player.open(_lavfiSource);
    _mount(first.textureId);
    await first.setSize(_largeSize.$1, _largeSize.$2);
    final presented = await _presented(player);
    expect(
      presented,
      isTrue,
      reason: 'the first frame must be presented within $_presentTimeout',
    );
    // lavfi is raw video and never reaches a decoder, so HWD-05 asks for a
    // printed and asserted software outcome (16-05 decision A).
    final hwdec = await awaitHwdecReport(
      player.mpv.tryGetProperty,
      test: 'backend_soak',
      sample: 'lavfi',
      at: 'first-frame',
      reason: reason,
      requested: hwdecOptionText(player.mpv.tryGetProperty('hwdec')),
    );
    print(hwdec.line);
    expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
    expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);

    _checkpoint(0);
    _soakActive = true;
    _soakStart = DateTime.now();
    await _runRounds();
    // D-05 requires 100 rounds AND >= 30 s.
    if (_soakSeconds() < _minSoakSeconds) {
      final remaining = (_minSoakSeconds - _soakSeconds()).ceil();
      await Future<void>.delayed(Duration(seconds: remaining));
    }
    final seconds = _soakSeconds();
    _soakActive = false;

    // Recorded only (never asserted): the last controller is sized and given
    // a bounded window to present. The soak never required a frame per round.
    await _controller!.setSize(_largeSize.$1, _largeSize.$2);
    final lastFrame = await _presented(player) ? 'presented' : 'not-presented';

    final memory = soakMemoryVerdict([
      for (final bytes in _rssBytes) bytes / _bytesPerMiB,
    ]);
    final lateMiB = memory.lateMiB;
    print(
      'SOAK ${jsonEncode(<String, Object?>{
        'schema': 'soak-1',
        'api': api,
        'reason': reason,
        'rounds': _rounds,
        'seconds': _round1(seconds),
        'renderErrors': _renderErrors,
        'deviceLost': _deviceLost,
        'idleSoak': _idleSoak,
        'apiMismatches': _apiMismatches,
        'rssMiB': [for (final bytes in _rssBytes) _round1(bytes / _bytesPerMiB)],
        'rssVerdict': memory.verdict.name,
        'rssLateMiB': lateMiB == null ? null : _round1(lateMiB),
        'lastControllerFrame': lastFrame,
      })}',
    );

    expect(_rounds, _soakRounds);
    expect(seconds, greaterThanOrEqualTo(_minSoakSeconds));
    expect(_deviceLost, 0, reason: 'no device may be lost during the soak');
    expect(_renderErrors, lessThan(10), reason: 'render errors in the soak');
    expect(_idleSoak, 0, reason: 'idle while the texture stayed mounted');
    expect(
      _apiMismatches,
      0,
      reason: 'every controller must report MPV_KIT_VIDEO_API=$api',
    );
    if (assertRss) {
      expect(
        memory.verdict,
        SoakMemoryVerdict.flat,
        reason: 'MPV_KIT_SOAK_MEMORY=rss: $memory over $_rssBytes bytes',
      );
    }
  }

  /// D-05 `_runSoakRounds`: [_soakRounds] rounds, sizes alternating, a
  /// checkpoint every [_checkpointEvery] rounds, [_roundGap] between rounds.
  Future<void> _runRounds() async {
    for (var i = 0; i < _soakRounds; i++) {
      final round = i + 1;
      await _remountCycle(i.isEven ? _largeSize : _smallSize);
      _rounds = round;
      if (round % _checkpointEvery == 0) _checkpoint(round);
      await Future<void>.delayed(_roundGap);
    }
  }

  /// D-05 `_remountCycle`: unmount, one frame, resize the outgoing controller,
  /// dispose it, create the next, mount it, one frame. The new controller is
  /// not sized (as in D-05); only the outgoing one is.
  Future<void> _remountCycle((int, int) size) async {
    _unmount();
    await _nextFrame();
    await _controller!.setSize(size.$1, size.$2);
    await _controller!.dispose();
    _controller = null;
    final next = await _create();
    _mount(next.textureId);
    await _nextFrame();
  }

  /// Creates a controller on the shared player, watches its events and checks
  /// that the forced api won.
  Future<MpvVideoController> _create() async {
    final controller = _controller = await MpvVideoController.create(_player!);
    _controllers++;
    if (reasonApi(controller.reason) != api) _apiMismatches++;
    _subscriptions.add(
      controller.events.listen(_onEvent, onError: (Object _) {}),
    );
    return controller;
  }

  void _onEvent(MpvVideoEvent event) {
    switch (event.kind) {
      case MpvVideoEventKind.resize:
        _resizeEvents++;
      case MpvVideoEventKind.idle:
        final mountedAt = _mountedAt;
        final mountedFor = mountedAt == null
            ? null
            : _clock.elapsed - mountedAt;
        if (_soakActive && mountedFor != null && mountedFor >= _idleTimeout) {
          _idleSoak++;
        }
      case MpvVideoEventKind.renderError:
        _renderErrors++;
      case MpvVideoEventKind.deviceLost:
        _deviceLost++;
      case MpvVideoEventKind.active:
      case MpvVideoEventKind.gpuTimeout:
      case MpvVideoEventKind.recovered:
      case MpvVideoEventKind.softwareFallback:
      case MpvVideoEventKind.unknown:
        // Not part of the D-05 verdict fields.
        break;
    }
  }

  /// Mounts the texture: pushes a route that holds only the Texture.
  void _mount(int textureId) {
    final route = PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => SizedBox(
        width: _largeSize.$1.toDouble(),
        height: _largeSize.$2.toDouble(),
        child: Texture(textureId: textureId),
      ),
    );
    _route = route;
    _mountedAt = _clock.elapsed;
    unawaited(_navigator.currentState!.push(route));
  }

  /// Unmounts the texture: pops the route pushed by [_mount].
  void _unmount() {
    if (_route == null) return;
    _route = null;
    _mountedAt = null;
    _navigator.currentState!.pop();
  }

  double _soakSeconds() {
    final start = _soakStart;
    if (start == null) return 0;
    return DateTime.now().difference(start).inMilliseconds / 1000.0;
  }

  /// Records and prints one SOAK-CHECKPOINT line.
  void _checkpoint(int round) {
    final rss = ProcessInfo.currentRss;
    _rssBytes.add(rss);
    print(
      'SOAK-CHECKPOINT ${jsonEncode(<String, Object?>{'schema': 'soak-1', 'round': round, 'utc': _utcMillis(), 'rssBytes': rss, 'controllers': _controllers, 'resizeEvents': _resizeEvents, 'renderErrors': _renderErrors, 'deviceLost': _deviceLost})}',
    );
  }

  /// Render context before mpv core (docs/ARCHITECTURE.md:76-90). Errors are
  /// swallowed so cleanup never masks the original failure.
  Future<void> dispose() async {
    _unmount();
    await _nextFrame();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } on Object {
        // Cleanup must continue; the test reports the real error.
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
