// Pins the release bundles of TAG in packages/mpv_kit_libs/lib/src/bundles.dart.
//
// usage:
//   dart run tools/pin_bundles.dart <tag>      rewrite the pins
//   dart run tools/pin_bundles.dart --check    verify pins against the
//                                              pinned tag's SHA256SUMS (CI)
// Reads the release's SHA256SUMS (published by the release workflow).
// Uses HTTPS_PROXY when set.
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tools/pin_bundles.dart <tag> | --check');
    exit(64);
  }
  final check = args.single == '--check';
  final tag = check ? pinnedTag() : args.single;
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

  if (check) {
    final current = pinnedSha256();
    var bad = 0;
    for (final target in pins.keys) {
      final published = pins[target]!;
      final pinned = current[target];
      if (pinned == null) {
        stderr.writeln('PINS FAIL: $target has no pin in bundles.dart');
        bad++;
      } else if (pinned != published) {
        stderr.writeln(
            'PINS FAIL: $target pinned $pinned but $tag published $published');
        bad++;
      }
    }
    for (final target in current.keys) {
      if (!pins.containsKey(target)) {
        stderr.writeln(
            'PINS FAIL: bundles.dart pins $target which $tag does not publish');
        bad++;
      }
    }
    if (bad > 0) {
      stderr.writeln('PINS: $bad failure(s) against $tag');
      exit(1);
    }
    stdout.writeln('PINS OK tag=$tag targets=${pins.length}');
    return;
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

String pinnedTag() {
  final m =
      RegExp(r"const bundleTag = '([^']*)';").firstMatch(pinnedSource());
  if (m == null) {
    stderr.writeln('bundles.dart: cannot read bundleTag');
    exit(1);
  }
  return m.group(1)!;
}

Map<String, String> pinnedSha256() {
  final block = RegExp(r'const bundleSha256 = <String, String>\{([^}]*)\};')
      .firstMatch(pinnedSource());
  if (block == null) {
    stderr.writeln('bundles.dart: cannot read bundleSha256');
    exit(1);
  }
  return {
    for (final m in RegExp(r"'([a-z0-9-]+)': '([0-9a-f]{64})'")
        .allMatches(block.group(1)!))
      m.group(1)!: m.group(2)!,
  };
}

String pinnedSource() =>
    File('packages/mpv_kit_libs/lib/src/bundles.dart').readAsStringSync();
