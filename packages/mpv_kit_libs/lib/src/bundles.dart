/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.4';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'cae3bc2edbee83a17c46de7f547c957be238243c993aeae647d8b261adc7d6d1',
  'linux-x64': '2e45998b64d2c7f790544a1e60dbbebbf3ceed34aaf2c58d6b12bd1840269f29',
  'macos-arm64': '38259f606702a587fc083c116fb18b9095fdd7c8049b6c99ea33951d300af71a',
  'macos-x64': 'c79b7de008fa7ce0699c49ebfbb21b18ba2a76d7645fcfc65752b60ee8f4e190',
  'windows-arm64': 'af6e6ba9767575298e6a909efe6cecc81fb373c7bcf5deac7c4364fc2fd800d1',
  'windows-x64': '6f30c84c35643c6f185fbb482ea82e80a4f059f9cc86f2d567714deb7d45c254',
};
