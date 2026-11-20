#!/usr/bin/env bash
# Run the app on a simulator / emulator for an AI agent to drive and test.
#
#   ./scripts/agent_run.sh ios [env]        # boots a simulator if none is running
#   ./scripts/agent_run.sh android [env]    # boots an emulator if none is running
#   ./scripts/agent_run.sh <device-id> [env]  # any `flutter devices` id
#   ./scripts/agent_run.sh reload|restart [ios|android|<id>]   # hot reload / restart
#   ./scripts/agent_run.sh shot [ios|android|<id>]  # screenshot → build/agent/<target>.png
#   ./scripts/agent_run.sh stop [ios|android|<id>]  # stop one, or every run
#   ./scripts/agent_run.sh status
#
# The app runs in the background in debug mode with the env file (like
# scripts/run.sh) and the Flutter Driver extension (test_driver/agent_app.dart,
# never in a release build). It prints the Dart Tooling Daemon (DTD) URI:
# give it to the Dart MCP server's `dtd` tool (connect), then use
# `flutter_driver_command` (tap, enter_text, screenshot…), `widget_inspector`,
# `get_runtime_errors` and `hot_reload`. Logs: build/agent/<target>.log.
# iOS needs a Mac with Xcode; Android needs the Android SDK and an AVD.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
. ./.project-kit.env

FLUTTER="flutter"
command -v fvm >/dev/null 2>&1 && FLUTTER="fvm flutter"
dir=build/agent
mkdir -p "$dir"

die() { echo "✗ $*" >&2; exit 1; }

# The device id of the first running device for a platform (ios / android),
# or the argument itself when it's already a device id.
device_for() {
  $FLUTTER devices --machine 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
text = sys.stdin.read()
devices = json.loads(text[text.index("["):]) if "[" in text else []
for d in devices:
    p = d.get("targetPlatform", "")
    if d.get("id") == want or (want == "ios" and p == "ios") or (want == "android" and p.startswith("android")):
        print(d["id"]); break
' "$1"
}

# Boots a simulator / emulator when none is running for the platform.
boot() {
  case "$1" in
    ios)
      [ "$(uname)" = Darwin ] || die "iOS needs a Mac with Xcode."
      $FLUTTER emulators --launch apple_ios_simulator >/dev/null ;;
    android)
      local avd
      avd=$($FLUTTER emulators 2>/dev/null | awk -F'•' '/android/ {gsub(/ /, "", $1); print $1; exit}')
      [ -n "$avd" ] || die "No Android emulator. Create one in Android Studio → Device Manager."
      $FLUTTER emulators --launch "$avd" >/dev/null ;;
    *) die "No running device '$1' (see: $FLUTTER devices)." ;;
  esac
  for _ in $(seq 1 60); do
    [ -n "$(device_for "$1")" ] && return 0
    sleep 3
  done
  die "The $1 device didn't come up in 3 minutes."
}

pid_of() { [ -f "$dir/$1.pid" ] && cat "$dir/$1.pid"; }
running() { local p; p=$(pid_of "$1") && kill -0 "$p" 2>/dev/null; }
# Running targets (ios, android, a device id); <target>.flutter.pid is the
# flutter tool's own pid, for hot reload signals.
targets() {
  for f in "$dir"/*.pid; do
    case "$f" in *.flutter.pid) continue ;; esac
    [ -e "$f" ] && basename "$f" .pid
  done
  return 0
}

run() {
  local target=$1 env_name=${2:-$DEFAULT_ENV}
  case " $ENV_LIST " in *" $env_name "*) ;; *) die "Unknown environment '$env_name' (have: $ENV_LIST)" ;; esac
  running "$target" && die "Already running on $target: ./scripts/agent_run.sh stop $target"

  local device
  device=$(device_for "$target")
  if [ -z "$device" ]; then boot "$target"; device=$(device_for "$target"); fi

  local env_file="env/$env_name.json"
  [ -f "$env_file" ] || cp env/example.json "$env_file"
  local flavor=()
  [ "$HAS_FLAVORS" = true ] && flavor=(--flavor "$env_name")

  local log="$dir/$target.log"
  : > "$log"
  # The env file holds publishable keys only; flutter run doesn't print them.
  nohup $FLUTTER run -d "$device" "${flavor[@]}" \
    --dart-define-from-file="$env_file" \
    --target test_driver/agent_app.dart \
    --print-dtd --pid-file "$dir/$target.flutter.pid" \
    > "$log" 2>&1 < /dev/null &
  echo $! > "$dir/$target.pid"

  echo "Building and starting on $device (log: $log)…"
  for _ in $(seq 1 400); do
    if grep -q 'Dart Tooling Daemon is available at:' "$log"; then
      local dtd vm
      dtd=$(sed -n 's/.*Dart Tooling Daemon is available at: *//p' "$log" | tail -n 1)
      vm=$(sed -n 's/.*Dart VM Service .* is available at: *//p' "$log" | tail -n 1)
      echo "$dtd" > "$dir/$target.dtd"
      echo "✓ Running on $device"
      echo "DTD: $dtd"
      echo "VM service: $vm"
      echo "Next: Dart MCP → dtd connect with the DTD URI, then flutter_driver_command / widget_inspector / get_runtime_errors / hot_reload."
      return 0
    fi
    running "$target" || { tail -n 40 "$log" >&2; die "flutter run stopped (see $log)."; }
    sleep 3
  done
  die "No DTD URI after 20 minutes (see $log)."
}

signal() {
  local sig=$1 target=${2:-}
  [ -n "$target" ] || target=$(targets | head -n 1)
  [ -n "$target" ] || die "Nothing running."
  local p
  p=$(cat "$dir/$target.flutter.pid" 2>/dev/null) || die "Not running on $target."
  kill "-$sig" "$p"
}

shot() {
  local target=${1:-}
  [ -n "$target" ] || target=$(targets | head -n 1)
  [ -n "$target" ] || target=ios
  local out="$dir/$target.png" device
  device=$(device_for "$target")
  [ -n "$device" ] || die "No running device '$target'."
  $FLUTTER screenshot -d "$device" -o "$out" >/dev/null
  echo "$out"
}

stop() {
  local list
  if [ -n "${1:-}" ]; then list=$1; else list=$(targets); fi
  for t in $list; do
    if running "$t"; then
      kill "$(pid_of "$t")" 2>/dev/null || true
      echo "Stopped $t"
    fi
    rm -f "$dir/$t.pid" "$dir/$t.flutter.pid" "$dir/$t.dtd"
  done
}

status() {
  local any=false
  for t in $(targets); do
    if running "$t"; then any=true; echo "$t: running · DTD $(cat "$dir/$t.dtd" 2>/dev/null || echo '(starting)')"; fi
  done
  $any || echo "Nothing running."
}

case "${1:-}" in
  ""|-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' ;;
  reload) signal USR1 "${2:-}" && echo "Hot reload sent" ;;
  restart) signal USR2 "${2:-}" && echo "Hot restart sent" ;;
  shot) shot "${2:-}" ;;
  stop) stop "${2:-}" ;;
  status) status ;;
  *) run "$1" "${2:-}" ;;
esac
