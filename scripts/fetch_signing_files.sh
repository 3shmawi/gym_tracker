#!/usr/bin/env bash
# Fetches the App Store signing files (certificate + profile) for one bundle
# id, with a time limit and retries.
#
#   ./scripts/fetch_signing_files.sh com.mohager.azm
#
# Why: on 2026-11-03 (Release run 33) `app-store-connect fetch-signing-files`
# found the profiles and then waited on App Store Connect with no output and no
# time limit until the 60-minute job timeout cancelled it. The run before took
# 6 seconds with the same code. Each attempt now gets SIGNING_TIMEOUT_SECONDS
# (default 180); a stalled or failed attempt is retried (SIGNING_TRIES,
# default 3).
#
# Needs what the caller already exports: APP_STORE_CONNECT_ISSUER_ID,
# APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY and
# CERTIFICATE_PRIVATE_KEY (as @file: paths, already masked). Nothing secret is
# printed here; no `set -x`.
set -euo pipefail

bundle_id="${1:?usage: fetch_signing_files.sh <bundle id>}"
if ! [[ "$bundle_id" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "::error title=Code signing::Invalid bundle id." >&2
  exit 2
fi
tries="${SIGNING_TRIES:-3}"
limit="${SIGNING_TIMEOUT_SECONDS:-180}"

# Runs the CLI in its own process group and stops the whole group after
# $limit seconds (exit status 142), so no child is left holding the step's
# output. macOS has no `timeout`; perl ships with it.
run_limited() {
  if command -v perl >/dev/null 2>&1; then
    perl -e '
      my $limit = shift;
      my $pid = fork() // die "fork failed\n";
      if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127; }
      local $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
      alarm $limit;
      waitpid($pid, 0);
      exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
    ' "$limit" "$@"
  else
    "$@"
  fi
}

for attempt in $(seq 1 "$tries"); do
  set +e
  # --strict-match-identifier: `com.mohager.azm` must not also match
  # `com.mohager.azm.stg` (the CLI matches prefixes by default).
  run_limited app-store-connect fetch-signing-files "$bundle_id" \
    --type IOS_APP_STORE --strict-match-identifier --create
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    exit 0
  fi
  if [ "$status" -eq 142 ]; then
    reason="no answer from App Store Connect within ${limit}s"
  else
    reason="exit code $status"
  fi
  echo "::warning title=Code signing::Attempt $attempt of $tries failed ($reason)."
  if [ "$attempt" -lt "$tries" ]; then
    sleep $((attempt * 15))
  fi
done

echo "::error title=Code signing::Could not fetch the signing files for $bundle_id after $tries attempts. Re-run the job; if it keeps failing, check App Store Connect status and the API key."
exit 1
