#!/usr/bin/env bash
# Builds an LGPL-2.1+ FFmpeg (shared libraries) into PREFIX from the pinned
# release tarball, then refuses to continue unless the configuration is
# really free of GPL/nonfree code.
#
# usage: native/build/ffmpeg.sh PREFIX [extra configure args...]
# Runs on Linux, macOS and MSYS2 (CLANG64/CLANGARM64).
set -euo pipefail

FFMPEG_VERSION=8.1.3
FFMPEG_SHA256=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3

prefix=${1:?usage: ffmpeg.sh PREFIX [configure args...]}
shift
work=${FFMPEG_WORKDIR:-$PWD/.ffmpeg-build}
mkdir -p "$work" "$prefix"
cd "$work"

tarball=ffmpeg-$FFMPEG_VERSION.tar.xz
if [ ! -f "$tarball" ]; then
  curl -fsSL --retry 3 -o "$tarball.part" "https://ffmpeg.org/releases/$tarball"
  mv "$tarball.part" "$tarball"
fi
if command -v sha256sum >/dev/null; then
  actual=$(sha256sum "$tarball" | cut -d' ' -f1)
else
  actual=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
fi
if [ "$actual" != "$FFMPEG_SHA256" ]; then
  echo "ffmpeg tarball sha256 mismatch: $actual" >&2
  exit 1
fi
rm -rf "ffmpeg-$FFMPEG_VERSION"
tar xJf "$tarball"
cd "ffmpeg-$FFMPEG_VERSION"
# On case-insensitive filesystems libc++'s <version> header resolves to this
# file through -I. ; version.sh then takes the version from RELEASE instead.
rm -f VERSION

platform_args=()
case "$(uname -s)" in
  MINGW*|MSYS*)
    # MSYS2 clang environments have no gcc.
    platform_args+=(--cc=clang --cxx=clang++ --enable-d3d11va --enable-dxva2)
    ;;
  Darwin)
    # Only system frameworks/libraries: Homebrew copies (xz, X11, SDL2 on
    # CI runners) would raise the minimum macOS version of the bundle.
    platform_args+=(--enable-videotoolbox --disable-lzma --disable-xlib
      --disable-libxcb --disable-sdl2)
    ;;
  Linux)
    # Distros ship libssl; OpenSSL 3 is compatible with an LGPL build.
    platform_args+=(--enable-openssl)
    ;;
esac

# Headers installed by deps.sh (Vulkan, dav1d) take precedence over the
# host's, which may be too old (FFmpeg 8.1 needs Vulkan headers 1.3.277+).
if [ -d "$prefix/include" ]; then
  inc=$prefix/include
  if command -v cygpath >/dev/null; then inc=$(cygpath -m "$inc"); fi
  platform_args+=(--extra-cflags="-I$inc")
fi

# No --enable-gpl / --enable-nonfree / --enable-version3: LGPL-2.1-or-later.
# Programs and docs are not used by libmpv; of libavdevice only the lavfi
# input device is kept (mpv's av://lavfi: sources, used by the tests).
# Playback needs every decoder/demuxer but almost no encoder or muxer:
#   encoders png, mjpeg  screenshots (screenshot-to-file .png/.jpg)
#            ac3         af=lavcac3enc (AC-3 over S/PDIF)
#   muxers   spdif       audio passthrough (ao spdif)
#            matroska, mov/mp4, mpegts  stream-record / dump-cache
# The full encoder set is roughly a third of libavcodec.
./configure \
  --prefix="$prefix" \
  --enable-shared --disable-static \
  --disable-programs --disable-doc --disable-debug \
  --disable-indevs --enable-indev=lavfi --disable-outdevs \
  --disable-encoders --enable-encoder=png,mjpeg,ac3 \
  --disable-muxers --enable-muxer=spdif,matroska,webm,mov,mp4,mpegts \
  --enable-pic \
  --enable-libdav1d \
  --enable-vulkan \
  ${platform_args[@]+"${platform_args[@]}"} \
  "$@"

# License gate: configure must have produced an LGPL build.
for flag in GPL NONFREE VERSION3; do
  if ! grep -q "^#define CONFIG_$flag 0" config.h; then
    echo "refusing to build: CONFIG_$flag is enabled" >&2
    exit 1
  fi
done

jobs=$( (nproc || sysctl -n hw.ncpu || echo 4) 2>/dev/null | head -1)
make -j"$jobs"
make install
echo "FFmpeg $FFMPEG_VERSION (LGPL) installed to $prefix"
