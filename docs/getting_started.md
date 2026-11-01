# Getting started

## 1. Environment files
Each environment (staging, prod) has `env/<name>.json` (git-ignored; the
template is `env/example.json`). Fill in:

| Key | Where to find it |
|---|---|
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Filled by `tool/setup_secrets.sh` when `SUPABASE_ADMIN_TOKEN` + `SUPABASE_ORG` are set (it creates the project); by hand: Supabase → Project settings → API Keys (`sb_publishable_…`) |
| `POSTHOG_API_KEY`, `POSTHOG_HOST` | Filled by `tool/setup_secrets.sh` when `POSTHOG_PERSONAL_API_KEY` + `POSTHOG_REGION` are set; by hand: PostHog → Project settings → Project API key (`phc_…`, not a personal `phx_…` key). Host = your region's **ingestion** address: `https://eu.i.posthog.com` or `https://us.i.posthog.com` (not `eu.posthog.com`) |
| `SENTRY_DSN` | Filled by `tool/setup_secrets.sh` (it creates the Sentry project if missing); by hand: Sentry → Project → Client keys |
| `CLARITY_PROJECT_ID` | Clarity → Settings (if Clarity is used) |

Every service is skipped while its key is empty, so the app runs before any
of this is set up. A debug run prints `Analytics off: <why>` when PostHog is
skipped, and every CI build warns about empty keys (`scripts/check_env.sh`).

**No events in PostHog?** Run `tool/setup_secrets.sh --dry-run`: it checks
each `env/*.json` key against its host and says when PostHog doesn't know
the key (wrong key, or EU/US region mix-up — events are then dropped with
no error in the app). Then check the build's run summary for
`ENV_…_JSON secret not set` / `empty: POSTHOG_API_KEY` warnings, and fix by
re-running `tool/setup_secrets.sh`, then building again: the key is baked
into the app at build time. Events show up in PostHog → Activity within a
minute (the SDK sends every 30 s or every 20 events).

**One PostHog project for all your apps.** Every event carries `app` (the
project name, `Analytics.appName`) and `environment` (the flavor:
`staging` / `prod`), and both are set on the person too. In PostHog:
- Insights / dashboards: add the filter `app = <name>` and
  `environment = prod` (save it on the dashboard: Filter → Save).
- Feature flags: flag keys are shared by every app in the project, so
  prefix them with the app (`<name>_new_onboarding`) and add the release
  condition `app = <name>` (+ `environment = prod` when it is ready).
- Internal users: Settings → Project → *Filter out internal and test
  users* → add `environment = staging` to hide all test builds at once.

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
