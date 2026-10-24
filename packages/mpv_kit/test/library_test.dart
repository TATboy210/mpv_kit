// Library resolution observability (OBS-04): resolvedPath/lastOpenAttempts
// make the loader's fall-throughs diagnosable (the Phase 1 wrong-DLL
// incident class). Each suite file runs in its own isolate, so the process
// cache starts cold here — test order matters: the fall-through test must
// run before any other open() primes the cache.
@TestOn('vm')
library;

import 'dart:io';

import 'package:mpv_kit/mpv_kit.dart';
import 'package:test/test.dart';

void main() {
  test('a failed explicit candidate is recorded when a later one succeeds',
      () {
    final missing = '${Directory.systemTemp.path}/definitely-missing-libmpv.dll';
    final b = MpvLibrary.open(path: missing);
    expect(MpvLibrary.resolvedPath, isNotNull);
    expect(MpvLibrary.resolvedPath, isNot(missing));
    expect(
      MpvLibrary.lastOpenAttempts.keys,
      contains(missing),
      reason: 'the failed candidate must be observable (OBS-04)',
    );
    expect(b, same(MpvLibrary.open()), reason: 'cache identity unchanged');
  });

  test('resolvedPath names the library that actually loaded', () {
    MpvLibrary.open();
    expect(MpvLibrary.resolvedPath, isNotNull);
    // The environment candidate (when set) or a platform default loaded.
    final env = Platform.environment['MPV_KIT_LIBMPV_PATH'];
    if (env != null) {
      expect(MpvLibrary.resolvedPath, env);
    }
    expect(MpvLibrary.apiVersion(MpvLibrary.open()).$1, 2);
  });

  test('an explicit path ignored by the process cache does not change the '
      'resolved library', () {
    final before = MpvLibrary.resolvedPath;
    final b = MpvLibrary.open(path: 'another-missing-candidate.dll');
    expect(b, same(MpvLibrary.open()));
    expect(MpvLibrary.resolvedPath, before);
  });
}
