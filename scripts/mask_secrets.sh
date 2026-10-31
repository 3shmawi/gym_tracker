#!/usr/bin/env bash
# Hides secret values in GitHub Actions logs (::add-mask::).
#
# GitHub only hides the exact text of a stored secret. A key decoded from a
# base64 secret, or read out of a JSON secret, is different text, so a tool
# that prints it (an error message, a debug line) would show it in the log —
# and in a public repo, logs are public. Run this right after writing such a
# file, before any tool reads it.
#
# Usage: scripts/mask_secrets.sh <file>...
#   PEM / .p8 keys → every line of the key
#   JSON key files → the private key (every line) and its id
set -euo pipefail

# Anywhere but GitHub Actions, "::add-mask::<line>" would just print the key.
[ "${GITHUB_ACTIONS:-}" = true ] || exit 0

mask() {
  local value=$1
  # Short values would hide ordinary words all over the log.
  [ "${#value}" -ge 8 ] && printf '::add-mask::%s\n' "$value"
  return 0
}

mask_lines() {
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in -----*|'') ;; *) mask "$line" ;; esac
  done
}

for file in "$@"; do
  [ -s "$file" ] || continue
  if jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    jq -r '.private_key // empty' "$file" | mask_lines
    mask "$(jq -r '.private_key_id // empty' "$file")"
  else
    mask_lines < "$file"
  fi
done
