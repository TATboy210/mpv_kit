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
