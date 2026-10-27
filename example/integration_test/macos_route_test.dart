// macOS route probe (Phase 13, MAC-02): the real plugin on a macOS runner,
// measured through a pixel probe, in the HEAD tree and in the pre-Phase-12
// tree (3a5f450) so the two readings can be compared.
//
// What it proves: which libmpv the app loaded (the hook bundle's
// `@rpath/mpv.2.framework/mpv.2`), which backend and reason the controller
// reports, and what a RepaintBoundary.toImage read of a paused lavfi
// testsrc2 frame (640x360) shows. 13-04 appends the hwdec sections (HWD-04).
//
// How to run: CI runs it in `.github/workflows/macos-route.yml`
// (`route-probe (macos-15)`). Locally on a Mac:
//   cd example && flutter test integration_test/macos_route_test.dart -d macos
//
// Report lines (a label plus one line of JSON, keys in this order):
//   ROUTE-IDENTITY {"tree","libmpv","attempts","backend","reason",
//                   "defaultHwdec"}
//   ROUTE-PIXEL {"tree","read","final","visibility","texture","control",
//                "background","image"}
//   ROUTE-FRAME {"tree","supported","captured","format","width","height",
//                "nonBlackRatio","meanR","meanG","meanB"}
//     (second channel: statistics of the IOSurface frame the plugin handed
//     to Flutter, read through the plugin's diagnostic `debugFrameProbe`;
//     statistics read after the probe is armed may be torn, so they only
//     support a non-black / approximate call)
//
// Configuration goes through --dart-define only (environment variables do
// not reliably reach a sandboxed app):
//   MPV_KIT_ROUTE_TREE      head | pre12 (default head)
//   MPV_KIT_ROUTE_SECTIONS  comma separated section names (default pixel)
//
// ONE Player and ONE controller per process. Phase 12 found that a second
// controller created in the same process may never receive a presented frame
// (todo 2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-
// front). The pixel section therefore runs first, and later sections reuse
// the same session instead of creating their own.
//
// Printing is the report channel (same as real_plugin_test.dart):
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

import 'macos_route_probe.dart';

/// Which tree this run measures; only a label in the report lines.
const _tree = String.fromEnvironment(
  'MPV_KIT_ROUTE_TREE',
  defaultValue: 'head',
);

/// Comma separated section names to run.
const _sections = String.fromEnvironment(
  'MPV_KIT_ROUTE_SECTIONS',
  defaultValue: 'pixel',
);

/// Sections this file knows. 13-04 adds more.
const _knownSections = {'pixel'};

/// Bound for every "wait until X" in the test (no unbounded awaits).
const _readyTimeout = Duration(seconds: 30);

/// Gap between the three pixel reads, so the compositor takes several
/// frames between them and a late first composite shows up in read 3.
const _readGap = Duration(seconds: 1);

/// Number of pixel reads; the last one is the one parity compares.
const _pixelReads = 3;

/// The paused test source: 640x360 so the texture region of the probe tree
/// shows its top-left quarter, identical in both trees.
const _source = 'av://lavfi:testsrc2=size=640x360:rate=30:duration=30';

/// Player options: no `hwdec` override, so [ROUTE-IDENTITY] reports the
/// Player's default list (13-04 uses it for the default-list run).
const _playerOptions = {
  'vo': 'libmpv',
  'keep-open': 'yes',
  'idle': 'yes',
  'terminal': 'no',
  'ao': 'null',
};

/// Waits for the next real frame, bounded so a live binding without a frame
/// source cannot hang the test (same helper as real_plugin_test.dart).
Future<void> _nextFrame() => Future.any<void>([
  WidgetsBinding.instance.endOfFrame,
  Future<void>.delayed(const Duration(milliseconds: 100)),
]);

/// Keeps the compositor pulling frames for [duration].
Future<void> _settleFor(Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await _nextFrame();
  }
}

/// The single Player / controller pair every section shares.
final class _RouteSession {
  const _RouteSession({
    required this.player,
    required this.controller,
    required this.texture,
    required this.boundaryKey,
  });

  final Player player;
  final MpvVideoController controller;

  /// The texture mounted in the probe tree; null shows nothing.
  final ValueNotifier<int?> texture;
  final GlobalKey boundaryKey;
}

/// One toImage read: the three regions plus the image size.
final class _PixelRead {
  const _PixelRead({
    required this.texture,
    required this.control,
    required this.background,
    required this.image,
  });

  const _PixelRead.unsupported(this.image)
    : texture = null,
      control = null,
      background = null;

  final RouteRegionStats? texture;
  final RouteRegionStats? control;
  final RouteRegionStats? background;

  /// `WxH` of the captured image, or `none` when the read failed.
  final String image;

  String get visibility => routeVisibility(
    texture: texture,
    control: control,
    background: background,
  );
}

/// The probe tree: green background, the texture region, the red patch,
/// all inside one RepaintBoundary of the logical probe size. Positioned
/// children avoid the StackFit.expand pitfall of 12-02 (tight constraints
/// stretching non-positioned children to the whole tree).
Widget _probeTree(GlobalKey key, ValueNotifier<int?> texture) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: routeProbeSize.width,
      height: routeProbeSize.height,
      child: RepaintBoundary(
        key: key,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: routeProbeBackground),
            ),
            Positioned.fromRect(
              rect: routeTextureRegion,
              child: ValueListenableBuilder<int?>(
                valueListenable: texture,
                builder: (context, id, child) => id == null
                    ? const SizedBox.shrink()
                    : Texture(textureId: id),
              ),
            ),
            Positioned.fromRect(
              rect: routeControlRegion,
              child: const ColoredBox(color: routeProbeControl),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Reads the probe boundary through RenderRepaintBoundary.toImage (the
/// channel 12-02 used) and computes the three region statistics. Any failure
/// yields an unsupported read, which classifies as `indeterminate`.
Future<_PixelRead> _readPixels(GlobalKey key) async {
  try {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return const _PixelRead.unsupported('none');
    }
    final logical = boundary.size;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return const _PixelRead.unsupported('none');
      // Same view slicing as 12-02 (the ByteData may be an offset view).
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (data.length < image.width * image.height * 4) {
        return const _PixelRead.unsupported('none');
      }
      final sx = image.width / logical.width;
      final sy = image.height / logical.height;
      RouteRegionStats? stats(ui.Rect region) => routeRegionStats(
        data,
        width: image.width,
        height: image.height,
        region: region,
        sx: sx,
        sy: sy,
      );
      return _PixelRead(
        texture: stats(routeTextureRegion),
        control: stats(routeControlRegion),
        background: stats(routeBackgroundRegion),
        image: '${image.width}x${image.height}',
      );
    } finally {
      image.dispose();
    }
  } on Object catch (error) {
    // A failed read is data: it prints as indeterminate with image=none.
    print('ROUTE-NOTE toImage read failed: ${error.runtimeType}: $error');
    return const _PixelRead.unsupported('none');
  }
}

/// Prints the ROUTE-IDENTITY line for [session].
void _printIdentity(_RouteSession session) {
  final controller = session.controller;
  print(
    'ROUTE-IDENTITY ${jsonEncode({'tree': _tree, 'libmpv': MpvLibrary.resolvedPath, 'attempts': MpvLibrary.lastOpenAttempts, 'backend': controller.backend.name, 'reason': controller.reason, 'defaultHwdec': session.player.mpv.tryGetProperty('hwdec')})}',
  );
}

/// The plugin's method channel; only the diagnostic method is used here.
const _channel = MethodChannel('mpv_kit_video');

/// Calls the plugin's `debugFrameProbe`. A missing method means the plugin of
/// this tree has no frame probe: the line is printed (supported=false) and
/// the test fails, because both trees must offer the second channel (HEAD
/// carries it, the pre-Phase-12 tree gets tools/macos_frame_probe.patch).
Future<Map<String, Object?>?> _frameProbe(
  _RouteSession session, {
  required bool arm,
}) async {
  try {
    return await _channel.invokeMapMethod<String, Object?>('debugFrameProbe', {
      'textureId': session.controller.textureId,
      'arm': arm,
    });
  } on MissingPluginException {
    print('ROUTE-FRAME ${jsonEncode(_frameRecord(methodMissing: true))}');
    fail('debugFrameProbe is not implemented by the plugin of tree "$_tree"');
  }
}

/// Rounds doubles to 4 decimals so the printed lines stay short.
Object? _roundStat(Object? value) =>
    value is double ? double.parse(value.toStringAsFixed(4)) : value;

/// The ROUTE-FRAME record. `captured` means the plugin had kept a frame and
/// could read it; `supported` is false when the method is missing or the
/// kept frame has a pixel format the probe does not read.
Map<String, Object?> _frameRecord({
  Map<String, Object?>? stats,
  bool methodMissing = false,
}) {
  final supported =
      !methodMissing && (stats == null || stats['supported'] == true);
  final captured = supported && stats != null;
  Object? field(String key) => captured ? _roundStat(stats[key]) : null;
  return {
    'tree': _tree,
    'supported': supported,
    'captured': captured,
    'format': field('format'),
    'width': field('width'),
    'height': field('height'),
    'nonBlackRatio': field('nonBlackRatio'),
    'meanR': field('meanR'),
    'meanG': field('meanG'),
    'meanB': field('meanB'),
  };
}

/// Pixel section: opens the paused source, waits until the decoder and the
/// renderer agree on 640x360, then reads the probe tree [_pixelReads] times,
/// [_readGap] apart, printing one ROUTE-PIXEL line per read.
Future<void> _pixelSection(_RouteSession session) async {
  final controller = session.controller;
  final player = session.player;
  // Arm the second channel before the texture is mounted, so the plugin
  // keeps the first frame the compositor takes and every one after it.
  await _frameProbe(session, arm: true);
  session.texture.value = controller.textureId;
  await _nextFrame();

  // Listen before requesting the size so the event cannot be missed. The
  // future resolves to false on timeout or stream end instead of throwing,
  // so an unawaited failure cannot surface as an unhandled async error.
  final resized = controller.events
      .any((e) => e.kind == MpvVideoEventKind.resize && e.message == '640x360')
      .timeout(_readyTimeout, onTimeout: () => false);
  await controller.setSize(
    routeProbeSize.width.toInt(),
    routeProbeSize.height.toInt(),
  );
  // Per-file hwdec option: software decode, and the Player's global hwdec
  // stays untouched for the sections that follow.
  await player.open(_source, play: false, options: {'hwdec': 'no'});

  var paramsReady = false;
  final deadline = DateTime.now().add(_readyTimeout);
  while (DateTime.now().isBefore(deadline) && !paramsReady) {
    await _nextFrame();
    final vp = player.videoParams.value;
    paramsReady = vp?.width == 640 && vp?.height == 360;
  }
  expect(
    paramsReady,
    isTrue,
    reason: 'the decoder did not report 640x360 within $_readyTimeout',
  );
  expect(
    await resized,
    isTrue,
    reason: 'no resize event "640x360" within $_readyTimeout',
  );

  _PixelRead? last;
  for (var read = 1; read <= _pixelReads; read++) {
    await _settleFor(_readGap);
    final result = await _readPixels(session.boundaryKey);
    last = result;
    print(
      'ROUTE-PIXEL ${jsonEncode({'tree': _tree, 'read': read, 'final': read == _pixelReads, 'visibility': result.visibility, 'texture': result.texture?.toJson(), 'control': result.control?.toJson(), 'background': result.background?.toJson(), 'image': result.image})}',
    );
  }
  // Second channel: statistics of the frame the compositor holds now. They
  // may be torn (armed reads are approximate), so the verdict script only
  // uses robust non-black bounds.
  final stats = await _frameProbe(session, arm: false);
  print('ROUTE-FRAME ${jsonEncode(_frameRecord(stats: stats))}');
  // A control or background that is not visible means the probe channel
  // itself failed; that must never pass as a measurement.
  expect(
    last?.visibility,
    isNot('indeterminate'),
    reason: 'control patch or background not visible in the probe image',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('macOS route probe', (tester) async {
    if (_tree != 'head' && _tree != 'pre12') {
      fail('MPV_KIT_ROUTE_TREE must be head or pre12, got "$_tree"');
    }
    final sections = _sections.split(',').map((s) => s.trim()).toSet();
    final unknown = sections.difference(_knownSections);
    if (unknown.isNotEmpty || sections.isEmpty) {
      fail('unknown MPV_KIT_ROUTE_SECTIONS "$_sections": $unknown');
    }

    // Pumped before runAsync: a tree pumped inside it is not reliably
    // composed (same note as real_plugin_test.dart).
    final texture = ValueNotifier<int?>(null);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(_probeTree(boundaryKey, texture));

    await tester.runAsync(() async {
      final player = Player(options: _playerOptions);
      MpvVideoController? controller;
      try {
        controller = await MpvVideoController.create(player);
        final session = _RouteSession(
          player: player,
          controller: controller,
          texture: texture,
          boundaryKey: boundaryKey,
        );
        _printIdentity(session);
        expect(
          MpvLibrary.resolvedPath,
          routeBundleLibrary,
          reason:
              'the probe must measure the hook bundle libmpv; attempts: '
              '${MpvLibrary.lastOpenAttempts}',
        );
        if (sections.contains('pixel')) await _pixelSection(session);
      } finally {
        // One teardown for every section: unmount, let the compositor drop
        // the texture, then controller before player (dispose-order rule).
        texture.value = null;
        await _nextFrame();
        await controller?.dispose();
        await player.dispose();
      }
    });
  }, skip: !Platform.isMacOS);
}
