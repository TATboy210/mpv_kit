/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.9';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'f70d88c0dc1a8a068c62d26a1fd137af2c9e8227450f375239c60d5b484ab721',
  'linux-x64': '94f28ca3055fdfbb92b85a3dd886ed9679a9a49bb07e4d6af87bc898c737756f',
  'macos-arm64': '80294b6d29789bea79c2cdb054a31a169f451a241fd99ba9c876799fe7eee6ea',
  'macos-x64': '74cabe5d9ce63be820bd5a158590fb4cc5c187384887c5c2b4f0a0b1147cb374',
  'windows-arm64': 'ccf0ae3d99e171794a6c35ce13d1298f53f850233151966117bbcaa05ac5d802',
  'windows-x64': '036ed371c477659136754f0c48a307f47fe46982e74d413c2e27845608e876e5',
};
