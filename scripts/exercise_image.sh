#!/usr/bin/env bash
# Makes the two bundled pictures of a library exercise from a source drawing.
#
#   ./scripts/exercise_image.sh <exercise_id> <source image>
#
# Writes assets/exercises/<id>.webp (large, 640 px) and
# assets/exercises/<id>_thumb.webp (160 px). The picture is a transparent
# mask: the dark lines of the source become opaque black, the white paper
# becomes transparent, and the app tints it with the theme text colour at
# run time (dark and light, no background). Needs ImageMagick with WebP.
# Then add the entry to assets/exercises/manifest.json (docs/features/exercise_images.md).
set -euo pipefail

id="${1:?usage: exercise_image.sh <exercise_id> <source image>}"
src="${2:?usage: exercise_image.sh <exercise_id> <source image>}"
[[ "$id" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "bad id: $id" >&2; exit 1; }
[[ -f "$src" ]] || { echo "no such file: $src" >&2; exit 1; }

out="$(cd "$(dirname "$0")/.." && pwd)/assets/exercises"
mkdir -p "$out"

for spec in "$id.webp:640" "${id}_thumb.webp:160"; do
  name="${spec%%:*}"
  size="${spec##*:}"
  convert -quiet "$src" -colorspace Gray -negate -write mpr:alpha +delete \
    \( "$src" -alpha off -fill black -colorize 100 \) mpr:alpha \
    -alpha off -compose CopyOpacity -composite \
    -trim +repage -bordercolor none -border 6 \
    -resize "${size}x${size}" \
    -define webp:lossless=true -define webp:alpha-quality=100 \
    "$out/$name"
  echo "wrote assets/exercises/$name"
done
