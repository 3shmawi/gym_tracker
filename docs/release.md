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
   The iOS integration job is the slow one, so it runs only when the PR
   changes something the app is built from (`lib/`, `ios/`,
   `integration_test/`, `assets/`, `env/`, pubspec, `.fvmrc`, `ci.yml`,
   `.github/actions/`);
   otherwise it is skipped (a skipped job counts as passed). It caches Swift
   packages and `build/ios`, not DerivedData (several GB: saving and restoring cost about what it saves) (`actions/cache` v6.1.0, checked
   2026-11-01; saved after green runs only), so later builds are
   incremental.
   Every job sets up Flutter through one shared action,
   `.github/actions/setup-flutter`: the version from `.fvmrc`, the SDK and
   pub packages cached (`subosito/flutter-action` v2.23.0), and for Android
   Java 17. PR builds also cache Gradle (`actions/setup-java` v6.1.0
   `cache: gradle`, checked 2026-11-01). Release and staging builds don't
   (see `docs/security.md` → "CI and secrets"). Change caching or versions in
   that one file; it reaches other projects through `kit_sync.sh`.
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
Push to `develop` → `staging.yml`:
- **Android** — signed APK attached to a `staging-…` pre-release (last 3
  kept), and a signed AAB uploaded to the Play track `PLAY_STAGING_TRACK`
  (default `internal`) of the separate staging app `com.mohager.azm.stg`
  ("Azm Stg", installs next to the store app).
- **iOS** — TestFlight of `com.mohager.azm.stg`.

Uses `ENV_STAGING_JSON` and the same keystore and `PLAY_SERVICE_ACCOUNT_JSON`
as prod. One-time setup for the Play upload:
1. Play Console → **Create app** with package `com.mohager.azm.stg`.
2. Play Console → **Users and permissions** → give the Play service account
   release access to that app too.
3. Upload its first AAB by hand (Google only accepts API uploads after
   that): the first run fails and keeps it as the
   `play-staging-aab-for-manual-upload` artifact → Test and release →
   Internal testing → create release → upload it → roll out. Add your
   testers to the internal testing list.

Without `PLAY_SERVICE_ACCOUNT_JSON` the Play step is skipped (APK only).
`ENABLE_PLAY_STAGING=false` turns it off.

## Backend deploys
Changes under `supabase/` merged to `main` → `supabase.yml` runs
`supabase db push` (migrations) and deploys Edge Functions. Needs
`SUPABASE_ACCESS_TOKEN` + `SUPABASE_DB_PASSWORD` (the project ref is read
from `SUPABASE_URL`). PRs touching `supabase/` run the RLS tests first.

### Gym accounts (migrations 0005–0011, Edge Functions `redeem_invite` and `delete-account`)
Facts checked 2026-11-02 against the Supabase docs on GitHub
(`supabase/supabase` → `apps/docs/content/guides/functions/` and
`database/`) and the `@supabase/server` 1.9.2 package docs; supabase.com itself
was not reachable from the build environment, so re-read the pages marked ★
before the first production deploy.

Do once, **before** merging (the deploy runs on merge):
1. **Auth → Sign In / Providers → Anonymous sign-ins: on.** Local dev has it
   on in `config.toml`; the hosted project needs the switch. ★
2. **API keys and JWT signing keys.** `@supabase/server` (used by the
   function) accepts only the new `sb_publishable_…` / `sb_secret_…` keys and
   asymmetric JWT signing keys; legacy HS256 user tokens are rejected. In the
   dashboard: Settings → API Keys (new keys in use) and Settings → JWT Keys
   (signing keys migrated). If the project is still on the legacy secret, do
   the migration first or the function answers 401. ★
3. **Vault** is on by default; migration `0006` creates the pepper
   (`invite_pepper`) itself. Check after the deploy:
   `select count(*) from vault.secrets where name = 'invite_pepper';` → 1.
   Never create or print it by hand.
4. **Captcha (later):** Authentication → Attack Protection → Turnstile, when
   the app step ships `signInAnonymously()`.

What the deploy does: `supabase db push` applies the four migrations (all new
tables are empty, nothing the live app uses changes, so it is backward
compatible with the store version), then `supabase functions deploy` publishes
`redeem_invite` with `verify_jwt = true` (`supabase/config.toml`). The function
needs no secret from us: the platform provides the URL and keys.

After the deploy:
- Smoke test without any real code:
  `curl -s -o /dev/null -w '%{http_code}\n' -X POST "$SUPABASE_URL/functions/v1/redeem_invite"`
  → `401` (no session); with an anonymous user's token and a made-up code →
  `404 not_found`.
- Create a pilot gym row (the developer does this; no self-service in v1):
  Table editor → `gyms` → insert `name`. Then make cards with
  `scripts/make_invites/run.sh` (see `docs/features/gym_accounts_backend.md`).
- **Schedule the clean-up** (once `pg_cron` is confirmed on the plan ★):
  `select cron.schedule('purge-invite-attempts', '17 3 * * *', 'select public.purge_invite_attempts()');`
  Until then run `select public.purge_invite_attempts();` from the SQL editor
  now and then (30-day retention promised in the privacy policy).
- Rolling back: migrations are never edited once applied; a fix is a new
  migration. Revoke leaked invites instead of dropping rows.

#### Demo gym for App Review
Apple (2.1) and Google need a way into the gym features without a real captain.
The demo code is a **secret-like value that never goes in the repo, a chat or a
log**: it lives only in App Store Connect → App Review → Notes, and in Play
Console → App content → App access (checked 2026-11-02 against the decision
doc §8; re-read both consoles' pages before submitting).
1. Once: Table editor → `gyms` → insert a gym named `Azm Demo Gym` with
   `is_demo = true` (nothing else); copy its `id`.
2. For each submission, on your computer:
   `scripts/make_invites/run.sh --demo --gym <demo-gym-id>`. It rotates the
   code (the previous one stops working) and writes one PDF card with the code
   and a QR, outside the repo, mode 0600.
3. Paste the code and attach the QR image in the review notes: "Open Azm →
   Join your gym → type the code (or scan the QR). Solo mode needs no account."
   Then delete the PDF.
4. The demo member is a trainee with all three permissions; its sessions and
   plans are wiped every night (`wipe_demo_data()`), so keep nothing real there.
5. Schedule the nightly jobs once `pg_cron` is on (Database → Extensions →
   `pg_cron`, or `create extension pg_cron with schema pg_catalog;`, Supabase
   Cron guide read 2026-11-02): run `select public.schedule_maintenance();` in
   the SQL editor as the project owner. It returns `scheduled`, or says that
   `pg_cron` is not enabled and does nothing. This also schedules the purge of
   invite attempts older than 30 days.

#### Account deletion (store requirement)
`delete-account` is the server half of Profile → Delete account (app step).
It hard-deletes the auth user (`auth.admin.deleteUser(id, false)`,
`@supabase/auth-js` 2.118.0 docs, read 2026-11-02) and everything of that
person cascades. A sole owner of a gym with members gets `409 last_owner` and
must hand over or empty the gym first. After the deploy, smoke test with a
throwaway anonymous user: `POST` without a token → `401`.

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

## Kit sync
`.github/workflows/kit-sync.yml` runs every Monday (or Actions → Kit sync →
Run workflow) and compares this app with the latest flutter-project-kit
using `scripts/kit_sync.sh` (3-way merge, your changes are kept).

- **With `KIT_SYNC_TOKEN`**: it opens a `chore/kit-sync-…` PR with the
  kit's changes; if some files conflict it is a draft with `<<<<<<<`
  markers to resolve. A newer sync closes an older unmerged one. A kit
  version you closed on purpose is not re-opened.
- **Without it**: it opens (and keeps updating) a "Kit update available"
  issue, and you run `scripts/kit_sync.sh` by hand.

Why a token: GitHub's built-in token cannot change files in
`.github/workflows`, and PRs it opens do not start CI. Create a fine-grained
token for this repo only (Contents, Pull requests, Workflows: read & write),
put it in `KIT_SYNC_TOKEN` in `~/.app-secrets/shared.env` (or
`apps/<repo>/app.env`) and run `tool/setup_secrets.sh`, or
`gh secret set KIT_SYNC_TOKEN`. Also allow Actions to open PRs: repo
Settings → Actions → General → "Allow GitHub Actions to create and approve
pull requests".

Always review the PR: kit changes can add packages or change workflows.

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
| Deno (`denoland/deno` image) | CI Edge Function tests | 2.9.6 |
| `@supabase/server`, `@std/assert` | `supabase/functions/redeem_invite/deno.json` + `deno.lock` | 1.9.2, 1.0.19 |
| Python packages for `scripts/make_invites` | `scripts/make_invites/requirements.txt` (hashes) | qrcode 8.2, pillow 13.0.0, reportlab 5.0.1, zxing-cpp 3.1.1, charset-normalizer 3.5.2 |

## One-time setup
- Create the app in Play Console and App Store Connect (bundle id
  `com.mohager.azm`).
- Google Play only accepts API uploads after the **first AAB is uploaded
  manually**. Build it once: `flutter build appbundle --flavor prod --dart-define-from-file=env/prod.json`.
- **Export compliance (iOS):** `ios/Runner/Info.plist` sets
  `ITSAppUsesNonExemptEncryption` to `NO`, so App Store Connect no longer
  asks "App Encryption Documentation" for each build (staging and prod share
  the plist). The app only uses HTTPS/TLS, which Apple treats as exempt
  ("Complying with Encryption Export Regulations", checked 2026-11-01). If
  the app ever adds its own encryption (e.g. end-to-end encrypted data), set
  it to `YES` and follow Apple's documentation steps. Apple notes that exempt
  encryption may still need the yearly U.S. self-classification report.
  `test/security/platform_config_test.dart` keeps the key in place.
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
| `ENV_PROD_JSON` | contents of `env/prod.json` (re-upload after changing a key; the release run warns about empty keys — `scripts/check_env.sh`) |

| `KIT_SYNC_TOKEN` | optional, see "Kit sync" below |

A store whose secrets are missing is skipped (with a warning), not failed.
iOS signing imports your .p12 and lets App Store Connect create/refresh the
provisioning profile with the API key — no new certificate is created.

Repository variables: `PLAY_TRACK` (default `internal`), `PLAY_RELEASE_STATUS`
(`draft` until the first review, then `completed`), optional
`ENABLE_ANDROID=false` / `ENABLE_IOS=false`, `BUILD_NUMBER_OFFSET`.
Staging (Play): `PLAY_STAGING_TRACK` (default `internal`),
`PLAY_STAGING_RELEASE_STATUS` (default `completed`), `ENABLE_PLAY_STAGING=false`
to skip it.

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

## Website (Cloudflare Pages)
`website/` is deployed by Cloudflare Pages' own Git integration (project
`azmm`, production branch `main`, build output directory `website/`, no
build command): https://azmm.pages.dev. There is no GitHub workflow and no
API token in this repo. Every PR gets a preview URL from Cloudflare.
`website/_headers` sets the JSON content type for the `.well-known` files.
Pages redirects `/privacy.html` to `/privacy` (308), so store listings use
the clean URLs (`/privacy`, `/terms`, `/delete-account`).

## Universal Links / App Links (manual store steps)
Host `azmm.pages.dev`, path `/join/*` (see `docs/deep_links.md`). Do once,
after the first Play upload and before relying on the links:
1. **Play app-signing SHA-256** — done for `com.mohager.azm` and
   `com.mohager.azm.stg` (public fingerprints in
   `website/.well-known/assetlinks.json`). Redo it if the app-signing key
   changes: Play Console → the app → Test and release → App integrity →
   App signing → "App signing key certificate" → SHA-256. Add the *upload*
   key fingerprint too if you want links to open sideloaded APK builds.
   After a merge, check `adb shell pm get-app-links com.mohager.azm` shows
   `verified`.
2. **Associated Domains capability** — Apple Developer → Certificates,
   Identifiers & Profiles → Identifiers → `com.mohager.azm` and
   `com.mohager.azm.stg` → tick **Associated Domains** → Save. Without it the
   entitlement in `Runner.entitlements` makes signing fail with "profile
   doesn't include the Associated Domains entitlement"; the CI profile is
   regenerated by the next build.
3. Apple caches the AASA file on its CDN; after a change allow some time, or
   test with `applinks:azmm.pages.dev?mode=developer` on a device in
   Developer Mode.
4. The site must keep serving both files with status 200 and no redirect
   (`curl -sI https://azmm.pages.dev/.well-known/apple-app-site-association`).

## Android signing locally (optional)
Create `android/key.properties` (git-ignored):
```
storeFile=/absolute/path/upload-keystore.jks
storePassword=…
keyAlias=<the ANDROID_KEY_ALIAS in ~/.app-secrets/apps/gym_tracker/app.env>
keyPassword=…
```
Without it, release builds fall back to debug signing.
