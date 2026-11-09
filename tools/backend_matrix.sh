#!/usr/bin/env bash
# Forced backend matrix (VER-02, Phase 17): runs the real-plugin texture probe
# (example/integration_test/texture_probe_test.dart: hwdec=no, non-black pixel
# probe on the mounted texture, resize keeps the texture id, a second
# controller gets the same backend) once per backend of the platform, each
# time with that backend forced through MPV_KIT_VIDEO_API (no fallback).
#
# usage:  backend_matrix.sh <linux|windows|macos>
#
# Cell table (api:expect):
#   linux    opengl:render vulkan:render software:render
#   windows  d3d11:render software:render vulkan:unavailable
#   macos    vulkan:render software:render
# `render` cells must win with exactly the forced api and pass every probe
# assertion. `unavailable` is an asserted absence, not a pass: the backend does
# not exist on that runner (hosted windows has only WARP, whose D3D11 device is
# not shared with a Vulkan device the compositor can use), and the probe checks
# that create throws render_init with the forced api's real reason
# (MPV_KIT_EXPECT_BACKEND=unavailable, PROBE-UNAVAILABLE line). The real-GPU
# Vulkan cell of Windows is run by hand on the RTX 4060 in 17-04.
#
# Output, per cell, in this key order:
#   BACKEND-MATRIX {"platform":..,"api":..,"expect":..,"exit":<n>,"result":"ok|fail"}
# and a last line
#   BACKEND-MATRIX-SUMMARY platform=<os> cells=<n> ok=<m>
# A cell is ok when the test exits 0 AND its log has the matching line
# (`PROBE {"api":"<api>"` for render, `PROBE-UNAVAILABLE {"api":"<api>"` for
# unavailable). Every cell runs even after a failure (no -e on purpose); the
# exit status is 1 if any cell failed, 2 for a usage error.
#
# The caller sets the libmpv environment (MPV_KIT_LIBMPV_PATH, PATH,
# LD_LIBRARY_PATH, MPV_KIT_REQUIRE_LIBMPV); see native-verify.yml.
set -uo pipefail

platform="${1:-}"
case "$platform" in
  linux)
    cells="opengl:render vulkan:render software:render"
    # xvfb-run provides the display; word splitting of the prefix is intended.
    prefix="xvfb-run -a"
    ;;
  windows)
    cells="d3d11:render software:render vulkan:unavailable"
    prefix=""
    ;;
  macos)
    cells="vulkan:render software:render"
    prefix=""
    ;;
  *)
    echo "usage: backend_matrix.sh <linux|windows|macos>" >&2
    exit 2
    ;;
esac

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
logdir="${RUNNER_TEMP:-/tmp}"
# RUNNER_TEMP is a Windows path on windows runners; git bash wants it POSIX.
if command -v cygpath >/dev/null 2>&1; then logdir=$(cygpath -u "$logdir"); fi
cd "$root/example" || exit 2

total=0
passed=0
for cell in $cells; do
  api="${cell%%:*}"
  expect="${cell##*:}"
  log="$logdir/matrix-$platform-$api.log"
  echo "BACKEND-MATRIX-RUN platform=$platform api=$api expect=$expect"
  # shellcheck disable=SC2086
  MPV_KIT_VIDEO_API="$api" MPV_KIT_EXPECT_BACKEND="$expect" \
    $prefix flutter test integration_test/texture_probe_test.dart -d "$platform" 2>&1 | tee "$log"
  code=${PIPESTATUS[0]}
  if [ "$expect" = "unavailable" ]; then
    needle="PROBE-UNAVAILABLE {\"api\":\"$api\""
  else
    needle="PROBE {\"api\":\"$api\""
  fi
  result=fail
  if [ "$code" -eq 0 ] && grep -qF -- "$needle" "$log"; then result=ok; fi
  total=$((total + 1))
  if [ "$result" = ok ]; then passed=$((passed + 1)); fi
  printf 'BACKEND-MATRIX {"platform":"%s","api":"%s","expect":"%s","exit":%s,"result":"%s"}\n' \
    "$platform" "$api" "$expect" "$code" "$result"
done

echo "BACKEND-MATRIX-SUMMARY platform=$platform cells=$total ok=$passed"
[ "$passed" -eq "$total" ]
