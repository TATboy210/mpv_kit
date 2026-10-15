// Audio device enumeration (`audio-device-list`). Tagged: hosts without
// any audio endpoint (CI runners) are tested separately.
@TestOn('vm')
@Tags(['devices'])
library;

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

void main() {
  test('audio devices include auto and parse into value objects', () async {
    final player = Player(options: const {'vo': 'null', 'ao': 'null'});
    addTearDown(player.dispose);
    final devices = player.audioDevices.value.isNotEmpty
        ? player.audioDevices.value
        : await player.audioDevices.stream
              .firstWhere((d) => d.isNotEmpty)
              .timeout(const Duration(seconds: 10));
    expect(devices.map((d) => d.name), contains('auto'));
    expect(
      devices.first,
      MpvAudioDevice.fromNode({
        'name': devices.first.name,
        'description': devices.first.description,
      }),
    );
  });
}
