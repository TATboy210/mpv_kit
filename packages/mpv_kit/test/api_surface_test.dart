// Headless coverage of the remaining Mpv / Player API surface: client
// identity, option/property helpers, async error paths and the Player's
// transport, playlist, audio, subtitle and video setters (each checked by
// reading the mpv property back).
//
// Requires libmpv: set MPV_KIT_LIBMPV_PATH or have it on the loader path.
@TestOn('vm')
library;

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

const _lavfi = 'av://lavfi:testsrc2=size=320x240:rate=30:duration=2';
const _timeout = Duration(seconds: 10);

void main() {
  group('Mpv', () {
    late Mpv mpv;
    setUp(
      () => mpv = Mpv.create(
        options: const {'vo': 'null', 'ao': 'null', 'idle': 'yes'},
      ),
    );
    tearDown(() => mpv.dispose());

    test('client identity, clock and name lookups', () {
      expect(mpv.clientName, isNotEmpty);
      expect(mpv.clientId, greaterThan(0));
      expect(mpv.timeNs, greaterThan(0));
      expect(mpv.errorString(MpvError.propertyNotFound.code), isNotEmpty);
      expect(mpv.eventName(MpvEventId.fileLoaded), 'file-loaded');
      mpv.wakeup();
      mpv.waitAsyncRequests();
    });

    test('weak sub-clients share the core', () {
      final weak = mpv.createClient('weakling', weak: true);
      addTearDown(weak.dispose);
      expect(weak.clientName, 'weakling');
      weak.setProperty('volume', 12.0);
      expect(mpv.getProperty('volume'), 12.0);
    });

    test('option, command-string and delete-property helpers', () {
      mpv.setOption('volume', 33.0);
      expect(mpv.getProperty('volume'), 33.0);
      mpv.commandString('set volume 44');
      expect(mpv.getProperty('volume'), 44.0);
      mpv.setProperty('user-data/mpv_kit/test', 'x');
      expect(mpv.getProperty('user-data/mpv_kit/test'), 'x');
      mpv.deleteProperty('user-data/mpv_kit/test');
      expect(mpv.tryGetProperty('user-data/mpv_kit/test'), isNull);
      expect(
        () => mpv.setOption('no-such-option', 1),
        throwsA(isA<MpvException>()),
      );
      expect(
        () => mpv.commandString('no-such-command'),
        throwsA(isA<MpvException>()),
      );
      expect(
        () => mpv.loadConfigFile('/definitely/not/here.conf'),
        throwsA(isA<MpvException>()),
      );
      mpv.requestEvent(MpvEventId.tick, enable: false);
    });

    test('typed integer options read back as int', () {
      mpv.setOptionValue(MpvOptions.cacheSecs, 7.0);
      expect(mpv.getOptionValue(MpvOptions.cacheSecs), 7.0);
      mpv.setOptionValue(MpvOptions.osdDuration, 1500);
      expect(mpv.getOptionValue(MpvOptions.osdDuration), 1500);
      mpv.setOptionValue(MpvOptions.osdLevel, '2');
      expect(mpv.getOptionValue(MpvOptions.osdLevel), '2');
    });

    test('async requests fail with MpvException', () async {
      await expectLater(
        mpv.commandAsync(['no-such-command']).result,
        throwsA(isA<MpvException>()),
      );
      await expectLater(
        mpv.commandAsync({'name': 'no-such-command'}).result,
        throwsA(isA<MpvException>()),
      );
      await expectLater(
        mpv.setPropertyAsync('no-such-property', 1),
        throwsA(isA<MpvException>()),
      );
      await expectLater(
        mpv.getPropertyAsync('no-such-property'),
        throwsA(isA<MpvException>()),
      );
    });

    test('aborting an async command still completes it', () async {
      final cmd = mpv.commandAsync(['loadfile', _lavfi]);
      cmd.abort();
      await cmd.result.then((_) {}, onError: (Object _) {});
      mpv.dispose();
      cmd.abort(); // no-op after dispose
    });
  });

  group('Player setters', () {
    late Player player;
    setUp(() => player = Player(options: const {'vo': 'null', 'ao': 'null'}));
    tearDown(() => player.dispose());

    Object? prop(String name) => player.mpv.getProperty(name);

    test('transport, A-B loop and frame stepping', () async {
      // Subscribe first: file-loaded may arrive before open() returns.
      final loaded = player.mpv.events
          .firstWhere((e) => e is FileLoadedEvent)
          .timeout(_timeout);
      await player.open(_lavfi, play: false);
      await loaded;
      player.play();
      expect(prop('pause'), isFalse);
      player.pause();
      expect(prop('pause'), isTrue);
      player.playOrPause();
      expect(prop('pause'), isFalse);
      player.pause();
      await player.seek(const Duration(milliseconds: 500), exact: true);
      await player.seekRelative(const Duration(milliseconds: 200));
      await player.seekRelative(
        const Duration(milliseconds: -100),
        exact: true,
      );
      player.frameStep();
      player.frameStep(backward: true);
      player.setAbLoop(const Duration(milliseconds: 100), null);
      expect(prop('ab-loop-a'), closeTo(0.1, 1e-9));
      expect(prop('ab-loop-b'), 'no');
      player.setAbLoop(null, const Duration(seconds: 1));
      expect(prop('ab-loop-a'), 'no');
      expect(prop('ab-loop-b'), closeTo(1.0, 1e-9));
      player.stop();
    });

    test('playlist editing', () async {
      // Subscribe first: file-loaded may arrive before open() returns.
      final loaded = player.mpv.events
          .firstWhere((e) => e is FileLoadedEvent)
          .timeout(_timeout);
      await player.openPlaylist([_lavfi, _lavfi, _lavfi], play: false);
      await loaded;
      expect(prop('playlist-count'), 3);
      // Step while the current entry is the first one.
      player.next();
      player.previous();
      player.move(2, 0);
      player.remove(2);
      expect(prop('playlist-count'), 2);
      player.shufflePlaylist();
      player.unshufflePlaylist();
      player.setLoopFile(true);
      expect(prop('loop-file'), 'inf');
      player.setLoopFile(false);
      expect(prop('loop-file'), isFalse);
      player.setLoopPlaylist(true);
      expect(prop('loop-playlist'), 'inf');
      // lavfi sources have no chapters: mpv rejects the write.
      expect(() => player.setChapter(0), throwsA(isA<MpvException>()));
      player.clearPlaylist();
      expect(prop('playlist-count'), lessThanOrEqualTo(1));
      await player.openPlaylist(const []); // stops playback
      expect(
        () => player.openPlaylist([_lavfi], startIndex: 5),
        throwsRangeError,
      );
    });

    test('audio, subtitle and video setters', () async {
      await player.open(_lavfi, play: false);
      player.setAudioFilters('lavfi=[volume=0.5]');
      expect(prop('af'), isNotEmpty);
      player.setAudioFilters(null);
      expect(prop('af'), isEmpty);
      player.selectTrack(MpvTrackType.video, null);
      expect(prop('vid'), isFalse);
      player.selectTrack(MpvTrackType.audio, null);
      player.selectTrack(MpvTrackType.unknown, null);
      expect(prop('sid'), isFalse);
      player.setSubtitlesVisible(false);
      expect(prop('sub-visibility'), isFalse);
      player.setVideoAdjustment(MpvVideoAdjustment.contrast, 500);
      expect(prop('contrast'), 100);
      player.setRotation(450);
      expect(prop('video-rotate'), 90);
      player.setAspectRatio(4 / 3);
      expect(prop('video-aspect-override'), closeTo(4 / 3, 1e-6));
      player.setAspectRatio(null);
      player.setDeinterlace(true);
      expect(prop('deinterlace'), anyOf(isTrue, 'yes'));
      player.setHardwareDecoding('no');
      expect(prop('hwdec'), anyOf('no', ['no']));
    });
  });
}
