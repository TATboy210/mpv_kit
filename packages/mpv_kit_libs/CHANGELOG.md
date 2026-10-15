## 0.1.0-dev.1

- Build hook that bundles a prebuilt LGPL libmpv (mpv 0.41.0 with the
  mpv_kit patches, FFmpeg 8.1.3) and its dependency closure for
  windows/linux/macos × x64/arm64.
- Downloads the GitHub release bundle for the target, verifies the archive
  against a pinned sha256 and every file against the bundle's
  `MANIFEST.txt`; nothing is executed during the build.
- `libmpv_bundle` hook user define for a local bundle archive or
  directory.
- Emits no assets when no release is pinned or no bundle exists for the
  target, so mpv_kit falls back to `MPV_KIT_LIBMPV_PATH` / a system libmpv.
