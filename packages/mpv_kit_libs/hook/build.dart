// Build hook: provides libmpv (LGPL build from the mpv_kit release
// workflow) and its dependency closure as bundled code assets for the
// target OS/architecture.
//
// Sources, in order:
//   1. user define `libmpv_bundle`: path to a local libmpv-<target>.tar.gz
//      or extracted bundle directory (offline / custom builds);
//   2. the pinned GitHub release asset (lib/src/bundles.dart), verified by
//      sha256 and by the bundle's own per-file MANIFEST.
// If neither applies, no asset is emitted and mpv_kit falls back to
// MPV_KIT_LIBMPV_PATH or a system libmpv.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mpv_kit_libs/src/bundle.dart';
import 'package:mpv_kit_libs/src/bundles.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final target = bundleTarget(
      code.targetOS.name,
      code.targetArchitecture.name,
    );
    if (target == null) return;

    final libs = await _resolve(input, output, target);
    for (final lib in libs) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          // Asset ids only need to be unique; mpv_kit opens libmpv by file
          // name, which the OS loader resolves in the bundle location.
          name: lib.uri.pathSegments.last,
          linkMode: DynamicLoadingBundled(),
          file: lib.uri,
        ),
      );
    }
  });
}

Future<List<File>> _resolve(
  BuildInput input,
  BuildOutputBuilder output,
  String target,
) async {
  final local = input.userDefines.path('libmpv_bundle');
  if (local != null) {
    output.dependencies.add(local);
    final dir = Directory.fromUri(local);
    if (dir.existsSync()) {
      // Bundles produced by package.sh carry a manifest; verify it when
      // present so a half-copied directory fails loudly.
      if (File('${dir.path}/MANIFEST.txt').existsSync()) verifyDirectory(dir);
      return sharedLibrariesIn(dir);
    }
    // An archive supplied by the user is trusted by path, not by pin.
    final archive = File.fromUri(local);
    final bytes = archive.readAsBytesSync();
    return installBundle(
      archive,
      sha256Hex(bytes),
      Directory.fromUri(input.outputDirectoryShared.resolve('local-$target/')),
    );
  }

  final pinned = bundleSha256[target];
  if (bundleTag.isEmpty || pinned == null) return const [];
  final cache = input.outputDirectoryShared.resolve('$bundleTag/');
  final archive = File.fromUri(cache.resolve('libmpv-$target.tar.gz'));
  final extracted = Directory.fromUri(cache.resolve('$target/'));
  final stamp = File.fromUri(cache.resolve('$target.ok'));
  if (stamp.existsSync() && stamp.readAsStringSync() == pinned) {
    return sharedLibrariesIn(extracted);
  }
  if (!archive.existsSync() || sha256Hex(archive.readAsBytesSync()) != pinned) {
    await download(bundleUrl(target), archive);
  }
  final libs = installBundle(archive, pinned, extracted);
  stamp.writeAsStringSync(pinned);
  return libs;
}
