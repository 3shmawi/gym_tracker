#!/usr/bin/env bash
# Prints the next release version from Conventional Commits since the last
# v* tag, or "skip" when only docs/chore/ci/test/style commits landed.
#
#   scripts/next_version.sh [auto|patch|minor|major]
#
# Rules:  feat → minor · fix/perf/refactor/anything else → patch
#         "!" after the type or "BREAKING CHANGE" → major
#         First release (no tag yet) → the version in pubspec.yaml
#         If pubspec.yaml was bumped higher by hand, that version wins.
set -euo pipefail
mode=${1:-auto}

pubspec_version=$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' pubspec.yaml | head -n 1)
last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
if [ -n "$last_tag" ]; then range="$last_tag..HEAD"; else range="HEAD"; fi

subjects=$(git log --format=%s "$range")
bodies=$(git log --format=%B "$range")
if [ -z "$subjects" ]; then echo skip; exit 0; fi

if [ "$mode" != auto ]; then
  bump=$mode
elif printf '%s\n' "$subjects" | grep -Eq '^[a-z]+(\([^)]*\))?!:' \
  || printf '%s\n' "$bodies" | grep -Eq '^BREAKING[ -]CHANGE'; then
  bump=major
elif printf '%s\n' "$subjects" | grep -Eq '^feat(\([^)]*\))?:'; then
  bump=minor
elif printf '%s\n' "$subjects" | grep -Evq '^(docs|chore|ci|test|style)(\([^)]*\))?:'; then
  bump=patch
else
  echo skip; exit 0
fi

# version_gt A B → true when A > B
version_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"; IFS=. read -r b1 b2 b3 <<<"$2"
  a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}; b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
  [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
  [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
  [ "$a3" -gt "$b3" ]
}

if [ -z "$last_tag" ]; then echo "$pubspec_version"; exit 0; fi

IFS=. read -r major minor patch <<<"${last_tag#v}"
major=${major:-0}; minor=${minor:-0}; patch=${patch:-0}
case "$bump" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *) echo "Unknown bump '$bump' (use auto|patch|minor|major)" >&2; exit 1 ;;
esac
next="$major.$minor.$patch"

if version_gt "$pubspec_version" "$next"; then next=$pubspec_version; fi
echo "$next"
