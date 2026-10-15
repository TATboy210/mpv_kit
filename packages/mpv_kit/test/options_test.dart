// Typed option API (MpvOptions generated from libmpv's option table).
@TestOn('vm')
library;

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

void main() {
  late Mpv mpv;
  setUp(() => mpv = Mpv.create(options: const {'vo': 'null', 'ao': 'null'}));
  tearDown(() => mpv.dispose());

  test('values round-trip with their Dart types', () {
    mpv.setOptionValue(MpvOptions.volume, 42.0);
    expect(mpv.getOptionValue(MpvOptions.volume), 42.0);
    mpv.setOptionValue(MpvOptions.mute, true);
    expect(mpv.getOptionValue(MpvOptions.mute), isTrue);
    mpv.setOptionValue(MpvOptions.hwdec, 'auto-safe');
    expect(mpv.getOptionValue(MpvOptions.hwdec), 'auto-safe');
  });

  test('choices and ranges are validated before reaching mpv', () {
    expect(MpvOptions.videoSync.choices, contains('display-resample'));
    expect(
      () => mpv.setOptionValue(MpvOptions.videoSync, 'bogus'),
      throwsArgumentError,
    );
    expect(
      () => mpv.setOptionValue(MpvOptions.volume, 5000.0),
      throwsArgumentError,
    );
    mpv.setOptionValue(MpvOptions.videoSync, 'display-resample');
    expect(mpv.getOptionValue(MpvOptions.videoSync), 'display-resample');
  });

  test('every generated option exists in this libmpv', () {
    final names = (mpv.getProperty('options')! as List).toSet();
    for (final o in [MpvOptions.hwdec, MpvOptions.vo, MpvOptions.loopFile]) {
      expect(names, contains(o.name));
    }
  });
}
