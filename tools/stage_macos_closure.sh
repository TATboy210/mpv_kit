#!/usr/bin/env bash
# Stages the Homebrew dylib closure of the macOS verify-tier libmpv next to it
# and proves that nothing else is loaded (quick 261030-3pc).
#
# Why: the `macos` job of native-verify.yml links libmpv.2.dylib against
# whatever Homebrew bottles that runner got (libplacebo 7.387.0 ->
# libplacebo.387.dylib). The `integration-test (macos-15, ...)` job used to run
# its own `brew install` and sometimes got an older bottle (7.360.1, no
# libplacebo.387.dylib), so dlopen failed and the test threw
# MpvLibraryNotFound (runs 40917086107, 40922504734). Shipping the exact
# closure with the artifact removes the second Homebrew resolution.
#
# usage:
#   bash tools/stage_macos_closure.sh <dir>/libmpv.2.dylib
#     stage mode: walks the entry's references breadth first, copies every
#     Homebrew dylib it needs into <dir> (the entry's directory), rewrites
#     each reference to @loader_path/<leaf> with install_name_tool, re-signs
#     every modified file ad hoc, then runs the check below.
#   bash tools/stage_macos_closure.sh --check <dir>/libmpv.2.dylib
#     check mode: follows only the @loader_path/<leaf> references from the
#     entry; every reference must be an OS library or a staged leaf, and every
#     reached file must pass `codesign --verify`.
#
#   HOMEBREW_PREFIX  prefix of the Homebrew install (default: `brew --prefix`,
#                    /opt/homebrew on arm64, /usr/local on Intel)
#
# output (stdout; failures on stderr):
#   MACOS-CLOSURE file=<leaf> from=<realpath>    one per copied dylib; the
#                                                realpath is the Cellar path,
#                                                i.e. the bottle-version record
#   MACOS-CLOSURE staged=<n> rewritten=<m> resigned=<r> bytes=<b>
#                                                resigned: unmodified copies that
#                                                did not verify (Intel bottles)
#   MACOS-CLOSURE external <ref> in <file>       check: reference not allowed
#   MACOS-CLOSURE badsig <file>                  check: codesign --verify failed
#   MACOS-CLOSURE check entry=<name> files=<n> external=<k>   final check line
#   MACOS-CLOSURE fail unresolved|unexpected|collision ...    stage mode, exit 1
#
# exit codes: 0 ok; 1 failed check or staging; 2 usage error.
#
# Verify tier only: Homebrew's FFmpeg may be GPL, so the staged directory is a
# 14-day CI artifact (like the Windows msys2 stage) and never a release
# bundle. release.yml and native/build/* do not call this script.
#
# Bash 3.2 compatible (the macOS runner default shell): no associative arrays,
# no file-to-array builtins, no case-modifying expansions. The maps are TAB
# separated files in a temp dir.
set -euo pipefail

mode=stage
if [ "${1:-}" = "--check" ]; then
  mode=check
  shift
fi
if [ $# -ne 1 ]; then
  echo "usage: $0 [--check] <dir>/libmpv.2.dylib" >&2
  exit 2
fi
entry=$1
TAB=$(printf '\t')

command -v otool >/dev/null 2>&1 || { echo "MACOS-CLOSURE fail otool not found" >&2; exit 1; }
command -v realpath >/dev/null 2>&1 || { echo "MACOS-CLOSURE fail realpath not found" >&2; exit 1; }
[ -f "$entry" ] || { echo "MACOS-CLOSURE fail no such entry $entry" >&2; exit 1; }

W=$(mktemp -d "${TMPDIR:-/tmp}/stage_macos_closure.XXXXXX")
trap 'rm -rf "$W"' EXIT

dir=$(cd "$(dirname "$entry")" && pwd -P)
entry_leaf=$(basename "$entry")

fail() {
  echo "MACOS-CLOSURE fail $*" >&2
  exit 1
}

# Own install id of a Mach-O file: line 2 of `otool -D`.
id_of() {
  otool -D "$1" | sed -n 2p
}

# References of $1 (the lines after the `otool -L` header), without the
# trailing version text and without the file's own id.
refs_of() {
  local id
  id=$(id_of "$1")
  otool -L "$1" | sed 1d | sed -e 's/^[[:space:]]*//' -e 's/ (compatibility version.*$//' \
    | ID="$id" awk '$0 != ENVIRON["ID"]'
}

# LC_RPATH entries of $1, one per line.
rpaths_of() {
  otool -l "$1" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { r = 1; next }
    r && $1 == "path" {
      s = $0
      sub(/^[ \t]*path /, "", s)
      sub(/ \(offset [0-9]+\)$/, "", s)
      print s
      r = 0
    }'
}

# ---------------------------------------------------------------- check mode
do_check() {
  local files=0 external=0 bad=0 n=1 leaf f ref rel
  printf '%s\n' "$entry_leaf" > "$W/cq.txt"
  printf '%s\n' "$entry_leaf" > "$W/cv.txt"
  while :; do
    leaf=$(sed -n "${n}p" "$W/cq.txt")
    [ -n "$leaf" ] || break
    n=$((n + 1))
    f="$dir/$leaf"
    files=$((files + 1))
    if ! codesign --verify "$f" >/dev/null 2>&1; then
      echo "MACOS-CLOSURE badsig $leaf"
      bad=1
    fi
    refs_of "$f" > "$W/crefs.txt"
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      case "$ref" in
        /usr/lib/* | /System/*) ;;
        @loader_path/*)
          rel=${ref#@loader_path/}
          case "$rel" in
            */*) echo "MACOS-CLOSURE external $ref in $leaf"; external=$((external + 1)) ;;
            *)
              if [ -f "$dir/$rel" ]; then
                if ! grep -qxF -- "$rel" "$W/cv.txt"; then
                  printf '%s\n' "$rel" >> "$W/cv.txt"
                  printf '%s\n' "$rel" >> "$W/cq.txt"
                fi
              else
                echo "MACOS-CLOSURE external $ref in $leaf"
                external=$((external + 1))
              fi
              ;;
          esac
          ;;
        *)
          echo "MACOS-CLOSURE external $ref in $leaf"
          external=$((external + 1))
          ;;
      esac
    done < "$W/crefs.txt"
  done
  echo "MACOS-CLOSURE check entry=$entry_leaf files=$files external=$external"
  if [ "$external" -gt 0 ] || [ "$bad" -ne 0 ]; then
    return 1
  fi
  return 0
}

if [ "$mode" = check ]; then
  do_check
  exit $?
fi

# ---------------------------------------------------------------- stage mode
command -v install_name_tool >/dev/null 2>&1 || fail "install_name_tool not found"
command -v codesign >/dev/null 2>&1 || fail "codesign not found"

prefix_raw=${HOMEBREW_PREFIX:-$(brew --prefix)}
prefix=$(realpath "$prefix_raw")

: > "$W/map.tsv"      # realpath<TAB>staged leaf
: > "$W/queue.tsv"    # original path<TAB>staged leaf (breadth-first queue)
: > "$W/changes.tsv"  # staged leaf<TAB>old reference<TAB>new reference

entry_real=$(realpath "$entry")
printf '%s\t%s\n' "$entry_real" "$entry_leaf" >> "$W/map.tsv"
printf '%s\t%s\n' "$entry_real" "$entry_leaf" >> "$W/queue.tsv"

copies=0
bytes=0

# Leaf already mapped to realpath $1 (empty when none).
leaf_of_real() {
  REAL=$1 awk -F'\t' '$1 == ENVIRON["REAL"] { print $2; exit }' "$W/map.tsv"
}

# Succeeds when leaf $1 is already used by a staged file.
leaf_taken() {
  LEAF=$1 awk -F'\t' '$2 == ENVIRON["LEAF"] { f = 1 } END { exit !f }' "$W/map.tsv"
}

# Prints the real path that reference $2 of node $1 (original path) resolves to,
# or fails the run with an unresolved/unexpected line.
resolve_ref() {
  local orig=$1 ref=$2 odir rel cand rp real
  odir=$(dirname "$orig")
  case "$ref" in
    @loader_path/*)
      rel=${ref#@loader_path/}
      cand="$odir/$rel"
      [ -e "$cand" ] || fail "unresolved $ref in $orig"
      realpath "$cand"
      return 0
      ;;
    @rpath/*)
      rel=${ref#@rpath/}
      rpaths_of "$orig" > "$W/rpaths.txt"
      while IFS= read -r rp; do
        [ -n "$rp" ] || continue
        case "$rp" in
          @loader_path) rp="$odir" ;;
          @loader_path/*) rp="$odir/${rp#@loader_path/}" ;;
          @executable_path*) continue ;;
        esac
        if [ -e "$rp/$rel" ]; then
          real=$(realpath "$rp/$rel")
          case "$real" in
            "$prefix"/*) printf '%s\n' "$real"; return 0 ;;
          esac
          fail "unexpected $ref in $orig"
        fi
      done < "$W/rpaths.txt"
      cand="$prefix/lib/$(basename "$rel")"
      [ -e "$cand" ] || fail "unresolved $ref in $orig"
      realpath "$cand"
      return 0
      ;;
    /*)
      real=$(realpath "$ref" 2>/dev/null || true)
      if [ -z "$real" ]; then
        case "$ref" in
          "$prefix"/*) fail "unresolved $ref in $orig" ;;
          *) fail "unexpected $ref in $orig" ;;
        esac
      fi
      case "$real" in
        "$prefix"/*) printf '%s\n' "$real"; return 0 ;;
      esac
      fail "unexpected $ref in $orig"
      ;;
    *)
      fail "unexpected $ref in $orig"
      ;;
  esac
}

n=1
while :; do
  line=$(sed -n "${n}p" "$W/queue.tsv")
  [ -n "$line" ] || break
  n=$((n + 1))
  orig=${line%%"$TAB"*}
  leaf=${line#*"$TAB"}
  refs_of "$orig" > "$W/refs.txt"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      /usr/lib/* | /System/*) continue ;;
    esac
    real=$(resolve_ref "$orig" "$ref")
    new_leaf=$(leaf_of_real "$real")
    if [ -z "$new_leaf" ]; then
      new_leaf=$(basename "$ref")
      if leaf_taken "$new_leaf" || [ -e "$dir/$new_leaf" ]; then
        fail "collision $new_leaf ($real)"
      fi
      cp "$real" "$dir/$new_leaf"
      # Homebrew installs dylibs read-only; install_name_tool needs write access.
      chmod u+w "$dir/$new_leaf"
      echo "MACOS-CLOSURE file=$new_leaf from=$real"
      printf '%s\t%s\n' "$real" "$new_leaf" >> "$W/map.tsv"
      printf '%s\t%s\n' "$real" "$new_leaf" >> "$W/queue.tsv"
      copies=$((copies + 1))
      size=$(wc -c < "$dir/$new_leaf" | tr -d ' ')
      bytes=$((bytes + size))
    fi
    new_ref="@loader_path/$new_leaf"
    if [ "$ref" != "$new_ref" ]; then
      printf '%s\t%s\t%s\n' "$leaf" "$ref" "$new_ref" >> "$W/changes.tsv"
    fi
  done < "$W/refs.txt"
done

# One install_name_tool call per modified file, then an ad hoc re-signature
# (install_name_tool invalidates arm64 signatures). Install ids stay as they
# are: dyld does not use a dependency's own id to find it.
rewritten=0
cut -f1 "$W/changes.tsv" | awk '!seen[$0]++' > "$W/modified.txt"
while IFS= read -r mleaf; do
  [ -n "$mleaf" ] || continue
  args=()
  while IFS="$TAB" read -r cleaf old new; do
    if [ "$cleaf" = "$mleaf" ]; then
      args+=(-change "$old" "$new")
    fi
  done < "$W/changes.tsv"
  install_name_tool "${args[@]}" "$dir/$mleaf"
  codesign --force --sign - "$dir/$mleaf"
  rewritten=$((rewritten + 1))
done < "$W/modified.txt"

# Copies nobody modified can still fail `codesign --verify`: Homebrew's Intel
# bottles carry no valid signature (run 40937808629, macos-15-intel). arm64
# refuses unsigned code and x86_64 tolerates it, so sign every staged copy that
# does not verify, the same ad hoc way as the rewritten ones.
resigned=0
cut -f2 "$W/map.tsv" | sed 1d > "$W/copied.txt"
while IFS= read -r cleaf; do
  [ -n "$cleaf" ] || continue
  if ! codesign --verify "$dir/$cleaf" >/dev/null 2>&1; then
    codesign --force --sign - "$dir/$cleaf"
    resigned=$((resigned + 1))
  fi
done < "$W/copied.txt"

echo "MACOS-CLOSURE staged=$copies rewritten=$rewritten resigned=$resigned bytes=$bytes"
do_check
