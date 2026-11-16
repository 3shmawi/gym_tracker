#!/usr/bin/env bash
# Builds the «من الصفر لحد النهارده» journey episodes into build/journey/.
#   tool/journey_video/build.sh 03            # one episode → build/journey/out/Azm_Journey_03.mp4 + cover
#   tool/journey_video/build.sh 00 01 02      # several (run 2 at a time)
#   tool/journey_video/build.sh all
#   tool/journey_video/build.sh stills 03     # key-moment stills + contact sheet only (fast)
# Needs: node + playwright (Chromium), python3 + numpy + Pillow, ffmpeg.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SRC" rev-parse --show-toplevel)"
OUT="$ROOT/build/journey"
mkdir -p "$OUT/assets/fonts" "$OUT/assets/g" "$OUT/assets/store" "$OUT/out" "$OUT/promo/img" "$OUT/promo/fonts"

# --- prepare (cheap, every run) ---
cp "$SRC"/journey.html "$SRC"/engine.js "$SRC"/episodes.js "$SRC"/prs.js "$SRC"/render.js "$OUT/"
cp "$ROOT"/website/assets/fonts/*.woff2 "$OUT/assets/fonts/"
cp "$ROOT"/assets/branding/icon.png "$OUT/assets/icon.png"
PROMO="$ROOT/docs/brand/promo_video"
cp "$PROMO"/index.html "$PROMO"/timeline.js "$OUT/promo/"
cp "$ROOT"/website/assets/fonts/*.woff2 "$OUT/promo/fonts/"
cp "$ROOT"/assets/branding/icon.png "$ROOT"/assets/branding/icon_foreground.png "$OUT/promo/img/"
python3 - "$ROOT" "$OUT" <<'PY'
import glob, os, sys
from PIL import Image
root, out = sys.argv[1:3]
def save(src, dst, w):
    if os.path.exists(dst) and os.path.getmtime(dst) > os.path.getmtime(src):
        return
    im = Image.open(src).convert('RGB')
    im.resize((w, round(im.height * w / im.width)), Image.LANCZOS).save(dst, quality=90)
# real screens: widget-test goldens (Arabic, dark) and the store screenshots
for d in glob.glob(f'{root}/test/features/*/presentation/goldens/*/'):
    name = os.path.basename(d.rstrip('/'))
    if os.path.exists(d + 'phone_ar_dark.png'):
        save(d + 'phone_ar_dark.png', f'{out}/assets/g/{name}.jpg', 760)
g = f'{root}/test/features/workout/presentation/goldens/next_workout/'
save(g + 'phone_en_light.png', f'{out}/assets/g/next_workout_en_light.jpg', 760)
save(g + 'small_ar_dark_x1.3.png', f'{out}/assets/g/next_workout_small.jpg', 760)
for f in glob.glob(f'{root}/store/android/ar/images/phoneScreenshots/*.png'):
    save(f, f'{out}/assets/store/{os.path.basename(f)[:-4]}.jpg', 760)
for n in ['flat_db_press', 'incline_barbell_press', 'pec_deck', 'rope_pushdown', 'push_ups', 'barbell_squat',
          'lat_pulldown_machine', 'db_shoulder_press', 'leg_press', 'hammer_curl']:
    dst = f'{out}/promo/img/{n}.png'
    if not os.path.exists(dst):
        Image.open(f'{root}/assets/exercises/{n}.webp').save(dst)
PY

cd "$OUT"
sheet() {  # contact sheet of an episode's stills
  python3 - "$1" <<'PY'
import glob, sys
from PIL import Image
ep = sys.argv[1]
fs = sorted(glob.glob(f'stills/{ep}/t_*.jpg'), key=lambda f: float(f.split('t_')[1][:-4]))
w = 270; h = 480; cols = min(6, len(fs)); rows = (len(fs) + cols - 1) // cols
s = Image.new('RGB', (cols * w, rows * h), 'black')
for i, f in enumerate(fs):
    s.paste(Image.open(f).resize((w, h)), ((i % cols) * w, (i // cols) * h))
s.save(f'stills/sheet_{ep}.jpg', quality=85)
print('sheet', f'stills/sheet_{ep}.jpg')
PY
}
one() {
  local ep=$1
  node render.js plan "$ep"
  python3 "$SRC/music.py" "plan_$ep.json" "music_$ep.wav"
  node render.js cover "$ep"
  rm -rf "stills/$ep"; node render.js stills "$ep"; sheet "$ep"
  node render.js video "$ep" "video_$ep.mp4"
  python3 "$SRC/mux.py" "video_$ep.mp4" "music_$ep.wav" "out/Azm_Journey_$ep.mp4"
  cp "covers/$ep.jpg" "out/Azm_Journey_${ep}_cover.jpg"
  rm -f "video_$ep.mp4"
}

if [ "${1:-}" = "stills" ]; then
  shift
  for ep in "$@"; do rm -rf "stills/$ep"; node render.js stills "$ep"; sheet "$ep"; node render.js cover "$ep"; done
  exit 0
fi
EPS=("$@")
[ "${1:-}" = "all" ] && EPS=(00 01 02 03 04 05 06 07 08 09 10 11)
running=0
for ep in "${EPS[@]}"; do
  one "$ep" > "log_$ep.txt" 2>&1 &
  running=$((running + 1))
  if [ "$running" -ge "${JOBS:-2}" ]; then wait -n; running=$((running - 1)); fi
done
wait
for ep in "${EPS[@]}"; do tail -n 1 "log_$ep.txt"; done
