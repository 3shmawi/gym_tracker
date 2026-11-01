#!/usr/bin/env bash
# Turns a raw screen recording into a 1080×1920 social video (TikTok, Reels,
# Shorts): brand-colored background, the recording centered, a title on top
# and your handle at the bottom.
#   scripts/compose_demo.sh <raw.mp4> <out.mp4> "<title>" ["@handle"]
# If record_demo_ios.sh left "<raw>.start" (seconds of build and install
# before the test), that part is cut.
set -euo pipefail
cd "$(dirname "$0")/.."
in=$1; out=$2; title=${3:-Azm}; handle=${4:-@3shmawi}
color="#22C55E"
font=$(ls assets/fonts/*/*-700.ttf assets/fonts/*/*-600.ttf assets/fonts/*/*.ttf 2>/dev/null | head -n 1 || true)
fontopt=""; [ -n "$font" ] && fontopt=":fontfile=$font"

# The title and handle go through files (drawtext textfile=), never inside
# the filter: a PR title with ' ; , or : broke ffmpeg's filter parsing.
# expansion=none: % is shown as is. Long titles wrap to stay inside 1080 px.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Short titles: one or two big lines; longer ones: smaller text, wider lines.
wrap() { printf '%s' "$title" | fold -s -w "$1" | sed 's/[[:space:]]*$//' > "$work/title.txt"; }
size=56; step=72; wrap 28
lines=$(($(wc -l < "$work/title.txt") + 1))
if [ "$lines" -gt 2 ]; then size=44; step=56; wrap 36; lines=$(($(wc -l < "$work/title.txt") + 1)); fi
printf '%s' "$handle" > "$work/handle.txt"
title_y=$((235 - lines * step)); [ "$title_y" -lt 24 ] && title_y=24

skip=()
start_file="${in%.*}.start"
if [ -s "$start_file" ]; then
  start=$(tr -dc '0-9.' < "$start_file")
  [ -n "$start" ] && skip=(-ss "$start") && echo "Cutting the first ${start}s (build and install)."
fi

ffmpeg -y -loglevel error ${skip[@]+"${skip[@]}"} -i "$in" -filter_complex "
  color=c=${color}:s=1080x1920:d=600[bg];
  [0:v]scale=-2:1500,setsar=1[rec];
  [bg][rec]overlay=(W-w)/2:250:shortest=1,
  drawtext=expansion=none:textfile=${work}/title.txt${fontopt}:fontsize=${size}:line_spacing=-$((size * 5 / 7)):fontcolor=white:x=(w-text_w)/2:y=${title_y},
  drawtext=expansion=none:textfile=${work}/handle.txt${fontopt}:fontsize=40:fontcolor=white@0.85:x=(w-text_w)/2:y=h-120
" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart -an "$out"
echo "✓ $out"
