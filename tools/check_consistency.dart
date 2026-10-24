// Build/doc consistency checker (BUILD-03): every invariant is anchored on
// an exact file/line shape so drift is detectable. Run from the repo root:
//   dart run tools/check_consistency.dart
//
// Exit 0 = all invariants hold; exit 1 prints every failure. The docs move
// to the truth sources — never the reverse.
import 'dart:io';

var failures = 0;

void ok(String name) => print('CONSISTENCY ok $name');

void fail(String name, String detail) {
  failures++;
  print('CONSISTENCY FAIL $name: $detail');
}

String read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    fail('read', '$path missing');
    return '';
  }
  return f.readAsStringSync();
}

void expectContains(String name, String haystack, String needle, String source) {
  if (haystack.contains(needle)) {
    ok(name);
  } else {
    fail(name, '$source must contain "$needle"');
  }
}

/// Matches `v0.41.0-1113-...` style mpv version mentions.
final mpvVersionPattern = RegExp(r'v?0\.\d+\.\d+(-\d+-g[0-9a-f]+)?');

void main() {
  final mpvVersion =
      read('native/mpv/MPV_VERSION').trim(); // v0.41.0-1113-gfd9265a905
  final mpvBase =
      mpvVersion.startsWith('v') ? mpvVersion.substring(1) : mpvVersion;
  final mpvShort = mpvBase.split('-g').first; // 0.41.0-1113
  final mpvUpToMinor =
      mpvBase.split('-').first; // 0.41.0

  // --- mpv version mentions ---
  final readme = read('README.md');
  expectContains('mpv-version-readme-exact', readme, mpvVersion, 'README.md');
  expectContains('mpv-version-readme-base', readme, mpvUpToMinor, 'README.md');
  final architecture = read('docs/ARCHITECTURE.md');
  expectContains(
      'mpv-version-architecture', architecture, mpvUpToMinor, 'docs/ARCHITECTURE.md');
  // Any mpv-looking version in the README header (first 30 lines — the
  // package-dependency section further down legitimately contains
  // mpv_kit's own ^0.1.0 versions) that is neither the base nor the exact
  // vendor version is drift (e.g. a stale "0.40.0").
  final newline = String.fromCharCode(10);
  final readmeHeader = readme.split(newline).take(30).join(newline);
  for (final m in mpvVersionPattern.allMatches(readmeHeader)) {
    final v = m.group(0)!;
    // Skip mpv_kit's own package versions (`^0.1.0-dev.3`, `0.1.0-dev.3`):
    // they continue with "-dev.", a scheme libmpv stamps never use.
    final end = m.end;
    if (readmeHeader.length >= end + 5 &&
        readmeHeader.substring(end, end + 5) == '-dev.') {
      continue;
    }
    final start = m.start;
    if (start > 0 && readmeHeader[start - 1] == '^') continue;
    if (v != mpvVersion && !mpvBase.startsWith(v) && !v.startsWith(mpvUpToMinor)) {
      fail('mpv-version-readme-foreign', 'README header mentions "$v" outside $mpvVersion');
    }
  }
  ok('mpv-version-readme-foreign');

  // --- macOS deployment target ---
  const target = '12.0';
  final pbxproj =
      read('example/macos/Runner.xcodeproj/project.pbxproj');
  final pbxCount =
      'MACOSX_DEPLOYMENT_TARGET = $target;'.allMatches(pbxproj).length;
  if (pbxCount >= 3) {
    ok('macos-target-pbxproj');
  } else {
    fail('macos-target-pbxproj',
        'expected >= 3 occurrences of MACOSX_DEPLOYMENT_TARGET = $target, found $pbxCount');
  }
  expectContains('macos-target-build-sh', read('native/build/build.sh'),
      'MACOSX_DEPLOYMENT_TARGET=\${MACOSX_DEPLOYMENT_TARGET:-$target}', 'build.sh');
  expectContains('macos-target-release', read('.github/workflows/release.yml'),
      "MACOSX_DEPLOYMENT_TARGET: '$target'", 'release.yml');
  final podspec =
      read('packages/mpv_kit_video/macos/mpv_kit_video.podspec');
  final podMatch = RegExp(r"s\.platform\s*=\s*:osx,\s*'(\d+\.\d+)'").firstMatch(podspec);
  if (podMatch == null) {
    fail('macos-target-podspec', 'no s.platform :osx declaration');
  } else {
    final podTarget = double.tryParse(podMatch.group(1)!) ?? 0;
    if (podTarget >= double.parse(target)) {
      ok('macos-target-podspec');
    } else {
      fail('macos-target-podspec',
          'podspec platform ${podMatch.group(1)} is below the $target floor');
    }
  }

  // --- SDK constraints: identical across all workspace pubspecs ---
  const pubspecs = [
    'pubspec.yaml',
    'packages/mpv_kit/pubspec.yaml',
    'packages/mpv_kit_video/pubspec.yaml',
    'packages/mpv_kit_libs/pubspec.yaml',
    'example/pubspec.yaml',
  ];
  final constraints = <String, String>{};
  for (final p in pubspecs) {
    final m = RegExp(r'sdk:\s*(\^3\.\d+\.\d+)').firstMatch(read(p));
    if (m == null) {
      fail('sdk-constraints', '$p has no sdk: constraint');
    } else {
      constraints[p] = m.group(1)!;
    }
  }
  if (constraints.length == pubspecs.length) {
    final distinct = constraints.values.toSet();
    if (distinct.length == 1) {
      ok('sdk-constraints');
    } else {
      fail('sdk-constraints', 'mismatched sdk constraints: $constraints');
    }
  }

  // --- README Dart floor matches the constraint ---
  final sdkMinor = constraints.values
      .map((c) => RegExp(r'\^3\.(\d+)\.').firstMatch(c)?.group(1))
      .whereType<String>()
      .toSet();
  if (sdkMinor.length == 1 &&
      readme.contains(RegExp('Dart 3\\.' + sdkMinor.first))) {
    ok('readme-dart-floor');
  } else {
    fail('readme-dart-floor',
        'README must state Dart 3.${sdkMinor.join('/')} to match the pubspec constraints');
  }

  // --- FFmpeg version ---
  final ffmpeg = read('native/build/ffmpeg.sh');
  final ffmpegMatch = RegExp(r"FFMPEG_VERSION=([^#\n]+)").firstMatch(ffmpeg);
  if (ffmpegMatch == null) {
    fail('ffmpeg-version', 'native/build/ffmpeg.sh has no FFMPEG_VERSION');
  } else {
    final v = ffmpegMatch.group(1)!.trim();
    expectContains('ffmpeg-version-architecture', architecture, v,
        'docs/ARCHITECTURE.md');
  }

  // --- reverse-engineering doc provenance date ---
  final re01 = read('docs/reverse-engineering/01-libmpv-render-pipeline.md');
  if (re01.contains('2023-09-24')) {
    fail('reverse-eng-provenance',
        'the libmpv render-pipeline doc still carries the wrong 2023-09-24 snapshot date');
  } else {
    ok('reverse-eng-provenance');
  }

  if (failures > 0) {
    print('CONSISTENCY: $failures failure(s)');
    exit(1);
  }
  print('CONSISTENCY: all invariants hold');
}
