#!/usr/bin/env bash
# Scroll performance of the main lists (docs/performance.md).
#   ./scripts/perf.sh                  # glass, on the connected device
#   ./scripts/perf.sh --lite           # GLASS_LITE=true (no shader, no blur)
#   ./scripts/perf.sh -d <device-id>   # a specific device
#   ./scripts/perf.sh --name before    # results in build/perf/before.*
# Profile mode on a real phone: emulators and simulators don't measure what
# users see (iOS simulators can't run profile builds at all; pass --debug to
# get debug-mode numbers there, and never compare them with profile ones).
# Uses env/example.json: no keys, so Sentry and PostHog stay off and don't
# take part in the measurement. Results: build/perf/<glass|lite|name>.{json,md}.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER="flutter"
command -v fvm >/dev/null 2>&1 && FLUTTER="fvm flutter"

mode=(--profile)
defines=()
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --lite) defines+=(--dart-define=GLASS_LITE=true) ;;
    --debug) mode=(--debug) ;;
    --name) shift; export PERF_NAME="$1" ;;
    *) args+=("$1") ;;
  esac
  shift
done

# --no-dds: the Dart Development Service on a phone isn't reachable from the
# computer (Flutter docs, "Measure performance with an integration test").
exec $FLUTTER drive \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/perf/scroll_perf.dart \
  --flavor staging \
  --dart-define-from-file=env/example.json \
  "${defines[@]+"${defines[@]}"}" \
  "${mode[@]}" --no-dds \
  "${args[@]+"${args[@]}"}"
