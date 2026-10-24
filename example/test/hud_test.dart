// Debug HUD widget tests (HUD-01/HUD-02/DND-01) — pure widgets, no
// libmpv: snapshots are fabricated, the predicate is a pure function.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_kit_example/hud.dart';

final _fab = HudSnapshot.fabricated();

void main() {
  group('DebugHud rendering', () {
    testWidgets('five groups render with their key values', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            DebugHud(
              visible: true,
              snapshot: _fab,
              events: [],
            ),
          ]),
        ),
      ));
      for (final title in ['SYNC', 'CACHE', 'DECODE', 'RENDER', 'AUDIO']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.textContaining('backend=vulkan'), findsOneWidget);
      // HUD-02: the composition path is visible.
      expect(find.textContaining('compositor=ANGLE'), findsOneWidget);
    });

    testWidgets('hidden state shows only the hint', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            DebugHud(
              visible: false,
              snapshot: _fab,
              events: [],
            ),
          ]),
        ),
      ));
      expect(find.text('F9: HUD'), findsOneWidget);
      expect(find.text('SYNC'), findsNothing);
    });

    testWidgets('error events render in the error style', (tester) async {
      final log = HudEventLog()..add('resize', '100x100')..add('deviceLost');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            DebugHud(
              visible: true,
              snapshot: _fab,
              events: log.items,
            ),
          ]),
        ),
      ));
      final error = tester.widget<Text>(
        find.textContaining('deviceLost'),
      );
      expect(error.style?.color, const Color(0xFFFF6666));
    });
  });

  group('HudEventLog ring buffer', () {
    test('keeps only the last 8 entries', () {
      final log = HudEventLog();
      for (var i = 0; i < 9; i++) {
        log.add('e$i');
      }
      expect(log.items.length, 8);
      expect(log.items.first.kind, 'e1');
      expect(log.items.last.kind, 'e8');
    });
  });

  group('isVideoPlayable', () {
    test('accepts video extensions case-insensitively', () {
      expect(isVideoPlayable('movie.mp4'), isTrue);
      expect(isVideoPlayable('SHOW.MKV'), isTrue);
      expect(isVideoPlayable('a/b/c.webm'), isTrue);
      expect(isVideoPlayable('clip.m2ts'), isTrue);
    });

    test('accepts stream URLs, rejects non-video and bare paths', () {
      expect(isVideoPlayable('av://lavfi:testsrc2'), isTrue);
      expect(isVideoPlayable('https://example.com/x'), isTrue);
      expect(isVideoPlayable('notes.txt'), isFalse);
      expect(isVideoPlayable('pic.jpg'), isFalse);
      expect(isVideoPlayable('noextension'), isFalse);
      expect(isVideoPlayable(''), isFalse);
    });
  });
}
