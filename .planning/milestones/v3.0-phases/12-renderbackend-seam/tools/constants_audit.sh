#!/usr/bin/env bash
# Phase 12 constants audit (12-09, threat T-12-18): the RenderBackend move
# must not change any timing, ring or timeout constant. For each fixed
# string in CHECKS, the number of occurrences in `git show <base>:<file>`
# must equal the number in the working-tree file.
#
# REPINNED holds the constants that 0e792c8 (quick 261029-rcc) changed on
# purpose, with the user-approved golden re-freeze. They are not compared
# with the base; each has a fixed expected count in the working-tree file.
# Quick 261030-3pc re-pinned them; any further change needs the same kind
# of reviewed re-pin.
#
# usage:
#   bash .planning/phases/12-renderbackend-seam/tools/constants_audit.sh
#
#   CONSTANTS_BASE  commit to compare against (default: 3a5f450, the
#                   milestone v3.0 roadmap commit, before any Phase 12 code)
#
# output / exit codes:
#   CONSTANTS ok                              every count matches, exit 0
#   CONSTANT DRIFT <pattern> base=<n> head=<m>  one line per CHECKS mismatch, exit 1
#   CONSTANT DRIFT <pattern> pinned=<n> head=<m> one line per REPINNED mismatch, exit 1
#   CONSTANTS usage: ...                      bad invocation / git error /
#                                             malformed REPINNED entry, exit 2
set -uo pipefail

readonly BASE="${CONSTANTS_BASE:-3a5f450}"
readonly PKG=packages/mpv_kit_video

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "CONSTANTS usage: not inside a git checkout" >&2
  exit 2
}
cd "$ROOT" || exit 2
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || {
  echo "CONSTANTS usage: unknown base commit '$BASE'" >&2
  exit 2
}

# file<TAB>fixed string. Every pattern is matched literally (grep -F) and
# counted per occurrence, not per line.
readonly CHECKS=(
  "src/video_renderer.h	kIdleTimeout{500}"
  "src/video_renderer.h	kMinBackoff{100}"
  "src/video_renderer.h	kMaxBackoff{5000}"
  "src/video_renderer.h	kMaxQuarantine = 4"
  "src/video_renderer.h	kProbeWindow = 120"
  "src/video_renderer.h	virtual int CompositorLatency() const { return 2; }"
  "src/video_renderer.h	int quarantine_count_ = 2;"
  "src/video_renderer.cc	const int fallback_quarantine = 2;"
  "src/video_renderer.cc	const int fallback_ring = fallback_quarantine + 3;"
  "src/video_renderer.cc	kMinBackoff * (1 << std::min(failures_ - 1, 6))"
  "src/vulkan_backend.cc	1'000'000'000ull"
  "windows/d3d11_interop.h	int CompositorLatency() const override { return 4; }"
)

# Constants changed on purpose by 0e792c8 (quick 261029-rcc: FIFO ready queue
# of two frames, mpv swap reported at publish, ring = quarantine + 2 +
# kReadyDepth, so Windows 8 and the other platforms 6; the allocation
# fallback keeps quarantine 2 / ring 5 and is still checked against the base
# above). The golden re-freeze was approved by the user (`golden_refreeze:
# approved` in 261029-rcc-CONTEXT.md, record golden-freeze-14-rcc.sha256).
# They are compared with a fixed count instead of the base commit, re-pinned
# in quick 261030-3pc. Any further change to them needs the same kind of
# reviewed re-pin.
# file<TAB>count<TAB>fixed string
readonly REPINNED=(
  "src/video_renderer.h	0	kPresentTimeout{50}"
  "src/video_renderer.h	1	static constexpr int kReadyDepth = 2;"
  "src/video_renderer.h	1	int ring_size_ = 6;"
  "src/video_renderer.cc	1	ring_size_ = quarantine_count_ + 2 + kReadyDepth;"
)

# Occurrences of fixed string $2 in stdin.
count() { grep -oF -- "$1" | wc -l | tr -d ' '; }

drift=0
for check in "${CHECKS[@]}"; do
  file="$PKG/${check%%	*}"
  pattern="${check#*	}"
  base_n=$(git show "$BASE:$file" 2>/dev/null | count "$pattern")
  if [ -f "$file" ]; then
    head_n=$(count "$pattern" < "$file")
  else
    head_n=0
  fi
  if [ "$base_n" != "$head_n" ]; then
    echo "CONSTANT DRIFT $pattern base=$base_n head=$head_n"
    drift=1
  fi
done

for entry in "${REPINNED[@]}"; do
  rfile="$PKG/${entry%%	*}"
  rest="${entry#*	}"
  pinned="${rest%%	*}"
  rpattern="${rest#*	}"
  # A missing file or non-numeric count is a malformed entry (also catches a
  # TAB typed as spaces), not drift.
  case "$pinned" in
    ''|*[!0-9]*)
      echo "CONSTANTS usage: bad REPINNED entry '$entry'" >&2
      exit 2
      ;;
  esac
  [ -f "$rfile" ] || {
    echo "CONSTANTS usage: REPINNED file missing '$rfile'" >&2
    exit 2
  }
  rhead=$(count "$rpattern" < "$rfile")
  if [ "$pinned" != "$rhead" ]; then
    echo "CONSTANT DRIFT $rpattern pinned=$pinned head=$rhead"
    drift=1
  fi
done

if [ "$drift" -ne 0 ]; then
  exit 1
fi
echo "CONSTANTS ok"
exit 0
