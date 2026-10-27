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
# config.h features that must be on after meson setup (extended per platform).
required_features="VULKAN LIBPLACEBO"
case "$(uname -s)" in
  Linux)
    # VA-API through DRM render nodes only: no libva-x11/libX11 in libavutil.
    ffmpeg_args+=(--enable-vaapi --disable-xlib --disable-libxcb)
    # Audio: PulseAudio (also served by PipeWire's pulse server) and ALSA
    # are host libraries, never bundled. vaapi: VA-API decoding via DRM.
    mpv_args+=(-Dpulse=enabled -Dalsa=enabled -Dpipewire=auto
      -Dvaapi=enabled -Ddrm=enabled -Dx11=disabled -Dwayland=disabled
      -Dvdpau=disabled -Ddmabuf-wayland=disabled
      -Dshaderc=disabled -Dspirv-cross=disabled)
    # OpenGL render API (MPV_RENDER_API_TYPE_OPENGL, libmpv_gl.c) for the
    # plugin's OpenGL backend. plain-gl is the only switch that compiles it
    # in while x11/wayland stay disabled (mpv meson.build:1324-1330). egl
    # links the host's libEGL.so.1 (a package.sh system-allowlist library,
    # never bundled) and builds dmabuf_interop_gl for the later vaapi zero-copy
    # path. egl-drm needs gbm, which libmpv does not use: off explicitly so a
    # host that happens to have gbm cannot change what ships.
    mpv_args+=(-Dgl=enabled -Degl=enabled -Dplain-gl=enabled -Degl-drm=disabled)
    required_features="$required_features GL EGL"
    ;;
  Darwin)
    export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
    # Header room for install-name rewrites (package.sh, native assets).
    export LDFLAGS="${LDFLAGS:+$LDFLAGS }-Wl,-headerpad_max_install_names"
    mpv_args+=(-Dswift-build=disabled -Dcocoa=disabled -Dcoreaudio=enabled
      -Dvideotoolbox-pl=enabled -Dx11=disabled
      -Dshaderc=disabled -Dspirv-cross=disabled)
    # No OpenGL on macOS: mpv_kit renders through Vulkan (MoltenVK).
    mpv_args+=(-Dgl=disabled -Degl=disabled)
    ;;
  MINGW*|MSYS*)
    # mpv's own D3D11 renderer (ra_d3d11, the libmpv D3D11 render API and
    # hwdec_d3d11va) needs shaderc (GLSL -> SPIR-V) and SPIRV-Cross (SPIR-V ->
    # HLSL); deps.sh builds both from pinned sources (D3D-01). mpv_kit's
    # default path stays Vulkan until the D3D11 backend is selected.
    mpv_args+=(-Dwasapi=enabled -Dd3d-hwaccel=enabled -Dd3d11=enabled
      -Dshaderc=enabled -Dspirv-cross=enabled -Ddirect3d=disabled)
    # Hard constraint (D3D-02): mpv_kit's own Windows chain never uses ANGLE,
    # EGL or WGL-GL. -Dgl/-Degl are disabled here and the remaining Windows GL
    # backends are made explicit instead of being left on "auto" (the config.h
    # check after meson setup enforces it).
    mpv_args+=(-Dgl=disabled -Degl=disabled)
    mpv_args+=(-Degl-angle=disabled -Degl-angle-lib=disabled
      -Degl-angle-win32=disabled -Dgl-win32=disabled -Dgl-dxinterop=disabled
      -Dgl-dxinterop-d3d9=disabled)
    # MSYS2's vulkan.pc (vulkan-loader) points at its own include dir, which
    # has no Vulkan headers; mpv's VK_VERSION_1_3 header check then fails and
    # meson silently turns Vulkan off despite -Dvulkan=enabled (0.1.0-dev.1/2
    # shipped without the Vulkan render API). Use the pinned headers from
    # deps.sh instead.
    export CFLAGS="${CFLAGS:+$CFLAGS }-I$(cygpath -m "$prefix")/include"
    ;;
esac

bash "$here/ffmpeg.sh" "$prefix" ${ffmpeg_args[@]+"${ffmpeg_args[@]}"}

# Everything optional is explicit, so a dependency that happens to be on
# the build host cannot change what ships.
# b_lundef=true: mpv defaults to allowing undefined symbols (on macOS
# -undefined dynamic_lookup), which turned a missing utils-mac.c into a
# NULL function pointer at run time instead of a link error.
build=${MPV_BUILDDIR:-$PWD/.mpv-build}
rm -rf "$build"
# mpv 0.41.0-1113 (master) additions: keep everything optional explicit,
# and the LGPL bundle free of new dependencies (amf FRC filter, dvdnav's
# sibling dvda, the libcurl stream backend, the subrandr subtitle renderer).
meson setup "$build" "$root/native/mpv" --prefix="$prefix" --libdir=lib \
  --buildtype=release -Db_ndebug=false -Db_lundef=true --wrap-mode=nodownload \
  -Dlibmpv=true -Dcplayer=false -Dtests=false -Dgpl=false \
  -Dvulkan=enabled -Dlcms2=enabled -Duchardet=enabled \
  -Diconv=enabled -Dzlib=enabled \
  -Djpeg=disabled -Dlibarchive=disabled \
  -Dlibbluray=disabled -Ddvdnav=disabled -Dcdda=disabled -Dzimg=disabled \
  -Dlua=disabled -Djavascript=disabled -Drubberband=disabled \
  -Dvapoursynth=disabled -Dsdl2-audio=disabled -Dsdl2-video=disabled \
  -Dsdl2-gamepad=disabled -Dopenal=disabled -Djack=disabled -Dsixel=disabled \
  -Dcaca=disabled -Dlibavdevice=enabled \
  -Damf=disabled -Ddvda=disabled -Dlibcurl=disabled -Dsubrandr=disabled \
  ${mpv_args[@]+"${mpv_args[@]}"}
# -Dvulkan=enabled only makes the dependency lookup mandatory; mpv's
# extra header check can still disable the feature without an error.
# mpv_kit renders exclusively through the Vulkan render API, so a build
# without it is a broken build. Linux also requires GL and EGL (the OpenGL
# render API); x11/wayland stay off.
for feature in $required_features; do
  grep -q "^#define HAVE_$feature 1" "$build/config.h" || {
    echo "error: mpv configured without $feature; see $build/meson-logs/meson-log.txt" >&2
    exit 1
  }
done
# D3D-02: on Windows no GL/EGL/ANGLE/WGL-GL feature may be configured on.
# Checked as "no `#define HAVE_<X> 1`" rather than "must be defined as 0",
# since a feature can be absent from config.h when its dependency is off.
case "$(uname -s)" in
  MINGW*|MSYS*)
    for feature in GL EGL EGL_ANGLE EGL_ANGLE_LIB EGL_ANGLE_WIN32 GL_WIN32 \
      GL_DXINTEROP GL_DXINTEROP_D3D9; do
      if grep -q "^#define HAVE_$feature 1" "$build/config.h"; then
        echo "error: mpv configured with $feature on Windows (ANGLE/EGL/WGL-GL ban)" >&2
        exit 1
      fi
    done
    # D3D-01: HAVE_D3D11, HAVE_SHADERC and HAVE_SPIRV_CROSS must all be 1, so the
    # bundle cannot ship without the native D3D11 renderer.
    for feature in D3D11 SHADERC SPIRV_CROSS; do
      grep -q "^#define HAVE_$feature 1" "$build/config.h" || {
        echo "error: mpv configured without $feature on Windows; see $build/meson-logs/meson-log.txt" >&2
        exit 1
      }
    done
    ;;
esac
meson compile -C "$build"
meson install -C "$build" --strip
grep -E "HAVE_(VULKAN|LIBPLACEBO|GL|EGL|X11|WAYLAND|UCHARDET|ICONV|LCMS2|PULSE|ALSA|PIPEWIRE|COREAUDIO|WASAPI|VAAPI|D3D_HWACCEL|D3D11|SHADERC|SPIRV_CROSS|VIDEOTOOLBOX_PL) " \
  "$build/config.h" || true
echo "libmpv installed to $prefix"
