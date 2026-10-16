// Audio device enumeration (`audio-device-list`).
//
// Regression tests for two native crashes that only showed on hosts without
// an audio endpoint (CI runners): a NULL import in CoreAudio's device list
// (macOS) and WASAPI hotplug objects released after their apartment ended,
// when libmpv destroys the player on the client thread (Windows). Both now
// have to pass on every host, with or without audio hardware.
@TestOn('vm')
library;

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

/// Waits for the first non-empty device list ([Player.audioDevices] is
/// observed lazily, so the first value arrives asynchronously).
Future<List<MpvAudioDevice>> _devices(Player player) async {
  final current = player.audioDevices.value;
  if (current.isNotEmpty) return current;
  return player.audioDevices.stream
      .firstWhere((d) => d.isNotEmpty)
      .timeout(const Duration(seconds: 10));
}

void main() {
  test('audio devices include auto and parse into value objects', () async {
    final player = Player(options: const {'vo': 'null', 'ao': 'null'});
    addTearDown(player.dispose);
    final devices = await _devices(player);
    expect(devices.map((d) => d.name), contains('auto'));
    expect(
      devices.first,
      MpvAudioDevice.fromNode({
        'name': devices.first.name,
        'description': devices.first.description,
      }),
    );
  });

  test('disposing right after enumeration does not crash', () async {
    // Default ao: the hotplug instance stays alive until
    // mpv_terminate_destroy, which runs on this (client) thread.
    final player = Player(options: const {'vo': 'null'});
    await _devices(player);
    await player.dispose();
  });

  test('repeated create, enumerate, dispose is stable', () async {
    for (var i = 0; i < 20; i++) {
      final player = Player(options: const {'vo': 'null', 'ao': 'null'});
      final devices = await _devices(player);
      expect(devices.map((d) => d.name), contains('auto'));
      await player.dispose();
    }
  });

  test('synchronous read enumerates on the caller thread', () async {
    // mpv_get_property evaluates the property on the calling thread, so the
    // hotplug instance's COM state belongs to it, not to the core thread.
    final player = Player(options: const {'vo': 'null', 'ao': 'null'});
    final list = player.mpv.getProperty('audio-device-list');
    expect(list, isA<List<Object?>>());
    await player.dispose();
  });
}
