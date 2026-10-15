## 0.1.0-dev.1

- Bundles are built from pinned sources (native/build/deps.sh, build.sh)
  and run on Windows 10+, macOS 12+ and Linux with glibc 2.35+; 14–17 MB
  per target compressed. Linux bundles include PulseAudio/ALSA output and
  VA-API; all bundles include uchardet (subtitle charset detection).
  Every bundle passes the Dart test suite and a ~40-format playback matrix
  before it is published.
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
