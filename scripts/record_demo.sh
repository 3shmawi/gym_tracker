#!/usr/bin/env bash
# Records an integration test on the running Android emulator.
#   scripts/record_demo.sh <integration_test/file.dart> <out.mp4>
# Uses --dart-define=DEMO=true so `beat()` pauses make the video readable.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./.project-kit.env
test_file=${1:-integration_test/app_test.dart}
out=${2:-build/demo/raw.mp4}
mkdir -p "$(dirname "$out")"

flavor=()
[ "$HAS_FLAVORS" = true ] && flavor=(--flavor "$DEFAULT_ENV")
env_file="env/$DEFAULT_ENV.json"; [ -f "$env_file" ] || env_file=env/example.json

# Build + install first so the recording starts at app launch, not at the build.
flutter build apk --debug ${flavor[@]+"${flavor[@]}"} --dart-define-from-file="$env_file" >/dev/null

adb shell rm -f /sdcard/demo.mp4
adb shell screenrecord --bit-rate 8000000 --time-limit 170 /sdcard/demo.mp4 &
recorder=$!
sleep 1
status=0
flutter test "$test_file" ${flavor[@]+"${flavor[@]}"} \
  --dart-define-from-file="$env_file" --dart-define=DEMO=true || status=$?
sleep 1
adb shell pkill -INT screenrecord || true
wait "$recorder" 2>/dev/null || true
sleep 2
adb pull /sdcard/demo.mp4 "$out" >/dev/null
echo "Recorded $out (test exit $status)"
exit "$status"
