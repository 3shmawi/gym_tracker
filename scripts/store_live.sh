#!/usr/bin/env bash
# Prints the app version that every user can download now — the lower of
# the two stores' live versions — or nothing while a store doesn't have
# one yet. Used by Actions → Announce update (daily run) to show the
# optional update in the app only once both stores have it.
#
#   PLAY_KEY_FILE="$RUNNER_TEMP/play.json" scripts/store_live.sh
#
# - Google Play: the production track's fully rolled-out release (status
#   `completed`; a staged rollout doesn't count — most users can't update
#   yet). Its name is the AAB's versionName unless you renamed it. Needs
#   the Play service account (the one CI uploads with); PLAY_KEY_FILE must
#   already be masked (scripts/mask_secrets.sh).
# - App Store: Apple's public lookup (no key). Apple's cache can lag a few
#   hours after "Ready for Distribution". APP_STORE_COUNTRY (default `us`)
#   picks the storefront the app is sold in.
# ENABLE_ANDROID=false / ENABLE_IOS=false leave a store out (same repo
# variables as the release workflow). A store that can't be checked prints
# a warning and counts as "not live", so nothing is announced too early.
set -euo pipefail
package=${PACKAGE_ID:-com.mohager.azm}
country=${APP_STORE_COUNTRY:-us}
semvers() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true; }

# GET/POST/DELETE that never fails the script; prints the body on 2xx.
call() { # method url [token]
  local out code
  out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" "$2" \
    ${3:+-H "Authorization: Bearer $3"} -H 'Content-Length: 0' || echo 000)
  if [ "${code:0:1}" = 2 ]; then cat "$out"; rm -f "$out"; return 0; fi
  echo "::warning::store_live: $1 ${2%%\?*} → HTTP $code $(jq -r '.error.message // empty' "$out" 2>/dev/null || true)" >&2
  rm -f "$out"
  return 1
}

play_live() {
  if [ -z "${PLAY_KEY_FILE:-}" ] && [ -z "${PLAY_TOKEN:-}" ]; then
    echo "::warning::store_live: no Play service account (PLAY_SERVICE_ACCOUNT_JSON) — can't check Google Play." >&2
    return 0
  fi
  local token api edit track
  token=${PLAY_TOKEN:-$(GCP_SCOPE=https://www.googleapis.com/auth/androidpublisher \
    "$(dirname "$0")/gcp_token.sh" "$PLAY_KEY_FILE")}
  api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package/edits"
  edit=$(call POST "$api" "$token" | jq -r '.id // empty') || return 0
  [ -n "$edit" ] || return 0
  track=$(call GET "$api/$edit/tracks/production" "$token") || track='{}'
  call DELETE "$api/$edit" "$token" >/dev/null || true   # read-only: discard the edit
  printf '%s' "$track" |
    jq -r '.releases[]? | select(.status == "completed") | .name // ""' |
    semvers | sort -V | tail -n 1
}

app_store_live() {
  call GET "https://itunes.apple.com/lookup?bundleId=$package&country=$country&entity=software" |
    jq -r '.results[0].version // ""' | semvers | head -n 1
}

versions=()
if [ "${ENABLE_ANDROID:-}" != false ]; then
  android=$(play_live)
  echo "Google Play: ${android:-not live}" >&2
  [ -n "$android" ] || exit 0
  versions+=("$android")
fi
if [ "${ENABLE_IOS:-}" != false ]; then
  ios=$(app_store_live || true)
  echo "App Store: ${ios:-not live}" >&2
  [ -n "$ios" ] || exit 0
  versions+=("$ios")
fi
[ "${#versions[@]}" -gt 0 ] || exit 0
printf '%s\n' "${versions[@]}" | sort -V | head -n 1
