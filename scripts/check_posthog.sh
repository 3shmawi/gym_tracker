#!/usr/bin/env bash
# Checks that the PostHog key and host in an env file work together, then
# sends one test event (`posthog_setup_checked`) you should see in
# PostHog → Activity within a minute.
#
# The most common reason for "no events": a US-cloud key with the EU host
# (or the other way round). PostHog then drops every event without an error.
#
# Usage: scripts/check_posthog.sh [env name]   (default: DEFAULT_ENV)
# Never prints the key.
set -euo pipefail
cd "$(dirname "$0")/.."

default_env=prod
# shellcheck source=/dev/null
[ -f .project-kit.env ] && default_env=$(. ./.project-kit.env && echo "${DEFAULT_ENV:-prod}")
file="env/${1:-$default_env}.json"
[ -f "$file" ] || { echo "✗ $file not found (copy env/example.json and fill it)"; exit 1; }

read -r key host < <(python3 - "$file" <<'PY'
import json, sys
env = json.load(open(sys.argv[1]))
key = str(env.get("POSTHOG_API_KEY", "")).strip() or "-"
host = str(env.get("POSTHOG_HOST", "")).strip().rstrip("/") or "https://eu.i.posthog.com"
print(key, host)
PY
)
[ "$key" != - ] || { echo "✗ POSTHOG_API_KEY is empty in $file: analytics is off"; exit 1; }
case $key in phc_*) ;; *) echo "✗ POSTHOG_API_KEY should be the project API key (phc_…)"; exit 1 ;; esac

# Asks the flags endpoint whether this host knows the key. Prints the HTTP code.
probe() {
  printf '{"api_key":"%s","distinct_id":"posthog-setup-check"}' "$key" |
    curl -sS -m 15 -o /dev/null -w '%{http_code}' -X POST "$1/flags/?v=2" \
      -H 'Content-Type: application/json' --data-binary @- 2>/dev/null || true
}

code=$(probe "$host")
if [ "$code" = 000 ]; then
  echo "✗ couldn't reach $host (offline, or a proxy/firewall blocks it)"
  exit 1
fi
if [ "$code" != 200 ]; then
  echo "✗ $host rejected the key (HTTP $code)."
  case $host in
    *eu.i.posthog.com*) other=https://us.i.posthog.com ;;
    *us.i.posthog.com*) other=https://eu.i.posthog.com ;;
    *) other= ;;
  esac
  if [ -n "$other" ] && [ "$(probe "$other")" = 200 ]; then
    echo "  The key belongs to $other: set POSTHOG_HOST to it in $file,"
    echo "  then upload the env file again (tool/setup_secrets.sh) and rebuild."
  else
    echo "  Check the key in PostHog → Project settings → Project API key."
  fi
  exit 1
fi
echo "✓ $host accepts the key"

printf '{"api_key":"%s","event":"posthog_setup_checked","distinct_id":"posthog-setup-check","properties":{"source":"scripts/check_posthog.sh"}}' "$key" |
  curl -sS -m 15 -o /dev/null -w '%{http_code}' -X POST "$host/i/v0/e/" \
    -H 'Content-Type: application/json' --data-binary @- |
  { read -r sent; [ "$sent" = 200 ] && echo "✓ test event sent: look for posthog_setup_checked in PostHog → Activity" \
    || { echo "✗ sending the test event failed (HTTP $sent)"; exit 1; }; }
