#!/usr/bin/env bash
# Renders the Azm promo video (1920×1080, 30 fps, ~103 s) into build/Azm_Promo_1080p.mp4.
# Needs: node + playwright (Chromium), python3 + numpy + scipy + pillow, ffmpeg.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(git rev-parse --show-toplevel)"
mkdir -p build/img build/fonts build/stills
cp index.html timeline.js render.js build/
cp "$ROOT"/website/assets/fonts/*.woff2 build/fonts/
cp "$ROOT"/assets/branding/icon.png "$ROOT"/assets/branding/icon_foreground.png build/img/
python3 - "$ROOT" <<'PY'
import sys
from PIL import Image
root = sys.argv[1]
for n in ['flat_db_press', 'incline_barbell_press', 'pec_deck', 'rope_pushdown', 'push_ups', 'barbell_squat',
          'lat_pulldown_machine', 'db_shoulder_press', 'leg_press', 'hammer_curl']:
    Image.open(f'{root}/assets/exercises/{n}.webp').save(f'build/img/{n}.png')
PY
cd build
python3 ../music.py
if [ "${1:-}" = "still" ]; then node render.js still "${2:-20}"; exit 0; fi
node render.js part0.mp4 0 26 30 & node render.js part1.mp4 26 52 30 &
node render.js part2.mp4 52 78 30 & node render.js part3.mp4 78 103 30 &
wait
printf "file 'part0.mp4'\nfile 'part1.mp4'\nfile 'part2.mp4'\nfile 'part3.mp4'\n" > list.txt
ffmpeg -y -loglevel error -f concat -safe 0 -i list.txt -i music.wav -map 0:v -map 1:a \
  -c:v copy -c:a aac -b:a 256k -movflags +faststart -shortest Azm_Promo_1080p.mp4
echo "done: $(pwd)/Azm_Promo_1080p.mp4"
