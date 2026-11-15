#!/usr/bin/env bash
# Generates the test media of the hardware-decode probes (Phase 16, HWD-05).
#
# usage:
#   tools/make_hwdec_samples.sh OUTDIR          three 640x360 samples:
#     h264-8bit.mp4, hevc-8bit.mp4, hevc-10bit.mp4 (30 fps, 4 s, one
#     keyframe per 30 frames, each at most 1 MiB; the same commands as the
#     "Generate route samples" step of .github/workflows/macos-route.yml)
#   tools/make_hwdec_samples.sh --uhd OUTDIR    one 3840x2160 sample:
#     hevc-10bit-2160p.mp4 (HEVC Main10, 30 fps, 10 s)
#
# Every file is read back with ffprobe and reported as
#   HWDEC-SAMPLES name=<file> codec=<c> pix_fmt=<p> size=<w>x<h> bytes=<n>
# A codec, pixel format or size that differs from the expectation exits 1.
#
# The encoders (libx264, libx265) are GPL. They only make test media here and
# never enter the LGPL libmpv bundle; the media files are not committed
# (.gitignore) and no bundle script calls this one.
set -euo pipefail

uhd=0
if [ "${1:-}" = "--uhd" ]; then
  uhd=1
  shift
fi
if [ $# -ne 1 ]; then
  echo "usage: $0 [--uhd] OUTDIR" >&2
  exit 2
fi
out=$1
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Write to a file first, then read it: a pipe into `head` can SIGPIPE the
# writer under pipefail.
ffmpeg -hide_banner -encoders > "$tmp/encoders.txt"
for enc in libx264 libx265; do
  if ! grep -q " $enc " "$tmp/encoders.txt"; then
    echo "ffmpeg has no $enc encoder; cannot generate the hwdec samples" >&2
    exit 1
  fi
done

# check NAME CODEC PIX_FMT SIZE MAX_BYTES
check() {
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,pix_fmt,width,height -of default=nw=1 \
    "$out/$1" > "$tmp/probe-$1.txt"
  local codec pix width height bytes
  codec=$(sed -n 's/^codec_name=//p' "$tmp/probe-$1.txt")
  pix=$(sed -n 's/^pix_fmt=//p' "$tmp/probe-$1.txt")
  width=$(sed -n 's/^width=//p' "$tmp/probe-$1.txt")
  height=$(sed -n 's/^height=//p' "$tmp/probe-$1.txt")
  bytes=$(wc -c < "$out/$1" | tr -d ' ')
  echo "HWDEC-SAMPLES name=$1 codec=$codec pix_fmt=$pix size=${width}x${height} bytes=$bytes"
  if [ "$codec" != "$2" ] || [ "$pix" != "$3" ] || [ "${width}x${height}" != "$4" ]; then
    echo "$1: unexpected codec/pix_fmt/size" >&2
    exit 1
  fi
  if [ "$bytes" -gt "$5" ]; then
    echo "$1: larger than $5 bytes" >&2
    exit 1
  fi
}

if [ "$uhd" -eq 1 ]; then
  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=size=3840x2160:rate=30:duration=10 \
    -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le -profile:v main10 \
    -tag:v hvc1 -x265-params log-level=error "$out/hevc-10bit-2160p.mp4"
  # The 4K sample is not size-capped (it is a CI artifact, not an asset).
  check hevc-10bit-2160p.mp4 hevc yuv420p10le 3840x2160 2000000000
else
  common=(-nostdin -hide_banner -loglevel error -y -f lavfi
    -i testsrc2=size=640x360:rate=30:duration=4)
  ffmpeg "${common[@]}" -c:v libx264 -pix_fmt yuv420p -g 30 \
    -movflags +faststart "$out/h264-8bit.mp4"
  ffmpeg "${common[@]}" -c:v libx265 -pix_fmt yuv420p -g 30 -tag:v hvc1 \
    -x265-params log-level=error "$out/hevc-8bit.mp4"
  ffmpeg "${common[@]}" -c:v libx265 -pix_fmt yuv420p10le -profile:v main10 \
    -g 30 -tag:v hvc1 -x265-params log-level=error "$out/hevc-10bit.mp4"
  check h264-8bit.mp4 h264 yuv420p 640x360 1048576
  check hevc-8bit.mp4 hevc yuv420p 640x360 1048576
  check hevc-10bit.mp4 hevc yuv420p10le 640x360 1048576
fi
