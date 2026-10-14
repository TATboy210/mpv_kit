# ADR 0002 — Self-built LGPL libmpv binaries

Status: accepted (2026-10-14)

## Decision
* libmpv is built in CI from `native/mpv` (0.41.0 + `native/patches`) with
  `-Dgpl=false -Drubberband=disabled`, against an FFmpeg configured without
  `--enable-gpl`/`--enable-nonfree`, for windows-{x64,arm64},
  linux-{x64,arm64}, macos-{x64,arm64}.
* Two CI tiers:
  * `native-verify` — distro/Homebrew/MSYS2 dependencies (often GPL FFmpeg);
    proves the patch compiles and works; artifacts are **not** distributed.
  * `release` — LGPL dependency stack built from pinned, sha256-verified
    sources; artifacts + checksums + ABI audit evidence go to GitHub Releases
    and are fetched by `mpv_kit_libs`.
* LGPL mode drops X11 VO, vdpau, DVD/CDDA/DVB, jack, OSS, caca — none are
  needed for an embedded player.

## Consequences
Applications can ship closed-source and only need to allow libmpv to be
replaced (dynamic linking) and point to this repository for sources.

## Status of the release tier (2026-10-15)

Implemented in `.github/workflows/release.yml`, green on all six targets:

* FFmpeg 8.1.3 is built from the pinned tarball by `native/build/ffmpeg.sh`,
  which aborts unless `config.h` has `CONFIG_GPL`, `CONFIG_NONFREE` and
  `CONFIG_VERSION3` all `0`. libavdevice keeps only the `lavfi` input device.
* Other dependencies (libplacebo, libass, dav1d, freetype, harfbuzz, ...)
  still come from the platform package manager. They are LGPL or
  permissive; `native/build/package.sh` refuses known GPL-only libraries,
  checks that libavcodec resolves from our prefix, and writes a sha256
  manifest that `mpv_kit_libs` verifies file by file.
* The packaged bundle itself is tested with the build prefix hidden
  (render smoke test on Linux/macOS, Dart suite on Windows).

Known gaps:

* macOS bundles require macOS 15: FFmpeg, libmpv and MoltenVK are built
  for 12.0, but Homebrew bottles (libass, libplacebo, dav1d, ...) carry
  the runner's OS as minimum. Building those from source with
  `MACOSX_DEPLOYMENT_TARGET` would lower it. The bundle also contains
  X11 client libraries pulled in by Homebrew's libplacebo/Vulkan loader;
  they are unused on macOS.
* Windows/Linux dependency versions follow MSYS2/Ubuntu 24.04 rather than
  pinned source builds.
