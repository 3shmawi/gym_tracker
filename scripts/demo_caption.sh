#!/usr/bin/env bash
# Writes the social post text for a feature from its doc's "Demo & post"
# section (filled by you or the coding agent), falling back to "What it does".
#   scripts/demo_caption.sh docs/features/<feature>.md > caption.md
set -euo pipefail
doc=${1:-}
section() { # heading
  [ -n "$doc" ] && [ -f "$doc" ] || return 0
  awk -v h="## $1" '$0==h{on=1;next} /^## /{on=0} on' "$doc" | sed '/^<!--.*-->$/d' | sed '/^[[:space:]]*$/N;/^\n$/D'
}
post=$(section "Demo & post")
what=$(section "What it does")
{
  echo "# Azm — post"
  echo
  if [ -n "$(printf '%s' "$post" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$post"
  else
    echo "## Caption"
    printf '%s\n' "${what:-New in Azm.}"
    echo
    echo "#flutter #buildinpublic #مصر #تطبيقات"
  fi
  echo
  echo "---"
  echo "Video: 1080×1920, ready for TikTok, Reels, Shorts and LinkedIn."
}
