#!/usr/bin/env bash
# Collects libmpv and every non-system library it loads into OUTDIR, makes
# the set relocatable (loader-relative lookup), and enforces the license
# contract of the selected flavor.
#
# usage: native/build/package.sh PREFIX OUTDIR
#   PREFIX  install prefix of the libmpv build (FFmpeg in the same prefix)
#   OUTDIR  created; receives lib/, include/, licenses and MANIFEST.txt
#   MPV_KIT_FLAVOR=gpl|lgpl (default gpl): "gpl" ships the disc-capable
#   bundle; "lgpl" keeps the old LGPL-only contract for self-builders.
set -euo pipefail

prefix=$(cd "${1:?usage: package.sh PREFIX OUTDIR}" && pwd)
out=${2:?usage: package.sh PREFIX OUTDIR}
root=$(cd "$(dirname "$0")/../.." && pwd)
flavor=${MPV_KIT_FLAVOR:-gpl}
case "$flavor" in gpl|lgpl) ;; *)
  echo "MPV_KIT_FLAVOR must be gpl or lgpl (got '$flavor')" >&2; exit 1;;
esac
mkdir -p "$out/lib" "$out/include"
out=$(cd "$out" && pwd)

# Libraries whose license turns an LGPL bundle into a GPL work.
gpl_pattern='x264|x265|xvid|postproc|rubberband|vidstab|frei0r|libcdio|dvdnav|dvdread|davs2|xavs|smbclient'
# The GPL full flavor must actually contain the disc stack.
full_pattern='libdvdnav|libdvdread|libcdio|libbluray|libcurl|libaacs|libbdplus'

check_flavor() {
  if [ "$flavor" = lgpl ]; then
    local bad
    bad=$(ls "$out/lib" | grep -iE "$gpl_pattern" || true)
    if [ -n "$bad" ]; then
      echo "GPL library in an LGPL bundle: $bad" >&2
      exit 1
    fi
    return
  fi
  local missing
  missing=$(ls "$out/lib" | grep -ciE "$full_pattern" || true)
  if [ "$missing" -lt 7 ]; then
    echo "GPL bundle is missing part of the disc stack:" >&2
    ls "$out/lib" >&2
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
    system='^(linux-vdso|ld-linux-[a-z0-9_-]+|libc|libm|libdl|libpthread|librt|libresolv|libstdc\+\+|libgcc_s|libz|libX[a-zA-Z0-9-]*|libxcb[a-z0-9-]*|libwayland-[a-z]+|libEGL|libGL|libGLX|libGLdispatch|libgbm|libdrm|libvulkan|libva|libva-[a-z0-9]+|libvdpau|libasound|libpulse|libpulse-simple|libpipewire-[0-9.]+|libjack|libsystemd|libudev|libdbus-1|libssl|libcrypto|libexpat|libffi|libuuid|libxkbcommon|libgnutls|libfontconfig)\.so'
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
    # Walk DT_NEEDED from libmpv, never descending into host libraries:
    # their own dependencies (libpulse -> libpulsecommon, libsndfile, ...)
    # must come from the host too. ldd's flat closure cannot tell them apart.
    paths=$(echo "$deps" | awk '/=> \//{print $1" "$3}')
    queue="libmpv.so.2"
    while [ -n "$queue" ]; do
      set -- $queue
      cur=$1
      shift
      queue="$*"
      for need in $(objdump -p "$out/lib/$cur" | awk '/NEEDED/{print $2}'); do
        echo "$need" | grep -qE "$system" && continue
        [ -f "$out/lib/$need" ] && continue
        src=$(echo "$paths" | awk -v n="$need" '$1==n{print $2; exit}')
        if [ -z "$src" ]; then echo "cannot resolve $need" >&2; exit 1; fi
        cp -L "$src" "$out/lib/$need"
        queue="$queue $need"
      done
    done
    # libbluray dlopens libaacs/libbdplus, and those link libgcrypt/
    # libgpg-error; none is in libmpv's DT_NEEDED. Copy one soname each.
    for base in libaacs libbdplus libgcrypt libgpg-error; do
      f=$(ls "$prefix/lib/$base".so.* 2>/dev/null | head -1 || true)
      [ -n "$f" ] && cp -L "$f" "$out/lib/$(basename "$f")"
    done
    for f in "$out"/lib/*.so*; do patchelf --set-rpath '$ORIGIN' "$f"; done
    ;;
  Darwin)
    require_prefix_avcodec "$(otool -L "$prefix/lib/libmpv.2.dylib")" "$prefix"
    cp "$prefix/lib/libmpv.2.dylib" "$out/lib/"
    # Rewrites install names to @rpath and copies the closure next to it.
    dylibbundler -of -cd -b -x "$out/lib/libmpv.2.dylib" \
      -d "$out/lib" -p @loader_path/ -s "$prefix/lib"
    # libbluray dlopens libaacs/libbdplus; dylibbundler never sees them in
    # libmpv's closure. Copy and relocate them (and their crypto deps).
    for base in libaacs libbdplus libgcrypt libgpg-error; do
      f=$(ls "$prefix/lib/$base"*.dylib 2>/dev/null | head -1 || true)
      [ -n "$f" ] && cp -L "$f" "$out/lib/"
    done
    # libbluray calls dlopen("libaacs") with version=NULL on macOS, i.e.
    # libaacs.dylib (unversioned).
    for base in libaacs libbdplus; do
      f=$(ls "$out/lib/$base".*.dylib 2>/dev/null | head -1 || true)
      [ -n "$f" ] && cp "$f" "$out/lib/$base.dylib"
    done
    for x in "$out"/lib/libaacs*.dylib "$out"/lib/libbdplus*.dylib; do
      [ -e "$x" ] || continue
      dylibbundler -of -cd -b -x "$x" -d "$out/lib" -p @loader_path/ \
        -s "$prefix/lib"
    done
    # Every install id must equal the name it is referenced by, so that
    # Flutter's native-assets packaging can rewrite both consistently.
    for f in "$out"/lib/*.dylib; do
      install_name_tool -id "@loader_path/$(basename "$f")" "$f"
    done
    # MoltenVK (libmpv links it directly, see deps.sh) is part of the
    # closure; the Flutter plugin loads the same copy.
    [ -f "$out/lib/libMoltenVK.dylib" ] || { echo "libMoltenVK.dylib missing from bundle" >&2; exit 1; }
    # Flutter/dart native-assets packaging rewrites every install name to
    # an absolute or framework path; without header room that fails with
    # "larger updated load commands do not fit".
    for f in "$out"/lib/*.dylib; do
      cmds=$(otool -h "$f" | awk 'NR==4{print $7}')
      first=$(otool -l "$f" | awk '$1=="offset" && $2>0{print $2}' | sort -n | head -1)
      pad=$((first - 32 - cmds))
      if [ "$pad" -lt 1024 ]; then
        echo "$(basename "$f"): only $pad bytes of Mach-O header padding" >&2
        exit 1
      fi
    done
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
          "$prefix"/*) cp "$unix" "$out/lib/" ;;
          # MSYS2 ships some DLLs with their COFF symbol table (libc++ carries
          # 3764 symbols, 250 KB); our own prefix is already installed with
          # --strip. --strip-all drops the whole COFF symbol table
          # (--strip-unneeded keeps its global symbols, which left dev.5
          # candidates unchanged); exports live in the PE export table and
          # are untouched, and the audit below still runs.
          /clang64/*|/clangarm64/*)
            cp "$unix" "$out/lib/"
            llvm-strip --strip-all "$out/lib/$(basename "$unix")" ;;
        esac
      done
    # libbluray dlopens libaacs/libbdplus; copy them and their MSYS2 deps.
    for f in "$prefix"/bin/libaacs*.dll "$prefix"/bin/libbdplus*.dll \
             "$prefix"/bin/libgcrypt*.dll "$prefix"/bin/libgpg-error*.dll; do
      [ -e "$f" ] && cp "$f" "$out/lib/"
    done
    # libbluray's dl_win32 appends ".dll" to the bare name (libaacs.dll),
    # while MSYS2 installs libaacs-0.dll.
    for base in libaacs libbdplus; do
      f=$(ls "$out/lib/$base"-*.dll 2>/dev/null | head -1 || true)
      [ -n "$f" ] && cp "$f" "$out/lib/$base.dll"
    done
    for dll in "$out"/lib/libaacs*.dll "$out"/lib/libbdplus*.dll \
               "$out"/lib/libgcrypt*.dll "$out"/lib/libgpg-error*.dll; do
      [ -e "$dll" ] || continue
      ntldd -R "$dll" | tr -d '\r' |
        sed -nE 's/.*=> (.*) \(0x[0-9a-fA-F]+\)$/\1/p' |
        while read -r dep; do
          unix=$(cygpath -u "$dep")
          case "$unix" in
            "$prefix"/*) cp "$unix" "$out/lib/" ;;
            /clang64/*|/clangarm64/*)
              cp "$unix" "$out/lib/"
              llvm-strip --strip-all "$out/lib/$(basename "$unix")" ;;
          esac
        done
    done
    # D3D-02: every DLL of the bundle is audited (ANGLE/EGL ban; the GPL
    # ban applies only to the LGPL flavor); no DLL is excluded by name.
    # libmpv-2.dll also gets the symbol check.
    audit_flags=(--forbid-angle)
    [ "$flavor" = lgpl ] && audit_flags+=(--forbid-gpl)
    for dll in "$out"/lib/*.dll; do
      if [ "$(basename "$dll")" = "libmpv-2.dll" ]; then
        python -I "$root/tools/rea_abi_audit/pe_audit.py" "$dll" \
          --expect "$root/tools/rea_abi_audit/expected_symbols.txt" \
          "${audit_flags[@]}"
      else
        python -I "$root/tools/rea_abi_audit/pe_audit.py" "$dll" \
          "${audit_flags[@]}"
      fi
    done
    ;;
  *)
    echo "unsupported host $(uname -s)" >&2
    exit 1
    ;;
esac

check_flavor
cp -r "$prefix/include/mpv" "$out/include/"
cp "$root/native/mpv/LICENSE.LGPL" "$out/LICENSE.LGPL"
if [ "$flavor" = gpl ]; then
  cp "$root/native/mpv/LICENSE.GPL" "$out/LICENSE.GPL"
fi
cp "$root/NOTICE" "$out/NOTICE"
# Third-party licenses of the bundled dependencies (deps.sh).
if [ -d "$prefix/share/licenses" ]; then cp -r "$prefix/share/licenses" "$out/"; fi
cp "$root/native/patches/"*.patch "$out/"
# GPL written offer / provenance: the repository plus these pins is the
# corresponding source. Release archives also carry a source tarball.
cat > "$out/SOURCE.txt" <<EOF
mpv_kit corresponding source
=============================
Bundle flavor: $flavor
mpv: $(cat "$root/native/mpv/MPV_VERSION") (https://github.com/mpv-player/mpv)
mpv_kit (patches, build scripts, dependency pins):
  https://github.com/TATboy210/mpv_kit
  native/patches/*.patch are shipped next to this file.
Every dependency URL and sha256 is pinned in native/build/deps.sh.
This file and the repository above are the written offer for the
corresponding source of the GPL/LGPL libraries in this bundle.
EOF

# Manifest: every shipped file with its sha256, for mpv_kit_libs to verify.
(
  cd "$out"
  find . -type f ! -name MANIFEST.txt | LC_ALL=C sort | while read -r f; do
    if command -v sha256sum >/dev/null; then sha256sum "$f"; else shasum -a 256 "$f"; fi
  done
) > "$out/MANIFEST.txt"
echo "packaged $(ls "$out/lib" | wc -l | tr -d ' ') libraries into $out"
