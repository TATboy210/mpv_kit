// Pins the per-platform default hwdec lists (HWD-01, ADR 0006). Pure Dart:
// no libmpv is needed, only the ordering rule and the exact values of the
// decision recorded in .planning/phases/16-hardware-decode-zero-copy/
// evidence/decisions.txt (decision=hwdec-defaults).
@TestOn('vm')
library;

import 'dart:io';

import 'package:mpv_kit/src/player/hwdec_defaults.dart';
import 'package:test/test.dart';

/// Exact lists of the user's decision (choice=adopt).
const _expected = <String, String>{
  'windows': 'vulkan,d3d11va,d3d11va-copy,auto-safe',
  'linux': 'vulkan,vaapi,auto-safe',
  'macos': 'videotoolbox,auto-safe',
  'fuchsia': 'auto-safe',
};

bool _isCopy(String e) => e.endsWith('-copy');
bool _isAuto(String e) => e.startsWith('auto');

void main() {
  for (final MapEntry(key: os, value: list) in _expected.entries) {
    group('defaultHwdecFor($os)', () {
      final entries = defaultHwdecFor(os).split(',');

      test('is the decided list', () {
        expect(defaultHwdecFor(os), list);
      });

      test('ends with auto-safe and has no duplicates', () {
        expect(entries.last, 'auto-safe');
        expect(entries.toSet().length, entries.length);
      });

      test(
        'lists every zero-copy candidate before any -copy or auto entry',
        () {
          final zeroCopy = [
            for (var i = 0; i < entries.length; i++)
              if (!_isCopy(entries[i]) && !_isAuto(entries[i])) i,
          ];
          final fallbacks = [
            for (var i = 0; i < entries.length; i++)
              if (_isCopy(entries[i]) || _isAuto(entries[i])) i,
          ];
          for (final z in zeroCopy) {
            for (final f in fallbacks) {
              expect(
                z,
                lessThan(f),
                reason: '${entries[z]} must precede ${entries[f]}',
              );
            }
          }
        },
      );
    });
  }

  test('windows tries d3d11va before d3d11va-copy', () {
    final entries = defaultHwdecFor('windows').split(',');
    expect(
      entries.indexOf('d3d11va'),
      lessThan(entries.indexOf('d3d11va-copy')),
    );
  });

  test('unknown platforms fall back to auto-safe', () {
    expect(defaultHwdecFor('someos'), 'auto-safe');
  });

  test('platformDefaultHwdec follows Platform.operatingSystem', () {
    expect(platformDefaultHwdec(), defaultHwdecFor(Platform.operatingSystem));
  });
}
