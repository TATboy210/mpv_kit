/// Child-process scenario for `library_test.dart`: run `MpvLibrary.open` in a
/// process whose environment the test controls.
///
/// `MPV_KIT_LIBMPV_PATH` is read from the process environment, which a running
/// Dart test cannot change for itself, and the loader caches the first
/// successful load per process. Both are why these cases run as a separate
/// process (like `dispose_with_children.dart`).
///
/// Usage: `dart run test/fixtures/open_probe.dart [explicit-path]`.
/// Prints exactly one JSON line and exits 0:
/// `{"ok":true,"resolvedPath":...}` when the library loaded, or
/// `{"ok":false,"attempts":{candidate: reason}}` on [MpvLibraryNotFound].
library;

import 'dart:convert';

import 'package:mpv_kit/mpv_kit.dart';

void main(List<String> args) {
  final explicit = args.isEmpty ? null : args.first;
  try {
    MpvLibrary.open(path: explicit);
    print(jsonEncode({'ok': true, 'resolvedPath': MpvLibrary.resolvedPath}));
  } on MpvLibraryNotFound catch (e) {
    print(jsonEncode({'ok': false, 'attempts': e.attempts}));
  }
}
