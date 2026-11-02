#!/usr/bin/env bash
# Runs make_invites.py in a private virtualenv with hash-pinned packages.
# Run it on YOUR computer, never in CI. Needs python3 (3.10+).
#
#   export SUPABASE_URL=https://<project-ref>.supabase.co
#   export SUPABASE_SECRET_KEY=…        # from your password manager, not a file in the repo
#   scripts/make_invites/run.sh --gym <gym-uuid> --count 20
#
# The key is only ever read from the environment (docs/security.md).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv="${XDG_CACHE_HOME:-$HOME/.cache}/azm-make-invites/venv"

if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
  echo "error: refusing to run in CI" >&2
  exit 2
fi

if [ ! -x "$venv/bin/python" ]; then
  python3 -m venv "$venv"
fi
stamp="$venv/.requirements.sha256"
if command -v shasum >/dev/null 2>&1; then
  want="$(shasum -a 256 "$here/requirements.txt" | cut -d' ' -f1)"
else
  want="$(sha256sum "$here/requirements.txt" | cut -d' ' -f1)"
fi
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$want" ]; then
  "$venv/bin/python" -m pip install --quiet --disable-pip-version-check \
    --require-hashes --only-binary=:all: -r "$here/requirements.txt"
  printf '%s' "$want" > "$stamp"
fi

exec "$venv/bin/python" -I "$here/make_invites.py" "$@"
