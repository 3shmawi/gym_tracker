#!/usr/bin/env bash
# Says which app keys are missing from an env file, so a build without
# analytics, crash reports or a backend is never a silent surprise.
#
#   scripts/check_env.sh env/prod.json
#
# Prints key NAMES only, never values. In GitHub Actions each problem is a
# ::warning:: (shown on the run's summary page); elsewhere plain text. It
# never fails the build: a fresh project builds before its keys exist.
set -euo pipefail
cd "$(dirname "$0")/.."

file=${1:?usage: scripts/check_env.sh env/<name>.json}
command -v jq >/dev/null || { echo "check_env: jq not installed, skipped"; exit 0; }

warn() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::warning title=$file::$1"; else echo "warning: $file: $1"; fi
}

if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
  warn "not valid JSON — every key is empty in this build"
  exit 0
fi

value() { jq -r --arg k "$1" '.[$k] // "" | tostring' "$file"; }

need=(SUPABASE_URL SUPABASE_PUBLISHABLE_KEY POSTHOG_API_KEY POSTHOG_HOST)
grep -q '^  sentry_flutter:' pubspec.yaml 2>/dev/null && need+=(SENTRY_DSN)
grep -q '^  clarity_flutter:' pubspec.yaml 2>/dev/null && need+=(CLARITY_PROJECT_ID)

missing=()
for key in "${need[@]}"; do
  [ -n "$(value "$key")" ] || missing+=("$key")
done
if [ ${#missing[@]} -gt 0 ]; then
  warn "empty: ${missing[*]} — those services are off in this build (fill env/*.json, then tool/setup_secrets.sh)"
fi

# PostHog: the project key starts with phc_. A personal key (phx_) or a
# key from the other region is accepted by the app but every event is dropped.
posthog_key=$(value POSTHOG_API_KEY)
if [ -n "$posthog_key" ] && [ "${posthog_key#phc_}" = "$posthog_key" ]; then
  warn "POSTHOG_API_KEY is not a project API key (should start with phc_) — PostHog drops every event"
fi
case "$(value POSTHOG_HOST)" in
  ''|https://eu.i.posthog.com|https://us.i.posthog.com) ;;
  https://eu.posthog.com|https://us.posthog.com|https://app.posthog.com)
    warn "POSTHOG_HOST is the dashboard address; the app must send to https://eu.i.posthog.com or https://us.i.posthog.com" ;;
  https://*) ;; # self-hosted or a reverse proxy
  *) warn "POSTHOG_HOST must start with https://" ;;
esac
exit 0
