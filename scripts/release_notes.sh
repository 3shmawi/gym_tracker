#!/usr/bin/env bash
# Release notes from Conventional Commits.
#   scripts/release_notes.sh [markdown|plain] [tag]
#     markdown  grouped notes for the GitHub release (default)
#     plain     ≤ 500 characters for Google Play "What's new" / the in-app
#               update dialog
#     tag       notes for that tag (since the tag before it); default: the
#               commits not released yet (since the last tag)
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-markdown}
tag=${2:-}

if [ -n "$tag" ]; then
  prev=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$tag^" 2>/dev/null || true)
  range="${prev:+$prev..}$tag"
else
  last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
  range="${last:+$last..}HEAD"
fi

features=(); fixes=(); breaking=()
while IFS= read -r subject; do
  [ -z "$subject" ] && continue
  type=$(printf '%s' "$subject" | sed -nE 's/^([a-z]+)(\([^)]*\))?(!)?: .*/\1\3/p')
  text=$(printf '%s' "$subject" | sed -E 's/^[a-z]+(\([^)]*\))?!?: //; s/ \(#[0-9]+\)$//')
  text="$(printf '%s' "${text:0:1}" | tr '[:lower:]' '[:upper:]')${text:1}"
  case "$type" in
    *!) breaking+=("$text") ;;
    feat) features+=("$text") ;;
    fix|perf) fixes+=("$text") ;;
  esac
done < <(git log --no-merges --format=%s "$range")

if [ "$mode" = plain ]; then
  out=""
  for item in ${breaking[@]+"${breaking[@]}"} ${features[@]+"${features[@]}"} ${fixes[@]+"${fixes[@]}"}; do
    out+="• $item"$'\n'
  done
  [ -z "$out" ] && out="Bug fixes and improvements."
  out=${out%$'\n'}
  if [ ${#out} -gt 500 ]; then out="${out:0:496}…"; fi
  printf '%s\n' "$out"
  exit 0
fi

section() { # title items...
  local title=$1; shift
  [ $# -eq 0 ] && return 0
  printf '### %s\n' "$title"
  for item in "$@"; do printf -- '- %s\n' "$item"; done
  printf '\n'
}
section "⚠️ Breaking changes" ${breaking[@]+"${breaking[@]}"}
section "✨ New" ${features[@]+"${features[@]}"}
section "🐛 Fixed" ${fixes[@]+"${fixes[@]}"}
if [ ${#breaking[@]} -eq 0 ] && [ ${#features[@]} -eq 0 ] && [ ${#fixes[@]} -eq 0 ]; then
  echo "Maintenance release: dependency updates and internal improvements."
fi
