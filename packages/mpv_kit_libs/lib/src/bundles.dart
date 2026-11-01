/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.5';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'f70d88c0dc1a8a068c62d26a1fd137af2c9e8227450f375239c60d5b484ab721',
  'linux-x64': '94f28ca3055fdfbb92b85a3dd886ed9679a9a49bb07e4d6af87bc898c737756f',
  'macos-arm64': 'd2c9a55c5143c74eaf24c4d2c19e88c7543295c5fe03db91ead380271500d026',
  'macos-x64': '02d2bb2de645676a035de87d82d7260272024ed8099a74de6470cd12f5b475f2',
  'windows-arm64': '900c123b1d639eb7a2f11c6841f053d74ebeaaf2e053bb49662843039b8af51b',
  'windows-x64': 'd7645834dc27e47da043c0485b637737562f12a971c39f47ee3b4a45e8650d80',
};
