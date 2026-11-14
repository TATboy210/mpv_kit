// Dependency compatibility check (v0.1.2): the resolved pubspec.lock must
// contain every package an app commonly combines with mpv_kit, at no less
// than the verified version. Run from the repo root after `flutter pub get`:
//   dart run tools/check_deps.dart
//
// Exit 0 = all present; exit 1 lists the missing/too-old packages.
import 'dart:io';

/// Package -> lowest verified version (the one the example resolves).
/// (0.1.3 dropped the example's unused deps — `path_provider`, `crypto`,
/// `flutter_video_thumbnail_plus`, `xdg_directories`, `intl`, `logger` and
/// `i18n` — so the compatibility matrix shrinks to what actually resolves.)
const _verified = <String, String>{
  'file_picker': '13.3.3',
  'shared_preferences': '2.5.6',
  'desktop_drop': '0.8.4',
  'path': '1.9.1',
  'crypto': '3.0.8',
  'ffi': '2.2.0',
  'cross_file': '0.3.5+5',
};

/// Compares dotted versions; a `+build` suffix is compared last.
int _compare(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[.+]')).map((e) => int.tryParse(e) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

void main() {
  final lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    stderr.writeln('pubspec.lock missing; run `flutter pub get` first');
    exit(1);
  }
  final text = lock.readAsStringSync();
  var failed = false;
  _verified.forEach((name, min) {
    final m = RegExp(
      '^  $name:\n(?:    .*\n)*?    version: "([^"]+)"',
      multiLine: true,
    ).firstMatch(text);
    final got = m?.group(1);
    if (got == null || _compare(got, min) < 0) {
      failed = true;
      stderr.writeln('FAIL $name: resolved ${got ?? 'nothing'}, need >= $min');
    } else {
      stdout.writeln('ok   $name $got');
    }
  });
  exit(failed ? 1 : 0);
}
