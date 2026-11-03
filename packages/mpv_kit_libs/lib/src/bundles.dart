/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.7';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'f70d88c0dc1a8a068c62d26a1fd137af2c9e8227450f375239c60d5b484ab721',
  'linux-x64': '94f28ca3055fdfbb92b85a3dd886ed9679a9a49bb07e4d6af87bc898c737756f',
  'macos-arm64': 'e502749d4eea085131f9b1579087326aec99b6800d20bcb8f69fe06ff6811ded',
  'macos-x64': '6e84620b76cb4d88d5505c7347cbd534cfe513d21d73100df5626a3332587938',
  'windows-arm64': '34ff773a9b90561a9355a23883d1855a2bf27488d2c813778b6854379a6f2d11',
  'windows-x64': 'a38b619074f9e62ed1be059c5dcb629f4ad111c98ceb1d46d5e35c0b55121706',
};
