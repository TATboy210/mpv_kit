#!/usr/bin/env bash
# Phase 17.1 expectation sets, SOURCED by the plans (no side effects):
#
#   source .planning/phases/17.1-close-gap-int-1-int-2-release-and-pin-a-libmpv-bundle-with-t/tools/gate_expectations.sh
#
# Each array is a flat argument list for run_gate.sh (release runs) or
# ci_gate.sh (PR pushes):
#   RELEASE_REHEARSAL  release.yml dispatched on the branch ref (publish skipped)
#   RELEASE_TAG        release.yml on the v* tag (publish succeeded, SHA256SUMS printed)
#   PR_BASE            native-verify + flutter-plugin + macos-route on a pushed head
#   PR_PREP            PR_BASE plus the pre-pin hook check (bundleTag still dev.3)
# Plan 05 appends PR_PIN to this file; keep the arrays in this order.

# Job-name regexes of the six bundle targets (release.yml matrix names).
LX='^linux \(ubuntu-24\.04, linux-x64\)'
LA='^linux \(ubuntu-24\.04-arm, linux-arm64\)'
MA='^macos \(macos-15, macos-arm64\)'
MX='^macos \(macos-15-intel, macos-x64\)'
WX='^windows \(windows-2025, '
WA='^windows \(windows-11-arm, '

# --- Release runs (run_gate.sh) -----------------------------------------------
RELEASE_COMMON=(
  --jobs-success '^linux \('
  --jobs-success '^macos \('
  --jobs-success '^windows \('
)
for _j in "$LX" "$LA" "$MA" "$MX" "$WX" "$WA"; do
  RELEASE_COMMON+=(
    --log "$_j" 'FFmpeg 8\.1\.3 \(LGPL\) installed'
    --log "$_j" 'packaged [0-9]+ libraries into'
  )
done
RELEASE_COMMON+=(
  --log "$WX" 'ANGLE-FREE .*libmpv-windows-x64/lib/libmpv-2\.dll'
  --log "$WA" 'ANGLE-FREE .*libmpv-windows-arm64/lib/libmpv-2\.dll'
  --log "$WX" '\[smoke\] active renderer: gpu-next'
  --log "$WA" '\[smoke\] active renderer: gpu-next'
  --log-absent '^windows \(' 'RESULT: FAIL'
  --log-absent '^windows \(' 'GPL DEPENDENCY'
  --log "$LX" 'NEEDED libEGL\.so\.1'
  --log "$LA" 'NEEDED libEGL\.so\.1'
  --log "$LX" 'RENDER_GL ok api=gl '
)
unset _j

RELEASE_REHEARSAL=("${RELEASE_COMMON[@]}" --jobs-skipped '^publish')

RELEASE_TAG=(
  "${RELEASE_COMMON[@]}"
  --jobs-success '^publish'
  --log '^publish' '[0-9a-f]{64}  libmpv-windows-x64\.tar\.gz'
)

# --- Pushed-head runs (ci_gate.sh; three workflows) ---------------------------
PR_BASE=(
  --jobs-success '^patch-drift'
  --jobs-success '^linux \('
  --jobs-success '^macos \('
  --jobs-success '^windows \('
  --jobs-success '^sanitizers'
  --jobs-success '^integration-test'
  --jobs-success '^flutter-video-coverage'
  --jobs-success '^build \('
  --jobs-success '^route-probe'
  --log '^build \(windows' 'ANGLE-FREE .*mpv_kit_video_plugin\.dll'
  --log '^windows \(windows-2025' 'ANGLE-FREE '
  --log '^integration-test \(ubuntu' 'BACKEND-MATRIX-SUMMARY platform=linux cells=3 ok=3'
  --log '^integration-test \(windows' 'BACKEND-MATRIX-SUMMARY platform=windows cells=3 ok=3'
  --log '^integration-test \(macos' 'BACKEND-MATRIX-SUMMARY platform=macos cells=2 ok=2'
  --log-absent '^integration-test' 'BACKEND-MATRIX \{.*"result":"fail"\}'
  --log '^route-probe' 'ROUTE-PARITY ok '
  --log '^build \(windows' 'tests passed\.'
  --log-absent '^build \(' 'could not be loaded'
  --log-absent '^build \(' 'tests passed, [0-9]+ failed'
  --log '^linux \(ubuntu-24\.04\)' 'resolvePinnedBundle reinstalls when the extracted directory is gone'
)

PR_PREP=(
  "${PR_BASE[@]}"
  --log '^linux \(ubuntu-24\.04\)' 'PINS OK tag=v0\.1\.0-dev\.3 targets=6'
)
