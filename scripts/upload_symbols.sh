#!/usr/bin/env bash
# Uploads the obfuscation symbols of the last release build to Sentry, so
# crash stack traces stay readable. Needs SENTRY_AUTH_TOKEN, SENTRY_ORG and
# SENTRY_PROJECT (secrets set by tool/setup_secrets.sh). Skips quietly when
# Sentry isn't used or not configured.
#
# Never fails the release: it runs after the stores already have the build,
# so a Sentry problem must not skip the tag and GitHub release. A failure is
# reported as a warning with Sentry's own error lines (the token is never in
# them: sentry-cli reads it from the environment).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! grep -q '^sentry:' pubspec.yaml; then
  echo "Sentry isn't used in this project — symbols kept as a CI artifact only."
  exit 0
fi
if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
  echo "::warning::SENTRY_AUTH_TOKEN / SENTRY_ORG / SENTRY_PROJECT not set — symbols not uploaded (run tool/setup_secrets.sh)."
  exit 0
fi
out=$(mktemp)
if dart run sentry_dart_plugin 2>&1 | tee "$out"; then
  rm -f "$out"
  exit 0
fi
reason=$(grep -iE 'error|denied|not found|invalid|unauthori[sz]ed|failed' "$out" | tail -n 5 | tr '\n' ' ' | cut -c1-600 || true)
rm -f "$out"
msg="Symbols not uploaded to Sentry; the release itself is fine. ${reason:-See the step log.}"
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  echo "::warning title=Sentry symbols::$msg"
else
  echo "WARNING: $msg"
fi
exit 0
