#!/usr/bin/env bash
# "What's new" of a release for the in-app update sheet (one point per line):
#
#   scripts/whats_new.sh <tag> en|ar
#
# The store text committed at that tag (store/android/<locale>/changelogs/
# default.txt, the Play "What's new" Store listing uploads) once it's filled
# in. Otherwise English falls back to the release's commits
# (scripts/release_notes.sh plain) and Arabic to nothing — the app then
# shows the English points.
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:?usage: scripts/whats_new.sh <tag> en|ar}
case ${2:-en} in
  en) path=store/android/en-US/changelogs/default.txt ;;
  ar) path=store/android/ar/changelogs/default.txt ;;
  *) echo "whats_new: language is en or ar" >&2; exit 1 ;;
esac

text=$(git show "$tag:$path" 2>/dev/null || true)
# The kit's placeholders (same list as test/store/listing_test.dart).
for placeholder in 'Feature one' 'اكتب هنا' 'TODO'; do
  case $text in *"$placeholder"*) text= ;; esac
done
if [ -n "${text//[[:space:]]/}" ]; then
  printf '%s\n' "$text"
elif [ "${2:-en}" = en ]; then
  ./scripts/release_notes.sh plain "$tag"
fi
