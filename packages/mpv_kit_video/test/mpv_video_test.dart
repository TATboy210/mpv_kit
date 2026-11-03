// MpvVideo widget lifecycle: a file switch must not unmount the Texture
// (black frame), and a replaced controller must get its own initial size.
// Uses a real Player (headless libmpv, vo=null) and a fake platform channel,
// the same harness as controller_channel_test.dart.

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

/// Waits until [test] holds, bounded so a lost event cannot hang the test.
Future<void> _until(bool Function() test, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available = _libmpvAvailable();
  final skip = available ? null : 'libmpv not available';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Player player;
  late List<MethodCall> calls;
  var textureId = 7;

  setUp(() {
    if (skip != null) return;
    calls = [];
    textureId = 7;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        return {
          'textureId': textureId++,
          'backend': 'vulkan',
          'reason': 'vulkan (gpu-next) on test',
        };
      }
      return null;
    });
    player = Player(options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes'});
  });

  tearDown(() async {
    if (skip == null) {
      await player.dispose();
      messenger.setMockMethodCallHandler(_channel, null);
    }
  });

  Future<void> pumpVideo(WidgetTester tester, MpvVideoController c) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: MpvVideo(controller: c),
          ),
        ),
      ),
    );
  }

  testWidgets('a video that disappears keeps the Texture and its geometry', (
    tester,
  ) async {
    final controller = await MpvVideoController.create(player);
    addTearDown(controller.dispose);
    await pumpVideo(tester, controller);
    await tester.runAsync(() async {
      await player.open('av://lavfi:testsrc2=size=320x180:rate=30:duration=8');
      await _until(
        () => player.videoParams.value?.width == 320,
        '320x180 params',
      );
    });
    // The player property events arrive on the libmpv event thread.
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
    expect(tester.getSize(find.byType(Texture)), const Size(400, 225));

    // stop() makes video-params unavailable: the frame must stay on screen.
    await tester.runAsync(() async {
      player.stop();
      await _until(
        () => player.videoParams.value == null,
        'video-params to become null',
      );
    });
    await tester.pump();
    expect(
      find.byType(Texture),
      findsOneWidget,
      reason: 'the last frame must stay mounted across a file switch',
    );
    expect(tester.getSize(find.byType(Texture)), const Size(400, 225));

    // A new aspect ratio updates the cached geometry.
    await tester.runAsync(() async {
      await player.open('av://lavfi:testsrc2=size=320x240:rate=30:duration=8');
      await _until(
        () =>
            player.videoParams.value?.width == 320 &&
            player.videoParams.value?.height == 240,
        '320x240 params',
      );
    });
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(find.byType(Texture)), const Size(400, 300));
  }, skip: skip != null);

  testWidgets('replacing the controller re-requests the current size', (
    tester,
  ) async {
    final first = await MpvVideoController.create(player);
    addTearDown(first.dispose);
    await tester.runAsync(() async {
      await player.open('av://lavfi:testsrc2=size=320x180:rate=30:duration=8');
      await _until(
        () => player.videoParams.value?.width == 320,
        '320x180 params',
      );
    });
    await pumpVideo(tester, first);
    await tester.pump();
    expect(
      calls.any(
        (c) =>
            c.method == 'setSize' &&
            (c.arguments as Map)['textureId'] == first.textureId,
      ),
      isTrue,
    );

    // Same widget position, different controller: the computed size is
    // identical, so only a didUpdateWidget reset can request it again.
    final second = await MpvVideoController.create(player);
    addTearDown(second.dispose);
    await pumpVideo(tester, second);
    await tester.pump();
    expect(
      calls.any(
        (c) =>
            c.method == 'setSize' &&
            (c.arguments as Map)['textureId'] == second.textureId,
      ),
      isTrue,
      reason: 'the new controller needs its own first setSize',
    );
  }, skip: skip != null);
}
