# Getting started

## 1. Environment files
Each environment (staging, prod) has `env/<name>.json` (git-ignored; the
template is `env/example.json`). Fill in:

| Key | Where to find it |
|---|---|
| `TURNSTILE_SITE_KEY` | Cloudflare → Turnstile → the widget's **site key** (publishable; the secret goes only in Supabase → Authentication → Attack Protection). Empty = no captcha token is sent |
| `CLOUDINARY_CLOUD_NAME` | Cloudinary → the product environment's **cloud name** (`azm`; public, it is in every picture URL). Empty = gym-chosen exercise pictures are off (bundled pictures only) |
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

## 2. Backend (Supabase)
Everything about the backend — what `tool/setup_secrets.sh` creates, the
credentials CI needs, how `supabase/` deploys on merge, the access
rules and their tests — is in [backend.md](backend.md). First time: run
`tool/setup_secrets.sh`, then the backend's deploy workflow once.

**Backend tests** (when you change `supabase/` or `scripts/make_invites/`):
`supabase start && supabase test db` (pgTAP, needs Docker);
`cd supabase/functions/redeem_invite && deno test --frozen --no-prompt`;
`python -m unittest discover -s scripts/make_invites` inside the venv that
`scripts/make_invites/run.sh` builds. Making QR cards:
`docs/features/gym_accounts_backend.md`.

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

## 5. Let an agent run the app (Dart MCP server)
The official [Dart & Flutter plugin](https://github.com/flutter/agent-plugins)
(Dart MCP server, skills) is pinned in `.claude/settings.json` (checked
2026-11-16: plugin 1.0.7, docs.flutter.dev/ai/mcp-server). It needs Dart 3.9+
on your `PATH` (the project's Flutter has it).

- **Claude Code on your Mac**: trust the folder and accept the plugin prompt,
  or `claude plugin marketplace add flutter/agent-plugins && claude plugin install dart-flutter@dart-flutter`.
- **Devices**: Xcode with an iOS Simulator for iOS; Android Studio with an
  emulator (Device Manager → create one) for Android.
- **Run**: ask the agent to test on a device, or run it yourself:
  ```bash
  ./scripts/agent_run.sh ios          # or: android, a device id; env optional
  ./scripts/agent_run.sh status
  ./scripts/agent_run.sh shot ios     # build/agent/ios.png
  ./scripts/agent_run.sh stop
  ```
  The agent connects the MCP server to the printed DTD URI and taps, types,
  takes screenshots, reads runtime errors and hot reloads (CLAUDE.md →
  "Running the app as an agent"). Both platforms can run at once.
- **Cloud sessions** have no simulator or emulator: agents there use
  `flutter test` and widget screenshots instead.

## 6. Design reviews (Elephant-Goldfish Model)
Big features get a written spec reviewed by fresh AI reviewers before any
code (rules in `CLAUDE.md`). The
[EGM plugin](https://github.com/google/elephant-goldfish-model) is pinned in
`.claude/settings.json`:

- **Claude Code on your Mac**: trust the folder when Claude Code asks, then
  accept the prompt to install `egm@egm`. Or install it yourself:
  `claude plugin marketplace add google/elephant-goldfish-model#v0.1.1 && claude plugin install egm@egm`.
- **Claude Code cloud sessions** don't install plugins from a repo's
  settings. The setup script in the kit's README installs it for every
  session (environment menu → **Edit** → **Setup script**).
- **Codex / Antigravity**: see the plugin's README for the one-time install.

```text
/egm:egm-brainstorm Add offline favorites   → concepts_brief.md
/egm:egm-draft                              → design_draft.md, section by section
/egm:egm-review design_draft.md             → fresh reviewers, five stages
/egm:egm-resolve                            → agree on fixes, then approve
```

Save the approved spec as `docs/designs/<feature>.md`. A full review starts
several sub-agents, so it uses more tokens than a normal session; skip it
for small changes. To upgrade EGM, change `ref` in `.claude/settings.json`
and the version in `docs/release.md` → "Pinned tools".
