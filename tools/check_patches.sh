#!/usr/bin/env bash
# Patch-drift gate (BUILD-01): proves the vendored mpv tree is exactly
# upstream-base + native/patches/0*.patch (applied in name order).
#
# Run from the repo root:
#   bash tools/check_patches.sh
#
# The base commit comes from native/mpv/MPV_VERSION (e.g.
# v0.41.0-1113-gfd9265a905). Patches are applied with GNU patch -p1 --
# git apply reports false success on these patches (see
# native/patches/UPSTREAM.md).
#
# Exclusions: only .git and .gitignore. Anything else that would need
# excluding must be added here with an explicit justification comment --
# silent exclusions defeat the gate.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version_file="$root/native/mpv/MPV_VERSION"

base_desc="$(tr -d ' \t\r\n' < "$version_file")"
short_sha="${base_desc##*-g}"
if [[ ! "$short_sha" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "CHECK-PATCHES FAIL: cannot parse a commit sha from $version_file ('$base_desc')" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "CHECK-PATCHES: cloning mpv (blobless) ..."
# LF working tree regardless of the host's autocrlf: the vendored tree is LF.
git -c core.autocrlf=false clone --quiet --filter=blob:none --no-checkout \
  https://github.com/mpv-player/mpv.git "$tmp/mpv"
# `-c` does not persist into the new repo; pin it there or the later
# checkout converts every file to CRLF and the diff explodes.
git -C "$tmp/mpv" config core.autocrlf false
# Short shas are not valid fetch refs; fetch the master branch (blobless:
# commits+trees only, blobs arrive on checkout) and resolve the sha locally.
git -C "$tmp/mpv" fetch --quiet origin master
if ! git -C "$tmp/mpv" cat-file -e "${short_sha}^{commit}" 2>/dev/null; then
  # The commit may live on another ref: fetch all refs and retry.
  git -C "$tmp/mpv" fetch --quiet origin \
    '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*'
fi
git -C "$tmp/mpv" checkout --quiet --detach "$short_sha"
echo "CHECK-PATCHES: base $(git -C "$tmp/mpv" rev-parse HEAD)"

shopt -s nullglob
patches=("$root"/native/patches/0*.patch)
if [[ "${#patches[@]}" -eq 0 ]]; then
  echo "CHECK-PATCHES FAIL: no patches found in native/patches" >&2
  exit 1
fi
for p in "${patches[@]}"; do
  patch --forward --silent --no-backup-if-mismatch -p1 -d "$tmp/mpv" < "$p"
done
echo "CHECK-PATCHES: applied ${#patches[@]} patches"
# patch leaves .orig/.rej artifacts when hunks fail or shift; they are not
# part of the provenance comparison.
find "$tmp/mpv" -name '*.orig' -o -name '*.rej' | while read -r f; do rm -f "$f"; done

# Exclusions: .git (the clone's metadata) and .gitignore (vendored tree has
# its own upstream .gitignore state committed as part of vendoring).
if ! diff -r --exclude=.git --exclude=.gitignore "$tmp/mpv" "$root/native/mpv"; then
  echo "CHECK-PATCHES FAIL: native/mpv differs from base($base_desc) + patches" >&2
  echo "CHECK-PATCHES FAIL: base $(git -C "$tmp/mpv" rev-parse HEAD), ${#patches[@]} patches applied" >&2
  exit 1
fi

echo "PATCH-DRIFT OK base=$(git -C "$tmp/mpv" rev-parse HEAD) patches=${#patches[@]}"
