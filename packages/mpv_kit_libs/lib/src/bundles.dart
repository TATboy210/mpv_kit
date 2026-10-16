/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.0-dev.3';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': '6d4a08472c86e5375a44583dfb0b9e981abca0fc66217a095f6ba22a79e977a8',
  'linux-x64': '7e81acfffee1a45b8f8af080d4cc57658f33992b7c8c93f9559378cf1355f8ce',
  'macos-arm64': 'da2f350cccb65446b4111d252b68751a84d720931fef4ae2583d20ce3fa982af',
  'macos-x64': 'e2e7d260b6e5738d51253ed0f91fce2d6e7e171c395a0667d251e4eae2bb6d08',
  'windows-arm64': 'e4b4e9522517dbef8289c4a300ecdcf850532b178fb4916cee8f029410fc9f3c',
  'windows-x64': '863f3643a5f948392c4c3ed3fc656b3354535d9ad9cdb5032d015775d7ca4ff8',
};
