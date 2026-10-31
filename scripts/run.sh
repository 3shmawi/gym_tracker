#!/usr/bin/env bash
# Run the app for an environment with its env file.
#   ./scripts/run.sh                 # default environment
#   ./scripts/run.sh staging -d iPhone
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
. ./.project-kit.env

env_name=${1:-$DEFAULT_ENV}
[ $# -gt 0 ] && shift
case " $ENV_LIST " in *" $env_name "*) ;; *) echo "Unknown environment '$env_name' (have: $ENV_LIST)"; exit 1 ;; esac

# Make sure the git hooks are active (not stored in the repo config).
git config core.hooksPath .githooks 2>/dev/null || true

# Use the project's pinned Flutter (.fvmrc) when FVM is installed.
FLUTTER="flutter"
command -v fvm >/dev/null 2>&1 && FLUTTER="fvm flutter"

env_file="env/$env_name.json"
[ -f "$env_file" ] || cp env/example.json "$env_file"

if [ "$HAS_FLAVORS" = true ]; then
  exec $FLUTTER run --flavor "$env_name" --dart-define-from-file="$env_file" "$@"
else
  exec $FLUTTER run --dart-define-from-file="$env_file" "$@"
fi
