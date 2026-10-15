# Migrating from media_kit

mpv_kit exposes mpv directly: state is one `MpvState<T>` per mpv property
(`value` + `stream`), commands are thin wrappers, and `player.mpv` is the
full client API for anything else. This table maps every media_kit API an
application like simple_player uses.

## Setup

| media_kit | mpv_kit |
|---|---|
| `MediaKit.ensureInitialized()` | not needed (libmpv is located by `mpv_kit_libs` / `MPV_KIT_LIBMPV_PATH`) |
| `Player(configuration: PlayerConfiguration(logLevel: …))` | `Player(options: {...})`, then `player.setLogLevel('warn')` |
| `VideoController(player)` | `await MpvVideoController.create(player)` |
| `Video(controller: c, controls: …)` | `MpvVideo(controller: c)` inside your own `Stack` for controls |
| `controller.id` (texture id) | `controller.textureId` |
| `NativePlayer.setProperty(k, v)` | `player.mpv.setPropertyString(k, v)` / `setProperty` |
| `NativePlayer.getProperty(k)` | `player.mpv.getPropertyString(k)` / `getProperty` |
| `NativePlayer.observeProperty(k, cb)` | `player.mpv.observeProperty(k).listen(cb)` |

## Opening media

| media_kit | mpv_kit |
|---|---|
| `open(Media(uri, start: d))` | `open(uri, start: d)` |
| `open(Media(uri, httpHeaders: h))` | `open(uri, options: {'http-header-fields': 'K: V,K2: V2'})` |
| `open(Media(uri), play: false)` | `open(uri, play: false)` |
| `open(Playlist(medias, index: i))` | `openPlaylist(uris, startIndex: i)` |
| `add(Media(uri))` / `remove(i)` / `move(a, b)` / `jump(i)` | `add(uri)` / `remove(i)` / `move(a, b)` / `jump(i)` |
| `next()` / `previous()` | `next()` / `previous()` |
| `setPlaylistMode(PlaylistMode.none/single/loop)` | `setLoopMode(MpvLoopMode.none/file/playlist)` |
| `setShuffle(true/false)` | `shufflePlaylist()` / `unshufflePlaylist()` |

## Transport and audio

| media_kit | mpv_kit |
|---|---|
| `play()` / `pause()` / `playOrPause()` / `stop()` | same names |
| `seek(d)` | `seek(d)` (`exact: true` for frame-exact) |
| `setVolume(v)` (0–100) | `setVolume(v)` (100 = unchanged, up to `volume-max`) |
| `setRate(r)` | `setSpeed(r)` |
| `setAudioDevice(AudioDevice)` / `state.audioDevices` | `setAudioDevice(name)` / `audioDevices` |
| `setPitch(p)` | `mpv.setProperty('pitch', p)` |

## State (`player.stream.X` / `player.state.X`)

Every `MpvState` has `.value` (media_kit's `state.X`) and `.stream`
(`stream.X`, changes only).

| media_kit | mpv_kit |
|---|---|
| `playing` | `paused` (inverted) |
| `completed` | `completed` |
| `position` / `duration` | `position` / `duration` |
| `buffer` (absolute) | `bufferedPosition` (`bufferedAhead` is relative) |
| `buffering` | `buffering` (`bufferingPercent` for the fill level) |
| `volume` / `rate` | `volume` / `speed` |
| `width` / `height` | `videoParams.value?.width` / `height` |
| `videoParams` / `audioParams` | `videoParams` / `audioParams` |
| `tracks` / `track` | `tracks` (one list, `MpvTrack.type`) / `videoTrack`, `audioTrack`, `subtitleTrack` ids |
| `playlist` | `playlist` + `playlistIndex` |
| `subtitle` (current text) | `subtitleText` |
| `log` | `logs` |
| `error` | `errors` (typed `MpvPlaybackError`) |
| — | `metadata` (music tags, ICY titles), `chapters`, `hwdecCurrent` |

## Tracks and subtitles

| media_kit | mpv_kit |
|---|---|
| `setAudioTrack(AudioTrack t)` | `selectTrack(MpvTrackType.audio, t.id)` |
| `setSubtitleTrack(SubtitleTrack.no())` | `selectTrack(MpvTrackType.sub, null)` |
| `setSubtitleTrack(SubtitleTrack.auto())` | `mpv.setPropertyString('sid', 'auto')` |
| `setSubtitleTrack(SubtitleTrack.uri(path))` | `addSubtitle(path)` |
| `SubtitleTrack` / `AudioTrack` / `VideoTrack` | `MpvTrack` (`id`, `type`, `title`, `lang`, `codec`, `isAlbumArt`, `raw`) |

## Music

Audio-only files play with the same `Player`. A cover image embedded in
the file is a video track with `isAlbumArt == true`; `MpvVideo` shows it
as a still frame (`audio-display=embedded-first`, mpv's default). Tags are
in `metadata` with the file's own key spelling (compare case-insensitively).
`setReplayGain(MpvReplayGain.album)` applies ReplayGain tags; gapless
playback is mpv's default (`gapless-audio=weak`).

## Lifetime

`player.dispose()` also disposes its `MpvVideoController` (in the right
order for libmpv). Disposing the controller alone keeps the player usable.
