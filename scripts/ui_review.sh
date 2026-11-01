#!/usr/bin/env bash
# Regenerates every screen screenshot (golden) and builds one page to review
# them side by side: build/ui_review/index.html.
#
#   ./scripts/ui_review.sh            # all screens
#   ./scripts/ui_review.sh home       # only goldens whose path contains "home"
#
# Review it before every UI commit: sizes consistent across screens, nothing
# too big or too small, Arabic mirrored, dark mode readable. Then commit the
# changed goldens with the code; CI fails if they drift.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter="flutter"
command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ] && flutter="fvm flutter"

$flutter test --tags golden --update-goldens

out=build/ui_review
rm -rf "$out" && mkdir -p "$out"
filter="${1:-}"

{
  echo '<!doctype html><meta charset="utf-8"><title>UI review</title>'
  echo '<style>body{font:14px system-ui;background:#111;color:#eee;margin:16px}'
  echo 'h2{margin:24px 0 8px}.row{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-start}'
  echo 'figure{margin:0}img{height:560px;border:1px solid #333;border-radius:12px}'
  echo 'figcaption{color:#aaa;margin-top:4px}</style>'
  for dir in $(find test -type d -path '*goldens/*' | sort); do
    case "$dir" in *"$filter"*) ;; *) continue ;; esac
    name="$(basename "$dir")"
    echo "<h2>$name</h2><div class=\"row\">"
    for png in "$dir"/*.png; do
      mkdir -p "$out/$name"
      cp "$png" "$out/$name/"
      echo "<figure><img src=\"$name/$(basename "$png")\"><figcaption>$(basename "$png" .png)</figcaption></figure>"
    done
    echo '</div>'
  done
} > "$out/index.html"

echo "Review: $out/index.html"
