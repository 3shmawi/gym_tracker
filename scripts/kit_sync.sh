#!/usr/bin/env bash
# Brings this project up to date with the latest flutter-project-kit.
#
#   scripts/kit_sync.sh            sync on a new branch (review, then PR)
#   scripts/kit_sync.sh --dry-run  only show what would change
#
# How: renders the kit's templates twice with this project's answers
# (.project-kit.env) — at the kit version the project was made/synced with,
# and at the latest — then 3-way merges the difference into your files:
#   unchanged by you → updated · new in the kit → added
#   changed by both  → merged; conflicts get <<<<<<< markers to resolve
# Native files patched at creation (AndroidManifest, Info.plist, Gradle) and
# your own code outside the templates are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

KIT_REPO=${KIT_REPO:-https://github.com/3shmawi/flutter-project-kit.git}
[ -f .project-kit.env ] || { echo "✗ .project-kit.env missing — not a kit project."; exit 1; }
# shellcheck source=/dev/null
. ./.project-kit.env
[ -n "${KIT_COMMIT:-}" ] && [ "$KIT_COMMIT" != unknown ] \
  || { echo "✗ This project doesn't record its kit version (made before kit sync existed)."; exit 1; }
if ! $DRY_RUN && [ -n "$(git status --porcelain)" ]; then
  echo "✗ Commit or stash your changes first."; exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "› Fetching the kit…"
git clone -q "$KIT_REPO" "$work/kit"
latest=$(git -C "$work/kit" rev-parse HEAD)
if [ "$latest" = "$KIT_COMMIT" ]; then echo "✓ Already up to date (kit ${latest:0:7})."; exit 0; fi
git -C "$work/kit" cat-file -e "$KIT_COMMIT^{commit}" 2>/dev/null \
  || { echo "✗ Kit commit $KIT_COMMIT not found in $KIT_REPO."; exit 1; }

echo "› Changes in the kit since ${KIT_COMMIT:0:7}:"
git -C "$work/kit" log --format='  %h %s' "$KIT_COMMIT..$latest" | head -n 30

answers="$work/answers.env"
cp .project-kit.env "$answers"
printf 'CREATE_REPO=no\nOUTPUT_DIR=%q\n' "$work/out" >> "$answers"
render() { # commit dir
  git -C "$work/kit" worktree add -q --detach "$work/src-$1" "$1"
  GEN_DATE="$GEN_DATE" FLUTTER_KIT_CONFIG=/dev/null \
    bash "$work/src-$1/new_project.sh" --answers "$answers" --render-only "$2" >/dev/null
  # Same formatting as the project, so only real changes show up.
  if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then fvm dart format "$2" >/dev/null 2>&1 || true
  elif command -v dart >/dev/null 2>&1; then dart format "$2" >/dev/null 2>&1 || true; fi
}
render "$KIT_COMMIT" "$work/base"
render "$latest" "$work/new"

updated=0; added=0; merged=0; conflicts=0; same=0
report=()
while IFS= read -r rel; do
  rel=${rel#./}
  new="$work/new/$rel"; base="$work/base/$rel"
  if [ ! -e "$rel" ]; then
    action="add"; added=$((added + 1))
    $DRY_RUN || { mkdir -p "$(dirname "$rel")"; cp "$new" "$rel"; }
  elif cmp -s "$rel" "$new"; then
    same=$((same + 1)); continue
  elif [ -e "$base" ] && cmp -s "$rel" "$base"; then
    action="update"; updated=$((updated + 1))
    $DRY_RUN || cp "$new" "$rel"
  elif [ -e "$base" ]; then
    if $DRY_RUN; then action="merge"
    elif git merge-file -L "yours" -L "kit ${KIT_COMMIT:0:7}" -L "kit ${latest:0:7}" "$rel" "$base" "$new"; then
      action="merged"; merged=$((merged + 1))
    else
      action="CONFLICT"; conflicts=$((conflicts + 1))
    fi
  else
    action="kit version saved as $rel.kit-new (you have your own file)"
    $DRY_RUN || cp "$new" "$rel.kit-new"
  fi
  report+=("  $action  $rel")
  [ -x "$new" ] && ! $DRY_RUN && chmod +x "$rel"
done < <(cd "$work/new" && find . -type f | sort)

while IFS= read -r rel; do
  rel=${rel#./}
  [ -e "$work/new/$rel" ] || report+=("  removed from kit (kept here, delete if unused)  $rel")
done < <(cd "$work/base" && find . -type f | sort)

printf '%s\n' ${report[@]+"${report[@]}"}
echo "Summary: $updated updated · $added added · $merged merged · $conflicts conflicts · $same already current"
$DRY_RUN && exit 0

sed -i.bak "s/^KIT_COMMIT=.*/KIT_COMMIT=$latest/" .project-kit.env && rm -f .project-kit.env.bak
branch="chore/kit-sync-${latest:0:7}"
git switch -q -c "$branch"
if [ "$conflicts" -gt 0 ]; then
  echo "! Resolve the CONFLICT files (search for <<<<<<<), then:"
  echo "  git add -A && git commit -m 'chore: sync with flutter-project-kit ${latest:0:7}' && gh pr create --fill"
else
  git add -A
  git commit -q -m "chore: sync with flutter-project-kit ${latest:0:7}"
  echo "✓ Committed on $branch. Review and open the PR:  gh pr create --fill"
fi
echo "  After merging: flutter pub get && flutter test (new templates may need new packages — see the kit changelog above)."
