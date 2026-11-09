// Default shader cache location per platform.
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_kit_video/src/video_controller.dart';

void main() {
  String? dir(String os, Map<String, String> env) =>
      MpvVideoController.defaultShaderCacheDir(os: os, environment: env);

  test('Windows uses LOCALAPPDATA, joined with forward slashes', () {
    expect(
      dir('windows', {'LOCALAPPDATA': r'C:\Users\a\AppData\Local'}),
      r'C:\Users\a\AppData\Local' '/mpv_kit/shader-cache',
    );
  });

  test('macOS uses ~/Library/Caches', () {
    expect(
      dir('macos', {'HOME': '/Users/a'}),
      '/Users/a/Library/Caches/mpv_kit/shader-cache',
    );
  });

  test('Linux prefers XDG_CACHE_HOME and falls back to ~/.cache', () {
    expect(
      dir('linux', {'XDG_CACHE_HOME': '/x', 'HOME': '/home/a'}),
      '/x/mpv_kit/shader-cache',
    );
    expect(
      dir('linux', {'XDG_CACHE_HOME': '', 'HOME': '/home/a'}),
      '/home/a/.cache/mpv_kit/shader-cache',
    );
  });

  test('MpvVideoBackend stays {vulkan, software} (API freeze)', () {
    // Public API freeze (ADR 0004): new GPU APIs are reported through
    // `vulkan` plus the reason string, never through new enum values.
    expect(
      MpvVideoBackend.values.map((b) => b.name).toList(),
      ['vulkan', 'software'],
    );
  });

  test('no usable environment disables the default', () {
    expect(dir('windows', {}), isNull);
    expect(dir('linux', {'HOME': ''}), isNull);
  });
}
