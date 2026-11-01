# Release & CI/CD (GitHub Actions)

**You never build by hand.** Open a PR → checks run. Merge to `main` → a new
version is built and uploaded to Google Play and App Store Connect.

## How the version is chosen
`scripts/next_version.sh` reads the Conventional Commit messages merged since
the last `v*` tag (squash-merge PRs so the PR title is the commit):

| Commits | Result |
|---|---|
| `feat: …` | minor — 1.4.2 → 1.5.0 |
| `fix:` / `perf:` / `refactor:` / anything else | patch — 1.4.2 → 1.4.3 |
| `feat!: …` or `BREAKING CHANGE:` in the body | major — 1.4.2 → 2.0.0 |
| only `docs:` `chore:` `ci:` `test:` `style:` | no release |

The build number is the CI run number (plus the optional `BUILD_NUMBER_OFFSET`
repository variable). The first release uses the version in `pubspec.yaml`.
A manual run (Actions → Release → Run workflow) can force patch/minor/major.

## Pipeline
1. **Checks** — format, analyze, unit/widget tests. PRs also run every
   integration test on an iPhone simulator (macOS runner, full Liquid Glass)
   and build a debug Android APK. Android flows aren't run in CI: the
   GitHub-hosted emulator has no GPU and went offline at the end of every
   app run, losing the results. Run them on a phone or local emulator when
   a change is Android-specific.
2. **Android** — signed release AAB (prod) → Play track `PLAY_TRACK`
   (default `internal`).
3. **iOS** — signing files fetched from App Store Connect with the API key →
   IPA → App Store Connect / TestFlight.
4. **GitHub release** — tag `vX.Y.Z` with generated notes.

## After the stores approve
Actions → **Announce update** → type `optional` or `force`. It writes the
version + changelog (from the release's commits, or your text in English and
Arabic) to `app_versions` in Supabase; the in-app dialog does the rest.
Needs the `SUPABASE_SECRET_KEY` secret.

## Staging builds
Push to `develop` → `staging.yml`: Android APK attached to a `staging-…`
pre-release (last 3 kept) and iOS to TestFlight of `com.mohager.azm.stg`
(create that app record in App Store Connect once). Uses `ENV_STAGING_JSON`.

## Backend deploys
Changes under `supabase/` merged to `main` → `supabase.yml` runs
`supabase db push` (migrations) and deploys Edge Functions. Needs
`SUPABASE_ACCESS_TOKEN` + `SUPABASE_DB_PASSWORD` (the project ref is read
from `SUPABASE_URL`). PRs touching `supabase/` run the RLS tests first.

## Store listing
Texts in `store/`, uploaded by Actions → **Store listing** (fastlane
supply/deliver) — see `store/README.md`.

## Store requirements (check each year)
| Store | Requirement | Where it's handled |
|---|---|---|
| App Store | Built with **Xcode 26+** / iOS 26 SDK (since 28 Apr 2026) | iOS jobs pick the newest Xcode on the runner, or fail with a clear message |
| Google Play | New apps and updates target **Android 16 (API 36)** (since 31 Aug 2026) | `targetSdk = flutter.targetSdkVersion` (36 in Flutter 3.47) |

Both stores raise these every year (Apple in spring, Google in August).
When a deadline is announced, update this table and the workflows in the
kit, then `scripts/kit_sync.sh` in each app.

## Crash symbols (Sentry)
Release builds are obfuscated; `scripts/upload_symbols.sh` sends the symbols
to Sentry after the store upload so stack traces stay readable. It never
fails the release: if Sentry rejects the upload, the run shows a **Sentry
symbols** warning with Sentry's error, and the tag and GitHub release still
happen. Commit linking is off (`commits: false` under `sentry:` in
`pubspec.yaml`); turn it on only after connecting the Sentry GitHub
integration.

## Pinned tools
Actions are pinned to commits and kept current by Dependabot. These tools
are pinned by hand — bump them here and in the kit together:

| Tool | Where | Version |
|---|---|---|
| Codemagic CLI (`codemagic-cli-tools`) | iOS release/staging jobs | 0.70.2 |
| fastlane | Store listing | 2.241.2 |
| zizmor | CI `security` job | 1.31.1 |
| gitleaks | CI `security` job | v8.30.1 |
| OSV-Scanner | CI `security` job | v2.7.0 |
| Supabase CLI | Supabase workflows | 2.120.0 |

## One-time setup
- Create the app in Play Console and App Store Connect (bundle id
  `com.mohager.azm`).
- Google Play only accepts API uploads after the **first AAB is uploaded
  manually**. Build it once: `flutter build appbundle --flavor prod --dart-define-from-file=env/prod.json`.
- Keep `PLAY_RELEASE_STATUS=draft` until the app has passed its first review,
  then set it to `completed`.
- Secrets: see the section for your CI below.

### GitHub Actions secrets
On your Mac, inside the clone: `tool/setup_secrets.sh` (`--dry-run` first to
preview). Shared values come from `~/.app-secrets/shared.env`; this app's
Android upload keystore is generated once into
`~/.app-secrets/apps/gym_tracker/` with a random password and the
alias `<repo>-upload` (not a common word: GitHub stars out a secret's text
in every log) — **back that folder up**, Play needs the same key for every
update. Each upload to GitHub is tried up to 4 times, so a network blip
doesn't stop the run halfway; re-running the script is always safe.

| Secret | Content |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | this app's upload keystore, base64 |
| `ANDROID_KEY_ALIAS`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD` | keystore credentials |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play service-account JSON |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | App Store Connect API key |
| `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD` | your Apple Distribution certificate (.p12) |
| `APPLE_TEAM_ID` | Team ID |
| `ENV_PROD_JSON` | contents of `env/prod.json` |

A store whose secrets are missing is skipped (with a warning), not failed.
iOS signing imports your .p12 and lets App Store Connect create/refresh the
provisioning profile with the API key — no new certificate is created.

Repository variables: `PLAY_TRACK` (default `internal`), `PLAY_RELEASE_STATUS`
(`draft` until the first review, then `completed`), optional
`ENABLE_ANDROID=false` / `ENABLE_IOS=false`, `BUILD_NUMBER_OFFSET`.

### Codemagic
Fully automated through the Codemagic API — nothing to click in the UI:
1. Once: connect GitHub to your **personal** Codemagic account and put
   `CODEMAGIC_API_TOKEN` (Settings → Integrations → Codemagic API) in
   `~/.app-secrets/shared.env`. Leave `CODEMAGIC_TEAM_ID` empty: the free
   plan (500 macOS M2 minutes/month) only covers personal accounts.
   Budget: a release (Android + iOS) is roughly 20–35 minutes, a PR check
   5–10, so about 10–15 releases a month fit in the free minutes.
2. Per app: `tool/setup_secrets.sh` adds the repo to Codemagic (if needed) and
   writes the same secrets as above as **secure variables** in the group
   `gym_tracker_secrets`. Re-running replaces the values.
3. `codemagic.yaml` signs Android from `ANDROID_KEYSTORE_BASE64` and iOS from
   your `.p12` + App Store Connect key (same commands as GitHub Actions),
   uploads to Play (`submit_as_draft: true` until the first review) and to
   App Store Connect, and tags the release with `RELEASE_TOKEN`.

## Android signing locally (optional)
Create `android/key.properties` (git-ignored):
```
storeFile=/absolute/path/upload-keystore.jks
storePassword=…
keyAlias=<the ANDROID_KEY_ALIAS in ~/.app-secrets/apps/gym_tracker/app.env>
keyPassword=…
```
Without it, release builds fall back to debug signing.
