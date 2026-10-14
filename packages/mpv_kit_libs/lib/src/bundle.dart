/// 发行包的获取、校验与解包（供 build hook 使用，可独立测试）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'tar.dart';

/// A bundle failed verification; never use it.
final class BundleIntegrityException implements Exception {
  BundleIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'BundleIntegrityException: $message';
}

/// Bundle target key (`<os>-<arch>`) used in release asset names, or null
/// when no bundle is built for the combination.
String? bundleTarget(String os, String arch) => switch ((os, arch)) {
      ('windows', 'x64') => 'windows-x64',
      ('windows', 'arm64') => 'windows-arm64',
      ('linux', 'x64') => 'linux-x64',
      ('linux', 'arm64') => 'linux-arm64',
      ('macos', 'arm64') => 'macos-arm64',
      ('macos', 'x64') => 'macos-x64',
      _ => null,
    };

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Parses `MANIFEST.txt` (`<sha256>  ./<path>` lines) into path → hash.
Map<String, String> parseManifest(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^([0-9a-f]{64}) [ *]?(.+)$').firstMatch(t);
    if (m == null) throw BundleIntegrityException('bad manifest line: $t');
    var path = m.group(2)!;
    if (path.startsWith('./')) path = path.substring(2);
    out[path] = m.group(1)!;
  }
  return out;
}

/// Checks every archive entry against the bundle's own manifest: same set
/// of files, same hashes. The manifest itself is covered by the pinned
/// archive hash.
void verifyEntries(List<TarEntry> entries) {
  final manifestEntry = entries.where((e) => e.path == 'MANIFEST.txt');
  if (manifestEntry.length != 1) {
    throw BundleIntegrityException('bundle has no MANIFEST.txt');
  }
  final manifest =
      parseManifest(String.fromCharCodes(manifestEntry.single.bytes));
  final files = {
    for (final e in entries)
      if (e.path != 'MANIFEST.txt') e.path: e,
  };
  if (files.length != manifest.length ||
      !manifest.keys.every(files.containsKey)) {
    throw BundleIntegrityException('bundle contents differ from MANIFEST.txt');
  }
  for (final MapEntry(key: path, value: hash) in manifest.entries) {
    if (sha256Hex(files[path]!.bytes) != hash) {
      throw BundleIntegrityException('sha256 mismatch for $path');
    }
  }
}

/// Extracts a verified archive into [dir] (created fresh) and returns the
/// paths of the shared libraries under `lib/`.
List<File> installBundle(File archive, String expectedSha256, Directory dir) {
  final bytes = archive.readAsBytesSync();
  final actual = sha256Hex(bytes);
  if (actual != expectedSha256) {
    throw BundleIntegrityException(
        '${archive.path}: sha256 $actual, expected $expectedSha256');
  }
  final entries = readTar(Uint8List.fromList(gzip.decode(bytes)));
  verifyEntries(entries);

  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final libs = <File>[];
  for (final e in entries) {
    final file = File('${dir.path}/${e.path}');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(e.bytes, flush: true);
    if (e.path.startsWith('lib/')) libs.add(file);
  }
  if (!Platform.isWindows) {
    // tar modes are not restored; shared libraries need to be mappable.
    Process.runSync('chmod', ['-R', 'u+rwX,go+rX', dir.path]);
  }
  return libs;
}

/// Downloads [url] to [target] (honours HTTPS_PROXY/HTTP_PROXY/NO_PROXY).
Future<void> download(Uri url, File target) async {
  final client = HttpClient()
    ..findProxy = (uri) => HttpClient.findProxyFromEnvironment(uri,
        environment: Platform.environment);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    target.parent.createSync(recursive: true);
    final part = File('${target.path}.part');
    await response.pipe(part.openWrite());
    part.renameSync(target.path);
  } finally {
    client.close(force: true);
  }
}
