#!/usr/bin/env bash
# Turns a raw screen recording into a 1080×1920 social video (TikTok, Reels,
# Shorts): brand-colored background, the recording centered, a title on top
# and your handle at the bottom.
#   scripts/compose_demo.sh <raw.mp4> <out.mp4> "<title>" ["@handle"]
# If record_demo_ios.sh left "<raw>.start" (seconds of build and install
# before the test), that part is cut.
set -euo pipefail
cd "$(dirname "$0")/.."
in=$1; out=$2; title=${3:-Gym Tracker}; handle=${4:-@3shmawi}
color="#22C55E"
font=$(ls assets/fonts/*/*-700.ttf assets/fonts/*/*-600.ttf assets/fonts/*/*.ttf 2>/dev/null | head -n 1 || true)
fontopt=""; [ -n "$font" ] && fontopt=":fontfile=$font"

esc() { printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g; s/:/\\\\:/g; s/%/\\\\%/g"; }
t=$(esc "$title"); h=$(esc "$handle")

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
  drawtext=text='${t}'${fontopt}:fontsize=64:fontcolor=white:x=(w-text_w)/2:y=110,
  drawtext=text='${h}'${fontopt}:fontsize=40:fontcolor=white@0.85:x=(w-text_w)/2:y=h-120
" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart -an "$out"
echo "✓ $out"
