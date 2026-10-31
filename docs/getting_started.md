# Getting started

## 1. Environment files
Each environment (staging, prod) has `env/<name>.json` (git-ignored; the
template is `env/example.json`). Fill in:

| Key | Where to find it |
|---|---|
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Filled by `tool/setup_secrets.sh` when `SUPABASE_ADMIN_TOKEN` + `SUPABASE_ORG` are set (it creates the project); by hand: Supabase → Project settings → API Keys (`sb_publishable_…`) |
| `POSTHOG_API_KEY`, `POSTHOG_HOST` | PostHog → Project settings |
| `SENTRY_DSN` | Filled by `tool/setup_secrets.sh` (it creates the Sentry project if missing); by hand: Sentry → Project → Client keys |
| `CLARITY_PROJECT_ID` | Clarity → Settings (if Clarity is used) |

Every service is skipped while its key is empty, so the app runs before any
of this is set up.

## 2. Supabase
After `tool/setup_secrets.sh` has uploaded the Supabase secrets, run Actions →
**Supabase deploy** once (`gh workflow run supabase.yml`); later changes under
`supabase/` deploy on every merge to `main`. By hand instead: run
`supabase/migrations/0001_app_versions.sql` in Supabase → SQL editor (or
`supabase db push`). Then fix the iOS `store_url` once the App Store id exists.

**Keep-alive:** free Supabase projects pause after 7 days without activity.
`.github/workflows/supabase-keepalive.yml` pings the `app_versions` table every
3 days using `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` from the
`ENV_PROD_JSON` secret (Actions → *Supabase keep-alive* → Run workflow to test
it). GitHub pauses scheduled workflows in repos with no commits for 60 days —
re-enable it from the Actions tab if that happens.

## 3. Run
```bash
./scripts/run.sh            # staging
./scripts/run.sh prod -d <device>
```
VS Code: pick a configuration in Run and Debug (one per environment).

## 4. Everyday commands
```bash
flutter test                         # unit + widget tests
flutter test integration_test --flavor staging --dart-define-from-file=env/staging.json
dart fix --apply && dart format .    # fix lints + format
flutter gen-l10n                     # after editing lib/l10n/*.arb
./scripts/new_feature.sh <name>      # scaffold a feature + its doc
```
