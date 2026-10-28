/// libmpv 动态库定位与加载。
library;

import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'bindings.dart';

/// 加载 libmpv 失败时抛出。
///
/// 显式指定的库（`path` 参数或 `MPV_KIT_LIBMPV_PATH`）加载失败时也抛出本异常，
/// 不会回退到其它副本；[attempts] 只含该显式候选及加载器给出的原因。
final class MpvLibraryNotFound implements Exception {
  MpvLibraryNotFound(this.attempts);

  /// 尝试过的路径/名称及各自的失败原因。
  final Map<String, String> attempts;

  @override
  String toString() =>
      'MpvLibraryNotFound: libmpv could not be loaded.\n'
      '${attempts.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
      'An explicit path or MPV_KIT_LIBMPV_PATH is never fallen back from: '
      'fix it (and make its dependency libraries reachable), or leave both '
      'unset to use the platform default names.';
}

/// 进程内唯一的 libmpv 实例。
///
/// Resolution is strict about explicitly named libraries (a deliberate
/// behavior change; the signature is unchanged):
///
/// 1. an explicit [open] `path` is tried alone;
/// 2. otherwise a non-empty `MPV_KIT_LIBMPV_PATH` env var is tried alone;
/// 3. only when neither is given, the platform default names are tried in
///    order (resolved by the OS loader, i.e. the bundled copy next to the
///    executable / inside the app bundle comes first).
///
/// A named library that fails to load — missing file, an unresolved
/// dependency (Windows error 127, "The specified procedure could not be
/// found") or an incompatible client API — throws [MpvLibraryNotFound]
/// carrying the loader's reason. It never falls back to another copy: that
/// silently ran the wrong libmpv (the Phase 1 wrong-DLL incident class).
abstract final class MpvLibrary {
  static MpvBindings? _bindings;

  /// The candidate that actually loaded, null until a successful [open]
  /// (OBS-04 diagnostic seam: which copy the process runs must be
  /// diagnosable from Dart). For an explicit path or `MPV_KIT_LIBMPV_PATH`
  /// this is always that very string.
  static String? resolvedPath;

  /// Candidate → failure reason for the most recent [open] call (OBS-04
  /// diagnostic seam). Empty when the first candidate succeeded (always, for
  /// an explicit path / env var that loaded); on failure the same map as
  /// [MpvLibraryNotFound.attempts].
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
  /// Throws [MpvLibraryNotFound] when the library fails to load; an explicit
  /// [path] or `MPV_KIT_LIBMPV_PATH` is the only candidate and is never
  /// fallen back from (see [MpvLibrary]). An empty env var counts as unset.
  /// Logged (OBS-04): a default name that failed before a later default
  /// loaded, and an explicit [path] ignored because the process cache
  /// already holds another library — the cache always wins (a process maps
  /// libmpv once), so a later `open(path:)` after a successful load returns
  /// the cached bindings.
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
    // Strict resolution: a named library (argument, then env var) is the
    // only candidate. Falling through to the default names would run a
    // different libmpv than the caller asked for.
    final env = Platform.environment['MPV_KIT_LIBMPV_PATH'];
    final candidates = path != null
        ? <String>[path]
        : (env != null && env.isNotEmpty)
        ? <String>[env]
        : defaultNames;
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
