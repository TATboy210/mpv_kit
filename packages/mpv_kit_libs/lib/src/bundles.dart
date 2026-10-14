/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
const bundleTag = '';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https('github.com',
    '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz');

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target.
const bundleSha256 = <String, String>{};
