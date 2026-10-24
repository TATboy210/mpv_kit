/// libmpv 动态库定位与加载。
library;

import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'bindings.dart';

/// 加载 libmpv 失败时抛出。
final class MpvLibraryNotFound implements Exception {
  MpvLibraryNotFound(this.attempts);

  /// 尝试过的路径/名称及各自的失败原因。
  final Map<String, String> attempts;

  @override
  String toString() =>
      'MpvLibraryNotFound: libmpv could not be loaded.\n'
      '${attempts.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
      'Set MPV_KIT_LIBMPV_PATH or pass an explicit path to MpvLibrary.open().';
}

/// 进程内唯一的 libmpv 实例。
///
/// Resolution order: explicit [path] → `MPV_KIT_LIBMPV_PATH` env var →
/// platform default names (resolved by the OS loader, i.e. the bundled copy
/// next to the executable / inside the app bundle comes first).
abstract final class MpvLibrary {
  static MpvBindings? _bindings;

  /// The candidate that actually loaded, null until a successful [open]
  /// (OBS-04 diagnostic seam: the Phase 1 wrong-DLL incident class — a
  /// failed `MPV_KIT_LIBMPV_PATH` silently falling back to another copy —
  /// must be diagnosable from Dart).
  static String? resolvedPath;

  /// Candidate → failure reason for the most recent [open] call (OBS-04
  /// diagnostic seam). Empty when the first candidate succeeded; on total
  /// failure the same map as [MpvLibraryNotFound.attempts].
  static Map<String, String> lastOpenAttempts = const {};

  /// 平台默认库名（按优先级）。
  static List<String> get defaultNames {
    if (Platform.isWindows) return const ['libmpv-2.dll', 'mpv-2.dll'];
    if (Platform.isMacOS) {
      return const [
        // mpv_kit_libs native asset (Flutter wraps each dylib in a
        // framework named after it), resolved via the app's LC_RPATH.
        '@rpath/mpv.2.framework/mpv.2',
        'libmpv.2.dylib',
        'libmpv.dylib',
      ];
    }
    return const ['libmpv.so.2', 'libmpv.so'];
  }

  /// 已加载则返回缓存实例，否则按解析顺序加载。
  ///
  /// Side effect: maps the shared library into the process (never unloaded).
  /// Fall-throughs are logged (OBS-04): a failed env/explicit candidate that
  /// is followed by a successful one warns, and an explicit [path] ignored
  /// because of the process cache warns too — neither changes behavior.
  static MpvBindings open({String? path}) {
    final cached = _bindings;
    if (cached != null) {
      if (path != null && path != resolvedPath) {
        developer.log(
          'mpv_kit: ignoring explicit libmpv path "$path"; the process '
          'already resolved "$resolvedPath"',
          level: 900,
        );
      }
      return cached;
    }
    final candidates = <String>[
      ?path,
      ?Platform.environment['MPV_KIT_LIBMPV_PATH'],
      ...defaultNames,
    ];
    final attempts = <String, String>{};
    for (final candidate in candidates) {
      try {
        final bindings = MpvBindings(DynamicLibrary.open(candidate));
        _checkApiVersion(bindings);
        resolvedPath = candidate;
        lastOpenAttempts = Map.of(attempts);
        if (attempts.isNotEmpty) {
          developer.log(
            'mpv_kit: libmpv candidate "$candidate" loaded after earlier '
            'candidates failed: $attempts',
            level: 900,
          );
        }
        return _bindings = bindings;
      } on ArgumentError catch (e) {
        attempts[candidate] = e.message.toString();
      } on UnsupportedError catch (e) {
        attempts[candidate] = e.message ?? 'unsupported';
      }
    }
    lastOpenAttempts = Map.of(attempts);
    throw MpvLibraryNotFound(attempts);
  }

  /// 最低兼容的 client API 主版本（mpv 0.35+ 为 2）。
  static const requiredMajor = 2;

  static void _checkApiVersion(MpvBindings b) {
    final v = b.clientApiVersion();
    final major = v >> 16;
    if (major != requiredMajor) {
      throw UnsupportedError(
        'libmpv client API $major.${v & 0xffff} is incompatible '
        '(need $requiredMajor.x)',
      );
    }
  }

  /// 已加载库的 client API 版本，形如 (2, 5)。
  static (int major, int minor) apiVersion(MpvBindings b) {
    final v = b.clientApiVersion();
    return (v >> 16, v & 0xffff);
  }
}
