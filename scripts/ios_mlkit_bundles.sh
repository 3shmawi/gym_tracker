#!/usr/bin/env bash
# Copies Google ML Kit's pose-detection model bundles into the iOS app
# (ios/Runner/MLKit/), taken from Google's own CocoaPods archives on
# dl.google.com and checked against pinned SHA-256 sums.
#
# Why by hand: google_mlkit_pose_detection uses Swift Package Manager
# (d-date/google-mlkit-swiftpm), which can't carry resource bundles inside
# binary targets (the plugin's README, "Requirements → iOS"). The bundles
# are committed; run this only to update them, then update the pins here and
# in test/security/platform_config_test.dart.
#
# Only the base ("fast") model ships: the accurate one is left out, as on
# Android (docs/designs/move_games.md §9).
#
#   ./scripts/ios_mlkit_bundles.sh          # verify the committed files
#   ./scripts/ios_mlkit_bundles.sh --fetch  # download from Google, verify, copy
set -euo pipefail

VERSION="1.0.0-beta16" # MLKitPoseDetection pod used by google-mlkit-swiftpm 9.0.2
DEST="ios/Runner/MLKit"

# pod path on dl.google.com (from the podspecs on cdn.cocoapods.org)
ARCHIVES=(
  "6dac78f485fb9567/MLKitPoseDetection"
  "8f7c2f27120fabc4/MLKitPoseDetectionCommon"
  "2fc196cfaef9b4b9/MLKitXenoCommon"
)

# Every file that ships, and its SHA-256 (checked 2026-11-13: identical in
# Google's archives and in google-mlkit-swiftpm 9.0.2's release bundles).
PINS="5258fc9ed2e1598b9739534e2393e012928f441de901451e85e9329b5d763012  MLKitPoseDetectionCommonResources.bundle/pose_non_tracking_graph.binarypb
e28fe1c1a0b8e1a014e4c4135499a70c50a0f248d834fb21ea0c0339e9e5d8b5  MLKitPoseDetectionCommonResources.bundle/pose_tracking_graph.binarypb
774adb54eb742c8a7f8fe39b19d0d1ae42cd776015bbdf3e57bde14c5fd8b773  MLKitPoseDetectionFastResources.bundle/pose_landmark_detector_fast.tflite
a63c614bef30d35947f13be361820b1e4e3bec9cfeebf4d11216a18373108e85  MLKitPoseDetectionFastResources.bundle/pose_person_detector_fast.tflite
943fec320f003427c2181f0712168b00f5b04108672906033013e452d2b1c73e  MLKitXenoResources.bundle/yuv_to_rgb_graph.binarypb"

sha() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

verify() {
  (cd "$1" && echo "$PINS" | sha -c --quiet -) || {
    echo "✗ ML Kit bundles in $1 don't match the pinned SHA-256 sums" >&2
    exit 1
  }
  local count
  count=$(find "$1" -type f | wc -l | tr -d ' ')
  if [ "$count" != "5" ]; then
    echo "✗ $1 has $count files, expected exactly 5 (nothing extra ships)" >&2
    exit 1
  fi
}

if [ "${1:-}" = "--fetch" ]; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  for a in "${ARCHIVES[@]}"; do
    name=$(basename "$a")
    curl --fail --silent --show-error --location --proto '=https' \
      -o "$work/$name.tar.gz" "https://dl.google.com/dl/cpdc/$a-$VERSION.tar.gz"
    tar -xzf "$work/$name.tar.gz" -C "$work"
  done
  staged="$work/staged"
  mkdir -p "$staged"
  for b in MLKitPoseDetectionFastResources MLKitPoseDetectionCommonResources MLKitXenoResources; do
    src=$(find "$work" -type d -path "*/Resources/$b" | head -1)
    [ -n "$src" ] || { echo "✗ $b not found in Google's archives" >&2; exit 1; }
    mkdir -p "$staged/$b.bundle"
    cp "$src"/* "$staged/$b.bundle/"
  done
  verify "$staged"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp -R "$staged"/. "$DEST"/
fi

verify "$DEST"
echo "✓ ML Kit bundles in $DEST match the pins"
