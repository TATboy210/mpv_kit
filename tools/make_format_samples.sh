#!/usr/bin/env bash
# Generates short media samples in mainstream and less common formats for
# the format matrix test (packages/mpv_kit/test/format_matrix_test.dart).
#
# usage: tools/make_format_samples.sh OUTDIR
# Needs an `ffmpeg` CLI on PATH (any distro/Homebrew/MSYS2 build: encoders
# such as libx264/libx265 are only used to *create* samples, the tested
# libmpv only decodes them). Samples whose encoder is missing are skipped
# with a warning. Writes OUTDIR/expect.tsv:
#   file <TAB> video codec or - <TAB> audio codec or - <TAB> subtitle codec or -
set -uo pipefail

out=${1:?usage: make_format_samples.sh OUTDIR}
mkdir -p "$out"
expect="$out/expect.tsv"
: > "$expect"

ff() { ffmpeg -nostdin -hide_banner -loglevel error -y "$@"; }

# Sources: 2 s test pattern + tone. Odd sizes are avoided (some codecs need
# even dimensions); 352x288 is CIF for H.263.
V="testsrc2=size=320x240:rate=25:duration=2"
A="sine=frequency=440:sample_rate=48000:duration=2"
A44="sine=frequency=440:sample_rate=44100:duration=2"

# sample NAME VCODEC ACODEC SCODEC ffmpeg-args...
sample() {
  local name=$1 v=$2 a=$3 s=$4
  shift 4
  if ff "$@" "$out/$name" 2>"$out/.err"; then
    printf '%s\t%s\t%s\t%s\n' "$name" "$v" "$a" "$s" >> "$expect"
  else
    echo "warning: skipped $name: $(head -c 300 "$out/.err")" >&2
    rm -f "$out/$name"
  fi
}

# --- Audio (music) ------------------------------------------------------
sample mp3.mp3     - mp3       - -f lavfi -i "$A44" -c:a libmp3lame -b:a 192k
sample aac.m4a     - aac       - -f lavfi -i "$A" -c:a aac -b:a 160k
sample alac.m4a    - alac      - -f lavfi -i "$A44" -c:a alac
sample flac.flac   - flac      - -f lavfi -i "$A44" -c:a flac
sample vorbis.ogg  - vorbis    - -f lavfi -i "$A44" -c:a libvorbis
sample opus.opus   - opus      - -f lavfi -i "$A" -c:a libopus -b:a 96k
sample pcm16.wav   - pcm_s16le - -f lavfi -i "$A44" -c:a pcm_s16le
sample hires.wav   - pcm_s24le - -f lavfi -i "sine=frequency=440:sample_rate=96000:duration=2" -c:a pcm_s24le
sample aiff.aiff   - pcm_s16be - -f lavfi -i "$A44" -c:a pcm_s16be
sample wavpack.wv  - wavpack   - -f lavfi -i "$A44" -c:a wavpack
sample tta.tta     - tta       - -f lavfi -i "$A44" -c:a tta
sample wma.wma     - wmav2     - -f lavfi -i "$A44" -c:a wmav2
sample ac3.ac3     - ac3       - -f lavfi -i "$A" -ac 6 -c:a ac3
sample eac3.eac3   - eac3      - -f lavfi -i "$A" -ac 6 -c:a eac3
sample dts.dts     - dts       - -f lavfi -i "$A" -c:a dca -strict -2
sample truehd.mka  - truehd    - -f lavfi -i "$A" -c:a truehd -strict -2
sample mp2.mp2     - mp2       - -f lavfi -i "$A" -c:a mp2
sample mulaw.au    - pcm_mulaw - -f lavfi -i "sine=frequency=440:sample_rate=8000:duration=2" -c:a pcm_mulaw
sample real.ra     - ra_144    - -f lavfi -i "sine=frequency=440:sample_rate=8000:duration=2" -c:a real_144 -f rm
sample opus.mka    - opus      - -f lavfi -i "$A" -c:a libopus
# Music file with tags and an embedded cover (albumart video track).
ff -f lavfi -i "color=c=orange:size=300x300:duration=1" -frames:v 1 "$out/.cover.png" 2>/dev/null
sample tagged.mp3  png mp3 - -f lavfi -i "$A44" -i "$out/.cover.png" \
  -map 0:a -map 1:v -c:a libmp3lame -c:v png -disposition:v attached_pic \
  -id3v2_version 3 -metadata title="Test Title" -metadata artist="Test Artist" \
  -metadata album="Test Album"
sample tagged.flac png flac - -f lavfi -i "$A44" -i "$out/.cover.png" \
  -map 0:a -map 1:v -c:a flac -c:v png -disposition:v attached_pic \
  -metadata title="Test Title" -metadata artist="Test Artist"

# --- Video ----------------------------------------------------------------
sample h264.mp4    h264       aac       - -f lavfi -i "$V" -f lavfi -i "$A" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest
sample hevc.mkv    hevc       opus      - -f lavfi -i "$V" -f lavfi -i "$A" -c:v libx265 -x265-params log-level=error -c:a libopus -shortest
sample hdr10.mkv   hevc       -         - -f lavfi -i "$V" -c:v libx265 -pix_fmt yuv420p10le \
  -x265-params "log-level=error:hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400"
sample av1.mkv     av1        opus      - -f lavfi -i "$V" -f lavfi -i "$A" -c:v libaom-av1 -cpu-used 8 -row-mt 1 -c:a libopus -shortest
sample vp9.webm    vp9        opus      - -f lavfi -i "$V" -f lavfi -i "$A" -c:v libvpx-vp9 -deadline realtime -c:a libopus -shortest
sample vp8.webm    vp8        vorbis    - -f lavfi -i "$V" -f lavfi -i "$A44" -c:v libvpx -deadline realtime -c:a libvorbis -shortest
sample mpeg2.ts    mpeg2video mp2       - -f lavfi -i "$V" -f lavfi -i "$A" -c:v mpeg2video -c:a mp2 -shortest
sample mpeg4.avi   mpeg4      mp3       - -f lavfi -i "$V" -f lavfi -i "$A44" -c:v mpeg4 -c:a libmp3lame -shortest
sample prores.mov  prores     pcm_s16le - -f lavfi -i "$V" -f lavfi -i "$A" -c:v prores_ks -c:a pcm_s16le -shortest
sample flv1.flv    flv1       mp3       - -f lavfi -i "$V" -f lavfi -i "$A44" -c:v flv -c:a libmp3lame -shortest
sample wmv2.wmv    wmv2       wmav2     - -f lavfi -i "$V" -f lavfi -i "$A44" -c:v wmv2 -c:a wmav2 -shortest
sample theora.ogv  theora     vorbis    - -f lavfi -i "$V" -f lavfi -i "$A44" -c:v libtheora -c:a libvorbis -shortest
sample h263.3gp    h263       aac       - -f lavfi -i "testsrc2=size=352x288:rate=25:duration=2" -f lavfi -i "$A" -c:v h263 -c:a aac -ar 16000 -ac 1 -shortest
sample ffv1.mkv    ffv1       flac      - -f lavfi -i "$V" -f lavfi -i "$A44" -c:v ffv1 -c:a flac -shortest
sample mjpeg.avi   mjpeg      pcm_s16le - -f lavfi -i "$V" -f lavfi -i "$A" -c:v mjpeg -c:a pcm_s16le -shortest
sample real.rm     rv20       ra_144    - -f lavfi -i "$V" -f lavfi -i "sine=frequency=440:sample_rate=8000:duration=2" -c:v rv20 -c:a real_144 -shortest

# --- Subtitles --------------------------------------------------------------
printf '1\n00:00:00,000 --> 00:00:02,000\nhello 字幕\n' > "$out/.sub.srt"
sample subs-srt.mkv  h264 - subrip -f lavfi -i "$V" -i "$out/.sub.srt" -c:v libx264 -pix_fmt yuv420p -c:s srt
sample subs-ass.mkv  h264 - ass    -f lavfi -i "$V" -i "$out/.sub.srt" -c:v libx264 -pix_fmt yuv420p -c:s ass
sample subs-tx3g.mp4 h264 - mov_text -f lavfi -i "$V" -i "$out/.sub.srt" -c:v libx264 -pix_fmt yuv420p -c:s mov_text

rm -f "$out/.err"
echo "$(wc -l < "$expect" | tr -d ' ') samples in $out"
