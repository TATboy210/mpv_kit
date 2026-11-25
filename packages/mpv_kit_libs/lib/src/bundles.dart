/// Release bundles the build hook may download, pinned by sha256.
///
/// Regenerate with `dart run tools/pin_bundles.dart <tag>` after the release
/// workflow published a tag: it reads the release's SHA256SUMS. A target
/// missing here has no prebuilt bundle; the hook then emits no assets and
/// mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / the system libmpv.
library;

/// GitHub release tag the pinned bundles belong to.
///
/// v0.1.5 is the mpv master snapshot `v0.42.0-228-g35efcf53d` (the
/// 0.43.0-dev base, client API 2.7) built from the rebased mpv_kit patch
/// set; `native/patches/UPSTREAM.md` documents the rebase and
/// `MPV_RENDER_PARAM_ACTIVE_RENDERER` replaces the retired
/// `MPV_RENDER_PARAM_VULKAN_RENDERER`.
const bundleTag = 'v0.1.5';

/// Download location of the bundle for [target] (e.g. `windows-x64`).
Uri bundleUrl(String target) => Uri.https(
  'github.com',
  '/TATboy210/mpv_kit/releases/download/$bundleTag/libmpv-$target.tar.gz',
);

/// sha256 of `libmpv-<target>.tar.gz`, keyed by target (release v0.1.5
/// SHA256SUMS).
const bundleSha256 = <String, String>{
  'linux-arm64': '4991f118224a58b15209d3ecbe9eca04a21eee8eaec62331a324964886ad6993',
  'linux-x64': 'ba268dbfe392855b32db928187a40573ecc4ae6cbd69fdc050e09cfb628590f6',
  'macos-arm64': '5ab07ecb20b65a8db2f4a6370190e5ca4ee5aac99f72f9299de6f00c56a6415c',
  'macos-x64': '16187443b3ca3430a08ea934192376907091607f4df06fdb25aab514b4149148',
  'windows-arm64': 'a63857838472ca436bf4aa8ae11350a56d0c33591a4a2e81b10c3fb990ceb0d7',
  'windows-x64': '9ac20c16b9f3de139756d2f332b2ed09508cac987f6ac2d2ae4a31b4232796b8',
};
