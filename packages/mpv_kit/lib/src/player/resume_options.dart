/// Resume-playback settings for [Player], mapped onto libmpv's own position
/// memory.
///
/// libmpv saves each file's position on quit (`save-position-on-quit`) and
/// restores it on the next open (`resume-playback`). Nothing is implemented
/// in Dart: these options only select that native behaviour.
library;

/// Options that control libmpv's resume-playback position memory.
///
/// Pass an instance as `Player(resume: ...)`. Values are sent to libmpv as
/// `yes` / `no`, and [watchLaterDir] is only sent when set, so libmpv's
/// default directory is used otherwise.
final class MpvResumeOptions {
  /// Creates resume options. The defaults enable resume, save-on-quit and the
  /// modification-time check. libmpv's own defaults keep save-on-quit and the
  /// check off, so `Player()` without `resume` differs from
  /// `Player(resume: const MpvResumeOptions())` in those two flags.
  const MpvResumeOptions({
    this.enabled = true,
    this.saveOnQuit = true,
    this.watchLaterDir,
    this.checkMtime = true,
  });

  /// Restore the saved position when a file is opened again
  /// (`resume-playback`).
  final bool enabled;

  /// Write the position when the player quits or another file replaces the
  /// current entry (`save-position-on-quit`).
  final bool saveOnQuit;

  /// Directory that stores the saved positions (`watch-later-dir`). When null
  /// libmpv's default directory is used.
  final String? watchLaterDir;

  /// Discard a saved position when the file changed since it was saved
  /// (`resume-playback-check-mtime`). Protects against resuming into a
  /// different file that reuses the same name.
  final bool checkMtime;

  /// Returns libmpv option pairs for [Player]'s `options` map.
  ///
  /// Keys are the libmpv option names; booleans are encoded as `yes` / `no`
  /// because libmpv parses boolean options from strings.
  Map<String, String> toOptions() => {
    'resume-playback': _yesNo(enabled),
    'save-position-on-quit': _yesNo(saveOnQuit),
    'resume-playback-check-mtime': _yesNo(checkMtime),
    // Only override the directory when the caller asked for one, so libmpv's
    // default location still applies otherwise.
    'watch-later-dir': ?watchLaterDir,
  };

  /// Encodes a boolean as libmpv's `yes` / `no` option string.
  static String _yesNo(bool value) => value ? 'yes' : 'no';
}
