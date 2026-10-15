// MpvVideoController against a fake platform channel (headless libmpv,
// vo=null). Skipped when no libmpv can be loaded (MPV_KIT_LIBMPV_PATH).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_kit_video/mpv_kit_video.dart';

const _channel = MethodChannel('mpv_kit_video');

bool _libmpvAvailable() {
  try {
    MpvLibrary.open();
    return true;
  } on MpvLibraryNotFound {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = _libmpvAvailable() ? null : 'libmpv not available';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  // Assigned in setUp only when libmpv is available; the tests that use it
  // are skipped otherwise.
  late Player player;
  var hasPlayer = false;

  setUp(() {
    if (skip != null) return;
    calls = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
      }
      return null;
    });
    player = Player(options: const {'vo': 'null', 'ao': 'null'});
    hasPlayer = true;
  });

  tearDown(() async {
    if (hasPlayer) await player.dispose();
    hasPlayer = false;
    messenger.setMockMethodCallHandler(_channel, null);
  });

  /// Delivers a native -> Dart "event" call as the plugin would.
  Future<void> nativeEvent(String kind, [String message = '']) =>
      messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(MethodCall('event', {
          'textureId': 7,
          'kind': kind,
          'message': message,
        })),
        (_) {},
      );

  test('create passes renderer and symbols, parses the result', () async {
    final c = await MpvVideoController.create(
      player,
      renderer: MpvVideoRenderer.gpu,
    );
    expect(c.textureId, 7);
    expect(c.backend, MpvVideoBackend.vulkan);
    expect(c.reason, 'vulkan (x)');
    final args = calls.single.arguments as Map;
    expect(args['renderer'], 'gpu');
    expect((args['symbols'] as List).length, 9);
    expect((args['symbols'] as List).every((s) => s is int && s != 0), isTrue);
    // The shader cache directory is configured before creation.
    expect(player.mpv.getProperty('gpu-shader-cache-dir'), isNotEmpty);
  }, skip: skip);

  test('setSize ignores repeats and invalid sizes', () async {
    final c = await MpvVideoController.create(player);
    await c.setSize(640, 360);
    await c.setSize(640, 360);
    await c.setSize(0, 10);
    expect(calls.where((m) => m.method == 'setSize'), hasLength(1));
  }, skip: skip);

  test('native events are routed and deviceLost marks it broken', () async {
    final c = await MpvVideoController.create(player);
    final got = <MpvVideoEvent>[];
    final sub = c.events.listen(got.add);
    await nativeEvent('resize', '640x360');
    await nativeEvent('something_new');
    await nativeEvent('device_lost', 'gone');
    await pumpEventQueue();
    expect(got.map((e) => e.kind), [
      MpvVideoEventKind.resize,
      MpvVideoEventKind.unknown,
      MpvVideoEventKind.deviceLost,
    ]);
    expect(got.first.toString(), 'MpvVideoEvent(resize: 640x360)');
    expect(c.isBroken, isTrue);
    await sub.cancel();
  }, skip: skip);

  test('display refresh rate follows the window but not a user value',
      () async {
    final c = await MpvVideoController.create(player);
    c.syncDisplayRefreshRate(144);
    expect(player.mpv.getProperty('display-fps-override'), 144);
    c.syncDisplayRefreshRate(60);
    expect(player.mpv.getProperty('display-fps-override'), 60);
    player.mpv.setProperty('display-fps-override', 75.0);
    c.syncDisplayRefreshRate(120);
    expect(player.mpv.getProperty('display-fps-override'), 75);
  }, skip: skip);

  test('setIccProfile toggles icc-profile-auto', () async {
    final c = await MpvVideoController.create(player);
    await c.setIccProfile(Uint8List.fromList([1, 2, 3]));
    expect(player.mpv.getProperty('icc-profile-auto'), isTrue);
    await c.setIccProfile(null);
    expect(player.mpv.getProperty('icc-profile-auto'), isFalse);
    expect(calls.where((m) => m.method == 'setIccProfile'), hasLength(2));
  }, skip: skip);

  test('player.dispose disposes the controller exactly once', () async {
    final c = await MpvVideoController.create(player);
    await player.dispose();
    await c.dispose();
    expect(calls.where((m) => m.method == 'dispose'), hasLength(1));
  }, skip: skip);

  testWidgets('MpvVideo shows nothing until the video size is known',
      (tester) async {
    final c = await MpvVideoController.create(player);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MpvVideo(controller: c),
    ));
    expect(find.byType(Texture), findsNothing);
  }, skip: skip != null);

  testWidgets('MpvVideo sizes the texture to the letterboxed video rect',
      (tester) async {
    final c = await tester.runAsync(() => MpvVideoController.create(player));
    await tester.runAsync(() async {
      await player.open('av://lavfi:testsrc=size=320x180:rate=10');
      while (player.videoParams.value?.width == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(width: 400, height: 400, child: MpvVideo(controller: c!)),
      ),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(Texture)), const Size(400, 225));
    // The first size is applied without waiting for the debounce.
    await tester.runAsync(pumpEventQueue);
    final sizes = calls.where((m) => m.method == 'setSize').toList();
    expect(sizes.single.arguments, containsPair('width', 1200));
  }, skip: skip != null);

  test('renderer names round-trip', () {
    for (final r in MpvVideoRenderer.values) {
      expect(MpvVideoRenderer.tryParse(r.wireName), r);
    }
    expect(MpvVideoRenderer.tryParse('vulkan'), isNull);
  });
}
