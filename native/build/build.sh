#!/usr/bin/env bash
# Release build of libmpv into PREFIX: dependencies (deps.sh), LGPL FFmpeg
# (ffmpeg.sh), then the patched mpv with exactly the features mpv_kit uses.
# The result is packaged by package.sh.
#
# usage: native/build/build.sh PREFIX
#   SKIP_DEPS=1  reuse the dependencies already in PREFIX (CI cache)
set -euo pipefail

prefix=${1:?usage: build.sh PREFIX}
mkdir -p "$prefix"
prefix=$(cd "$prefix" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

if [ "${SKIP_DEPS:-0}" != 1 ]; then
  bash "$here/deps.sh" "$prefix"
fi

ffmpeg_args=()
mpv_args=()
case "$(uname -s)" in
  Linux)
    # VA-API through DRM render nodes only: no libva-x11/libX11 in libavutil.
    ffmpeg_args+=(--enable-vaapi --disable-xlib --disable-libxcb)
    # Audio: PulseAudio (also served by PipeWire's pulse server) and ALSA
    # are host libraries, never bundled. vaapi: VA-API decoding via DRM.
    mpv_args+=(-Dpulse=enabled -Dalsa=enabled -Dpipewire=auto
      -Dvaapi=enabled -Ddrm=enabled -Dx11=disabled -Dwayland=disabled
      -Dvdpau=disabled -Ddmabuf-wayland=disabled)
    ;;
  Darwin)
    export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
    mpv_args+=(-Dswift-build=disabled -Dcocoa=disabled -Dcoreaudio=enabled
      -Dvideotoolbox-pl=enabled -Dx11=disabled)
    ;;
  MINGW*|MSYS*)
    # d3d11va-copy/dxva2-copy decoding needs only d3d-hwaccel; mpv's own
    # D3D11 renderer (and with it shaderc + spirv-cross) is not used.
    mpv_args+=(-Dwasapi=enabled -Dd3d-hwaccel=enabled -Dd3d11=disabled
      -Ddirect3d=disabled)
    ;;
esac

bash "$here/ffmpeg.sh" "$prefix" ${ffmpeg_args[@]+"${ffmpeg_args[@]}"}

# Everything optional is explicit, so a dependency that happens to be on
# the build host cannot change what ships.
build=${MPV_BUILDDIR:-$PWD/.mpv-build}
rm -rf "$build"
meson setup "$build" "$root/native/mpv" --prefix="$prefix" --libdir=lib \
  --buildtype=release -Db_ndebug=false --wrap-mode=nodownload \
  -Dlibmpv=true -Dcplayer=false -Dtests=false -Dgpl=false \
  -Dvulkan=enabled -Dlcms2=enabled -Duchardet=enabled \
  -Diconv=enabled -Dzlib=enabled \
  -Dgl=disabled -Degl=disabled -Djpeg=disabled -Dlibarchive=disabled \
  -Dlibbluray=disabled -Ddvdnav=disabled -Dcdda=disabled -Dzimg=disabled \
  -Dlua=disabled -Djavascript=disabled -Drubberband=disabled \
  -Dvapoursynth=disabled -Dsdl2-audio=disabled -Dsdl2-video=disabled \
  -Dsdl2-gamepad=disabled -Dopenal=disabled -Djack=disabled -Dsixel=disabled \
  -Dcaca=disabled -Dlibavdevice=enabled -Dshaderc=disabled \
  -Dspirv-cross=disabled \
  ${mpv_args[@]+"${mpv_args[@]}"}
meson compile -C "$build"
meson install -C "$build" --strip
grep -E "HAVE_(VULKAN|LIBPLACEBO|UCHARDET|ICONV|LCMS2|PULSE|ALSA|PIPEWIRE|COREAUDIO|WASAPI|VAAPI|D3D_HWACCEL|VIDEOTOOLBOX_PL) " \
  "$build/config.h" || true
echo "libmpv installed to $prefix"
