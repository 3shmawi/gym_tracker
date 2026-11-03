#!/usr/bin/env bash
# Fetches everkinetic/data at the reviewed commit and builds the picture
# package. Used by .github/workflows/exercise-images.yml (no secrets here).
#
#   tool/exercise_images/ci_build.sh <work dir>
set -euo pipefail

work="${1:?usage: ci_build.sh <work dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
repo="https://github.com/everkinetic/data"
# Same commit as SOURCE_COMMIT in build.py, which refuses any other.
commit="$(sed -n 's/^SOURCE_COMMIT = "\([0-9a-f]\{40\}\)"$/\1/p' "$here/build.py")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "no pinned commit in build.py" >&2; exit 1; }

mkdir -p "$work/source"
git -C "$work/source" init --quiet
git -C "$work/source" fetch --quiet --depth 1 "$repo" "$commit"
git -C "$work/source" checkout --quiet FETCH_HEAD

python3 "$here/build.py" --source "$work/source" --out "$work/package"

# The committed seed must be what the script builds today.
if ! diff -q "$work/package/seed.sql" \
  "$here/../../supabase/migrations/0014_exercise_images_seed.sql" >/dev/null; then
  echo "0014_exercise_images_seed.sql is out of date: rebuild it with build.py" >&2
  exit 1
fi
