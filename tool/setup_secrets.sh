#!/usr/bin/env bash
# Pushes this repo's release secrets to GitHub, from one folder on your Mac.
#
#   tool/setup_secrets.sh            set every secret that has a value
#   tool/setup_secrets.sh --dry-run  show what would be set, change nothing
#
# Values shared by all your apps live in ~/.app-secrets/shared.env (made as a
# template on the first run). Values that belong to one app -- its Android
# upload keystore and passwords -- live in ~/.app-secrets/apps/<repo>/ and are
# generated the first time, with a random password. Set APP_SECRETS_DIR to
# keep the folder elsewhere.
#
# Needs: gh (logged in), keytool (any JDK), openssl. Secret values are piped
# to gh on stdin, never passed as arguments or printed.
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

DIR="${APP_SECRETS_DIR:-$HOME/.app-secrets}"
SHARED="$DIR/shared.env"

die() { echo "setup_secrets: $*" >&2; exit 1; }
for tool in gh keytool openssl; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) ||
  die "run this inside a GitHub repo, after 'gh auth login'"
APP_DIR="$DIR/apps/${REPO#*/}"

umask 077
mkdir -p "$DIR" "$APP_DIR"

# --- Shared values: written once as a template, filled in by hand ----------
if [[ ! -f "$SHARED" ]]; then
  cat > "$SHARED" <<'TEMPLATE'
# Values every app shares. Paths may use ~. Leave a value empty to skip
# the secrets that need it; the release workflow then skips that job.

# Apple (developer.apple.com -> Membership)
APPLE_TEAM_ID=

# App Store Connect API key (Users and Access -> Integrations -> Keys)
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_KEY_P8_PATH=~/.app-secrets/AuthKey_XXXXXXXXXX.p8

# Apple Distribution certificate, exported from Keychain as .p12 (iOS)
IOS_CERTIFICATE_P12_PATH=~/.app-secrets/ios_distribution.p12
IOS_CERTIFICATE_PASSWORD=

# Developer ID Application certificate as .p12 (macOS outside the store)
MACOS_DEVELOPER_ID_P12_PATH=~/.app-secrets/developer_id.p12
MACOS_DEVELOPER_ID_P12_PASSWORD=

# Google Play service account JSON (one per developer account)
PLAY_SERVICE_ACCOUNT_JSON_PATH=~/.app-secrets/play-service-account.json

# Fine-grained GitHub token with Contents: write, so a bump tag starts the
# release. One token can cover all your repos.
RELEASE_TOKEN=

# Supabase personal access token (Account → Access Tokens): lets CI deploy
# migrations and Edge Functions for every app. Using several Supabase
# accounts? Leave it empty here and set SUPABASE_ACCESS_TOKEN per app in
# apps/<repo>/app.env (app.env is read after this file). Per app, add to
# apps/<repo>/app.env:  SUPABASE_SECRET_KEY=sb_secret_…  (Project settings →
# API Keys; used only by CI to announce updates — never put it in env/*.json)
# and SUPABASE_DB_PASSWORD=… (the database password).
SUPABASE_ACCESS_TOKEN=

# Optional: create each app's Supabase project automatically. A second access
# token that never leaves this Mac, allowed to create projects and to read
# API keys + API key secrets. When env/prod.json has no SUPABASE_URL, this
# script creates (or reuses) a project named like the repo, with a random DB
# password, and fills env/prod.json + app.env (SUPABASE_SECRET_KEY,
# SUPABASE_DB_PASSWORD). SUPABASE_ORG = Organization settings → General →
# slug. Free plan: 2 active projects per account.
SUPABASE_ADMIN_TOKEN=
SUPABASE_ORG=
SUPABASE_REGION=eu-central-1

# Sentry (only for apps using Sentry): User settings → Auth Tokens, scopes
# org:read, team:read, project:read, project:write, project:releases -- this
# script then creates each app's project and fills SENTRY_DSN in env/*.json.
# The project slug defaults to the repo name; override per app with
# SENTRY_PROJECT in apps/<repo>/app.env. Optional: SENTRY_TEAM (default: the
# org's first team), SENTRY_URL (default https://sentry.io; EU: https://de.sentry.io).
SENTRY_AUTH_TOKEN=
SENTRY_ORG=

# Codemagic (only for repos with codemagic.yaml): personal account →
# Settings → Integrations → Codemagic API → Show. Leave the team id empty to
# keep the free plan (free minutes don't apply to teams).
CODEMAGIC_API_TOKEN=
CODEMAGIC_TEAM_ID=

# Who new Android keystores are issued to
KEYSTORE_DNAME="CN=Your Name, O=Your Company, C=EG"
TEMPLATE
  echo "Created $SHARED -- fill it in, then run this again."
  exit 0
fi

# shellcheck disable=SC1090
source "$SHARED"
expand() { local p="${1:-}"; echo "${p/#\~/$HOME}"; }

# --- Per-app Android keystore: generated once, then reused -----------------
# The alias is stored as a secret, and GitHub hides every secret's text in
# all logs. A common word ("upload") would be starred out everywhere it
# appears, so new keystores use "<repo>-upload". Existing keystores keep
# their alias (it's in app.env; changing it would break signing).
KEYSTORE="$APP_DIR/upload.jks"
APP_ENV="$APP_DIR/app.env"
KEY_ALIAS="$(printf '%s' "${REPO#*/}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')-upload"
if [[ ! -f "$KEYSTORE" ]]; then
  PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
  if $DRY_RUN; then
    echo "would create   $KEYSTORE (alias $KEY_ALIAS, random password)"
  else
    keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 2048 \
      -validity 10000 -alias "$KEY_ALIAS" -keystore "$KEYSTORE" \
      -storepass "$PASSWORD" -keypass "$PASSWORD" \
      -dname "${KEYSTORE_DNAME:-CN=Android Upload}" >/dev/null 2>&1
    # Keep whatever app.env already holds (Supabase keys…); replace only the
    # keystore lines, so filling app.env before the first run is safe.
    touch "$APP_ENV"
    grep -vE '^(ANDROID_KEY_ALIAS|ANDROID_STORE_PASSWORD|ANDROID_KEY_PASSWORD)=' "$APP_ENV" > "$APP_ENV.tmp" || true
    printf 'ANDROID_KEY_ALIAS=%s\nANDROID_STORE_PASSWORD=%s\nANDROID_KEY_PASSWORD=%s\n' \
      "$KEY_ALIAS" "$PASSWORD" "$PASSWORD" >> "$APP_ENV.tmp"
    mv "$APP_ENV.tmp" "$APP_ENV"
    echo "created       $KEYSTORE -- back this folder up; Play needs the same key for every update"
  fi
fi
# shellcheck disable=SC1090
[[ -f "$APP_ENV" ]] && source "$APP_ENV"

# --- Supabase project: created once when env/prod.json has no SUPABASE_URL --
# Needs SUPABASE_ADMIN_TOKEN + SUPABASE_ORG (shared.env, or app.env per app).
# Fills env/prod.json and app.env, which are then read and uploaded below.
if [[ -n "${SUPABASE_ADMIN_TOKEN:-}" ]]; then
  if [[ ! -f env/prod.json && -f env/example.json ]] && ! $DRY_RUN; then
    cp env/example.json env/prod.json
  fi
  if ! command -v python3 >/dev/null; then
    echo "skip          Supabase project (python3 not installed)"
  else
    DRY_RUN=$DRY_RUN SUPABASE_ADMIN_TOKEN="$SUPABASE_ADMIN_TOKEN" \
      SUPABASE_ORG="${SUPABASE_ORG:-}" SUPABASE_REGION="${SUPABASE_REGION:-}" \
      SUPABASE_PROJECT="${SUPABASE_PROJECT:-${REPO#*/}}" APP_ENV="$APP_ENV" \
      python3 "$(dirname "$0")/supabase_project.py" env/prod.json ||
      echo "skip          Supabase project (see the message above)"
    # shellcheck disable=SC1090
    [[ -f "$APP_ENV" ]] && source "$APP_ENV"
  fi
fi

# --- Push ------------------------------------------------------------------
# Target: GitHub Actions secrets, or Codemagic when the repo has codemagic.yaml
# (needs CODEMAGIC_API_TOKEN in shared.env: Codemagic → Teams → Integrations →
# Codemagic API → Show).
TARGET=github
if [[ -f codemagic.yaml ]]; then
  TARGET=codemagic
  [[ -n "${CODEMAGIC_API_TOKEN:-}" ]] || die "add CODEMAGIC_API_TOKEN to $SHARED (Codemagic → Teams → Integrations → Codemagic API)"
  command -v python3 >/dev/null || die "python3 is required for Codemagic"
  STAGE_DIR=$(mktemp -d)
  trap 'rm -rf "$STAGE_DIR"' EXIT
fi

# A network blip (a TLS handshake timeout) once stopped a run halfway, so
# each GitHub call is tried up to 4 times, a few seconds apart. Only the
# label is printed, never a value.
retry() { # label command...
  local label=$1 attempt=1
  shift
  until "$@"; do
    if (( attempt >= 4 )); then
      echo "failed        $label (after $attempt tries)" >&2
      return 1
    fi
    echo "retry         $label (try $((attempt + 1)) of 4 in $((attempt * 5)) s)" >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done
}

# The value stays in memory (never on disk or in a command line) so every
# try can pipe it to gh again.
SECRET_VALUE=""
gh_secret_set() { # name
  printf '%s' "$SECRET_VALUE" | gh secret set "$1" --repo "$REPO" >/dev/null
}

push() { # name  (value on stdin)
  if [[ $TARGET == github ]]; then
    # The trailing x keeps trailing newlines that $(...) would drop.
    SECRET_VALUE=$(cat; printf x)
    SECRET_VALUE=${SECRET_VALUE%x}
    retry "$1" gh_secret_set "$1"
    SECRET_VALUE=""
    echo "set           $1"
  else
    cat > "$STAGE_DIR/$1"   # uploaded to Codemagic in one go at the end
  fi
}

set_value() { # name value
  local name=$1 value=${2:-}
  if [[ -z "$value" ]]; then echo "skip          $name (no value)"; return; fi
  if $DRY_RUN; then echo "would set     $name ($TARGET)"; return; fi
  printf '%s' "$value" | push "$name"
}

set_file() { # name path [base64]
  local name=$1 path encode=${3:-}
  path=$(expand "${2:-}")
  if [[ -z "$path" || ! -f "$path" ]]; then echo "skip          $name (no file${path:+ at $path})"; return; fi
  if $DRY_RUN; then echo "would set     $name from $path ($TARGET)"; return; fi
  if [[ -n "$encode" ]]; then
    base64 < "$path" | tr -d '\n' | push "$name"
  else
    push "$name" < "$path"
  fi
}

echo "Repo: $REPO"
set_file  ANDROID_KEYSTORE_BASE64          "$KEYSTORE" base64
set_value ANDROID_KEY_ALIAS                "${ANDROID_KEY_ALIAS:-}"
set_value ANDROID_STORE_PASSWORD           "${ANDROID_STORE_PASSWORD:-}"
set_value ANDROID_KEY_PASSWORD             "${ANDROID_KEY_PASSWORD:-}"
set_file  PLAY_SERVICE_ACCOUNT_JSON        "${PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
set_value APPLE_TEAM_ID                    "${APPLE_TEAM_ID:-}"
set_value ASC_KEY_ID                       "${ASC_KEY_ID:-}"
set_value ASC_ISSUER_ID                    "${ASC_ISSUER_ID:-}"
set_file  ASC_KEY_P8_BASE64                "${ASC_KEY_P8_PATH:-}" base64
set_file  IOS_CERTIFICATE_P12_BASE64       "${IOS_CERTIFICATE_P12_PATH:-}" base64
set_value IOS_CERTIFICATE_PASSWORD         "${IOS_CERTIFICATE_PASSWORD:-}"
set_file  MACOS_DEVELOPER_ID_P12_BASE64    "${MACOS_DEVELOPER_ID_P12_PATH:-}" base64
set_value MACOS_DEVELOPER_ID_P12_PASSWORD  "${MACOS_DEVELOPER_ID_P12_PASSWORD:-}"
set_value RELEASE_TOKEN                    "${RELEASE_TOKEN:-}"

# --- flutter-project-kit additions ------------------------------------------
# Sentry: create this app's project if it's missing and fill SENTRY_DSN in
# env/*.json where it's still empty (before the env files are uploaded below).
if grep -q '^sentry:' pubspec.yaml 2>/dev/null; then
  if [[ -z "${SENTRY_AUTH_TOKEN:-}" || -z "${SENTRY_ORG:-}" ]]; then
    echo "skip          Sentry project (needs SENTRY_AUTH_TOKEN and SENTRY_ORG)"
  elif ! command -v python3 >/dev/null; then
    echo "skip          Sentry project (python3 not installed)"
  else
    DRY_RUN=$DRY_RUN SENTRY_AUTH_TOKEN="$SENTRY_AUTH_TOKEN" SENTRY_ORG="$SENTRY_ORG" \
      SENTRY_PROJECT="${SENTRY_PROJECT:-${REPO#*/}}" SENTRY_TEAM="${SENTRY_TEAM:-}" \
      SENTRY_URL="${SENTRY_URL:-https://sentry.io}" \
      python3 "$(dirname "$0")/sentry_project.py" env/*.json ||
      echo "skip          Sentry project (see the message above; set SENTRY_DSN by hand)"
  fi
fi
# App config for the release build (Supabase/PostHog/Sentry keys).
set_file  ENV_PROD_JSON                    "env/prod.json"
set_file  ENV_STAGING_JSON                 "env/staging.json"
# Supabase: announce updates (secret key) and deploy migrations/functions.
set_value SUPABASE_SECRET_KEY              "${SUPABASE_SECRET_KEY:-}"
set_value SUPABASE_ACCESS_TOKEN            "${SUPABASE_ACCESS_TOKEN:-}"
set_value SUPABASE_DB_PASSWORD             "${SUPABASE_DB_PASSWORD:-}"
# Sentry symbol upload for obfuscated builds (only when the app uses Sentry).
if grep -q '^sentry:' pubspec.yaml 2>/dev/null; then
  set_value SENTRY_AUTH_TOKEN              "${SENTRY_AUTH_TOKEN:-}"
  set_value SENTRY_ORG                     "${SENTRY_ORG:-}"
  set_value SENTRY_PROJECT                 "${SENTRY_PROJECT:-${REPO#*/}}"
fi

if [[ $TARGET == codemagic ]]; then
  if ! $DRY_RUN; then
    GROUP="${REPO#*/}_secrets" REPO="$REPO" STAGE_DIR="$STAGE_DIR" \
      CODEMAGIC_API_TOKEN="$CODEMAGIC_API_TOKEN" CODEMAGIC_TEAM_ID="${CODEMAGIC_TEAM_ID:-}" \
      python3 "$(dirname "$0")/codemagic_secrets.py"
  fi
  exit 0
fi

# Play release behaviour (repository variables). Keep "draft" until Google
# has reviewed the app once, then: gh variable set PLAY_RELEASE_STATUS --body completed
if ! $DRY_RUN; then
  existing=$(gh variable list --repo "$REPO" 2>/dev/null || true)
  grep -q '^PLAY_TRACK' <<<"$existing" ||
    retry PLAY_TRACK gh variable set PLAY_TRACK --body internal --repo "$REPO" >/dev/null
  grep -q '^PLAY_RELEASE_STATUS' <<<"$existing" ||
    retry PLAY_RELEASE_STATUS gh variable set PLAY_RELEASE_STATUS --body draft --repo "$REPO" >/dev/null
  echo "variables     PLAY_TRACK, PLAY_RELEASE_STATUS (unchanged if already set)"
fi
