/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = 'v0.1.1';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{
  'linux-arm64': 'c5d2122572516a82faaf4b645105ff23ca0498c2911432ed6f3897c7ab1651c4',
  'linux-x64': '6e55db4567a48aa2101d2cb809cccd010a91a59e2df06e60893a75edf20d0fac',
  'macos-arm64': '1c9e3fdc63a060da9d9530555efa2f9555d7e8fb7761c4545b642c15aeac1135',
  'macos-x64': '1893691813d90961eb3eb7f63a493fa73f495add4f37d24d63b9686ae7b86c35',
  'windows-arm64': 'd8ed471db5928b420babf76f7ee606aac2cf543811b4a341aa2c71dfac278259',
  'windows-x64': '3146405f26581f39c2491b75d405c0529117d9f3af650c2cac5dbe570d656f01',
};
