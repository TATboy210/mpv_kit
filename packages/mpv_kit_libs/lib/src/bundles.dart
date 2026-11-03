/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.6';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'f70d88c0dc1a8a068c62d26a1fd137af2c9e8227450f375239c60d5b484ab721',
  'linux-x64': '94f28ca3055fdfbb92b85a3dd886ed9679a9a49bb07e4d6af87bc898c737756f',
  'macos-arm64': '5432155d5eb36a46681936caf2c1aeed8a15579fd50d946522d71f193a4d6d42',
  'macos-x64': 'bb6dc5f9cdaeea49672b0286894f80a81d14bbac7beccac3d452eda134af3ae0',
  'windows-arm64': '8c2bf91512f8907526559256e69edef92662b9713e328ff4062583868477547c',
  'windows-x64': 'b8c0dd563ec9bfd534bef7889707914e33eda235b289d743b33f3dfcd8be422c',
};
