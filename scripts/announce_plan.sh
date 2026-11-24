#!/usr/bin/env bash
# Which platforms should get an optional-update notice for a live version:
#
#   scripts/announce_plan.sh <live> <android_announced> <ios_announced>
#
# Prints `both`, `android`, `ios` or nothing. A platform qualifies when the
# live version is newer than what the app announces there now — so a
# version you already announced by hand (or a newer one) is never
# overwritten. ENABLE_ANDROID / ENABLE_IOS=false leave a platform out.
set -euo pipefail
live=${1:?live version}
semver='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ $live =~ $semver ]] || { echo "announce_plan: '$live' is not x.y.z" >&2; exit 1; }

newer() { # $1 newer than $2 (empty/invalid $2 = nothing announced)
  [[ ${2:-} =~ $semver ]] || return 0
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

platforms=()
if [ "${ENABLE_ANDROID:-}" != false ] && newer "$live" "${2:-}"; then platforms+=(android); fi
if [ "${ENABLE_IOS:-}" != false ] && newer "$live" "${3:-}"; then platforms+=(ios); fi
case "${platforms[*]-}" in
  "android ios") echo both ;;
  "") ;;
  *) echo "${platforms[0]}" ;;
esac
