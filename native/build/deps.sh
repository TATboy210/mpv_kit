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

# cmake_dest=DIR cmake_build ...: installs into DIR instead of PREFIX (used
# where only part of an install may reach PREFIX, see shaderc below).
cmake_build() {
  local name=$1
  shift
  (
    cd "$work/src/$name"
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${cmake_dest:-$prefix}" -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      ${cmake_extra[@]+"${cmake_extra[@]}"} "$@"
    cmake --build build
    cmake --install build --strip
  )
}

# autotools_build NAME [configure args...]: release tarballs ship configure.
# --libdir is forced to PREFIX/lib so 64-bit Linux does not install to lib64.
autotools_build() {
  local name=$1
  shift
  (
    # libaacs/libbdplus and libgcrypt use the legacy *-config scripts,
    # which install into PREFIX/bin; make them discoverable by configure.
    export PATH="$prefix/bin:$PATH"
    cd "$work/src/$name"
    if [ ! -x ./configure ]; then
      echo "$name: source archive has no configure script" >&2
      exit 1
    fi
    ./configure --prefix="$prefix" --libdir="$prefix/lib" \
      --disable-static --enable-shared --disable-dependency-tracking \
      --disable-nls "$@"
    make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    make install
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

# --- Windows only: SPIR-V -> HLSL (SPIRV-Cross) and shaderc ----------------
# mpv's D3D11 renderer (-Dd3d11) needs shaderc (GLSL -> SPIR-V) and
# spirv-cross-c-shared (SPIR-V -> HLSL); libplacebo's pl_d3d11 needs only
# spirv-cross-c-shared. Both are built from the pinned official sources,
# never taken from MSYS2 packages (D3D-01). Linux and macOS skip this block.
if [ "$os" = windows ]; then
  # Shared C API library: the pkg-config name spirv-cross-c-shared is the one
  # libplacebo and mpv look up, and only the shared build installs it. One
  # extra DLL in the bundle (shipped with its license, audited like the rest).
  fetch spirv-cross \
    "https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz" \
    f708982e88b763ef5b0394ed468fc2c3628f68cdab89f2e7a946cd628c04e721
  cmake_build spirv-cross -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF
  license spirv-cross LICENSE

  # shaderc is built against the glslang 16.6.0 sources fetched above (one
  # glslang version in the bundle) and the SPIRV-Tools / SPIRV-Headers of the
  # same Vulkan SDK (SPIRV-Tools equals shaderc's own DEPS pin ef96ed76).
  # SPIRV-Tools is linked statically into shaderc_shared.
  fetch spirv-headers \
    "https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz" \
    5b3a0d099f5c7649e29c0938476c462e71d66ad89a0bde42fa1ba3eb476956c9
  fetch spirv-tools \
    "https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/vulkan-sdk-$VK_SDK.tar.gz" \
    e6c83a215538fbfd265ccf398d3877985055df1273dbed73912bd05307664688
  fetch shaderc https://github.com/google/shaderc/archive/refs/tags/v2026.4.tar.gz \
    f06ce5bcca94e5df7f34e115743597d0ad2e13c5fe9213c67dc8c76031241947
  # shaderc's install step also installs the glslang, SPIRV-Tools and
  # SPIRV-Headers it builds from source. It is staged first because that
  # glslang (optimizer on) must not overwrite the one libplacebo links
  # statically. Only shaderc's headers, import library, DLL and pkg-config
  # file are copied into PREFIX.
  shaderc_stage="$work/shaderc-stage"
  rm -rf "$shaderc_stage"
  cmake_dest="$shaderc_stage" cmake_build shaderc -DBUILD_SHARED_LIBS=OFF \
    -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_EXECUTABLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSHADERC_ENABLE_WERROR_COMPILE=OFF -DSPIRV_SKIP_EXECUTABLES=ON \
    -DSHADERC_GLSLANG_DIR="$(cygpath -m "$work/src/glslang")" \
    -DSHADERC_SPIRV_TOOLS_DIR="$(cygpath -m "$work/src/spirv-tools")" \
    -DSHADERC_SPIRV_HEADERS_DIR="$(cygpath -m "$work/src/spirv-headers")"
  mkdir -p "$prefix/bin" "$prefix/include/shaderc"
  cp "$shaderc_stage"/include/shaderc/*.h* "$prefix/include/shaderc/"
  cp "$shaderc_stage/lib/libshaderc_shared.dll.a" "$prefix/lib/"
  cp "$shaderc_stage/bin/libshaderc_shared.dll" "$prefix/bin/"
  # The staged shaderc.pc points at the staging directory.
  sed "s|^prefix=.*|prefix=$prefix|" "$shaderc_stage/lib/pkgconfig/shaderc.pc" \
    > "$prefix/lib/pkgconfig/shaderc.pc"
  license shaderc LICENSE
  license spirv-tools LICENSE
  license spirv-headers LICENSE
fi

# --- Color management ---------------------------------------------------
fetch lcms2 https://github.com/mm2/Little-CMS/releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz \
  bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8
meson_build lcms2 -Djpeg=disabled -Dtiff=disabled -Dutils=false
license lcms2 LICENSE

# --- libplacebo ---------------------------------------------------------
# mpv 0.42 requires >= 7.387.0. The 16 backports used with 7.360.1 were all
# ancestors of 7.387.0 and have been removed (see native/patches/UPSTREAM.md).
fetch libplacebo https://code.videolan.org/videolan/libplacebo/-/archive/v7.387.0/libplacebo-v7.387.0.tar.bz2 \
  14ceeeb14d1c08fcdb1a782a06129da11f842c6fddbf3a43c1c4061406ad03d2
# Vulkan everywhere, plus pl_d3d11 on Windows (mpv_kit's native D3D11 path;
# an OpenGL backend would only add size). Dolby Vision metadata is handled
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
# pl_d3d11 renders through SPIRV-Cross plus the inbox d3dcompiler_47.dll.
placebo_d3d11=disabled
if [ "$os" = windows ]; then placebo_d3d11=enabled; fi
meson_build libplacebo -Dprefer_static=true -Dvulkan-sdk="$nprefix" \
  -Dc_args="-I$nprefix/include" -Dcpp_args="-I$nprefix/include" \
  -Dvulkan=enabled -Dvk-proc-addr=enabled \
  -Dvulkan-registry="$nprefix/share/vulkan/registry/vk.xml" \
  -Dopengl=disabled -Dd3d11=$placebo_d3d11 -Dglslang=enabled -Dshaderc=disabled \
  -Dlcms=enabled -Ddovi=enabled -Dlibdovi=disabled -Dunwind=disabled \
  -Dxxhash=disabled -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false
license libplacebo LICENSE

# --- Optical disc support (GPL full flavor) --------------------------------
# mpv 0.42 gates CD and DVD behind -Dgpl; the 0.1.0-dev.10 bundle is GPL.
# Blu-ray/UHD and its AACS/BD+ helpers are LGPL but dlopened by libbluray,
# so they are copied explicitly by package.sh.
fetch libgpg-error https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.61.tar.bz2 \
  7a85413f2bc354f4f8aa832b718af122e48965e9e0eb9012ee659c13c6385c93
autotools_build libgpg-error --disable-doc --disable-tests \
  --disable-languages --disable-werror --enable-install-gpg-error-config
license libgpg-error COPYING COPYING.LIB

fetch libgcrypt https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.12.4.tar.bz2 \
  d77f68f48879510e79a2f65977ccc68981781ea0923e5bdffac2a193ea3d660e
gcrypt_args=()
if [ "$os" = windows ]; then
  # MSYS2 CLANG64 cannot assemble libgcrypt's GAS sources; software AES is
  # plenty for AACS/BD+ key derivation.
  gcrypt_args+=(--disable-asm)
  # libgpg-error builds a static-only archive on MinGW and libtool drops it
  # from libgcrypt's shared link, so force the archive into the DLL.
  LDFLAGS="-Wl,--whole-archive $nprefix/lib/libgpg-error.a -Wl,--no-whole-archive" \
    autotools_build libgcrypt --disable-large-data-tests \
      --disable-hmac-binary-check --disable-werror "${gcrypt_args[@]}"
else
  autotools_build libgcrypt --disable-large-data-tests \
    --disable-hmac-binary-check --disable-werror
fi
license libgcrypt COPYING COPYING.LIB

fetch libaacs https://download.videolan.org/pub/videolan/libaacs/0.11.1/libaacs-0.11.1.tar.bz2 \
  a88aa0ebe4c98a77f7aeffd92ab3ef64ac548c6b822e8248a8b926725bea0a39
autotools_build libaacs --disable-werror
license libaacs COPYING

fetch libbdplus https://download.videolan.org/pub/videolan/libbdplus/0.2.0/libbdplus-0.2.0.tar.bz2 \
  b93eea3eaef33d6e9155d2c34b068c505493aa5a4936e63274f4342ab0f40a58
autotools_build libbdplus --disable-werror
license libbdplus COPYING

fetch libudfread https://download.videolan.org/pub/videolan/libudfread/libudfread-1.2.0.tar.xz \
  bb477cbd4cfbfc7787d9d05b71ee5e70430f5cfebf1297497f7e83547958050f
meson_build libudfread -Denable_examples=false
license libudfread COPYING

fetch libxml2 https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.4.tar.xz \
  98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821
cmake_build libxml2 -DBUILD_SHARED_LIBS=ON \
  -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_ICONV=OFF \
  -DLIBXML2_WITH_HTTP=OFF -DLIBXML2_WITH_PROGRAMS=OFF \
  -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_ZLIB=OFF
license libxml2 Copyright

fetch libbluray https://code.videolan.org/videolan/libbluray/-/archive/1.5.1/libbluray-1.5.1.tar.bz2 \
  0f415b559d7f074ba78db259f61c3c61458057263a0181aaafdee1856b0fb17f
# HDMV menus only: no BD-J JAR (no JVM), no font stack (menus are bitmaps).
# libaacs/libbdplus are dlopened at runtime; package.sh ships them.
meson_build libbluray -Denable_docs=false -Denable_tools=false \
  -Denable_devtools=false -Denable_examples=false -Dbdj_jar=disabled \
  -Dfreetype=disabled -Dfontconfig=disabled -Dlibxml2=enabled \
  -Dembed_udfread=false
license libbluray COPYING

fetch libdvdcss https://download.videolan.org/pub/videolan/libdvdcss/1.6.0/libdvdcss-1.6.0.tar.xz \
  7ea556c846b7bfc32d47b41cae56d1863a6b6d5f706bb162778d6f298490977c
autotools_build libdvdcss
license libdvdcss COPYING

fetch libdvdread https://code.videolan.org/videolan/libdvdread/-/archive/v7.1.1/libdvdread-7.1.1.tar.bz2 \
  6dec544f502d7af70c5a8f8f19a49ffe2daca60dbd8fc0b4ffe3597fa791c24c
meson_build libdvdread -Denable_docs=false -Dlibdvdcss=enabled
license libdvdread COPYING

fetch libdvdnav https://code.videolan.org/videolan/libdvdnav/-/archive/v7.0.0/libdvdnav-7.0.0.tar.bz2 \
  1363cdfaf6e92c0b574579299b5480f5867fb32989451468a28f3f402ec48787
meson_build libdvdnav -Denable_docs=false -Denable_examples=false
license libdvdnav COPYING

fetch libcdio https://github.com/libcdio/libcdio/releases/download/2.3.0/libcdio-2.3.0.tar.bz2 \
  53e83d284667535a767fd2d31edad1a6701591960459df373a10f1f21e80a7ed
autotools_build libcdio --disable-cxx --disable-cpp-progs \
  --disable-example-progs --disable-vcd-info
license libcdio COPYING

# --- HTTP/2 stream backend (curl, HTTP/2 only) -----------------------------
fetch mbedtls https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2 \
  a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
cmake_build mbedtls -DBUILD_SHARED_LIBS=ON \
  -DUSE_SHARED_MBEDTLS_LIBRARY=ON -DUSE_STATIC_MBEDTLS_LIBRARY=OFF \
  -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DMBEDTLS_FATAL_WARNINGS=OFF
license mbedtls LICENSE

fetch nghttp2 https://github.com/nghttp2/nghttp2/releases/download/v1.70.0/nghttp2-1.70.0.tar.xz \
  e05cb1388eaca3830aded4ccf20044b6e1ac1a61411dcca11b0437c4285c8bc2
cmake_build nghttp2 -DENABLE_LIB_ONLY=ON -DENABLE_APP=OFF \
  -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_HPACK_TOOLS=OFF \
  -DENABLE_STATIC_LIB=OFF -DENABLE_SHARED_LIB=ON
license nghttp2 COPYING

fetch curl https://curl.se/download/curl-8.23.0.tar.xz \
  8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
cmake_build curl -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF \
  -DBUILD_CURL_EXE=OFF -DCURL_USE_MBEDTLS=ON -DUSE_NGHTTP2=ON \
  -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DUSE_LIBIDN2=OFF \
  -DCURL_ZSTD=OFF -DCURL_BROTLI=OFF -DCURL_DISABLE_LDAP=ON \
  -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMB=ON \
  -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_IMAP=ON \
  -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_TFTP=ON \
  -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_MQTT=ON
license curl COPYING

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
