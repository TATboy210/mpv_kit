#!/usr/bin/env bash
# Collects libmpv and every non-system library it loads into OUTDIR, makes
# the set relocatable (loader-relative lookup), and fails if any GPL-only
# library slipped into the closure.
#
# usage: native/build/package.sh PREFIX OUTDIR
#   PREFIX  install prefix of the libmpv build (FFmpeg in the same prefix)
#   OUTDIR  created; receives lib/, include/ and MANIFEST.txt
set -euo pipefail

prefix=$(cd "${1:?usage: package.sh PREFIX OUTDIR}" && pwd)
out=${2:?usage: package.sh PREFIX OUTDIR}
root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$out/lib" "$out/include"
out=$(cd "$out" && pwd)

# Libraries whose license would turn the bundle into a GPL work.
gpl_pattern='x264|x265|xvid|postproc|rubberband|vidstab|frei0r|libcdio|dvdnav|dvdread|davs2|xavs|smbclient'

check_gpl() {
  local bad
  bad=$(ls "$out/lib" | grep -iE "$gpl_pattern" || true)
  if [ -n "$bad" ]; then
    echo "GPL library in bundle: $bad" >&2
    exit 1
  fi
}

# libmpv must resolve FFmpeg from PREFIX (the LGPL build), never from a
# system copy that may be GPL.
require_prefix_avcodec() {
  if ! echo "$1" | grep -i avcodec | grep -qF "$2"; then
    echo "libavcodec is not resolved from $2:" >&2
    echo "$1" | grep -i avcodec >&2 || true
    exit 1
  fi
}

case "$(uname -s)" in
  Linux)
    # Host libraries every desktop provides (and that must match the host:
    # libc, GPU drivers, display servers). Everything else is bundled.
    # Exact library names (anchored at ".so" so that e.g. libc does not
    # also match libcairo/libcap). X11 libraries are matched as families.
    system='^(linux-vdso|ld-linux-[a-z0-9_-]+|libc|libm|libdl|libpthread|librt|libresolv|libstdc\+\+|libgcc_s|libz|libX[a-zA-Z0-9]*|libxcb[a-z0-9-]*|libwayland-[a-z]+|libEGL|libGL|libGLX|libGLdispatch|libgbm|libdrm|libvulkan|libva|libva-[a-z0-9]+|libvdpau|libasound|libpulse|libpulse-simple|libpipewire-[0-9.]+|libjack|libsystemd|libudev|libdbus-1|libssl|libcrypto|libexpat|libffi|libuuid|libxkbcommon|libgnutls|libfontconfig)\.so'
    # meson installs without an rpath; resolve our own libraries from PREFIX.
    deps=$(LD_LIBRARY_PATH="$prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      ldd "$prefix/lib/libmpv.so.2")
    if echo "$deps" | grep -q 'not found'; then
      echo "unresolved libmpv dependencies:" >&2
      echo "$deps" | grep 'not found' >&2
      exit 1
    fi
    require_prefix_avcodec "$deps" "$prefix"
    # Only the soname file: bundles carry regular files, no symlinks.
    cp -L "$prefix/lib/libmpv.so.2" "$out/lib/"
    echo "$deps" | awk '/=> \//{print $1" "$3}' |
      while read -r name path; do
        if ! echo "$name" | grep -qE "$system"; then cp -L "$path" "$out/lib/$name"; fi
      done
    for f in "$out"/lib/*.so*; do patchelf --set-rpath '$ORIGIN' "$f"; done
    ;;
  Darwin)
    require_prefix_avcodec "$(otool -L "$prefix/lib/libmpv.2.dylib")" "$prefix"
    cp "$prefix/lib/libmpv.2.dylib" "$out/lib/"
    # Rewrites install names to @rpath and copies the closure next to it.
    dylibbundler -of -cd -b -x "$out/lib/libmpv.2.dylib" \
      -d "$out/lib" -p @loader_path/ -s "$prefix/lib"
    # Every install id must equal the name it is referenced by, so that
    # Flutter's native-assets packaging can rewrite both consistently.
    for f in "$out"/lib/*.dylib; do
      install_name_tool -id "@loader_path/$(basename "$f")" "$f"
    done
    # MoltenVK (libmpv links it directly, see deps.sh) is part of the
    # closure; the Flutter plugin loads the same copy.
    [ -f "$out/lib/libMoltenVK.dylib" ] || { echo "libMoltenVK.dylib missing from bundle" >&2; exit 1; }
    # install_name_tool invalidates signatures; arm64 refuses unsigned code.
    codesign --force --sign - "$out"/lib/*.dylib
    ;;
  MINGW*|MSYS*)
    # ntldd prints Windows paths; compare them in forward-slash form.
    require_prefix_avcodec \
      "$(ntldd -R "$prefix/bin/libmpv-2.dll" | tr -d '\r' | sed 's#\\#/#g')" \
      "$(cygpath -m "$prefix")"
    cp "$prefix/bin/libmpv-2.dll" "$out/lib/"
    # ntldd reads PE imports natively; keep only MSYS2 environment DLLs and
    # our own prefix (Windows system DLLs are not redistributed).
    ntldd -R "$prefix/bin/libmpv-2.dll" | tr -d '\r' |
      sed -nE 's/.*=> (.*) \(0x[0-9a-fA-F]+\)$/\1/p' |
      while read -r dll; do
        unix=$(cygpath -u "$dll")
        case "$unix" in
          "$prefix"/*|/clang64/*|/clangarm64/*) cp "$unix" "$out/lib/" ;;
        esac
      done
    python -I "$root/tools/rea_abi_audit/pe_audit.py" "$out/lib/libmpv-2.dll" \
      --expect "$root/tools/rea_abi_audit/expected_symbols.txt" --forbid-gpl
    ;;
  *)
    echo "unsupported host $(uname -s)" >&2
    exit 1
    ;;
esac

check_gpl
cp -r "$prefix/include/mpv" "$out/include/"
cp "$root/native/mpv/LICENSE.LGPL" "$out/LICENSE.LGPL"
# Third-party licenses of the bundled dependencies (deps.sh).
if [ -d "$prefix/share/licenses" ]; then cp -r "$prefix/share/licenses" "$out/"; fi
cp "$root/native/patches/"*.patch "$out/"

# Manifest: every shipped file with its sha256, for mpv_kit_libs to verify.
(
  cd "$out"
  find . -type f ! -name MANIFEST.txt | LC_ALL=C sort | while read -r f; do
    if command -v sha256sum >/dev/null; then sha256sum "$f"; else shasum -a 256 "$f"; fi
  done
) > "$out/MANIFEST.txt"
echo "packaged $(ls "$out/lib" | wc -l | tr -d ' ') libraries into $out"
