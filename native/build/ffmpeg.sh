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

platform_args=()
case "$(uname -s)" in
  MINGW*|MSYS*)
    # MSYS2 clang environments have no gcc.
    platform_args+=(--cc=clang --cxx=clang++ --enable-d3d11va --enable-dxva2)
    ;;
  Darwin)
    platform_args+=(--enable-videotoolbox)
    ;;
  Linux)
    # Distros ship libssl; OpenSSL 3 is compatible with an LGPL build.
    platform_args+=(--enable-openssl)
    ;;
esac

# No --enable-gpl / --enable-nonfree / --enable-version3: LGPL-2.1-or-later.
# Programs, docs and libavdevice are not used by libmpv.
./configure \
  --prefix="$prefix" \
  --enable-shared --disable-static \
  --disable-programs --disable-doc --disable-debug \
  --disable-avdevice \
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
