/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.8';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'f70d88c0dc1a8a068c62d26a1fd137af2c9e8227450f375239c60d5b484ab721',
  'linux-x64': '94f28ca3055fdfbb92b85a3dd886ed9679a9a49bb07e4d6af87bc898c737756f',
  'macos-arm64': '93cd6f17e17af75e0d6bdec9eed70201ac6d3aaed6eb230dd3e8b3136569eb15',
  'macos-x64': '3f29d3fde2b1bd469b40a28591daff782ee196b2038cb5d5cc5c604272bdcd1f',
  'windows-arm64': '720a4be7961ac694cf0eb2b8344dad266f249bd5ad5e9649d906d448230f28ef',
  'windows-x64': '60fdb4e12358297f07c2414996b746aba902ee3fc7adea5972916ac11ff895d1',
};
