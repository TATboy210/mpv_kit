// Mounted-texture pixel and orientation probe (GLX-03, Phase 15 spike).
//
// Real plugin, no method-channel mocks. Runs on CI via native-verify.yml's
// integration-test job (linux step "Texture probe (linux)", under xvfb) and
// locally via
//   flutter test integration_test/texture_probe_test.dart -d linux
// with MPV_KIT_LIBMPV_PATH set (see README "Local libmpv for tests").
//
// What it does: mounts the controller's texture inside a RepaintBoundary,
// plays a red-over-blue 640x360 lavfi source, waits until a frame has really
// been presented (same rule as impeller_smoke_modes `_firstFrameGate`: fps > 0
// and time-pos advancing), then reads the boundary back with toImage. It does
// this twice, before and after a resize to 320x180.
//
// Report channel: one `PROBE {json}` line (printing is intended). Keys, in
// order: api, reason, supported, nonBlackRatio, orientation,
// afterResizeNonBlackRatio, afterResizeOrientation, textureId, renderErrors,
// events.
//
// A second controller is then created on the same player and must report the
// same api as the first: one `SECOND-CONTROLLER {json}` line (first, second,
// secondReason).
//
// Assertions (15-05): video params arrive, the presentation gate passes
// within 30 s, no device is lost, there is no render error, the textureId does
// not change across the resize, and BOTH reads are supported and non-black
// (nonBlackRatio >= 0.01, the threshold of Phase 12). When the winning api is
// opengl, both reads must also be `upright`. A black or unsupported read is
// never counted as a rendered frame.
//
// Why the pixel assertions are on: evidence/spike-flutter-linux.txt has
// D-PROBE=unknown (its control ran on software), but the first run of this
// probe on the OpenGL path (evidence/backend-runs.txt, native-verify run
// 40647806493) read supported=true, nonBlackRatio=1.0, upright, before and
// after the resize, so toImage does see the external texture on Linux.
// Orientation of the Vulkan path (D-ORIENT is unknown) is only reported, not
// asserted: a flipped Vulkan texture would be an existing defect outside
// Phase 15. Everything here ran on Mesa llvmpipe only; other drivers are
// unverified.
//
// Forced backend matrix (VER-02, Phase 17): tools/backend_matrix.sh runs this
// file once per cell on every platform, with two optional variables:
//   MPV_KIT_VIDEO_API=<api>            forces one backend (no fallback). In
//       the default `render` mode the winner's reason must start with that
//       api, on top of every assertion above.
//   MPV_KIT_EXPECT_BACKEND=render|unavailable   (default render)
//       `unavailable` is for a cell whose backend does not exist on the
//       runner (hosted Windows has only WARP, no Vulkan device the
//       compositor can share). It requires MPV_KIT_VIDEO_API and asserts that
//       create throws `render_init` with a real reason: the forced api's own
//       trail names why it failed (never `excluded`), and every other
//       candidate is only `excluded by MPV_KIT_VIDEO_API=<api>`. It prints
//       `PROBE-UNAVAILABLE {"api","reason"}` and never counts as a rendered
//       frame. A create that succeeds there fails the test: the runner
//       changed, and the cell table is the user's to update.
//
// Only one testWidgets per file: a second one in the same file hangs the
// live binding (STATE.md).
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'hwdec_probe.dart';

/// Upper bound for the renderer to report a requested size.
const _resizeTimeout = Duration(seconds: 5);

/// Upper bound for the first presented frame, generous for a software runner.
const _presentTimeout = Duration(seconds: 30);

/// A component above this counts as non-black (same threshold as
/// impeller_smoke_test `_probePixels`).
const _blackThreshold = 8;

/// Minimum share of non-black pixels for a read to count as a rendered frame
/// (same 0.01 as Phase 12's probes; evidence/backend-runs.txt shows 1.0).
const _minNonBlackRatio = 0.01;

/// A source colour channel must exceed the other by this factor, and this
/// absolute floor, to be called red or blue (tolerates colour conversion and
/// scaling at the edges of the quarter bands).
const _dominanceFactor = 2;
const _dominanceFloor = 100;

/// Red-over-blue 640x360 source: two 640x180 `color` sources stacked. The
/// `[out0]` label is how mpv's lavfi demuxer names the video output.
const _source =
    'av://lavfi:color=c=red:s=640x180:r=30:d=60[a];'
    'color=c=blue:s=640x180:r=30:d=60[b];'
    '[a][b]vstack[out0]';

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the test.
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

/// Asks [controller] for [width]x[height] and waits for its resize event.
/// The listener is attached before the request, so the event cannot be
/// missed.
Future<void> _resizeTo(
  MpvVideoController controller,
  int width,
  int height,
) async {
  final resized = controller.events
      .firstWhere(
        (e) =>
            e.kind == MpvVideoEventKind.resize &&
            e.message == '${width}x$height',
      )
      .timeout(_resizeTimeout);
  await controller.setSize(width, height);
  await resized;
}

/// Waits until a frame has been presented: fps estimate > 0 and time-pos
/// advanced by >= 0.2 s over one 400 ms window. Returns false on timeout.
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

/// Mean RGB of rows [from, to) of a [width]-wide RGBA buffer.
List<double> _meanRgb(List<int> data, int width, int from, int to) {
  var r = 0, g = 0, b = 0;
  final count = (to - from) * width;
  for (var y = from; y < to; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      r += data[i];
      g += data[i + 1];
      b += data[i + 2];
    }
  }
  if (count == 0) return const [0, 0, 0];
  return [r / count, g / count, b / count];
}

bool _isRed(List<double> c) =>
    c[0] > _dominanceFactor * c[2] && c[0] > _dominanceFloor;
bool _isBlue(List<double> c) =>
    c[2] > _dominanceFactor * c[0] && c[2] > _dominanceFloor;

/// Reads [key]'s boundary back: {supported, nonBlackRatio, orientation} or
/// {supported: false, reason}. Orientation compares the top and bottom
/// quarters of the image: red over blue is `upright`, blue over red
/// `flipped`, anything else `unknown`.
Future<Map<String, Object?>> _read(GlobalKey key) async {
  try {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return {'supported': false, 'reason': 'probe boundary is not mounted'};
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) {
        return {'supported': false, 'reason': 'toByteData returned null'};
      }
      // `bytes.buffer` is the whole backing buffer: honour the view's
      // offset and length so unrelated memory is never read as pixels.
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final w = image.width;
      final h = image.height;
      if (data.length < w * h * 4) {
        return {
          'supported': false,
          'reason': 'short pixel buffer: ${data.length} < ${w * h * 4}',
        };
      }
      var nonBlack = 0;
      for (var i = 0; i + 3 < w * h * 4; i += 4) {
        if (data[i] > _blackThreshold ||
            data[i + 1] > _blackThreshold ||
            data[i + 2] > _blackThreshold) {
          nonBlack++;
        }
      }
      final quarter = h ~/ 4;
      final top = _meanRgb(data, w, 0, quarter);
      final bottom = _meanRgb(data, w, h - quarter, h);
      final orientation = _isRed(top) && _isBlue(bottom)
          ? 'upright'
          : _isBlue(top) && _isRed(bottom)
          ? 'flipped'
          : 'unknown';
      return {
        'supported': true,
        'nonBlackRatio': w * h == 0 ? 0.0 : nonBlack / (w * h),
        'orientation': orientation,
      };
    } finally {
      image.dispose();
    }
  } on Object catch (e) {
    // toImage may be unimplemented for external textures on a platform; that
    // is the finding, not a test failure.
    return {'supported': false, 'reason': 'toImage failed: $e'};
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('texture probe: mounted pixels and orientation', (tester) async {
    // VER-02 cell selection; see the file header.
    final forcedApi = Platform.environment['MPV_KIT_VIDEO_API'] ?? '';
    final expectMode = Platform.environment['MPV_KIT_EXPECT_BACKEND'] ?? '';
    final expectUnavailable = _expectsUnavailable(expectMode, forcedApi);
    final texture = ValueNotifier<int?>(null);
    final probeKey = GlobalKey();
    // Pumped before runAsync: a tree pumped inside it is not reliably
    // composed.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int?>(
          valueListenable: texture,
          builder: (context, id, child) => RepaintBoundary(
            key: probeKey,
            child: SizedBox(
              width: 640,
              height: 360,
              child: id == null ? null : Texture(textureId: id),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final events = <MpvVideoEventKind>[];
      final player = Player(
        options: const {
          'vo': 'libmpv',
          // Hosted runners have validation-layer rules that make hardware
          // decode unreliable; the probe is about presentation, not decode.
          'hwdec': 'no',
          'keep-open': 'yes',
          'idle': 'yes',
          'terminal': 'no',
          'ao': 'null',
        },
      );
      if (expectUnavailable) {
        // The forced backend does not exist on this runner: assert why and
        // stop. No pixel section, so this can never count as a rendered cell.
        await _expectUnavailable(player, forcedApi);
        await player.dispose();
        return;
      }
      final controller = await MpvVideoController.create(player);
      final sub = controller.events.listen(
        (e) => events.add(e.kind),
        onError: (Object _) {},
      );

      // Size first, then mount: the texture shows a front from the start.
      await _resizeTo(controller, 640, 360);
      texture.value = controller.textureId;
      await _nextFrame();

      await player.open(_source);
      final paramsReady = await _waitForParams(player, 640, 360);
      expect(
        paramsReady,
        isTrue,
        reason: 'the decoder must report the requested video size',
      );
      final presented = await _presented(player);
      expect(
        presented,
        isTrue,
        reason: 'a frame must be presented within $_presentTimeout',
      );
      // lavfi is raw video and never reaches a decoder, so HWD-05 asks for a
      // printed and asserted software outcome (16-05 decision A).
      final hwdec = await awaitHwdecReport(
        player.mpv.tryGetProperty,
        test: 'texture_probe',
        sample: 'lavfi',
        at: 'first-frame',
        reason: controller.reason,
        requested: 'no',
      );
      print(hwdec.line);
      expect(hwdec.outcome, HwdecOutcome.software, reason: hwdec.line);
      expect(hwdec.zeroCopy, isFalse, reason: hwdec.line);
      final first = await _read(probeKey);
      final textureBeforeResize = controller.textureId;

      await _resizeTo(controller, 320, 180);
      final presentedAfter = await _presented(player);
      expect(
        presentedAfter,
        isTrue,
        reason: 'frames must keep flowing after the resize',
      );
      final second = await _read(probeKey);

      final reason = controller.reason;
      final report = <String, Object?>{
        'api': reason.split(' ').first,
        'reason': reason,
        'supported': first['supported'],
        if (first['supported'] != true) 'unsupportedReason': first['reason'],
        'nonBlackRatio': first['nonBlackRatio'],
        'orientation': first['orientation'],
        'afterResizeNonBlackRatio': second['nonBlackRatio'],
        'afterResizeOrientation': second['orientation'],
        'textureId': controller.textureId,
        'renderErrors': events
            .where((k) => k == MpvVideoEventKind.renderError)
            .length,
        'events': events.map((k) => k.name).toSet().toList()..sort(),
      };
      print('PROBE ${jsonEncode(report)}');

      texture.value = null;
      await _nextFrame();
      await controller.dispose();

      // A second controller on the same player must get the same backend as
      // the first. evidence/spike-flutter-linux.txt D-THREAD: the Linux
      // interop probe used to fail on the platform thread in later
      // controllers (EGL_BAD_ACCESS), silently dropping them off the
      // backend the first one had; this guards that defect (15-06).
      final secondController = await MpvVideoController.create(player);
      final secondReason = secondController.reason;
      final secondApi = secondReason.split(' ').first;
      print(
        'SECOND-CONTROLLER ${jsonEncode({'first': report['api'], 'second': secondApi, 'secondReason': secondReason})}',
      );
      await secondController.dispose();
      await player.dispose();
      await sub.cancel();
      expect(
        secondApi,
        report['api'],
        reason:
            'the second controller must report the backend of the first: '
            'first "$reason", second "$secondReason"',
      );
      if (forcedApi.isNotEmpty) {
        // VER-02: a forced run must be won by exactly that backend (the
        // first token of the reason is the real graphics API).
        expect(
          report['api'],
          forcedApi,
          reason:
              'MPV_KIT_VIDEO_API=$forcedApi must win; the controller '
              'reported "$reason"',
        );
      }
      expect(events, isNot(contains(MpvVideoEventKind.deviceLost)));
      expect(
        events,
        isNot(contains(MpvVideoEventKind.renderError)),
        reason: 'no render error while probing',
      );
      expect(
        controller.textureId,
        textureBeforeResize,
        reason: 'a resize must not replace the texture',
      );
      for (final read in [first, second]) {
        expect(
          read['supported'],
          isTrue,
          reason: 'toImage must see the texture: ${read['reason']}',
        );
        final ratio = read['nonBlackRatio'];
        expect(
          ratio is num && ratio >= _minNonBlackRatio,
          isTrue,
          reason: 'the mounted texture must not be black (got $ratio)',
        );
        if (report['api'] == 'opengl') {
          expect(
            read['orientation'],
            'upright',
            reason:
                'FLIP_Y 0 (spike-gl D-FLIP-MPV, D-FLUTTER-ORIGIN '
                'top-left) must show red over blue',
          );
        }
      }
    });
  });
}

/// Parses MPV_KIT_EXPECT_BACKEND: true for `unavailable`, false for `render`
/// (also the default when unset). Anything else, or `unavailable` without a
/// forced api, is a usage error and fails at once.
bool _expectsUnavailable(String mode, String forcedApi) {
  if (mode.isEmpty || mode == 'render') return false;
  if (mode != 'unavailable') {
    fail(
      'MPV_KIT_EXPECT_BACKEND must be "render" or "unavailable", got "$mode"',
    );
  }
  if (forcedApi.isEmpty) {
    fail('MPV_KIT_EXPECT_BACKEND=unavailable needs MPV_KIT_VIDEO_API=<api>');
  }
  return true;
}

/// One trail of the reason grammar starts a new item at `; ` followed by
/// `<api>/<renderer> unavailable: `; a why that itself contains `; ` is not
/// split.
final _trailBoundary = RegExp(r'; (?=[a-z0-9-]+/[a-z-]+ unavailable: )');

/// The unavailable cell (VER-02): creating a controller with [api] forced
/// must fail with `render_init` and a reason that explains the forced api's
/// failure. Every candidate of another api is only
/// `excluded by MPV_KIT_VIDEO_API=<api>` (a forced run never falls back), so
/// a reason without a real failure of [api] itself would be a vacuous pass.
/// Prints `PROBE-UNAVAILABLE {"api","reason"}`.
Future<void> _expectUnavailable(Player player, String api) async {
  MpvVideoController controller;
  try {
    controller = await MpvVideoController.create(player);
  } on PlatformException catch (e) {
    expect(e.code, 'render_init', reason: 'create failed with ${e.code}');
    final details = e.details;
    expect(details, isA<String>(), reason: 'details: $details');
    final reason = details! as String;
    print('PROBE-UNAVAILABLE ${jsonEncode({'api': api, 'reason': reason})}');
    // No head: a winner would read `<api> (<renderer>) on <device>`.
    expect(
      RegExp(r'^[a-z0-9-]+ \(').hasMatch(reason),
      isFalse,
      reason: 'a forced-unavailable reason has no head: $reason',
    );
    final own = '$api/gpu-next unavailable: ';
    final at = reason.indexOf(own);
    expect(
      at,
      greaterThanOrEqualTo(0),
      reason: 'the forced api must report its own failure: $reason',
    );
    expect(
      reason.substring(at + own.length),
      isNot(startsWith('excluded')),
      reason: 'the forced api itself must not be excluded: $reason',
    );
    for (final trail in reason.split(_trailBoundary)) {
      if (trail.startsWith('$api/')) continue;
      expect(
        trail.endsWith('unavailable: excluded by MPV_KIT_VIDEO_API=$api'),
        isTrue,
        reason: 'every other candidate is only excluded: "$trail" in $reason',
      );
    }
    return;
  }
  final reason = controller.reason;
  await controller.dispose();
  fail(
    'MPV_KIT_VIDEO_API=$api was expected to be unavailable on this runner but '
    'created a controller ("$reason"); update the matrix cell table in '
    'tools/backend_matrix.sh',
  );
}

/// Waits (bounded) until the decoder reports [width]x[height].
Future<bool> _waitForParams(Player player, int width, int height) async {
  final deadline = DateTime.now().add(_presentTimeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final vp = player.videoParams.value;
    if (vp?.width == width && vp?.height == height) return true;
  }
  return false;
}
