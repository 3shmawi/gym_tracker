#!/usr/bin/env bash
# Fails when line coverage (from `flutter test --coverage`) is below the
# minimum. Generated code is excluded.
#   scripts/coverage_check.sh [min-percent]   (default: $COVERAGE_MIN or 60)
set -euo pipefail
cd "$(dirname "$0")/.."
min=${1:-${COVERAGE_MIN:-60}}
lcov=coverage/lcov.info
[ -f "$lcov" ] || { echo "No $lcov — run: flutter test --coverage"; exit 1; }

report=$(awk -v min="$min" '
  /^SF:/ { file = substr($0, 4); skip = (file ~ /lib\/l10n\/gen\// || file ~ /\.(g|freezed)\.dart$/) }
  /^LF:/ { if (!skip) { lf += substr($0, 4); files[file] = 1 } }
  /^LH:/ { if (!skip) lh += substr($0, 4) }
  END {
    pct = lf ? lh * 100 / lf : 100
    printf "%.1f %d %d %d\n", pct, lh, lf, length(files)
  }' "$lcov")
read -r pct hit total files <<<"$report"

line="Line coverage: ${pct}% (${hit}/${total} lines in ${files} files) — minimum ${min}%"
echo "$line"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "### 🧪 $line" >> "$GITHUB_STEP_SUMMARY"

if awk -v p="$pct" -v m="$min" 'BEGIN { exit !(p + 0 < m + 0) }'; then
  echo "::error::Coverage ${pct}% is below ${min}%. Add tests (or lower COVERAGE_MIN with a reason in docs/decisions/)."
  exit 1
fi
