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
      final entries = readTar(tar([
        ('./lib/', '5', ''),
        ('./lib/a.so', '0', 'AAA'),
      ]));
      expect(entries.single.path, 'lib/a.so');
      expect(utf8.decode(entries.single.bytes), 'AAA');
    });

    test('rejects parent-directory traversal', () {
      expect(() => readTar(tar([('../evil', '0', 'x')])),
          throwsA(isA<TarFormatException>()));
    });

    test('rejects absolute paths', () {
      expect(() => readTar(tar([('/etc/passwd', '0', 'x')])),
          throwsA(isA<TarFormatException>()));
    });

    test('rejects symlinks', () {
      expect(() => readTar(tar([('lib/link', '2', '')])),
          throwsA(isA<TarFormatException>()));
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
      final libs = installBundle(archive, sha256Hex(archive.readAsBytesSync()),
          Directory('${tmp.path}/out'));
      expect(libs.map((f) => f.uri.pathSegments.last), ['libmpv.so.2']);
      expect(libs.single.readAsStringSync(), 'MPV');
    });

    test('rejects an archive whose hash does not match the pin', () {
      final archive = writeGz(validTar());
      expect(
          () => installBundle(
              archive, '0' * 64, Directory('${tmp.path}/out')),
          throwsA(isA<BundleIntegrityException>()));
      expect(Directory('${tmp.path}/out').existsSync(), isFalse);
    });

    test('rejects a file that differs from the manifest', () {
      final archive = writeGz(tar([
        ('./lib/libmpv.so.2', '0', 'TAMPERED'),
        ('./LICENSE.LGPL', '0', 'L'),
        ('./MANIFEST.txt', '0', manifestFor(files)),
      ]));
      expect(
          () => installBundle(archive, sha256Hex(archive.readAsBytesSync()),
              Directory('${tmp.path}/out')),
          throwsA(isA<BundleIntegrityException>()));
    });

    test('rejects files missing from the manifest', () {
      final archive = writeGz(tar([
        ('./lib/libmpv.so.2', '0', 'MPV'),
        ('./LICENSE.LGPL', '0', 'L'),
        ('./lib/extra.so', '0', 'X'),
        ('./MANIFEST.txt', '0', manifestFor(files)),
      ]));
      expect(
          () => installBundle(archive, sha256Hex(archive.readAsBytesSync()),
              Directory('${tmp.path}/out')),
          throwsA(isA<BundleIntegrityException>()));
    });

    test('rejects a bundle without manifest', () {
      final archive = writeGz(tar([('./lib/libmpv.so.2', '0', 'MPV')]));
      expect(
          () => installBundle(archive, sha256Hex(archive.readAsBytesSync()),
              Directory('${tmp.path}/out')),
          throwsA(isA<BundleIntegrityException>()));
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
    expect(parseManifest('$h  ./lib/a\n$h *./b\n'),
        {'lib/a': h, 'b': h});
    expect(() => parseManifest('nothex  ./a'),
        throwsA(isA<BundleIntegrityException>()));
  });
}
