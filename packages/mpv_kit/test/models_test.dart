// Pure-Dart unit tests: node parsing of the Player models, error mapping,
// option validation, event decoding from hand-built native structs and the
// in-memory stream source. None of these need libmpv.
@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

void main() {
  group('MpvTrack.fromNode', () {
    test('parses every documented field', () {
      final node = <String, Object?>{
        'id': 2,
        'type': 'audio',
        'title': 'Commentary',
        'lang': 'en',
        'codec': 'aac',
        'selected': true,
        'default': true,
        'external': true,
        'demux-w': 1920.0, // doubles are rounded
        'demux-h': 1080,
        'demux-channel-count': 6,
      };
      final t = MpvTrack.fromNode(node);
      expect(t.id, 2);
      expect(t.type, MpvTrackType.audio);
      expect(t.title, 'Commentary');
      expect(t.lang, 'en');
      expect(t.codec, 'aac');
      expect(t.selected, isTrue);
      expect(t.isDefault, isTrue);
      expect(t.external, isTrue);
      expect(t.width, 1920);
      expect(t.height, 1080);
      expect(t.channels, 6);
      expect(t.raw, same(node));
    });

    test('maps every type and tolerates missing fields', () {
      expect(MpvTrack.fromNode({'type': 'video'}).type, MpvTrackType.video);
      expect(MpvTrack.fromNode({'type': 'sub'}).type, MpvTrackType.sub);
      final t = MpvTrack.fromNode({'type': 'data', 'id': 'x'});
      expect(t.type, MpvTrackType.unknown);
      expect(t.id, -1);
      expect(t.selected, isFalse);
      expect(t.width, isNull);
    });
  });

  test('MpvPlaylistEntry.fromNode', () {
    final e = MpvPlaylistEntry.fromNode({
      'filename': 'a.mkv',
      'title': 'A',
      'current': true,
      'id': 7,
    });
    expect((e.filename, e.title, e.current, e.id), ('a.mkv', 'A', true, 7));
    final empty = MpvPlaylistEntry.fromNode(const {});
    expect((empty.filename, empty.current, empty.id), ('', false, null));
  });

  test('MpvChapter.fromNode converts seconds to Duration', () {
    final c = MpvChapter.fromNode({'time': 1.5, 'title': 'Intro'});
    expect(c.time, const Duration(milliseconds: 1500));
    expect(c.title, 'Intro');
    expect(MpvChapter.fromNode(const {}).time, Duration.zero);
  });

  test('MpvAudioParams.fromNode', () {
    final p = MpvAudioParams.fromNode({
      'format': 'floatp',
      'samplerate': 44100,
      'channels': 'stereo',
      'channel-count': 2,
    });
    expect(p.format, 'floatp');
    expect(p.sampleRate, 44100);
    expect(p.channels, 'stereo');
    expect(p.channelCount, 2);
    expect(MpvAudioParams.fromNode({}).sampleRate, isNull);
  });

  test('MpvAudioDevice value semantics', () {
    final a = MpvAudioDevice.fromNode({'name': 'auto', 'description': 'Auto'});
    expect(a, const MpvAudioDevice(name: 'auto', description: 'Auto'));
    expect(
      a.hashCode,
      const MpvAudioDevice(name: 'auto', description: 'Auto').hashCode,
    );
    expect(a.toString(), 'MpvAudioDevice(auto: Auto)');
    expect(MpvAudioDevice.fromNode({}).name, '');
  });

  test('album art tracks and replay gain values', () {
    expect(
      MpvTrack.fromNode({
        'id': 1,
        'type': 'video',
        'albumart': true,
      }).isAlbumArt,
      isTrue,
    );
    expect(MpvReplayGain.values.map((g) => g.value), ['no', 'track', 'album']);
  });

  test('MpvVideoParams.fromNode', () {
    final node = <String, Object?>{
      'w': 3840,
      'h': 2160,
      'pixelformat': 'p010',
      'primaries': 'bt.2020',
      'gamma': 'pq',
      'rotate': 90,
      'aspect': 16 / 9,
    };
    final p = MpvVideoParams.fromNode(node);
    expect((p.width, p.height), (3840, 2160));
    expect((p.pixelFormat, p.primaries, p.gamma), ('p010', 'bt.2020', 'pq'));
    expect(p.rotate, 90);
    expect(p.aspect, closeTo(1.7778, 1e-4));
    expect(p.raw, same(node));
    final empty = MpvVideoParams.fromNode(const {'aspect': 2});
    expect((empty.width, empty.rotate, empty.aspect), (null, 0, 2.0));
  });

  group('MpvScreenshot.fromNode', () {
    test('parses a well-formed node', () {
      final data = Uint8List(4 * 2 * 3);
      final s = MpvScreenshot.fromNode({
        'w': 2,
        'h': 3,
        'stride': 8,
        'format': 'rgba64',
        'data': data,
      });
      expect(s, isNotNull);
      expect((s!.width, s.height, s.stride, s.format), (2, 3, 8, 'rgba64'));
      expect(s.data, same(data));
    });

    test('defaults the format to bgr0', () {
      final s = MpvScreenshot.fromNode({
        'w': 1,
        'h': 1,
        'stride': 4,
        'data': Uint8List(4),
      });
      expect(s?.format, 'bgr0');
    });

    test('rejects malformed nodes', () {
      expect(MpvScreenshot.fromNode(null), isNull);
      expect(MpvScreenshot.fromNode('x'), isNull);
      expect(MpvScreenshot.fromNode({'w': 1, 'h': 1, 'stride': 4}), isNull);
      expect(
        MpvScreenshot.fromNode({'w': 1, 'stride': 4, 'data': Uint8List(4)}),
        isNull,
      );
    });
  });

  test('MpvMediaInfo and MpvPlaybackError hold their values', () {
    const info = MpvMediaInfo(
      path: '/a.mkv',
      width: 640,
      fps: 25,
      audioChannels: 2,
      duration: Duration(seconds: 3),
    );
    expect(
      (info.path, info.width, info.fps, info.audioChannels),
      ('/a.mkv', 640, 25.0, 2),
    );
    expect(info.hwdec, isNull);
    const err = MpvPlaybackError(
      error: MpvError.loadingFailed,
      message: 'loading failed',
      playlistEntryId: 3,
    );
    expect(err.toString(), 'MpvPlaybackError(loadingFailed: loading failed)');
    expect(MpvVideoAdjustment.values.map((a) => a.property), [
      'brightness',
      'contrast',
      'saturation',
      'gamma',
      'hue',
    ]);
  });

  group('errors', () {
    test('MpvError.fromCode maps known and unknown codes', () {
      for (final e in MpvError.values) {
        if (e == MpvError.unknown) continue;
        expect(MpvError.fromCode(e.code), e);
      }
      expect(MpvError.fromCode(-12345), MpvError.unknown);
    });

    test('MpvException exposes the typed error and formats itself', () {
      const withOp = MpvException(
        -8,
        'property not found',
        operation: 'get_property(foo)',
      );
      expect(withOp.error, MpvError.propertyNotFound);
      expect(
        withOp.toString(),
        'MpvException(propertyNotFound @ get_property(foo)): property not found',
      );
      const bare = MpvException(-20, 'error running command');
      expect(bare.toString(), 'MpvException(generic): error running command');
    });

    test('MpvLibraryNotFound lists every attempt', () {
      final e = MpvLibraryNotFound({'a.dll': 'not found', 'b.dll': 'bad'});
      final s = e.toString();
      expect(s, contains('a.dll: not found'));
      expect(s, contains('b.dll: bad'));
      expect(s, contains('MPV_KIT_LIBMPV_PATH'));
      expect(MpvLibrary.defaultNames, isNotEmpty);
    });
  });

  group('MpvOption.check', () {
    const range = MpvOption<double>(
      'volume',
      MpvOptionType.real,
      min: 0,
      max: 100,
    );
    const choiceRange = MpvOption<String>(
      'aid',
      MpvOptionType.choice,
      choices: ['no', 'auto'],
      min: 0,
      max: 10,
    );
    const choiceOnly = MpvOption<String>(
      'mode',
      MpvOptionType.choice,
      choices: ['a', 'b'],
    );
    const openEnded = MpvOption<int>('n', MpvOptionType.integer, min: 1);

    test('numeric ranges', () {
      range.check(0);
      range.check(100);
      expect(() => range.check(-1), throwsArgumentError);
      expect(() => range.check(100.5), throwsArgumentError);
      openEnded.check(1 << 40);
      expect(() => openEnded.check(0), throwsArgumentError);
    });

    test('choices, optionally with numeric strings in range', () {
      choiceRange.check('auto');
      choiceRange.check('3');
      expect(() => choiceRange.check('11'), throwsArgumentError);
      expect(() => choiceRange.check('bogus'), throwsArgumentError);
      choiceOnly.check('a');
      expect(() => choiceOnly.check('1'), throwsArgumentError);
    });

    test('string options are not validated; toString is the name', () {
      const s = MpvOption<String>('title', MpvOptionType.string);
      s.check('anything');
      expect(s.toString(), 'title');
      expect(MpvOptions.volume.toString(), 'volume');
    });
  });

  test('MpvCatalogEntry.toString is the name', () {
    const e = MpvCatalogEntry('pause', 'Pause playback.', writable: true);
    expect(e.toString(), 'pause');
    expect(e.writable, isTrue);
  });

  test('EndFileReason.fromCode', () {
    expect(EndFileReason.fromCode(0), EndFileReason.eof);
    expect(EndFileReason.fromCode(4), EndFileReason.error);
    expect(EndFileReason.fromCode(99), EndFileReason.unknown);
  });

  group('MpvMemoryStreamSource', () {
    test('reads, seeks with clamping and reports its size', () {
      final src = MpvMemoryStreamSource(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(src.size, 5);
      expect(src.read(2), [1, 2]);
      expect(src.read(10), [3, 4, 5]);
      expect(src.read(10), isEmpty); // EOF
      expect(src.seek(1), 1);
      expect(src.read(1), [2]);
      expect(src.seek(-5), 0);
      expect(src.seek(99), 5);
      src.close();
    });
  });

  group('MpvEventData.decode', () {
    // Builds an mpv_event in native memory, as libmpv would hand it out.
    MpvEventData decode(
      Arena a,
      int id, {
      int error = 0,
      int ud = 0,
      Pointer<Void>? data,
    }) {
      final e = a<MpvEvent>();
      e.ref
        ..eventId = id
        ..error = error
        ..replyUserdata = ud
        ..data = data ?? nullptr;
      return MpvEventData.decode(e);
    }

    test('payload-less events map to their classes', () {
      using((a) {
        expect(decode(a, MpvEventId.shutdown), isA<ShutdownEvent>());
        expect(decode(a, MpvEventId.fileLoaded), isA<FileLoadedEvent>());
        expect(decode(a, MpvEventId.idle), isA<IdleEvent>());
        expect(decode(a, MpvEventId.tick), isA<TickEvent>());
        expect(decode(a, MpvEventId.videoReconfig), isA<VideoReconfigEvent>());
        expect(decode(a, MpvEventId.audioReconfig), isA<AudioReconfigEvent>());
        expect(decode(a, MpvEventId.seek), isA<SeekEvent>());
        expect(
          decode(a, MpvEventId.playbackRestart),
          isA<PlaybackRestartEvent>(),
        );
        expect(decode(a, MpvEventId.queueOverflow), isA<QueueOverflowEvent>());
        final set = decode(a, MpvEventId.setPropertyReply, ud: 9, error: -8);
        expect(set, isA<SetPropertyReplyEvent>());
        expect((set.replyUserdata, set.error), (9, -8));
        final cmd = decode(a, MpvEventId.commandReply, ud: 3);
        expect(cmd, isA<CommandReplyEvent>());
        expect((cmd as CommandReplyEvent).result, isNull);
      });
    });

    test('unknown ids are preserved for forward compatibility', () {
      using((a) {
        final e = decode(a, 999);
        expect(e, isA<UnknownEvent>());
        expect((e as UnknownEvent).eventId, 999);
      });
    });

    test('client messages copy every argument', () {
      using((a) {
        final args = a<Pointer<Utf8>>(2);
        args[0] = 'hello'.toNativeUtf8(allocator: a);
        args[1] = 'wörld'.toNativeUtf8(allocator: a);
        final msg = a<MpvEventClientMessage>();
        msg.ref
          ..numArgs = 2
          ..args = args;
        final e = decode(a, MpvEventId.clientMessage, data: msg.cast());
        expect((e as ClientMessageEvent).args, ['hello', 'wörld']);
      });
    });

    test('log, start-file, end-file and hook payloads', () {
      using((a) {
        final log = a<MpvEventLogMessage>();
        log.ref
          ..prefix = 'cplayer'.toNativeUtf8(allocator: a)
          ..level = 'warn'.toNativeUtf8(allocator: a)
          ..text = 'careful\n'.toNativeUtf8(allocator: a)
          ..logLevel = 30;
        final l = decode(a, MpvEventId.logMessage, data: log.cast());
        expect(l, isA<LogMessageEvent>());

        final start = a<MpvEventStartFile>()..ref.playlistEntryId = 5;
        final s = decode(a, MpvEventId.startFile, data: start.cast());
        expect((s as StartFileEvent).playlistEntryId, 5);

        final end = a<MpvEventEndFile>();
        end.ref
          ..reason = 4
          ..error = -13
          ..playlistEntryId = 5
          ..playlistInsertId = 0
          ..playlistInsertNumEntries = 0;
        final ef = decode(a, MpvEventId.endFile, data: end.cast());
        expect(ef, isA<EndFileEvent>());

        final hook = a<MpvEventHook>();
        hook.ref
          ..name = 'on_load'.toNativeUtf8(allocator: a)
          ..id = 42;
        final h = decode(a, MpvEventId.hook, data: hook.cast()) as HookEvent;
        expect((h.name, h.id), ('on_load', 42));
      });
    });

    test('property events: format NONE means unavailable', () {
      using((a) {
        final prop = a<MpvEventProperty>();
        prop.ref
          ..name = 'duration'.toNativeUtf8(allocator: a)
          ..format = MpvFormat.none
          ..data = nullptr;
        final c = decode(a, MpvEventId.propertyChange, data: prop.cast());
        expect((c as PropertyChangeEvent).name, 'duration');
        expect(c.value, isNull);
        final g = decode(a, MpvEventId.getPropertyReply, data: prop.cast());
        expect((g as GetPropertyReplyEvent).name, 'duration');
      });
    });

    test('property events with a node value', () {
      using((a) {
        final prop = a<MpvEventProperty>();
        prop.ref
          ..name = 'track-list'.toNativeUtf8(allocator: a)
          ..format = MpvFormat.node
          ..data = writeNode([
            {'id': 1, 'type': 'video'},
          ], a).cast();
        final c = decode(a, MpvEventId.propertyChange, data: prop.cast());
        expect((c as PropertyChangeEvent).value, [
          {'id': 1, 'type': 'video'},
        ]);
      });
    });

    test('a property event decodes its node exactly once (PERF-01)', () {
      using((a) {
        final prop = a<MpvEventProperty>();
        prop.ref
          ..name = 'time-pos'.toNativeUtf8(allocator: a)
          ..format = MpvFormat.node
          ..data = writeNode(1.234, a).cast();
        final e = a<MpvEvent>();
        e.ref
          ..eventId = MpvEventId.propertyChange
          ..error = 0
          ..replyUserdata = 1
          ..data = prop.cast();
        final before = MpvEventData.propDecodesForTesting;
        MpvEventData.decode(e);
        expect(
          MpvEventData.propDecodesForTesting - before,
          1,
          reason: 'the name/value pair must come from a single _prop call',
        );
      });
    });
  });

  group('nodes', () {
    test('every supported value round-trips', () {
      using((a) {
        final value = <String, Object?>{
          'null': null,
          'flag': true,
          'int': -(1 << 40),
          'double': 0.25,
          'string': 'ünïcode',
          'list': [1, 'two', false],
          'bytes': Uint8List.fromList([0, 255, 7]),
        };
        expect(readNode(writeNode(value, a)), value);
      });
    });

    test('unknown formats are rejected', () {
      using((a) {
        final n = a<MpvNode>()..ref.format = 1234;
        expect(() => readNode(n), throwsUnsupportedError);
      });
    });
  });
}
