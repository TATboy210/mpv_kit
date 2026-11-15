/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
///
/// v0.1.3 rebuilds the same mpv 0.42.0 vendor (b0841e8c) as v0.1.1 with the
/// newer CI toolchain: the Linux artifacts are byte-identical to v0.1.1,
/// macOS/Windows differ only from toolchain-version drift (verified
/// functionally: mpv reports 0.42.0, curl-enabled present, full test suite
/// green — see the 0.1.4 mpv_kit_libs CHANGELOG).
const bundleTag = 'v0.1.3';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target (release v0.1.3
/// SHA256SUMS).
const bundleSha256 = <String, String>{
  'linux-arm64': 'c5d2122572516a82faaf4b645105ff23ca0498c2911432ed6f3897c7ab1651c4',
  'linux-x64': '6e55db4567a48aa2101d2cb809cccd010a91a59e2df06e60893a75edf20d0fac',
  'macos-arm64': '3d3c6abec4a4193386179d5ba58a8a5a2a6d171c29592cbf5c93a5b3f68be952',
  'macos-x64': 'b11d8e601241280fb316bb4185773d88d125ae68f1ff19b213e0ea6d4860f935',
  'windows-arm64': '27530c736c70e8f24a908e6023995fe63c8ccb7696ec792ae04a652722605d36',
  'windows-x64': 'f4bfef033c16e3fa5c890c8c6422345d24be3140d259b7ad537ad3b7bd235f9d',
};
