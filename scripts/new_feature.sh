#!/usr/bin/env bash
# Scaffolds a feature: folders for the project's architecture, a docs page
# and test folders.   ./scripts/new_feature.sh menu_search
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=/dev/null
. ./.project-kit.env

name=${1:-}
printf '%s' "$name" | grep -Eq '^[a-z][a-z0-9_]*$' || { echo "Usage: $0 <feature_name in snake_case>"; exit 1; }
[ -e "lib/features/$name" ] && { echo "lib/features/$name already exists"; exit 1; }

if [ "$ARCHITECTURE" = layered ]; then
  dirs="data/datasources data/models data/repositories domain/entities domain/repositories domain/usecases presentation/widgets"
else
  dirs="data presentation/widgets"
fi
for d in $dirs; do mkdir -p "lib/features/$name/$d"; touch "lib/features/$name/$d/.gitkeep"; done
for d in $dirs; do case "$d" in presentation/widgets) ;; *) mkdir -p "test/features/$name/$d"; touch "test/features/$name/$d/.gitkeep" ;; esac; done
mkdir -p "test/features/$name/presentation"; touch "test/features/$name/presentation/.gitkeep"
mkdir -p docs/features

title=$(printf '%s' "$name" | tr '_' ' ')
cat > "docs/features/$name.md" <<DOC
# Feature: $title

> Keep this page current — it is how a new developer or AI agent learns the feature.

## What it does
<!-- One paragraph, from the user's point of view. -->

## User flows
1.

## Architecture
- Layers / main files: \`lib/features/$name/\`
- State: $STATE
- Data sources: <!-- Supabase tables, APIs, local storage -->
- Routes / deep links: <!-- add to AppRoutes and docs/deep_links.md -->

## Analytics events
| Event | When | Properties |
|---|---|---|

## Feature flags
<!-- Flags.* used to gate this feature, if any -->

## Tests
- Unit: \`test/features/$name/\`
- Widget: \`test/features/$name/presentation/\`
- Integration: \`integration_test/\`

## Decisions & edge cases
-

## Demo & post
<!-- Filled when the feature is done. The PR automatically gets the
     integration test recorded on an iOS Simulator as a 1080×1920 video,
     posted with this text. -->
**Hook (first 2 seconds):**
**Scenario (what the integration test shows, with beat() pauses):**
1.
**Caption (English):**
**Caption (Egyptian Arabic):**
**Hashtags:** #flutter #buildinpublic
DOC

if ! grep -q "features/$name.md" docs/README.md 2>/dev/null; then
  printf -- '- [%s](features/%s.md)\n' "$title" "$name" >> docs/README.md
fi
echo "✓ lib/features/$name, test/features/$name, docs/features/$name.md"
echo "  Next: build it, add unit + widget + integration tests, fill the doc."
