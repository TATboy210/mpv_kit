// Integrity and safety of release-bundle handling.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mpv_kit_libs/src/bundle.dart';
import 'package:mpv_kit_libs/src/tar.dart';
import 'package:test/test.dart';

/// Builds a ustar archive; [type] '0' = file, '2' = symlink, '5' = dir.
Uint8List tar(List<(String, String, String)> entries) {
  final out = BytesBuilder();
  for (final (name, type, body) in entries) {
    final data = utf8.encode(body);
    final h = Uint8List(512);
    void put(int at, String s) => h.setRange(at, at + s.length, utf8.encode(s));
    put(0, name);
    put(100, '0000644\x00');
    put(108, '0000000\x00');
    put(116, '0000000\x00');
    put(124, '${data.length.toRadixString(8).padLeft(11, '0')}\x00');
    put(136, '00000000000\x00');
    h[156] = type.codeUnitAt(0);
    put(257, 'ustar\x0000');
    put(148, '        ');
    final sum = h.fold<int>(0, (a, b) => a + b);
    put(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 ');
    out
      ..add(h)
      ..add(data)
      ..add(Uint8List((512 - data.length % 512) % 512));
  }
  out.add(Uint8List(1024));
  return out.toBytes();
}

String manifestFor(Map<String, String> files) => [
  for (final MapEntry(:key, :value) in files.entries)
    '${sha256Hex(utf8.encode(value))}  ./$key',
].join('\n');

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mpv_kit_libs_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File writeGz(Uint8List tarBytes) =>
      File('${tmp.path}/b.tar.gz')..writeAsBytesSync(gzip.encode(tarBytes));

  group('readTar', () {
    test('extracts regular files and skips directories', () {
      final entries = readTar(
        tar([('./lib/', '5', ''), ('./lib/a.so', '0', 'AAA')]),
      );
      expect(entries.single.path, 'lib/a.so');
      expect(utf8.decode(entries.single.bytes), 'AAA');
    });

    test('rejects parent-directory traversal', () {
      expect(
        () => readTar(tar([('../evil', '0', 'x')])),
        throwsA(isA<TarFormatException>()),
      );
    });

    test('rejects absolute paths', () {
      expect(
        () => readTar(tar([('/etc/passwd', '0', 'x')])),
        throwsA(isA<TarFormatException>()),
      );
    });

    test('rejects symlinks', () {
      expect(
        () => readTar(tar([('lib/link', '2', '')])),
        throwsA(isA<TarFormatException>()),
      );
    });

    test('detects corrupted headers', () {
      final bytes = tar([('a', '0', 'x')]);
      bytes[0] ^= 1;
      expect(() => readTar(bytes), throwsA(isA<TarFormatException>()));
    });
  });

  group('installBundle', () {
    const files = {'lib/libmpv.so.2': 'MPV', 'LICENSE.LGPL': 'L'};

    Uint8List validTar() => tar([
      for (final MapEntry(:key, :value) in files.entries)
        ('./$key', '0', value),
      ('./MANIFEST.txt', '0', manifestFor(files)),
    ]);

    test('installs a pinned, manifest-consistent bundle', () {
      final archive = writeGz(validTar());
      final libs = installBundle(
        archive,
        sha256Hex(archive.readAsBytesSync()),
        Directory('${tmp.path}/out'),
      );
      expect(libs.map((f) => f.uri.pathSegments.last), ['libmpv.so.2']);
      expect(libs.single.readAsStringSync(), 'MPV');
    });

    test('rejects an archive whose hash does not match the pin', () {
      final archive = writeGz(validTar());
      expect(
        () => installBundle(archive, '0' * 64, Directory('${tmp.path}/out')),
        throwsA(isA<BundleIntegrityException>()),
      );
      expect(Directory('${tmp.path}/out').existsSync(), isFalse);
    });

    test('rejects a file that differs from the manifest', () {
      final archive = writeGz(
        tar([
          ('./lib/libmpv.so.2', '0', 'TAMPERED'),
          ('./LICENSE.LGPL', '0', 'L'),
          ('./MANIFEST.txt', '0', manifestFor(files)),
        ]),
      );
      expect(
        () => installBundle(
          archive,
          sha256Hex(archive.readAsBytesSync()),
          Directory('${tmp.path}/out'),
        ),
        throwsA(isA<BundleIntegrityException>()),
      );
    });

    test('rejects files missing from the manifest', () {
      final archive = writeGz(
        tar([
          ('./lib/libmpv.so.2', '0', 'MPV'),
          ('./LICENSE.LGPL', '0', 'L'),
          ('./lib/extra.so', '0', 'X'),
          ('./MANIFEST.txt', '0', manifestFor(files)),
        ]),
      );
      expect(
        () => installBundle(
          archive,
          sha256Hex(archive.readAsBytesSync()),
          Directory('${tmp.path}/out'),
        ),
        throwsA(isA<BundleIntegrityException>()),
      );
    });

    test('rejects a bundle without manifest', () {
      final archive = writeGz(tar([('./lib/libmpv.so.2', '0', 'MPV')]));
      expect(
        () => installBundle(
          archive,
          sha256Hex(archive.readAsBytesSync()),
          Directory('${tmp.path}/out'),
        ),
        throwsA(isA<BundleIntegrityException>()),
      );
    });
  });

  group('local bundle directory', () {
    Directory makeDir(Map<String, String> files, {String? manifest}) {
      final dir = Directory('${tmp.path}/local');
      for (final MapEntry(:key, :value) in files.entries) {
        File('${dir.path}/$key')
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
      if (manifest != null) {
        File('${dir.path}/MANIFEST.txt').writeAsStringSync(manifest);
      }
      return dir;
    }

    test('only shared libraries are emitted', () {
      final dir = makeDir({
        'lib/libmpv-2.dll': 'a',
        'lib/libmpv.so.2': 'b',
        'lib/libfoo.2.dylib': 'c',
        'lib/libmpv.dll.a': 'x',
        'lib/libmpv.la': 'x',
        'lib/pkgconfig/mpv.pc': 'x',
      });
      expect(sharedLibrariesIn(dir).map((f) => f.uri.pathSegments.last), [
        'libfoo.2.dylib',
        'libmpv-2.dll',
        'libmpv.so.2',
      ]);
    });

    test('verifyDirectory accepts a matching manifest', () {
      const files = {'lib/libmpv.so.2': 'MPV'};
      expect(
        () => verifyDirectory(makeDir(files, manifest: manifestFor(files))),
        returnsNormally,
      );
    });

    test('verifyDirectory rejects a modified file', () {
      final dir = makeDir({
        'lib/libmpv.so.2': 'CHANGED',
      }, manifest: manifestFor({'lib/libmpv.so.2': 'MPV'}));
      expect(
        () => verifyDirectory(dir),
        throwsA(isA<BundleIntegrityException>()),
      );
    });
  });

  test('installBundle replaces an existing extraction atomically', () {
    const files = {'lib/libmpv.so.2': 'NEW'};
    final archive = writeGz(
      tar([
        ('./lib/libmpv.so.2', '0', 'NEW'),
        ('./MANIFEST.txt', '0', manifestFor(files)),
      ]),
    );
    final out = Directory('${tmp.path}/out');
    File('${out.path}/lib/stale.so')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    final libs = installBundle(
      archive,
      sha256Hex(archive.readAsBytesSync()),
      out,
    );
    expect(libs.map((f) => f.uri.pathSegments.last), ['libmpv.so.2']);
    expect(File('${out.path}/lib/stale.so').existsSync(), isFalse);
    // No staging directories are left behind.
    expect(
      tmp.listSync().map(
        (e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last,
      ),
      isNot(contains(startsWith('.staging-'))),
    );
  });

  group('resolvePinnedBundle', () {
    const target = 'linux-x64';
    const files = {'lib/libmpv.so.2': 'MPV', 'LICENSE.LGPL': 'L'};

    Uint8List validTar() => tar([
      for (final MapEntry(:key, :value) in files.entries)
        ('./$key', '0', value),
      ('./MANIFEST.txt', '0', manifestFor(files)),
    ]);

    late Directory cache;
    late Uint8List archiveBytes;
    late String pin;
    var fetches = 0;

    setUp(() {
      cache = Directory('${tmp.path}/cache');
      archiveBytes = Uint8List.fromList(gzip.encode(validTar()));
      pin = sha256Hex(archiveBytes);
      fetches = 0;
    });

    // Fake release download: writes the valid archive and counts calls.
    Future<void> fetch(File archive) async {
      fetches++;
      archive.parent.createSync(recursive: true);
      archive.writeAsBytesSync(archiveBytes);
    }

    // A fetch that must never run (the cache already holds a good archive).
    Future<void> noFetch(File archive) async =>
        throw StateError('fetch must not run');

    File archiveFile() => File('${cache.path}/libmpv-$target.tar.gz');
    File stampFile() => File('${cache.path}/$target.ok');

    Future<List<File>> resolve(Future<void> Function(File) fetcher) =>
        resolvePinnedBundle(
          cache: cache,
          target: target,
          pinnedSha256: pin,
          fetch: fetcher,
        );

    test('reuses a matching stamp with libraries', () async {
      File('${cache.path}/$target/lib/libmpv.so.2')
        ..createSync(recursive: true)
        ..writeAsStringSync('MPV');
      stampFile().writeAsStringSync(pin);
      final libs = await resolve(noFetch);
      expect(libs.map((f) => f.uri.pathSegments.last), ['libmpv.so.2']);
    });

    test('reinstalls when the extracted directory is gone', () async {
      // A cleaned cache: archive and stamp survive, the extraction does not.
      cache.createSync(recursive: true);
      archiveFile().writeAsBytesSync(archiveBytes);
      stampFile().writeAsStringSync(pin);
      final libs = await resolve(noFetch);
      expect(libs, isNotEmpty);
      expect(
        File('${cache.path}/$target/lib/libmpv.so.2').existsSync(),
        isTrue,
      );
    });

    test('reinstalls when lib/ is empty', () async {
      cache.createSync(recursive: true);
      Directory('${cache.path}/$target/lib').createSync(recursive: true);
      archiveFile().writeAsBytesSync(archiveBytes);
      stampFile().writeAsStringSync(pin);
      final libs = await resolve(noFetch);
      expect(libs, isNotEmpty);
    });

    test('downloads when the cached archive does not match the pin', () async {
      cache.createSync(recursive: true);
      archiveFile().writeAsBytesSync(utf8.encode('not the pinned archive'));
      final libs = await resolve(fetch);
      expect(fetches, 1);
      expect(libs, isNotEmpty);
      expect(stampFile().readAsStringSync(), pin);
    });

    test('fails loudly when the bundle has no shared libraries', () async {
      // MANIFEST-consistent but without any lib/ entry.
      const bare = {'LICENSE.LGPL': 'L'};
      final bareBytes = Uint8List.fromList(
        gzip.encode(
          tar([
            ('./LICENSE.LGPL', '0', 'L'),
            ('./MANIFEST.txt', '0', manifestFor(bare)),
          ]),
        ),
      );
      pin = sha256Hex(bareBytes);
      Future<void> fetchBare(File archive) async {
        archive.parent.createSync(recursive: true);
        archive.writeAsBytesSync(bareBytes);
      }

      await expectLater(
        resolve(fetchBare),
        throwsA(
          isA<BundleIntegrityException>().having(
            (e) => e.message,
            'message',
            contains('no shared libraries'),
          ),
        ),
      );
      expect(stampFile().existsSync(), isFalse);
    });
  });

  test('bundleTarget covers the six release targets only', () {
    expect(bundleTarget('windows', 'arm64'), 'windows-arm64');
    expect(bundleTarget('macos', 'x64'), 'macos-x64');
    expect(bundleTarget('linux', 'arm64'), 'linux-arm64');
    expect(bundleTarget('android', 'arm64'), isNull);
    expect(bundleTarget('linux', 'riscv64'), isNull);
  });

  test('parseManifest accepts sha256sum and shasum output', () {
    final h = '1' * 64;
    expect(parseManifest('$h  ./lib/a\n$h *./b\n'), {'lib/a': h, 'b': h});
    expect(
      () => parseManifest('nothex  ./a'),
      throwsA(isA<BundleIntegrityException>()),
    );
  });
}
