import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

void main() {
  group('MpvResumeOptions.toOptions', () {
    test('defaults enable resume, save-on-quit and the mtime check', () {
      // Arrange
      const options = MpvResumeOptions();

      // Act
      final map = options.toOptions();

      // Assert
      expect(map, {
        'resume-playback': 'yes',
        'save-position-on-quit': 'yes',
        'resume-playback-check-mtime': 'yes',
      });
    });

    test('omits watch-later-dir when no directory is given', () {
      // Arrange
      const options = MpvResumeOptions();

      // Act
      final map = options.toOptions();

      // Assert
      expect(map.containsKey('watch-later-dir'), isFalse);
    });

    test('maps a custom watch-later directory and disabled flags to no', () {
      // Arrange
      const options = MpvResumeOptions(
        enabled: false,
        saveOnQuit: false,
        checkMtime: false,
        watchLaterDir: r'D:\state\watch_later',
      );

      // Act
      final map = options.toOptions();

      // Assert
      expect(map, {
        'resume-playback': 'no',
        'save-position-on-quit': 'no',
        'resume-playback-check-mtime': 'no',
        'watch-later-dir': r'D:\state\watch_later',
      });
    });
  });
}
