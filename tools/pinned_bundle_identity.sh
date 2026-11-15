#!/usr/bin/env bash
# Proves which libmpv a build or a test run used: the one the build hook
# downloaded from the release pinned in packages/mpv_kit_libs/lib/src/bundles.dart.
# Used by the pinned-only steps of flutter-plugin.yml (Phase 17.1) and by the
# RTX check of Plan 17.1-06.
#
# usage:  pinned_bundle_identity.sh TARGET [APP_LIB_DIR]
#   TARGET       bundle target (linux-x64, windows-x64, macos-arm64, ...)
#   APP_LIB_DIR  optional: the directory the built app loads its shared
#                libraries from (e.g. example/build/windows/x64/runner/Debug)
#
# Checks, in order (the first failure ends the run):
#   1. the hook stamp `<target>.ok` holds the pinned sha256;
#   2. the cached archive `libmpv-<target>.tar.gz` hashes to the pin;
#   3. the extracted bundle verifies against its own MANIFEST.txt;
#   4. the MANIFEST lists shared libraries directly under lib/ (the set the
#      hook emits as code assets, symlinks excluded);
#   5. with APP_LIB_DIR: every such library is in it, byte-identical;
#   6. with MPV_KIT_LIBMPV_PATH set: it names the cache copy (same hash as the
#      MANIFEST entry, same directory as <target>/lib of the hook cache).
#
# Output (stdout, one line):
#   PINNED-IDENTITY tag=<tag> target=<target> stamp=match archive=match
#     manifest=ok libs=<n> app_copy=<same|skipped> libmpv_env=<unset|hook-cache>
#     libmpv_sha256=<MANIFEST hash of libmpv-2.dll | libmpv.so.2 | libmpv.2.dylib>
#   or  PINNED-IDENTITY FAIL tag=<tag> target=<target> reason=<what>
# Exit: 0 identity proven, 1 a check failed, 2 usage error.
# Read-only: it never writes or deletes anything.
set -uo pipefail

target="${1:-}"
app_dir="${2:-}"
if [ -z "$target" ]; then
  echo "usage: pinned_bundle_identity.sh TARGET [APP_LIB_DIR]" >&2
  exit 2
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bundles="$root/packages/mpv_kit_libs/lib/src/bundles.dart"
tag=$(sed -n "s/^const bundleTag = '\([^']*\)';.*/\1/p" "$bundles")
pin=$(sed -n "s/^  '$target': '\([0-9a-f]\{64\}\)',.*/\1/p" "$bundles")

fail() {
  echo "PINNED-IDENTITY FAIL tag=$tag target=$target reason=$1"
  exit 1
}

# The tool needs the pin to compare against; a target without one has no
# bundle (the hook emits nothing for it).
[ -n "$tag" ] || fail "no bundleTag in bundles.dart"
[ -n "$pin" ] || fail "no pin for target in bundles.dart"

cache="$root/.dart_tool/hooks_runner/shared/mpv_kit_libs/build/$tag"
dir="$cache/$target"
manifest="$dir/MANIFEST.txt"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Hash of a path as listed in the MANIFEST (`<sha256> *./<path>` or
# `<sha256>  ./<path>`).
manifest_hash() {
  awk -v p="$1" '{ f = $2; sub(/^\*/, "", f); sub(/^\.\//, "", f);
                   if (f == p) { print $1; exit } }' "$manifest"
}

# 1. stamp
[ -f "$cache/$target.ok" ] || fail "stamp missing"
[ "$(cat "$cache/$target.ok")" = "$pin" ] || fail "stamp differs from pin"

# 2. cached archive
[ -f "$cache/libmpv-$target.tar.gz" ] || fail "archive missing"
[ "$(sha256_of "$cache/libmpv-$target.tar.gz")" = "$pin" ] ||
  fail "archive sha256 differs from pin"

# 3. extracted bundle against its own manifest
[ -f "$manifest" ] || fail "MANIFEST.txt missing"
(cd "$dir" && sha256sum -c --quiet MANIFEST.txt >/dev/null 2>&1) ||
  fail "extracted bundle differs from MANIFEST.txt"

# 4. shared libraries directly under lib/ (what sharedLibrariesIn emits)
libs=()
while IFS= read -r rel; do
  [ -L "$dir/$rel" ] && continue
  libs+=("${rel#lib/}")
done < <(awk '{ f = $2; sub(/^\*/, "", f); sub(/^\.\//, "", f); print f }' "$manifest" |
  grep -E '^lib/[^/]+(\.dll|\.dylib|\.so(\.[0-9]+)*)$')
[ "${#libs[@]}" -gt 0 ] || fail "no shared library under lib/ in MANIFEST"

case "$target" in
  windows-*) libmpv_name="libmpv-2.dll" ;;
  linux-*) libmpv_name="libmpv.so.2" ;;
  macos-*) libmpv_name="libmpv.2.dylib" ;;
  *) fail "unknown target family" ;;
esac
libmpv_sha=$(manifest_hash "lib/$libmpv_name")
[ -n "$libmpv_sha" ] || fail "$libmpv_name not in MANIFEST"

# 5. the app's own copies
app_copy=skipped
if [ -n "$app_dir" ]; then
  [ -d "$app_dir" ] || fail "app dir missing"
  for name in "${libs[@]}"; do
    [ -f "$app_dir/$name" ] || fail "app copy missing: $name"
    [ "$(sha256_of "$app_dir/$name")" = "$(manifest_hash "lib/$name")" ] ||
      fail "app copy differs: $name"
  done
  app_copy=same
fi

# 6. MPV_KIT_LIBMPV_PATH is unset or the hook-cache copy
libmpv_env=unset
if [ -n "${MPV_KIT_LIBMPV_PATH:-}" ]; then
  env_file="$MPV_KIT_LIBMPV_PATH"
  if command -v cygpath >/dev/null 2>&1; then
    env_file=$(cygpath -u "$env_file")
  fi
  [ -f "$env_file" ] || fail "MPV_KIT_LIBMPV_PATH names no file"
  base=$(basename "$env_file")
  expected=$(manifest_hash "lib/$base")
  [ -n "$expected" ] || fail "MPV_KIT_LIBMPV_PATH file not in MANIFEST"
  [ "$(sha256_of "$env_file")" = "$expected" ] ||
    fail "MPV_KIT_LIBMPV_PATH file differs from MANIFEST"
  [ "$(cd "$(dirname "$env_file")" && pwd -P)" = "$(cd "$dir/lib" && pwd -P)" ] ||
    fail "MPV_KIT_LIBMPV_PATH is outside the hook cache"
  libmpv_env=hook-cache
fi

echo "PINNED-IDENTITY tag=$tag target=$target stamp=match archive=match manifest=ok libs=${#libs[@]} app_copy=$app_copy libmpv_env=$libmpv_env libmpv_sha256=$libmpv_sha"
exit 0
