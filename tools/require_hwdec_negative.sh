#!/usr/bin/env bash
# Negative leg of the MPV_KIT_REQUIRE_HWDEC guard (VER-03, Phase 17).
#
# usage:  require_hwdec_negative.sh <windows|linux> <api> <required> [sample]
#         sample defaults to h264-8bit.mp4
#
# Runs example/integration_test/hwdec_zero_copy_test.dart with
#   MPV_KIT_REQUIRE_HWDEC=<required> MPV_KIT_VIDEO_API=<api> MPV_KIT_HWDEC_SAMPLES=<sample>
# on a machine WITHOUT that zero-copy hardware decode (hosted WARP, or the
# RTX 4060 forced onto the software backend in 17-04) and turns the expected
# failure into this step's success. It proves the guard fails loudly instead
# of skipping or passing; it says nothing about hardware decode itself.
#
# Passes (prints `REQUIRE-HWDEC-NEGATIVE ok required=<r> api=<a> exit=<n>`,
# exit 0) only when ALL hold:
#   * the test exited non-zero,
#   * the log has a HWDEC-IDENTITY line (the test really reached playback and
#     the guard, it did not die on setup),
#   * at least one `HWDEC-REQUIRE {"schema":"hwdec-require-1","required":"<r>"`
#     line has "result":"fail",
#   * no HWDEC-REQUIRE line for <r> has "result":"ok".
# Otherwise prints `REQUIRE-HWDEC-NEGATIVE fail <reason>` and exits 1
# (2 for a usage error).
#
# The caller sets the libmpv environment (MPV_KIT_LIBMPV_PATH, PATH, ...).
set -uo pipefail

platform="${1:-}"
api="${2:-}"
required="${3:-}"
sample="${4:-h264-8bit.mp4}"
case "$platform" in
  windows) prefix="" ;;
  linux) prefix="xvfb-run -a" ;;
  *)
    echo "usage: require_hwdec_negative.sh <windows|linux> <api> <required> [sample]" >&2
    exit 2
    ;;
esac
if [ -z "$api" ] || [ -z "$required" ]; then
  echo "usage: require_hwdec_negative.sh <windows|linux> <api> <required> [sample]" >&2
  exit 2
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log=$(mktemp "${TMPDIR:-/tmp}/require-hwdec-negative.XXXXXX")
trap 'rm -f "$log"' EXIT
cd "$root/example" || exit 2

# shellcheck disable=SC2086
MPV_KIT_REQUIRE_HWDEC="$required" MPV_KIT_VIDEO_API="$api" MPV_KIT_HWDEC_SAMPLES="$sample" \
  $prefix flutter test integration_test/hwdec_zero_copy_test.dart -d "$platform" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}

head="HWDEC-REQUIRE {\"schema\":\"hwdec-require-1\",\"required\":\"$required\""
fail() {
  echo "REQUIRE-HWDEC-NEGATIVE fail $1 (required=$required api=$api exit=$code)"
  exit 1
}

[ "$code" -ne 0 ] || fail "the test passed although no zero-copy $required decode is expected here"
grep -q 'HWDEC-IDENTITY ' "$log" || fail "no HWDEC-IDENTITY line: the test never reached playback"
grep -F -- "$head" "$log" | grep -q '"result":"fail"' || fail "no HWDEC-REQUIRE fail line"
if grep -F -- "$head" "$log" | grep -q '"result":"ok"'; then
  fail "an HWDEC-REQUIRE ok line exists"
fi

echo "REQUIRE-HWDEC-NEGATIVE ok required=$required api=$api exit=$code"
