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
  final manifest = parseManifest(
    String.fromCharCodes(manifestEntry.single.bytes),
  );
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

/// Whether [name] is a shared library the OS loader can map.
bool isSharedLibrary(String name) =>
    name.endsWith('.dll') ||
    name.endsWith('.dylib') ||
    RegExp(r'\.so(\.\d+)*$').hasMatch(name);

/// Shared libraries directly under `<dir>/lib`; symlinks are skipped (the
/// files they point at are listed themselves).
List<File> sharedLibrariesIn(Directory dir) {
  final lib = Directory('${dir.path}/lib');
  if (!lib.existsSync()) return const [];
  return [
    for (final e in lib.listSync(followLinks: false))
      if (e is File && isSharedLibrary(e.uri.pathSegments.last)) e,
  ]..sort((a, b) => a.path.compareTo(b.path));
}

/// Verifies an extracted bundle directory against its MANIFEST.txt.
void verifyDirectory(Directory dir) {
  final manifestFile = File('${dir.path}/MANIFEST.txt');
  if (!manifestFile.existsSync()) {
    throw BundleIntegrityException('${dir.path} has no MANIFEST.txt');
  }
  final manifest = parseManifest(manifestFile.readAsStringSync());
  for (final MapEntry(key: path, value: hash) in manifest.entries) {
    final f = File('${dir.path}/$path');
    if (!f.existsSync() || sha256Hex(f.readAsBytesSync()) != hash) {
      throw BundleIntegrityException(
        '${dir.path}: $path does not match MANIFEST.txt',
      );
    }
  }
}

/// Extracts a verified archive into [dir] and returns its shared libraries.
///
/// Extraction goes to a sibling temporary directory that is renamed into
/// place, so concurrent builds never observe a half-written bundle.
List<File> installBundle(File archive, String expectedSha256, Directory dir) {
  final bytes = archive.readAsBytesSync();
  final actual = sha256Hex(bytes);
  if (actual != expectedSha256) {
    throw BundleIntegrityException(
      '${archive.path}: sha256 $actual, expected $expectedSha256',
    );
  }
  final entries = readTar(Uint8List.fromList(gzip.decode(bytes)));
  verifyEntries(entries);

  dir.parent.createSync(recursive: true);
  final staging = dir.parent.createTempSync('.staging-');
  try {
    for (final e in entries) {
      final file = File('${staging.path}/${e.path}');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(e.bytes, flush: true);
    }
    if (!Platform.isWindows) {
      // tar modes are not restored; shared libraries need to be mappable.
      Process.runSync('chmod', ['-R', 'u+rwX,go+rX', staging.path]);
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    staging.renameSync(dir.path);
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
  return sharedLibrariesIn(dir);
}

/// Whether [dir] has a MANIFEST.txt and every shared library it lists
/// directly under `lib/` exists (at least one must be listed).
///
/// Nested paths (`lib/x/y.so`) and non-library files are ignored, matching
/// what [sharedLibrariesIn] reports.
bool _hasAllManifestLibraries(Directory dir) {
  final manifestFile = File('${dir.path}/MANIFEST.txt');
  if (!manifestFile.existsSync()) return false;
  final expected = [
    for (final path in parseManifest(manifestFile.readAsStringSync()).keys)
      if (path.startsWith('lib/') &&
          !path.substring(4).contains('/') &&
          isSharedLibrary(path.substring(4)))
        path,
  ];
  return expected.isNotEmpty &&
      expected.every((path) => File('${dir.path}/$path').existsSync());
}

/// Resolves the pinned release bundle for [target] from the build-hook
/// [cache] directory and returns its shared libraries.
///
/// Cache layout (names shared with the hook): archive
/// `libmpv-<target>.tar.gz`, extracted directory `<target>/` and the stamp
/// `<target>.ok` holding the pinned sha256. [fetch] writes the release
/// archive to the file it is given (the hook passes a download).
Future<List<File>> resolvePinnedBundle({
  required Directory cache,
  required String target,
  required String pinnedSha256,
  required Future<void> Function(File archive) fetch,
}) async {
  final archive = File('${cache.path}/libmpv-$target.tar.gz');
  final extracted = Directory('${cache.path}/$target');
  final stamp = File('${cache.path}/$target.ok');
  if (stamp.existsSync() && stamp.readAsStringSync() == pinnedSha256) {
    // A cleaned cache can leave a valid stamp over a missing, empty or
    // partial extraction (e.g. libmpv gone while one dependency remains).
    // Trust the stamp only while every shared library the MANIFEST lists
    // under lib/ is really there; otherwise fall through and reinstall (the
    // archive is re-hashed against the pin before it is reused). Existence
    // only: the files were verified when they were extracted.
    if (_hasAllManifestLibraries(extracted)) {
      return sharedLibrariesIn(extracted);
    }
  }
  if (!archive.existsSync() ||
      sha256Hex(archive.readAsBytesSync()) != pinnedSha256) {
    await fetch(archive);
  }
  final libs = installBundle(archive, pinnedSha256, extracted);
  if (libs.isEmpty) {
    // No stamp is written, so the next build retries instead of trusting a
    // bundle that would silently emit no libmpv.
    throw BundleIntegrityException(
      '${archive.path}: no shared libraries under lib/ after installation',
    );
  }
  stamp.writeAsStringSync(pinnedSha256);
  return libs;
}

/// Downloads [url] to [target] (honours HTTPS_PROXY/HTTP_PROXY/NO_PROXY).
///
/// Writes to a uniquely named temporary file that is renamed into place.
Future<void> download(Uri url, File target) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 30)
    ..findProxy = (uri) => HttpClient.findProxyFromEnvironment(
      uri,
      environment: Platform.environment,
    );
  target.parent.createSync(recursive: true);
  final part = File(
    '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.part',
  );
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    // A stalled transfer must not hang the build forever.
    await response.timeout(const Duration(seconds: 60)).pipe(part.openWrite());
    part.renameSync(target.path);
  } finally {
    client.close(force: true);
    if (part.existsSync()) part.deleteSync();
  }
}
