#!/usr/bin/env bash
# Builds libmpv's dependencies (everything except FFmpeg, see ffmpeg.sh) from
# pinned, sha256-verified source tarballs into PREFIX as shared libraries.
#
# Building from source instead of taking Homebrew/MSYS2/distro packages is
# what makes the release bundles portable and small:
#   * macOS: every library is built for MACOSX_DEPLOYMENT_TARGET (12.0);
#     Homebrew bottles require the runner's own macOS version.
#   * Linux: run in an old distro container (glibc baseline) with current
#     libplacebo/dav1d, which the old distro does not have.
#   * all: no glib/X11/libjpeg/shaderc/spirv-cross pulled in by packaged
#     builds' optional features (harfbuzz-glib, freetype-png, ...).
#
# usage: native/build/deps.sh PREFIX
# Runs on Linux, macOS and MSYS2 (CLANG64/CLANGARM64). Needs a C/C++
# toolchain, meson, ninja, cmake, pkg-config, nasm (x86), python3 + jinja2.
set -euo pipefail

prefix=${1:?usage: deps.sh PREFIX}
# Resolved before anything changes directory.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$prefix/lib/pkgconfig" "$prefix/include"
prefix=$(cd "$prefix" && pwd)
# Native Windows tools (meson, clang) need drive-letter paths (X:/...) in
# arguments; MSYS2 only converts whole path arguments.
nprefix=$prefix
if command -v cygpath >/dev/null; then nprefix=$(cygpath -m "$prefix"); fi
work=${DEPS_WORKDIR:-$PWD/.deps-build}
mkdir -p "$work/src" "$work/dl"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  MINGW*|MSYS*) os=windows ;;
  *) echo "unsupported host $(uname -s)" >&2; exit 1 ;;
esac

cmake_extra=()
if [ "$os" = macos ]; then
  export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
  cmake_extra+=(-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET")
  # Room for install_name_tool: package.sh and native-assets packaging
  # (which uses absolute build paths) rewrite every install name.
  export LDFLAGS="${LDFLAGS:+$LDFLAGS }-Wl,-headerpad_max_install_names"
fi

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch NAME URL SHA256: downloads (cached in $work/dl), verifies and
# extracts into $work/src/NAME (the archive's single top-level directory).
fetch() {
  local name=$1 url=$2 want=$3 file="$work/dl/$1-${2##*/}"
  # URL may list mirrors (space-separated) serving the identical file.
  if [ ! -f "$file" ]; then
    local u
    for u in $url; do
      if curl -fsSL --retry 5 --retry-all-errors -o "$file.part" "$u"; then
        mv "$file.part" "$file"
        break
      fi
    done
    [ -f "$file" ] || { echo "$name: download failed" >&2; exit 1; }
  fi
  local got
  got=$(sha256 "$file")
  if [ "$got" != "$want" ]; then
    echo "$name: sha256 mismatch ($got)" >&2
    exit 1
  fi
  rm -rf "${work:?}/src/$name" "$work/src/.x"
  mkdir -p "$work/src/.x"
  tar xf "$file" -C "$work/src/.x"
  mv "$work/src/.x"/* "$work/src/$name"
  rmdir "$work/src/.x"
}

# Keeps each dependency's license next to the binaries (package.sh ships
# share/licenses).
license() {
  local name=$1
  shift
  mkdir -p "$prefix/share/licenses/$name"
  for f in "$@"; do cp "$work/src/$name/$f" "$prefix/share/licenses/$name/"; done
}

meson_build() {
  local name=$1
  shift
  (
    cd "$work/src/$name"
    meson setup build --prefix="$prefix" --libdir=lib --buildtype=release \
      -Ddefault_library=shared -Db_ndebug=true --wrap-mode=nodownload "$@"
    meson compile -C build
    meson install -C build --strip
  )
}

cmake_build() {
  local name=$1
  shift
  (
    cd "$work/src/$name"
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      ${cmake_extra[@]+"${cmake_extra[@]}"} "$@"
    cmake --build build
    cmake --install build --strip
  )
}

VK_SDK=1.4.363.0

# --- Vulkan headers / loader -------------------------------------------
fetch vulkan-headers \
  "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz" \
  4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e
cmake_build vulkan-headers
license vulkan-headers LICENSE.md

case "$os" in
  linux)
    # Only linked against: at run time the host's libvulkan.so.1 (same
    # soname, part of the GPU driver stack) is used. Old distros ship
    # loaders older than mpv's minimum of 1.3.238 for linking.
    fetch vulkan-loader \
      "https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz" \
      941eff558fc74f248745fb7df367640cf89a8457f216dae498a74ae14b6ba6f7
    cmake_build vulkan-loader -DBUILD_TESTS=OFF \
      -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_WSI_XLIB_SUPPORT=OFF \
      -DBUILD_WSI_XLIB_XRANDR_SUPPORT=OFF -DBUILD_WSI_WAYLAND_SUPPORT=OFF
    # mpv's DRM support (needed for VA-API over render nodes) requires
    # libdisplay-info, which Ubuntu 22.04 does not ship. Small, MIT.
    fetch libdisplay-info \
      "https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/0.2.0/downloads/libdisplay-info-0.2.0.tar.xz" \
      5a2f002a16f42dd3540c8846f80a90b8f4bdcd067a94b9d2087bc2feae974176
    meson_build libdisplay-info
    license libdisplay-info LICENSE
    ;;
  macos)
    # MoltenVK is linked directly (it exports the whole Vulkan API); it is
    # also what the Flutter plugin uses, so one Vulkan implementation is
    # loaded. The official release dylib supports macOS 10.15+.
    fetch moltenvk \
      https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar \
      f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e
    # Relinked from the release's static library instead of copying its
    # dylib: that one has only ~56 bytes of header padding, so Flutter's /
    # dart's native-assets packaging cannot rewrite its install name
    # ("larger updated load commands do not fit"). Linking it ourselves
    # adds the padding, keeps only the target architecture (the release
    # dylib is universal) and exports only the Vulkan API.
    mvk_a=$(find "$work/src/moltenvk/MoltenVK/static" -path '*macos*' -name 'libMoltenVK.a' | head -1)
    [ -n "$mvk_a" ] || { echo "moltenvk: static library not found" >&2; exit 1; }
    printf '_vk*\n' > "$work/moltenvk.exports"
    clang++ -dynamiclib -arch "$(uname -m)" -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
      -o "$prefix/lib/libMoltenVK.dylib" -install_name "$prefix/lib/libMoltenVK.dylib" \
      -Wl,-all_load "$mvk_a" -Wl,-exported_symbols_list,"$work/moltenvk.exports" \
      -Wl,-headerpad_max_install_names -Wl,-dead_strip \
      -framework Metal -framework IOSurface -framework IOKit -framework QuartzCore \
      -framework CoreGraphics -framework AppKit -framework Foundation \
      -framework CoreFoundation -lobjc -lc++
    strip -x "$prefix/lib/libMoltenVK.dylib"
    cat > "$prefix/lib/pkgconfig/vulkan.pc" <<EOF
prefix=$prefix
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: Vulkan-Loader
Description: Vulkan (MoltenVK, linked directly)
Version: $VK_SDK
Libs: -L\${libdir} -lMoltenVK
Cflags: -I\${includedir}
EOF
    license moltenvk LICENSE
    ;;
  windows)
    # vulkan-1.dll comes from MSYS2 (vulkan-loader package); it is the
    # standard loader that every Vulkan driver registers with.
    ;;
esac

# --- Shader compiler (static, inside libplacebo) ------------------------
fetch glslang https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz \
  9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2
# No SPIRV-Tools optimizer: libplacebo does not need it, and it is the
# bulk of a shaderc build.
cmake_build glslang -DBUILD_SHARED_LIBS=OFF -DENABLE_OPT=OFF \
  -DGLSLANG_TESTS=OFF -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_HLSL=OFF \
  -DGLSLANG_ENABLE_INSTALL=ON
license glslang LICENSE.txt

# --- Color management ---------------------------------------------------
fetch lcms2 https://github.com/mm2/Little-CMS/releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz \
  bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8
meson_build lcms2 -Djpeg=disabled -Dtiff=disabled -Dutils=false
license lcms2 LICENSE

# --- libplacebo ---------------------------------------------------------
fetch libplacebo https://code.videolan.org/videolan/libplacebo/-/archive/v7.360.1/libplacebo-v7.360.1.tar.gz \
  14c0a99f4b01557ec9826ce6b1d52f6de21be274ba03fd5aab7307f18766dc39
# Upstream fixes after 7.360.1 (Vulkan command races, external image
# hand-off, pl_queue lifetime, memory safety, color metadata), applied in
# order; see native/deps/libplacebo/ and native/patches/UPSTREAM.md.
# GNU patch only (BSD patch differs on fuzz and exit codes), no fuzz, and
# every patch must match its pinned sha256.
placebo_patches="$here/../deps/libplacebo"
gpatch=$(command -v gpatch || command -v patch || true)
if [ -z "$gpatch" ] || ! "$gpatch" --version 2>/dev/null | grep -q 'GNU patch'; then
  echo "libplacebo: GNU patch is required (install gpatch)" >&2
  exit 1
fi
n_patches=0
while read -r want name; do
  [ -n "$name" ] || continue
  f="$placebo_patches/$name"
  got=$(sha256 "$f")
  if [ "$got" != "$want" ]; then
    echo "libplacebo: $name sha256 mismatch ($got)" >&2
    exit 1
  fi
  "$gpatch" -p1 --batch --forward --fuzz=0 --no-backup-if-mismatch -s     -d "$work/src/libplacebo" -i "$f"
  n_patches=$((n_patches + 1))
done < "$placebo_patches/SHA256SUMS"
n_files=$(find "$placebo_patches" -name '0*.patch' | wc -l)
if [ "$n_patches" -ne 16 ] || [ "$n_files" -ne 16 ]; then
  echo "libplacebo: expected 16 pinned patches, applied $n_patches of $n_files" >&2
  exit 1
fi
# Vulkan only: mpv_kit renders through the Vulkan render API (OpenGL and
# D3D11 backends would only add size). Dolby Vision metadata is handled
# by libplacebo itself (libdovi is optional).
# libplacebo finds glslang with find_library, which searches only the
# -Dvulkan-sdk directory and not for every library: point both at PREFIX.
sed -i.orig \
  -e "s|find_library('glslang', required: required, static: static)|find_library('glslang', required: required, static: static, dirs: vulkan_lib_dirs)|" \
  -e "s|find_library('glslang-default-resource-limits', required: false)|find_library('glslang-default-resource-limits', required: false, static: true, dirs: [get_option('vulkan-sdk') / 'lib'])|" \
  "$work/src/libplacebo/src/glsl/meson.build"
# The source archive has no git submodules; fast_float (header-only) is
# required where the C++ library lacks floating-point from_chars (macOS).
fetch fast_float https://github.com/fastfloat/fast_float/archive/refs/tags/v8.3.2.tar.gz \
  71bb9e865b888df01351558db5a39586d13ea97ada162156b3a07784d8c1b26b
rm -rf "$work/src/libplacebo/3rdparty/fast_float"
cp -r "$work/src/fast_float" "$work/src/libplacebo/3rdparty/fast_float"
license fast_float LICENSE-MIT
meson_build libplacebo -Dprefer_static=true -Dvulkan-sdk="$nprefix" \
  -Dc_args="-I$nprefix/include" -Dcpp_args="-I$nprefix/include" \
  -Dvulkan=enabled -Dvk-proc-addr=enabled \
  -Dvulkan-registry="$nprefix/share/vulkan/registry/vk.xml" \
  -Dopengl=disabled -Dd3d11=disabled -Dglslang=enabled -Dshaderc=disabled \
  -Dlcms=enabled -Ddovi=enabled -Dlibdovi=disabled -Dunwind=disabled \
  -Dxxhash=disabled -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false
license libplacebo LICENSE

# --- AV1 decoder ----------------------------------------------------------
fetch dav1d https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz \
  686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5
meson_build dav1d -Denable_tools=false -Denable_tests=false -Denable_examples=false
license dav1d COPYING

# --- Subtitle rendering (libass and its text stack) ---------------------
fetch freetype https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.xz \
  36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f
meson_build freetype -Dzlib=internal -Dpng=disabled -Dbrotli=disabled \
  -Dharfbuzz=disabled -Dtests=disabled
license freetype LICENSE.TXT docs/FTL.TXT

fetch fribidi https://github.com/fribidi/fribidi/releases/download/v1.0.17/fribidi-1.0.17.tar.xz \
  6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2
meson_build fribidi -Ddocs=false -Dbin=false -Dtests=false
license fribidi COPYING

fetch harfbuzz https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz \
  d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586
meson_build harfbuzz -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled \
  -Dcairo=disabled -Dchafa=disabled -Dicu=disabled -Dgraphite=disabled \
  -Dpng=disabled -Dzlib=disabled -Draster=disabled -Dvector=disabled \
  -Dgpu=disabled -Dsubset=disabled -Dtests=disabled -Ddocs=disabled \
  -Dutilities=disabled -Dintrospection=disabled -Dbenchmark=disabled
license harfbuzz COPYING

fetch libass https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz \
  2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc
# System font lookup: DirectWrite / Core Text; fontconfig on Linux (a host
# library every desktop provides).
ass_fonts=(-Dfontconfig=disabled -Ddirectwrite=disabled -Dcoretext=disabled)
case "$os" in
  linux) ass_fonts=(-Dfontconfig=enabled -Ddirectwrite=disabled -Dcoretext=disabled) ;;
  macos) ass_fonts=(-Dfontconfig=disabled -Ddirectwrite=disabled -Dcoretext=enabled) ;;
  windows) ass_fonts=(-Dfontconfig=disabled -Ddirectwrite=enabled -Dcoretext=disabled) ;;
esac
meson_build libass "${ass_fonts[@]}" -Dlibunibreak=disabled \
  -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled \
  -Dcheckasm=disabled
license libass COPYING

# --- Subtitle charset detection (sub-codepage=auto, e.g. GBK .srt) ------
fetch uchardet "https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz https://deb.debian.org/debian/pool/main/u/uchardet/uchardet_0.0.8.orig.tar.xz" \
  e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0
cmake_build uchardet -DBUILD_BINARY=OFF -DBUILD_STATIC=OFF -DCHECK_SSE2=OFF
license uchardet COPYING

echo "dependencies installed to $prefix"
