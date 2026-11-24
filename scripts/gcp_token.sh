#!/usr/bin/env bash
# Prints a short-lived (1 h) Google OAuth access token for a service-account
# key file — no gcloud needed, only openssl, jq and curl (all on GitHub's
# runners). Used by the workflows that call Google APIs (Firestore, FCM).
#
#   token=$(scripts/gcp_token.sh "$RUNNER_TEMP/firebase-sa.json")
#
# Never prints the key. In GitHub Actions the token is masked in the log.
set -euo pipefail
key_file=${1:?usage: scripts/gcp_token.sh <service-account.json>}
scope=${GCP_SCOPE:-https://www.googleapis.com/auth/cloud-platform}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

email=$(jq -r '.client_email // empty' "$key_file")
[ -n "$email" ] || { echo "gcp_token: $key_file is not a service-account key" >&2; exit 1; }
pem=$(mktemp)
trap 'rm -f "$pem"' EXIT
jq -r '.private_key' "$key_file" > "$pem"

now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
claims=$(jq -cn --arg iss "$email" --arg scope "$scope" --argjson now "$now" \
  '{iss: $iss, scope: $scope, aud: "https://oauth2.googleapis.com/token", iat: $now, exp: ($now + 3600)}' | b64url)
signature=$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$pem" -binary | b64url)

response=$(curl -sS https://oauth2.googleapis.com/token \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$header.$claims.$signature")
token=$(printf '%s' "$response" | jq -r '.access_token // empty')
if [ -z "$token" ]; then
  echo "gcp_token: no token ($(printf '%s' "$response" | jq -r '.error_description // .error // "unknown error"'))" >&2
  exit 1
fi
[ "${GITHUB_ACTIONS:-}" = true ] && echo "::add-mask::$token" >&2
printf '%s\n' "$token"
