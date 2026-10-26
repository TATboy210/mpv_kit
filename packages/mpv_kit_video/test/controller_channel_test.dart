// MpvVideoController against a fake platform channel (headless libmpv,
// vo=null). Skipped when no libmpv can be loaded (MPV_KIT_LIBMPV_PATH) —
// unless MPV_KIT_REQUIRE_LIBMPV is set (CI): a missing library is then a
// failure, never a silent skip.
import 'dart:async';
import 'dart:io';

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
  final available = _libmpvAvailable();
  if (!available && Platform.environment['MPV_KIT_REQUIRE_LIBMPV'] != null) {
    fail('libmpv is required by CI (MPV_KIT_REQUIRE_LIBMPV) but could not '
        'be loaded — set MPV_KIT_LIBMPV_PATH (see README)');
  }
  final skip = available ? null : 'libmpv not available';
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
    // create 加上初始的 getDisplayRefreshRate 探测,按方法名过滤。
    final args =
        calls.firstWhere((c) => c.method == 'create').arguments as Map;
    expect(args['renderer'], 'gpu');
    expect((args['symbols'] as List).length, 9);
    expect((args['symbols'] as List).every((s) => s is int && s != 0), isTrue);
    // The shader cache directory is configured before creation.
    expect(player.mpv.getProperty('gpu-shader-cache-dir'), isNotEmpty);
  }, skip: skip);

  test('malformed create result throws PlatformException and releases the texture',
      () async {
    final shapes = <Map<String, Object?>>[
      {'backend': 'vulkan', 'reason': 'x'},
      {'textureId': 'x', 'backend': 'vulkan', 'reason': 'x'},
      {'textureId': 7, 'backend': 'garbage', 'reason': 'x'},
      {'textureId': 7, 'backend': 'vulkan', 'reason': 5},
    ];
    for (final shape in shapes) {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'create') return shape;
        return null;
      });
      await expectLater(
        MpvVideoController.create(player),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code',
            'render_init')),
      );
    }
    // Only the shapes carrying an int textureId can release the native
    // context; the wrong-typed-textureId shapes cannot name it.
    expect(calls.where((m) => m.method == 'dispose'), hasLength(2));
  }, skip: skip);

  test('malformed create result without textureId cannot release native resources',
      () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'create') return {'backend': 'vulkan', 'reason': 'x'};
      return null;
    });
    await expectLater(MpvVideoController.create(player),
        throwsA(isA<PlatformException>()));
    expect(calls.where((m) => m.method == 'dispose'), isEmpty);
    // Nothing was registered, so player disposal adds no controller teardown.
    await player.dispose();
    expect(calls.where((m) => m.method == 'dispose'), isEmpty);
  }, skip: skip);

  test('create rolls back when the player dies mid-create, retry succeeds',
      () async {
    // Hold the create response until the player core is gone, so the later
    // create steps (initial refresh-rate sync) hit a disposed mpv.
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          await gate.future;
          return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
        case 'getDisplayRefreshRate':
          return 60.0;
        default:
          return null;
      }
    });
    final createFuture = MpvVideoController.create(player);
    await player.dispose();
    gate.complete();
    await expectLater(createFuture, throwsA(isA<StateError>()));
    expect(calls.where((m) => m.method == 'dispose'), hasLength(1));
    // A retry on a live player succeeds and leaves exactly one live hook.
    final player2 = Player(options: const {'vo': 'null', 'ao': 'null'});
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        return {'textureId': 8, 'backend': 'vulkan', 'reason': 'vulkan (y)'};
      }
      return null;
    });
    try {
      final c = await MpvVideoController.create(player2);
      expect(c.textureId, 8);
      final disposedBefore = calls.where((m) => m.method == 'dispose').length;
      await player2.dispose();
      expect(
          calls.where((m) => m.method == 'dispose').length, disposedBefore + 1);
    } finally {
      if (!player2.mpv.isDisposed) await player2.dispose();
    }
  }, skip: skip);

  test('setSize ignores repeats and invalid sizes', () async {
    final c = await MpvVideoController.create(player);
    await c.setSize(640, 360);
    await c.setSize(640, 360);
    await c.setSize(0, 10);
    expect(calls.where((m) => m.method == 'setSize'), hasLength(1));
  }, skip: skip);

  test('dispose closes events even when the native call throws', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'dispose') {
        throw PlatformException(code: 'render_init', message: 'gone');
      }
      if (call.method == 'create') {
        return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
      }
      return null;
    });
    final c = await MpvVideoController.create(player);
    final done = Completer<void>();
    c.events.listen((_) {}, onDone: done.complete);
    await expectLater(c.dispose(), throwsA(isA<PlatformException>()));
    await done.future.timeout(const Duration(seconds: 5));
    await c.dispose();
  }, skip: skip);

  test('resize during dispose does not surface an uncaught error', () async {
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'setSize') {
        await gate.future;
        throw PlatformException(code: 'no_texture', message: 'gone');
      }
      if (call.method == 'create') {
        return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
      }
      return null;
    });
    final c = await MpvVideoController.create(player);
    // MpvVideo issues resize through unawaited(...), so a post-dispose
    // failure must be dropped by the controller, not reach the zone.
    unawaited(c.setSize(640, 360));
    await c.dispose();
    gate.complete();
    await pumpEventQueue();
  }, skip: skip);

  test('resize failure on a live controller still throws', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'setSize') {
        throw PlatformException(code: 'no_texture', message: 'unknown');
      }
      if (call.method == 'create') {
        return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
      }
      return null;
    });
    final c = await MpvVideoController.create(player);
    await expectLater(c.setSize(640, 360), throwsA(isA<PlatformException>()));
    await c.dispose();
  }, skip: skip);

  test('resize and dispose interleave 100 rounds without sticking', () async {
    // Hold every setSize in flight until the round ends, so dispose always
    // races a pending resize like MpvVideo's debounced requests do.
    final gates = <Completer<void>>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
        case 'setSize':
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          return null;
        default:
          return null;
      }
    });
    for (var round = 0; round < 100; round++) {
      final c = await MpvVideoController.create(player);
      final done = Completer<void>();
      c.events.listen((e) {
        // Every 10th round disposes re-entrantly from inside the listener.
        if (round % 10 == 0) unawaited(c.dispose());
      }, onDone: done.complete);
      unawaited(c.setSize(640, 360));
      if (round % 10 != 0) {
        await c.dispose();
      } else {
        await nativeEvent('resize', '1x1');
        await pumpEventQueue();
      }
      await done.future.timeout(const Duration(seconds: 5));
      // A controller recreated in the same texture id routes events and
      // accepts new sizes — no stuck state left behind.
      final fresh = await MpvVideoController.create(player);
      final freshGot = <MpvVideoEventKind>[];
      final freshSub = fresh.events.listen((e) => freshGot.add(e.kind));
      await nativeEvent('resize', '1x1');
      await pumpEventQueue();
      expect(freshGot, contains(MpvVideoEventKind.resize));
      await freshSub.cancel();
      await fresh.dispose();
      for (final gate in List.of(gates)) {
        if (!gate.isCompleted) gate.complete();
      }
      gates.clear();
      await pumpEventQueue();
    }
    // Restore an ungated mock: the final controller must respond to sizes
    // immediately (the gated handler above is only for the in-flight rounds).
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        return {'textureId': 7, 'backend': 'vulkan', 'reason': 'vulkan (x)'};
      }
      return null;
    });
    final last = await MpvVideoController.create(player);
    await last.setSize(2, 2);
    await last.setSize(3, 3);
    expect(
      calls.where((m) => m.method == 'setSize').map(
            (m) => (m.arguments as Map)['width'],
          ),
      containsAll([2, 3]),
    );
    await last.dispose();
  }, skip: skip);

  test('create/dispose cycles do not accumulate hooks', () async {
    for (var i = 0; i < 100; i++) {
      final c = await MpvVideoController.create(player);
      final done = Completer<void>();
      c.events.listen((_) {}, onDone: done.complete);
      await c.dispose();
      await done.future.timeout(const Duration(seconds: 5));
    }
    final disposeCount = calls.where((m) => m.method == 'dispose').length;
    expect(disposeCount, 100);
    // A create still works while the player is alive.
    final last = await MpvVideoController.create(player);
    final lastDone = Completer<void>();
    last.events.listen((_) {}, onDone: lastDone.complete);
    await last.dispose();
    await lastDone.future.timeout(const Duration(seconds: 5));
    final total = calls.where((m) => m.method == 'dispose').length;
    expect(total, 101);
    // No leaked hooks: player disposal adds no controller teardown calls.
    await player.dispose();
    expect(calls.where((m) => m.method == 'dispose').length, total);
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

  test('create maps every private GPU wire name to MpvVideoBackend.vulkan',
      () async {
    // ADR 0004: d3d11/opengl/vulkan are private wire names of the GPU
    // zero-copy backend; the real API stays visible as reason's first token.
    for (final name in const ['d3d11', 'opengl', 'vulkan']) {
      final reason = '$name (gpu-next) on test';
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'create') {
          return {'textureId': 7, 'backend': name, 'reason': reason};
        }
        return null;
      });
      final c = await MpvVideoController.create(player);
      final got = <MpvVideoEventKind>[];
      final sub = c.events.listen((e) => got.add(e.kind));
      await nativeEvent('resize', '1x1');
      await pumpEventQueue();
      expect(c.backend, MpvVideoBackend.vulkan, reason: name);
      expect(c.reason, reason);
      expect(got, isNot(contains(MpvVideoEventKind.softwareFallback)),
          reason: name);
      expect(got, contains(MpvVideoEventKind.resize), reason: name);
      await sub.cancel();
      await c.dispose();
    }
  }, skip: skip);

  test('unknown backend wire names still throw render_init and release the '
      'texture', () async {
    // Exact match only: case variants, empty, unknown APIs and garbage are
    // protocol breaks (STAB-04), never a silent downgrade.
    for (final name in const ['D3D11', '', 'metal', 'garbage']) {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'create') {
          return {'textureId': 7, 'backend': name, 'reason': 'x'};
        }
        return null;
      });
      await expectLater(
        MpvVideoController.create(player),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code',
            'render_init')),
        reason: name,
      );
    }
    expect(calls.where((m) => m.method == 'dispose'), hasLength(4));
  }, skip: skip);

  test('concurrent creates validate their own responses independently',
      () async {
    final player2 = Player(options: const {'vo': 'null', 'ao': 'null'});
    try {
      final first = player.mpv.handle.address;
      // Hold both create calls until both are in flight, so the two
      // validations really overlap.
      final bothArrived = Completer<void>();
      var creates = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method != 'create') return null;
        if (++creates == 2) bothArrived.complete();
        await bothArrived.future;
        final handle = (call.arguments as Map)['handle'];
        return handle == first
            ? {
                'textureId': 7,
                'backend': 'd3d11',
                'reason': 'd3d11 (gpu) on test',
              }
            : {'textureId': 8, 'backend': 'garbage', 'reason': 'x'};
      });
      final goodFuture = MpvVideoController.create(player);
      final badFuture = MpvVideoController.create(player2);
      final c = await goodFuture.timeout(const Duration(seconds: 5));
      await expectLater(
        badFuture,
        throwsA(isA<PlatformException>().having((e) => e.code, 'code',
            'render_init')),
      );
      expect(c.textureId, 7);
      expect(c.backend, MpvVideoBackend.vulkan);
      expect(c.reason, 'd3d11 (gpu) on test');
      // Only the malformed response's texture was released.
      final disposed = calls.where((m) => m.method == 'dispose').toList();
      expect(disposed, hasLength(1));
      expect((disposed.single.arguments as Map)['textureId'], 8);
      // The healthy controller still receives its events.
      final got = <MpvVideoEventKind>[];
      final sub = c.events.listen((e) => got.add(e.kind));
      await nativeEvent('resize', '640x360');
      await pumpEventQueue();
      expect(got, [MpvVideoEventKind.resize]);
      await sub.cancel();
    } finally {
      await player2.dispose();
    }
  }, skip: skip);

  test('renderer names round-trip', () {
    for (final r in MpvVideoRenderer.values) {
      expect(MpvVideoRenderer.tryParse(r.wireName), r);
    }
    expect(MpvVideoRenderer.tryParse('vulkan'), isNull);
  });
}
