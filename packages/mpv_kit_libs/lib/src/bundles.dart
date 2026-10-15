/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.1';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': '15a276b3e70a90625435ec59079f0edea29086646258a2198884b02296626d37',
  'linux-x64': 'a5fe1bbd1121ce007b17d6421989dab7b18bd69fff1437b4e11ff4616eecbbfb',
  'macos-arm64': 'c1529245999b7ad86befa78fb4d1189ac22a72a2789d84702fc31e963c1816d7',
  'macos-x64': '3180d4e06812eeb8ed74aa0c6ef8d6756290323cedb0f470d2facb2ee36d142e',
  'windows-arm64': '571466fc2e30264ce3a2b6ec78636d6f2ea21753afb77060fbfad829bf3d6230',
  'windows-x64': '002a430b785d9de595748b1d4c66fa41b824e1fa8937344753ac97ceb9edd233',
};
