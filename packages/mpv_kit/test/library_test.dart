// Strict library resolution (OBS-04 + the option-C decision): an explicitly
// named libmpv — the `path` argument, else a non-empty MPV_KIT_LIBMPV_PATH —
// is tried alone and never fallen back from; only with neither given do the
// platform default names run. Each suite file runs in its own isolate, so the
// process cache starts cold here and test ORDER matters: the cold-cache
// failure tests must run before any other open() primes the cache. The cases
// that need a different environment (the env var) or a cold cache after the
// library loaded run in a child process (test/fixtures/open_probe.dart).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

/// Upper bound for one probe process (a cold `dart run` compile + dlopen).
const _probeTimeout = Duration(seconds: 90);

/// Result of one `open_probe.dart` run.
typedef _Probe = Map<String, Object?>;

/// Runs `open_probe.dart` with [env] overriding the inherited environment and
/// an optional [explicitPath] argument; returns the probe's JSON line.
Future<_Probe> _probe({
  required Map<String, String> env,
  String? explicitPath,
}) async {
  final r = await Process.run(Platform.resolvedExecutable, [
    'run',
    'test/fixtures/open_probe.dart',
    ?explicitPath,
  ], environment: env).timeout(_probeTimeout);
  expect(r.exitCode, 0, reason: 'probe failed:\n${r.stdout}\n${r.stderr}');
  final line = (r.stdout as String).trim().split('\n').last;
  return jsonDecode(line) as _Probe;
}

/// A path that does not exist.
String _missing(String name) => '${Directory.systemTemp.path}/$name';

void main() {
  // Set by the defaults test; null when no libmpv could be loaded locally.
  MpvBindings? loaded;

  test('an explicit path that fails to load throws and is not fallen back '
      'from', () {
    final missing = _missing('definitely-missing-libmpv.dll');
    // Cold cache: nothing has been opened in this isolate yet.
    expect(MpvLibrary.resolvedPath, isNull);
    late MpvLibraryNotFound error;
    try {
      MpvLibrary.open(path: missing);
      fail('open(path:) of a missing file must not succeed');
    } on MpvLibraryNotFound catch (e) {
      error = e;
    }
    expect(error.attempts.keys.toList(), [
      missing,
    ], reason: 'only the explicit path may be tried, never the defaults');
    expect(error.attempts[missing], isNotEmpty, reason: 'loader reason kept');
    expect(MpvLibrary.lastOpenAttempts, error.attempts);
    expect(MpvLibrary.resolvedPath, isNull, reason: 'a failure caches nothing');
    expect(error.toString(), contains('never fallen back from'));
  });

  test('a failed explicit path wins over a working environment variable', () {
    final missing = _missing('missing-explicit-libmpv.dll');
    // Even with MPV_KIT_LIBMPV_PATH set to something loadable, the explicit
    // argument is the only candidate.
    expect(
      () => MpvLibrary.open(path: missing),
      throwsA(
        isA<MpvLibraryNotFound>().having(
          (e) => e.attempts.keys.toList(),
          'attempts',
          [missing],
        ),
      ),
    );
  });

  test('with neither an explicit path nor the env var, defaults resolve', () {
    final env = Platform.environment['MPV_KIT_LIBMPV_PATH'];
    try {
      loaded = MpvLibrary.open();
    } on MpvLibraryNotFound catch (e) {
      if (Platform.environment['MPV_KIT_REQUIRE_LIBMPV'] != null) {
        fail(
          'libmpv is required by CI (MPV_KIT_REQUIRE_LIBMPV) but could not '
          'be loaded: ${e.attempts}',
        );
      }
      markTestSkipped('libmpv not available locally: ${e.attempts}');
      return;
    }
    expect(MpvLibrary.resolvedPath, isNotNull);
    if (env != null && env.isNotEmpty) {
      // The CI/local environment names the library: it is the only candidate.
      expect(MpvLibrary.resolvedPath, env);
      expect(MpvLibrary.lastOpenAttempts, isEmpty);
    } else {
      expect(MpvLibrary.defaultNames, contains(MpvLibrary.resolvedPath));
    }
    expect(MpvLibrary.apiVersion(MpvLibrary.open()).$1, 2);
  });

  test('an explicit path ignored by the process cache does not change the '
      'resolved library', () {
    final b = loaded;
    if (b == null) {
      markTestSkipped('libmpv not available locally');
      return;
    }
    final before = MpvLibrary.resolvedPath;
    // After a successful load the cache wins; the differing path only logs.
    expect(MpvLibrary.open(path: 'another-missing-candidate.dll'), same(b));
    expect(MpvLibrary.open(), same(b));
    expect(MpvLibrary.resolvedPath, before);
  });

  group('MPV_KIT_LIBMPV_PATH (child process)', () {
    test(
      'pointing at a missing file throws and is not fallen back from',
      () async {
        final missing = _missing('missing-env-libmpv.dll');
        final p = await _probe(env: {'MPV_KIT_LIBMPV_PATH': missing});
        expect(p['ok'], isFalse, reason: 'the defaults must not rescue it: $p');
        final attempts = (p['attempts']! as Map).cast<String, String>();
        expect(attempts.keys.toList(), [missing]);
        expect(attempts[missing], isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    test('an empty value counts as unset (defaults are tried)', () async {
      final p = await _probe(env: {'MPV_KIT_LIBMPV_PATH': ''});
      if (p['ok'] == true) {
        expect(MpvLibrary.defaultNames, contains(p['resolvedPath']));
      } else {
        // No default libmpv on this machine: the attempts are the defaults.
        final attempts = (p['attempts']! as Map).keys;
        expect(attempts, MpvLibrary.defaultNames);
      }
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('a valid explicit path wins over a broken env var', () async {
      final real = MpvLibrary.resolvedPath;
      if (loaded == null || real == null) {
        markTestSkipped('libmpv not available locally');
        return;
      }
      final p = await _probe(
        env: {'MPV_KIT_LIBMPV_PATH': _missing('broken-env-libmpv.dll')},
        explicitPath: real,
      );
      expect(p, {'ok': true, 'resolvedPath': real});
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
