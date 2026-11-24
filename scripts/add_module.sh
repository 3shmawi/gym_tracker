#!/usr/bin/env bash
# Adds a flutter-project-kit module to this app after it was created.
#
#   scripts/add_module.sh auth=email      sign-in (email + password)
#   scripts/add_module.sh auth=social     sign-in + Apple + Google
#   scripts/add_module.sh paywall         paid features (RevenueCat)
#   scripts/add_module.sh push            push notifications (FCM)
#   scripts/add_module.sh onboarding      first-launch welcome screens
#   scripts/add_module.sh api[=freezed|retrofit|plain]   REST API client from OpenAPI
#   scripts/add_module.sh <module> --dry-run   only show what would change
#
# How: renders the kit at this app's kit version (KIT_COMMIT in
# .project-kit.env) twice — with the app's answers, and with the module
# turned on — and 3-way merges the difference into your files, like
# scripts/kit_sync.sh: new files are added, the module's blocks are merged
# into files you changed. Then it adds the packages, the native setup
# (entitlements, Info.plist, privacy manifest), records the module in
# .project-kit.env, refreshes the goldens and commits on a new branch.
# Older kit version without modules? Run scripts/kit_sync.sh first.
set -euo pipefail
cd "${KIT_SYNC_PROJECT_DIR:-$(dirname "$0")/..}"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
[ $# -ge 1 ] || usage 1
DRY_RUN=false
MODULE=""
EXTRA=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage 0 ;;
    *) MODULE=$arg ;;
  esac
done
case "$MODULE" in
  auth=email|auth=social) KEY=AUTH; VALUE=${MODULE#auth=} ;;
  auth) KEY=AUTH; VALUE=email ;;
  paywall) KEY=PAYWALL; VALUE=revenuecat ;;
  push) KEY=PUSH; VALUE=fcm ;;
  onboarding) KEY=ONBOARDING; VALUE=yes ;;
  api|api=freezed|api=retrofit|api=plain)
    KEY=API; VALUE=rest; EXTRA="API_STYLE=${MODULE#api=}"
    [ "$MODULE" = api ] && EXTRA=API_STYLE=freezed ;;
  *) echo "✗ Unknown module '$MODULE'."; usage 1 ;;
esac

KIT_REPO=${KIT_REPO:-https://github.com/3shmawi/flutter-project-kit.git}
[ -f .project-kit.env ] || { echo "✗ .project-kit.env missing — not a kit project."; exit 1; }
# shellcheck source=/dev/null
. ./.project-kit.env
current=$(eval "printf '%s' \"\${$KEY:-}\"")
case "$current" in
  "$VALUE") echo "✓ $KEY is already $VALUE."; exit 0 ;;
  ""|none|no) ;;
  *) echo "✗ $KEY is $current; changing a module's variant isn't automatic (edit by hand)."; exit 1 ;;
esac
if [ "${BACKEND:-}" = none ] && [ "$KEY" = AUTH ]; then
  [ "$VALUE" = email ] || { echo "✗ Without a backend, sign-in is email only (through your API)."; exit 1; }
  [ "${API:-none}" = rest ] || { echo "✗ Without a backend, sign-in goes through your API: run scripts/add_module.sh api first."; exit 1; }
fi
[ -n "${KIT_COMMIT:-}" ] && [ "$KIT_COMMIT" != unknown ] \
  || { echo "✗ This project doesn't record its kit version — run scripts/kit_sync.sh first."; exit 1; }
if ! $DRY_RUN && [ -n "$(git status --porcelain)" ]; then
  echo "✗ Commit or stash your changes first."; exit 1
fi

flutter_cmd() { if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then fvm flutter "$@"; else flutter "$@"; fi; }
dart_cmd() { if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then fvm dart "$@"; else dart "$@"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "› Fetching the kit…"
git clone -q "$KIT_REPO" "$work/kit"
git -C "$work/kit" cat-file -e "$KIT_COMMIT^{commit}" 2>/dev/null \
  || { echo "✗ Kit commit $KIT_COMMIT not found in $KIT_REPO."; exit 1; }
git -C "$work/kit" worktree add -q --detach "$work/src" "$KIT_COMMIT"
[ -d "$work/src/templates/modules" ] \
  || { echo "✗ This app's kit version has no modules yet — run scripts/kit_sync.sh first, merge it, then try again."; exit 1; }

cp .project-kit.env "$work/before.env"
printf 'CREATE_REPO=no\nOUTPUT_DIR=%q\n' "$work/out" >> "$work/before.env"
cp "$work/before.env" "$work/after.env"
printf '%s=%q\n' "$KEY" "$VALUE" >> "$work/after.env"
[ -z "$EXTRA" ] || printf '%s\n' "$EXTRA" >> "$work/after.env"

kit() { GEN_DATE="$GEN_DATE" FLUTTER_KIT_CONFIG=/dev/null bash "$work/src/new_project.sh" --answers "$@"; }
# Same fixes and formatting as the project got (import order, constructor
# syntax, …), so only real changes show up: dart fix needs the project's
# packages, borrowed for the run.
normalize() { # dir
  local d=$1 f borrowed=()
  for f in pubspec.yaml pubspec.lock analysis_options.yaml .dart_tool/package_config.json; do
    [ -f "$f" ] && [ ! -e "$d/$f" ] && { mkdir -p "$d/$(dirname "$f")"; cp "$f" "$d/$f"; borrowed+=("$d/$f"); }
  done
  if [ -d lib/l10n/gen ] && [ ! -e "$d/lib/l10n/gen" ]; then
    mkdir -p "$d/lib/l10n"; cp -R lib/l10n/gen "$d/lib/l10n/gen"; borrowed+=("$d/lib/l10n/gen")
  fi
  (cd "$d" && { dart_cmd fix --apply >/dev/null 2>&1 || true; dart_cmd format . >/dev/null 2>&1 || true; })
  rm -rf ${borrowed[@]+"${borrowed[@]}"}
  rmdir "$d/.dart_tool" 2>/dev/null || true
}
render() { # answers dir
  kit "$1" --render-only "$2" >/dev/null
  normalize "$2"
}
render "$work/before.env" "$work/base"
render "$work/after.env" "$work/new"

added=0; merged=0; conflicts=0
report=()
while IFS= read -r rel; do
  rel=${rel#./}
  new="$work/new/$rel"; base="$work/base/$rel"
  if [ -e "$base" ] && cmp -s "$base" "$new"; then continue; fi  # not the module's
  if [ ! -e "$rel" ]; then
    action="add"; added=$((added + 1))
    $DRY_RUN || { mkdir -p "$(dirname "$rel")"; cp "$new" "$rel"; }
  elif [ ! -e "$base" ]; then
    action="kit version saved as $rel.kit-new (you have your own file)"
    $DRY_RUN || cp "$new" "$rel.kit-new"
  elif $DRY_RUN; then
    action="merge"
  elif git merge-file -L "yours" -L "without $MODULE" -L "with $MODULE" "$rel" "$base" "$new"; then
    action="merged"; merged=$((merged + 1))
  else
    action="CONFLICT"; conflicts=$((conflicts + 1))
  fi
  report+=("  $action  $rel")
  [ -x "$new" ] && [ -e "$rel" ] && ! $DRY_RUN && chmod +x "$rel"
done < <(cd "$work/new" && find . -type f | sort)

printf '%s\n' ${report[@]+"${report[@]}"}
echo "Summary: $added added · $merged merged · $conflicts conflicts"
if $DRY_RUN; then
  echo "Packages: $(kit "$work/after.env" --module-packages)"
  exit 0
fi

# Record the module, so kit sync keeps rendering it.
if grep -q "^$KEY=" .project-kit.env; then
  sed -i.bak "s/^$KEY=.*/$KEY=$VALUE/" .project-kit.env && rm -f .project-kit.env.bak
else
  printf '%s=%s\n' "$KEY" "$VALUE" >> .project-kit.env
fi
if [ -n "$EXTRA" ]; then
  grep -v "^${EXTRA%%=*}=" .project-kit.env > .project-kit.env.tmp || true
  printf '%s\n' "$EXTRA" >> .project-kit.env.tmp && mv .project-kit.env.tmp .project-kit.env
fi

echo "› Packages"
missing=()
for package in $(kit "$work/after.env" --module-packages); do
  # `dev:<name>` = a dev dependency.
  grep -qE "^  ${package#dev:}:" pubspec.yaml || missing+=("$package")
done
# One `pub add`, so pub picks versions that fit the app's other packages.
[ ${#missing[@]} -eq 0 ] || flutter_cmd pub add "${missing[@]}" >/dev/null
echo "› Native setup"
kit "$work/after.env" --patch-native "$PWD"
# New env keys from env/example.json: add them (empty) to your env files.
for env_file in env/*.json; do
  [ "$env_file" = env/example.json ] && continue
  [ -f "$env_file" ] || continue
  python3 - "$env_file" <<'PY'
import json, sys
path = sys.argv[1]
mine = json.load(open(path))
example = json.load(open("env/example.json"))
missing = [k for k in example if k not in mine]
if missing:
    mine.update({k: example[k] for k in missing})
    json.dump(mine, open(path, "w"), indent=2)
    open(path, "a").write("\n")
    print(f"  {path}: added {', '.join(missing)} (fill them in)")
PY
done

flutter_cmd pub get >/dev/null
flutter_cmd gen-l10n >/dev/null
# REST API client from api/openapi.yaml.
if [ -f swagger_parser.yaml ]; then
  dart_cmd run swagger_parser >/dev/null
  # freezed / Retrofit parts.
  grep -q '^  build_runner:' pubspec.yaml && dart_cmd run build_runner build -d >/dev/null
fi
dart_cmd fix --apply >/dev/null 2>&1 || true
dart_cmd format . >/dev/null
[ -f test/golden/golden_test.dart ] && { flutter_cmd test --update-goldens test/golden >/dev/null 2>&1 || echo "! Goldens not refreshed — run: flutter test --update-goldens test/golden"; }

branch="feat/add-${MODULE%%=*}"
git switch -q -c "$branch"
if [ "$conflicts" -gt 0 ]; then
  echo "! Resolve the CONFLICT files (search for <<<<<<<), then:"
  echo "  flutter analyze && flutter test && git add -A && git commit -m 'feat: add the ${MODULE%%=*} module' && gh pr create --fill"
else
  git add -A
  git commit -q -m "feat: add the ${MODULE%%=*} module (flutter-project-kit)"
  echo "✓ Committed on $branch. Next: flutter analyze && flutter test, then gh pr create --fill"
fi
echo "  Setup steps (console, keys, store): docs/features/ — the new module's page."
