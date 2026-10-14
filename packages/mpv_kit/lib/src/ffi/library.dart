/// libmpv 动态库定位与加载。
library;

import 'dart:ffi';
import 'dart:io';

import 'bindings.dart';

/// 加载 libmpv 失败时抛出。
final class MpvLibraryNotFound implements Exception {
  MpvLibraryNotFound(this.attempts);

  /// 尝试过的路径/名称及各自的失败原因。
  final Map<String, String> attempts;

  @override
  String toString() => 'MpvLibraryNotFound: libmpv could not be loaded.\n'
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
  static MpvBindings open({String? path}) {
    final cached = _bindings;
    if (cached != null) return cached;
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
        return _bindings = bindings;
      } on ArgumentError catch (e) {
        attempts[candidate] = e.message.toString();
      } on UnsupportedError catch (e) {
        attempts[candidate] = e.message ?? 'unsupported';
      }
    }
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
          '(need $requiredMajor.x)');
    }
  }

  /// 已加载库的 client API 版本，形如 (2, 5)。
  static (int major, int minor) apiVersion(MpvBindings b) {
    final v = b.clientApiVersion();
    return (v >> 16, v & 0xffff);
  }
}
