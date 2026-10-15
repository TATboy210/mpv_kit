// Pins the release bundles of TAG in packages/mpv_kit_libs/lib/src/bundles.dart.
//
// usage: dart run tools/pin_bundles.dart <tag>
// Reads the release's SHA256SUMS (published by the release workflow).
// Uses HTTPS_PROXY when set.
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tools/pin_bundles.dart <tag>');
    exit(64);
  }
  final tag = args.single;
  final url = Uri.https(
    'github.com',
    '/TATboy210/mpv_kit/releases/download/$tag/SHA256SUMS',
  );
  final client = HttpClient();
  final proxy = Platform.environment['HTTPS_PROXY'];
  if (proxy != null) {
    final p = Uri.parse(proxy);
    client.findProxy = (_) => 'PROXY ${p.host}:${p.port}';
  }
  final res = await (await client.getUrl(url)).close();
  if (res.statusCode != 200) {
    stderr.writeln('$url: HTTP ${res.statusCode}');
    exit(1);
  }
  final sums = await res.transform(const SystemEncoding().decoder).join();
  client.close();

  // "<sha256>  libmpv-<target>.tar.gz"
  final line = RegExp(r'^([0-9a-f]{64})\s+\*?libmpv-([a-z0-9-]+)\.tar\.gz$');
  final pins = <String, String>{
    for (final m in sums.split('\n').map((l) => line.firstMatch(l.trim())))
      if (m != null) m[2]!: m[1]!,
  };
  if (pins.isEmpty) {
    stderr.writeln('no bundles in SHA256SUMS');
    exit(1);
  }

  final file = File('packages/mpv_kit_libs/lib/src/bundles.dart');
  var src = file.readAsStringSync();
  src = src.replaceFirst(
    RegExp(r"const bundleTag = '[^']*';"),
    "const bundleTag = '$tag';",
  );
  final entries = (pins.keys.toList()..sort())
      .map((t) => "  '$t': '${pins[t]}',")
      .join('\n');
  src = src.replaceFirst(
    RegExp(r'const bundleSha256 = <String, String>\{[^}]*\};'),
    'const bundleSha256 = <String, String>{\n$entries\n};',
  );
  file.writeAsStringSync(src);
  stdout.writeln('pinned ${pins.length} bundles of $tag');
}
