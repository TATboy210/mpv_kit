#!/usr/bin/env bash
# Prints the size and the minimum OS requirement of a packaged bundle and
# fails if it needs more than promised.
#
# usage: tools/bundle_report.sh BUNDLE_DIR [MAX_MACOS_VERSION]
#   Linux: highest GLIBC_/GLIBCXX_ symbol version any library needs.
#   macOS: highest LC_BUILD_VERSION minos; fails above MAX_MACOS_VERSION.
set -euo pipefail

dir=${1:?usage: bundle_report.sh BUNDLE_DIR [MAX_MACOS_VERSION]}
name=$(basename "$dir")
lib="$dir/lib"

# Largest files first, sizes in KiB.
du -k "$lib"/* | sort -rn | awk '{printf "%8.1f MiB  %s\n", $1/1024, $2}'
total=$(du -sk "$dir" | cut -f1)
count=$(find "$lib" -type f | wc -l | tr -d ' ')
echo "::notice::$name: $count libraries, $(awk -v k="$total" 'BEGIN{printf "%.1f", k/1024}') MiB unpacked"

case "$(uname -s)" in
  Linux)
    need() {
      objdump -T "$lib"/*.so* | grep -oE "\b$1_[0-9]+(\.[0-9]+)*\b" | sort -uV | tail -1
    }
    echo "::notice::$name requires $(need GLIBC) and $(need GLIBCXX || echo 'no libstdc++')"
    ;;
  Darwin)
    max=${2:-}
    worst=0
    for f in "$lib"/*.dylib; do
      v=$(otool -l "$f" | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')
      [ -n "$v" ] || v=$(otool -l "$f" | awk '/LC_VERSION_MIN_MACOSX/{b=1} b&&/version/{print $2; exit}')
      printf '%-36s macOS %s\n' "$(basename "$f")" "$v"
      worst=$(printf '%s\n%s\n' "$worst" "$v" | sort -V | tail -1)
    done
    echo "::notice::$name requires macOS $worst+"
    if [ -n "$max" ] && [ "$(printf '%s\n%s\n' "$worst" "$max" | sort -V | tail -1)" != "$max" ]; then
      echo "::error::$name requires macOS $worst, more than $max" >&2
      exit 1
    fi
    ;;
esac
