// API-freeze assertion for phase 01: the reflected public surface of `Mpv`
// and `Player` must stay at the pre-phase baseline plus the two documented
// `@visibleForTesting` seams. Uses `dart:mirrors` only — no libmpv required.
//
// `dart:mirrors` is a VM-only library, so a local `dart analyze` over the
// full Flutter workspace cannot resolve it. This file is therefore excluded
// from static analysis in `analysis_options.yaml`; `dart test` still compiles
// and executes it, so a compile error still fails the test run.
@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

/// Public (non-private, non-constructor) declarations of [type].
Set<String> publicMembers(Type type) {
  final classMirror = reflectClass(type);
  return {
    for (final declaration in classMirror.declarations.values)
      if (declaration is! MethodMirror || !declaration.isConstructor)
        MirrorSystem.getName(declaration.simpleName),
  }.where((name) => !name.startsWith('_')).toSet();
}

/// The only `*ForTesting` members this phase adds.
const _seams = <Type, Set<String>>{
  Mpv: {'nativeEntriesForTesting', 'ignoredOptionsForTesting'},
  Player: {'stateStreamsForTesting', 'demuxerQueueBudgetForTesting'},
};

/// Public surface before phase 01-02; the phase adds only [_seams].
const _baseline = <Type, Set<String>>{
  Mpv: <String>{
    'bindings',
    'clientId',
    'clientName',
    'command',
    'commandAsync',
    'commandString',
    'createClient',
    'deleteProperty',
    'dispose',
    'errorString',
    'eventName',
    'events',
    'getOptionValue',
    'getProperty',
    'getPropertyAsync',
    'getPropertyString',
    'handle',
    'hookAdd',
    'hookContinue',
    'initialize',
    'isDisposed',
    'loadConfigFile',
    'observeProperty',
    // Phase 3 (OBS-01): the stream-source error sink Player installs.
    'onSourceError',
    'registerStreamProtocol',
    'requestEvent',
    'requestLogMessages',
    'secureDefaultOptions',
    'setOption',
    'setOptionString',
    'setOptionValue',
    'setProperty',
    'setPropertyAsync',
    'setPropertyString',
    'timeNs',
    'tryGetProperty',
    'waitAsyncRequests',
    'wakeup',
  },
  Player: <String>{
    'add',
    'addDisposeHook',
    'addSubtitle',
    'audioDelay',
    'audioDevice',
    'audioDevices',
    'audioParams',
    'audioTrack',
    'bufferedAhead',
    'bufferedPosition',
    'buffering',
    'bufferingPercent',
    'chapter',
    'chapters',
    'clearPlaylist',
    'completed',
    'decodeWarning',
    'dispose',
    'duration',
    'errors',
    'frameStep',
    'hwdecCurrent',
    'idle',
    'jump',
    'logs',
    'loopFile',
    'loopMode',
    'loopPlaylist',
    'mediaInfo',
    'metadata',
    'move',
    'mpv',
    'muted',
    'next',
    'open',
    'openPlaylist',
    'path',
    'pause',
    'paused',
    'play',
    'playOrPause',
    'playlist',
    'playlistIndex',
    'position',
    'previous',
    'remove',
    'removeDisposeHook',
    'screenshot',
    'screenshotToFile',
    'seek',
    'seekRelative',
    'seeking',
    'selectTrack',
    'setAbLoop',
    'setAspectRatio',
    'setAudioDelay',
    'setAudioDevice',
    'setAudioFilters',
    'setChapter',
    'setDeinterlace',
    'setHardwareDecoding',
    'setLogLevel',
    'setLoopFile',
    'setLoopMode',
    'setLoopPlaylist',
    'setMute',
    'setReplayGain',
    'setRotation',
    'setSpeed',
    'setSubtitleDelay',
    'setSubtitlesVisible',
    'setVideoAdjustment',
    'setVolume',
    'shufflePlaylist',
    'speed',
    'stop',
    'subtitleDelay',
    'subtitleText',
    'subtitleTrack',
    'subtitlesVisible',
    'title',
    'tracks',
    'unshufflePlaylist',
    'videoParams',
    'videoTrack',
    'volume',
  },
};

void main() {
  test('public API is frozen to the baseline plus the documented seams', () {
    for (final type in _baseline.keys) {
      final members = publicMembers(type);
      final seam = _seams[type]!;
      final sorted = members.toList()..sort();
      expect(
        members.where((name) => name.endsWith('ForTesting')).toSet(),
        seam,
        reason:
            '$type must expose exactly the documented test seam(s). '
            'Reflected public members: ${sorted.join(', ')}',
      );
      expect(
        members.difference(seam),
        _baseline[type]!,
        reason:
            '$type public API drifted from the pre-phase baseline. '
            'Reflected public members: ${sorted.join(', ')}',
      );
    }
  });
}
