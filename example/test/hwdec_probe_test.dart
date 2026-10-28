// Unit tests of the hardware-decode probe's pure helpers (Phase 16, HWD-05):
// the classification table, the option text of a list-valued property, the
// reason-to-api rule, the `HWDEC` line format and the bounded wait. No plugin
// and no libmpv.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/hwdec_probe.dart';

/// Key order of the `HWDEC` line (contract with the CI gates).
const _lineKeys = [
  'schema',
  'test',
  'sample',
  'at',
  'api',
  'requested',
  'hwdecCurrent',
  'hwdecInterop',
  'pixelformat',
  'hwPixelformat',
  'd3d11vaZeroCopy',
  'outcome',
  'zeroCopy',
  'reason',
];

HwdecReport _report(Map<String, Object?> properties, {String reason = 'x'}) =>
    HwdecReport.read(
      (name) => properties[name],
      test: 'hwdec_zero_copy',
      sample: 'hevc-10bit',
      at: 'end',
      reason: reason,
      requested: 'no',
    );

void main() {
  group('classifyHwdec', () {
    // current, pixelformat, hwPixelformat, expected
    const table = <(String?, String?, String?, HwdecOutcome)>[
      ('d3d11va', 'd3d11', 'p010', HwdecOutcome.zeroCopy),
      ('vaapi', 'vaapi', 'nv12', HwdecOutcome.zeroCopy),
      ('vulkan', 'vulkan', 'nv12', HwdecOutcome.zeroCopy),
      ('videotoolbox', 'videotoolbox', 'p010', HwdecOutcome.zeroCopy),
      ('drm', 'drm_prime', 'nv12', HwdecOutcome.zeroCopy),
      ('d3d11va', 'd3d11', null, HwdecOutcome.unexpected),
      ('d3d11va', 'nv12', null, HwdecOutcome.copyBack),
      ('d3d11va-copy', 'nv12', null, HwdecOutcome.copyBack),
      ('vaapi-copy', 'yuv420p10', null, HwdecOutcome.copyBack),
      ('videotoolbox-copy', 'nv12', null, HwdecOutcome.copyBack),
      ('no', 'yuv420p', null, HwdecOutcome.software),
      (null, null, null, HwdecOutcome.unexpected),
      ('', null, null, HwdecOutcome.unexpected),
      ('nvdec', 'cuda', 'nv12', HwdecOutcome.unexpected),
    ];
    for (final (current, pixelformat, hw, expected) in table) {
      test('"$current" / $pixelformat / $hw is ${expected.wire}', () {
        expect(
          classifyHwdec(
            hwdecCurrent: current,
            pixelformat: pixelformat,
            hwPixelformat: hw,
          ),
          expected,
        );
      });
    }

    test('hwdec-current alone never makes a zero-copy verdict', () {
      for (final method in hwdecZeroCopyFormats.keys) {
        expect(
          classifyHwdec(hwdecCurrent: method),
          isNot(HwdecOutcome.zeroCopy),
          reason: method,
        );
      }
    });

    test('an unknown -copy method is unexpected', () {
      expect(
        classifyHwdec(hwdecCurrent: 'nvdec-copy', pixelformat: 'nv12'),
        HwdecOutcome.unexpected,
      );
    });
  });

  group('hwdecOptionText', () {
    test('joins a list with commas and no brackets', () {
      expect(
        hwdecOptionText(['vulkan', 'd3d11va-copy', 'auto-safe']),
        'vulkan,d3d11va-copy,auto-safe',
      );
    });

    test('passes a string through', () {
      expect(hwdecOptionText('auto-safe'), 'auto-safe');
    });

    test('maps null to an empty string', () {
      expect(hwdecOptionText(null), '');
    });
  });

  group('reasonApi', () {
    test('takes the first word of a reason with a trail', () {
      expect(
        reasonApi('d3d11 (gpu-next) on NVIDIA; vulkan unavailable: x'),
        'd3d11',
      );
    });

    test('keeps a one-word reason', () {
      expect(reasonApi('opengl'), 'opengl');
    });
  });

  group('HwdecReport.line', () {
    test('starts with the schema and keeps the key order', () {
      final report = _report({
        'hwdec-current': 'no',
        'hwdec-interop': null,
        'video-params/pixelformat': 'yuv420p10',
        'options/d3d11va-zero-copy': 'no',
      }, reason: 'opengl (gpu) on llvmpipe');
      expect(report.line, startsWith('HWDEC {"schema":"hwdec-1","test":'));
      final decoded =
          jsonDecode(report.line.substring('HWDEC '.length))
              as Map<String, Object?>;
      expect(decoded.keys.toList(), _lineKeys);
      expect(decoded['api'], 'opengl');
      expect(decoded['outcome'], 'software');
      expect(decoded['zeroCopy'], isFalse);
      expect(decoded['d3d11vaZeroCopy'], isFalse);
    });

    test('zeroCopy follows the outcome', () {
      final report = _report({
        'hwdec-current': 'vaapi',
        'video-params/pixelformat': 'vaapi',
        'video-params/hw-pixelformat': 'nv12',
      });
      expect(report.outcome, HwdecOutcome.zeroCopy);
      expect(report.zeroCopy, isTrue);
      expect(report.line, contains('"outcome":"zero-copy","zeroCopy":true'));
    });

    test('a bool flag and an unreadable flag map to bool and null', () {
      expect(
        _report({'options/d3d11va-zero-copy': true}).d3d11vaZeroCopy,
        isTrue,
      );
      expect(_report({}).d3d11vaZeroCopy, isNull);
    });
  });

  group('awaitHwdecReport', () {
    test('waits for hwdec-current to appear', () async {
      var calls = 0;
      final report = await awaitHwdecReport(
        (name) {
          if (name != 'hwdec-current') return null;
          calls++;
          return calls <= 3 ? null : 'no';
        },
        test: 't',
        sample: 's',
        at: 'first-frame',
        reason: 'opengl',
        requested: 'no',
        poll: const Duration(milliseconds: 1),
      );
      expect(report.outcome, HwdecOutcome.software);
    });

    test('a hwdec-current that never appears yields unexpected', () async {
      final report = await awaitHwdecReport(
        (_) => null,
        test: 't',
        sample: 's',
        at: 'first-frame',
        reason: 'opengl',
        requested: 'no',
        timeout: const Duration(milliseconds: 100),
        poll: const Duration(milliseconds: 10),
      );
      expect(report.outcome, HwdecOutcome.unexpected);
    });
  });
}
