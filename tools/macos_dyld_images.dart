/// In-process proof of which images a staged libmpv loads on macOS
/// (quick 261030-3pc).
///
/// The `integration-test (macos-15, ...)` job of native-verify.yml installs no
/// Homebrew formula; the staged libmpv and its dependency closure sit in one
/// directory with `@loader_path` install names (tools/stage_macos_closure.sh).
/// This probe makes that checkable at runtime: it opens the library the same
/// way `MpvLibrary` does (`DynamicLibrary.open`), asks dyld for every loaded
/// image and asserts that the dependencies came from the staged directory and
/// that none came from the Homebrew prefix.
///
/// usage:
///   dart tools/macos_dyld_images.dart <libmpv.dylib> <homebrew-prefix>
///
/// output:
///   MACOS-DYLD api=<major>.<minor> libmpv=<path>
///   MACOS-DYLD image=<path>              every image outside /usr/lib and
///                                        /System
///   MACOS-DYLD summary staged=<n> homebrew=<m> libplacebo=<path-or-none>
///   MACOS-DYLD fail <reason>             on a failed assertion, exit 1
///   MACOS-DYLD usage: ...                wrong arguments or not macOS, exit 2
///
/// exit codes: 0 ok; 1 failed assertion; 2 usage error.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// The staged dylibs a working closure has at least: libmpv itself plus one
/// dependency.
const _minStaged = 2;

/// Image paths under these prefixes belong to the OS (dyld shared cache) and
/// are not part of the closure.
const _osPrefixes = ['/usr/lib/', '/System/'];

/// Reads the NUL-terminated UTF-8 string at [p].
String _cString(Pointer<Uint8> p) {
  var length = 0;
  while (p[length] != 0) {
    length++;
  }
  return utf8.decode(p.asTypedList(length));
}

/// Symlink-resolved [path], or [path] unchanged when it cannot be resolved.
String _resolved(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}

/// Whether [path] lies inside directory [dir] (given without a trailing `/`).
bool _isUnder(String path, String dir) => path.startsWith('$dir/');

void main(List<String> args) {
  if (args.length != 2 || !Platform.isMacOS) {
    stderr.writeln(
      'MACOS-DYLD usage: dart tools/macos_dyld_images.dart '
      '<libmpv.dylib> <homebrew-prefix> (macOS only)',
    );
    exit(2);
  }
  final libmpvPath = args[0];
  final prefix = Directory(args[1]).resolveSymbolicLinksSync();
  final stagedDir = File(libmpvPath).parent.resolveSymbolicLinksSync();

  // Same call as MpvLibrary; the dependencies resolve through the install
  // names of the staged files.
  final mpv = DynamicLibrary.open(libmpvPath);
  final apiVersion = mpv
      .lookupFunction<UnsignedLong Function(), int Function()>(
        'mpv_client_api_version',
      )();
  stdout.writeln(
    'MACOS-DYLD api=${apiVersion >> 16}.${apiVersion & 0xffff} '
    'libmpv=$libmpvPath',
  );

  final process = DynamicLibrary.process();
  final imageCount = process.lookupFunction<Uint32 Function(), int Function()>(
    '_dyld_image_count',
  );
  final imageName = process
      .lookupFunction<
        Pointer<Uint8> Function(Uint32),
        Pointer<Uint8> Function(int)
      >('_dyld_get_image_name');

  var staged = 0;
  var homebrew = 0;
  String? libplacebo;
  var libplaceboStaged = false;
  for (var i = 0; i < imageCount(); i++) {
    final name = _cString(imageName(i));
    if (_osPrefixes.any(name.startsWith)) continue;
    stdout.writeln('MACOS-DYLD image=$name');
    final real = _resolved(name);
    if (_isUnder(real, stagedDir)) staged++;
    if (_isUnder(real, prefix)) homebrew++;
    final base = name.substring(name.lastIndexOf('/') + 1);
    if (libplacebo == null && base.startsWith('libplacebo.')) {
      libplacebo = name;
      libplaceboStaged = _isUnder(real, stagedDir);
    }
  }
  stdout.writeln(
    'MACOS-DYLD summary staged=$staged homebrew=$homebrew '
    'libplacebo=${libplacebo ?? 'none'}',
  );

  String? failure;
  if (homebrew > 0) {
    failure = '$homebrew image(s) loaded from the Homebrew prefix $prefix';
  } else if (libplacebo == null) {
    failure = 'libplacebo is not loaded';
  } else if (!libplaceboStaged) {
    failure = 'libplacebo is not from $stagedDir: $libplacebo';
  } else if (staged < _minStaged) {
    failure = 'only $staged image(s) loaded from $stagedDir';
  }
  if (failure != null) {
    stderr.writeln('MACOS-DYLD fail $failure');
    exit(1);
  }
}
