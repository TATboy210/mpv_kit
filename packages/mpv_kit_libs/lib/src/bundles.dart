/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.2';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'a142ba057d0c436145153101052a9d70ef826369ec4db13d1ebd62cc8d2ac172',
  'linux-x64': 'c4eb80dcaadd229492ef734414c165c2e613ab0cdd0d2ec700ae2cbb1ffc0fdb',
  'macos-arm64': '94436c359ed27c4f0264c1cf4a94df37db8067c8ff69ab84dfd514549628a435',
  'macos-x64': '13ebe12d53b30d649d6755f205248f56a2edf59dc4267e18cede7925d02dcea0',
  'windows-arm64': '52cac89ec826804213aa59895fd48703175b059b0cecdfd35fd6baed6d951a6f',
  'windows-x64': '3d93aeed9d37cea640202fc1a68c7e660272d4e57d3cc798b71a5752fe392df4',
};
