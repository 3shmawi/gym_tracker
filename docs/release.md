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
   Scroll performance is **not** measured on every PR (it is a second
   macOS run): add the **`perf`** label or run
   Actions → **Performance** (`.github/workflows/perf.yml`,
   `docs/performance.md`).
   Every job sets up Flutter through one shared action,
   `.github/actions/setup-flutter`: the version from `.fvmrc`, the SDK and
   pub packages cached (`subosito/flutter-action` v2.23.0), and for Android
   Java 17. PR builds also cache Gradle (`actions/setup-java` v6.1.0
   `cache: gradle`, checked 2026-11-01). Release and staging builds don't
   (see `docs/security.md` → "CI and secrets"). Change caching or versions in
   that one file; it reaches other projects through `kit_sync.sh`.
2. **Android** — signed release AAB (prod) → Play track `PLAY_TRACK`
   (default `internal`).
3. **iOS** — signing files fetched from App Store Connect with the API key
   (`scripts/fetch_signing_files.sh`: 3 attempts of at most 3 minutes each,
   exact bundle id) → IPA → App Store Connect / TestFlight.
4. **GitHub release** — tag `vX.Y.Z` with generated notes.

## After the stores approve
**Optional updates announce themselves.** Every day **Announce update**
checks the stores (`scripts/store_live.sh`): once a version is fully live
on Google Play (production track, status *completed* — a staged rollout
doesn't count) **and** on the App Store (Apple's public lookup), it writes
it to `app_versions` as an optional update, with the store "What's new"
texts of that release (`store/android/<locale>/changelogs/default.txt`;
English falls back to the commits, Arabic to the English text). Only a
version newer than what the app already announces is written, so a notice
you made by hand is never overwritten. It needs `PLAY_SERVICE_ACCOUNT_JSON`
(Codemagic apps: add it to the GitHub secrets too) plus the backend
credentials; without them the run only warns. Repository variables:
`AUTO_ANNOUNCE=false` turns it off, `APP_STORE_COUNTRY` (default `us`) is
the storefront to look the app up in, `ENABLE_ANDROID` / `ENABLE_IOS=false`
leave a store out. Apple's lookup can lag a few hours, so the notice may
come a day after the release.

**By hand / forced:** Actions → **Announce update** → type `optional` or
`force`. A forced update is never automatic. It writes the version +
"What's new" (your text, else the store texts of that release, else its
commits) to `app_versions`; the app shows an optional update as a sheet
("Update" / "Later") and a forced one as a full screen with "Update" only.
Credentials: [backend.md](backend.md) → "CI credentials".

## Social posts
`.github/workflows/social.yml` announces updates on LinkedIn, the Facebook
Page, Instagram, YouTube and TikTok — and, once you add them to
`SOCIAL_PLATFORMS`, Threads, Bluesky, Telegram and X — through
[3shmawi/social-publisher](https://github.com/3shmawi/social-publisher)
(pinned to v1.6.0; its `docs/` have the step-by-step setup per platform). A version is
written per platform in English and Arabic, you approve, then each platform
posts on its own; one failing doesn't stop the others.

- **Who writes:** Claude, on your Claude Pro/Max plan, when the
  `CLAUDE_CODE_OAUTH_TOKEN` secret is set (run `claude setup-token` once a
  year; no API credit needed). Without it, fixed templates write the posts
  from `store/android/<lang>/changelogs/default.txt` (keep it filled in for
  each release, in both languages) and the `SOCIAL_HASHTAGS` variable
  (default `Flutter,MobileApps`).

- **When:** after every store release (GitHub Actions: `release.yml` starts
  it, since a release created by the workflow's token starts no other
  workflow; Codemagic: the `v*` tag it pushes), when you publish a GitHub
  Release by hand, every two weeks with the changes since the last post, or
  Actions → **Social posts** → Run workflow.
- **Turn it on:** create the environment **`social`** (Settings →
  Environments) with yourself as required reviewer, add the secrets (table
  below), set the repo variable `SOCIAL_ENABLED=true`, then run it by hand
  with `dry_run` ticked and read the posts in the job summary.
- **Go live:** set `SOCIAL_LIVE=true`. Release and schedule runs then stop at
  **Approve posts**; approve once the version is live in the stores
  (approval waits up to 30 days). Until then they're dry runs.
- **Never twice:** posted updates are tagged `social/posted/<tag>/<platform>`;
  `force` posts again. Internal-only updates (chore, ci, refactor…) and notes
  containing `[skip social]` are skipped.
- **Video:** a `*.mp4` release asset or `marketing/videos/v<version>.mp4`
  (e.g. the Demo video output) goes to YouTube, Facebook, LinkedIn, Instagram
  (a Reel) and TikTok; none → Instagram, YouTube and TikTok are skipped. YouTube keeps API uploads private until the Google Cloud project
  passes YouTube's audit; then set `SOCIAL_YOUTUBE_AUDITED=true` and
  `SOCIAL_YOUTUBE_PRIVACY=public`.
- **Optional variables:** `APP_STORE_URL` (once the app is on the App
  Store), `PLAY_STORE_URL`, `SOCIAL_WEBSITE_URL`, `SOCIAL_LANGUAGES`
  (default `en,ar`), `SOCIAL_LINKEDIN_AS` (`person`, `organization`,
  default `both`), `SOCIAL_PLATFORMS` (default `facebook,instagram,linkedin,youtube,tiktok`),
  `SOCIAL_TIKTOK_TOKEN_REPOS` (below), `SOCIAL_X_LINKS` (`false` leaves
  the link out of X posts — X bills a post with a link much more),
  `SOCIAL_POST_AT` + `SOCIAL_POST_TIMEZONE` (post at e.g. `18:00`
  `Africa/Cairo` after approval; `SOCIAL_POST_AT_OVERRIDES` like
  `linkedin=09:00`), `APP_STORE_PROVIDER_TOKEN` (App Analytics campaign
  tags on App Store links; other links get `utm_source=<platform>`
  automatically), `SOCIAL_THREADS_TOKEN_REPOS`, `SOCIAL_X_INSIGHTS`.
- **More platforms (opt-in):** Threads, Bluesky, Telegram (your channel,
  through a bot) and X (pay-per-use API). Put their secrets in
  `shared.env` (`tool/setup_secrets.sh` uploads them) and add the names to
  `SOCIAL_PLATFORMS`, e.g. `facebook,instagram,linkedin,youtube,tiktok,threads,bluesky`.
- **No video?** Release images (`*.png`/`*.jpg` assets, up to 10, or
  `marketing/images/v<version>/`) become an Instagram image or carousel and
  a LinkedIn image post; each image's alt text is its asset label (or a
  `.txt` next to it). A video that a platform wouldn't take (HEVC, 120 fps,
  odd size) is re-encoded automatically. YouTube also takes a `*thumb*`
  image as the thumbnail and `*.en.srt` / `*.ar.srt` as captions.
- **Weekly credential check:** `social-health.yml` checks every platform's
  token on Mondays and keeps an issue (label `social-credentials`) open while
  one would fail — fix it before the next release. It also refreshes the
  Threads token.
- **Insights:** `social-insights.yml` reports each post's views, likes,
  comments and shares 7 days after it went out (Actions → Social insights →
  the run summary). Instagram needs `instagram_manage_insights` on the Page
  token; YouTube captions need a token made with the current
  `get-youtube-token.ts`.
- **TikTok:** the video lands in your TikTok **inbox as a draft**; open
  TikTok, add a sound and the suggested caption (in the run summary), post.
  TikTok replaces the refresh token on every run, and the workflow saves the
  new one back to `TIKTOK_REFRESH_TOKEN` with `SOCIAL_SECRETS_TOKEN` (without
  it the TikTok job is skipped). So put `TIKTOK_REFRESH_TOKEN` in
  `shared.env` only for the first `tool/setup_secrets.sh`, then delete its
  value there (an empty value doesn't overwrite the secret). Several apps on
  one TikTok account: set `SOCIAL_TIKTOK_TOKEN_REPOS` to all of them
  (`owner/app1,owner/app2`) in each, and give `SOCIAL_SECRETS_TOKEN` access to
  all of them. Setup: social-publisher README → "3b. TikTok".

## Social posts
`.github/workflows/social.yml` announces updates on LinkedIn, the Facebook
Page, Instagram, YouTube and TikTok through
[3shmawi/social-publisher](https://github.com/3shmawi/social-publisher)
(its README has the step-by-step setup for each platform). A version is
written per platform in English and Arabic, you approve, then each platform
posts on its own; one failing doesn't stop the others.

- **Who writes:** Claude, on your Claude Pro/Max plan, when the
  `CLAUDE_CODE_OAUTH_TOKEN` secret is set (run `claude setup-token` once a
  year; no API credit needed). Without it, fixed templates write the posts
  from `store/android/<lang>/changelogs/default.txt` (keep it filled in for
  each release, in both languages) and the `SOCIAL_HASHTAGS` variable
  (default `Flutter,MobileApps`).

- **When:** after every store release (GitHub Actions: `release.yml` starts
  it, since a release created by the workflow's token starts no other
  workflow; Codemagic: the `v*` tag it pushes), when you publish a GitHub
  Release by hand, every two weeks with the changes since the last post, or
  Actions → **Social posts** → Run workflow.
- **Turn it on:** create the environment **`social`** (Settings →
  Environments) with yourself as required reviewer, add the secrets (table
  below), set the repo variable `SOCIAL_ENABLED=true`, then run it by hand
  with `dry_run` ticked and read the posts in the job summary.
- **Go live:** set `SOCIAL_LIVE=true`. Release and schedule runs then stop at
  **Approve posts**; approve once the version is live in the stores
  (approval waits up to 30 days). Until then they're dry runs.
- **Never twice:** posted updates are tagged `social/posted/<tag>/<platform>`;
  `force` posts again. Internal-only updates (chore, ci, refactor…) and notes
  containing `[skip social]` are skipped.
- **Video:** a `*.mp4` release asset or `marketing/videos/v<version>.mp4`
  (e.g. the Demo video output) goes to YouTube, Facebook, LinkedIn, Instagram
  (a Reel) and TikTok; none → Instagram, YouTube and TikTok are skipped. YouTube keeps API uploads private until the Google Cloud project
  passes YouTube's audit; then set `SOCIAL_YOUTUBE_AUDITED=true` and
  `SOCIAL_YOUTUBE_PRIVACY=public`.
- **Optional variables:** `APP_STORE_URL` (once the app is on the App
  Store), `PLAY_STORE_URL`, `SOCIAL_WEBSITE_URL`, `SOCIAL_LANGUAGES`
  (default `en,ar`), `SOCIAL_LINKEDIN_AS` (`person`, `organization`,
  default `both`), `SOCIAL_PLATFORMS` (default `facebook,instagram,linkedin,youtube,tiktok`),
  `SOCIAL_TIKTOK_TOKEN_REPOS` (below).
- **TikTok:** the video lands in your TikTok **inbox as a draft**; open
  TikTok, add a sound and the suggested caption (in the run summary), post.
  TikTok replaces the refresh token on every run, and the workflow saves the
  new one back to `TIKTOK_REFRESH_TOKEN` with `SOCIAL_SECRETS_TOKEN` (without
  it the TikTok job is skipped). So put `TIKTOK_REFRESH_TOKEN` in
  `shared.env` only for the first `tool/setup_secrets.sh`, then delete its
  value there (an empty value doesn't overwrite the secret). Several apps on
  one TikTok account: set `SOCIAL_TIKTOK_TOKEN_REPOS` to all of them
  (`owner/app1,owner/app2`) in each, and give `SOCIAL_SECRETS_TOKEN` access to
  all of them. Setup: social-publisher README → "3b. TikTok".

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
Changes under `supabase/` merged to `main` are deployed by the backend's
workflow; PRs touching it run the access-rules tests first. What is
deployed and the secrets it needs: [backend.md](backend.md) → "Deploys".

**A new optional plan key ships server first.** `private.plan_problem`
refuses keys it doesn't know, and only `main` deploys the migration (to the
project in `ENV_PROD_JSON`), so the migration and the dashboard's reading of
the key merge to `main` in their own PR **before** any app build that writes
the key, staging included. If the staging app (`ENV_STAGING_JSON`) uses a
separate Supabase project, apply the migration there by hand too. First
used for rep ranges (0024, `top`; `docs/designs/rep_ranges.md`).

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

#### Gym accounts in the app (`gym_join` flag)
Everything in the app is behind the PostHog flag `gym_join` (off by default):
shipping the build changes nothing for users until it is turned on. Turn it on
for staging first (PostHog → Feature flags → `gym_join`, filter
`app = gym_tracker`, `environment = staging`).
Before the flag goes on in production:
1. **Turnstile (built; needs your keys).** The app asks Turnstile for a token
   before every anonymous sign-in (`lib/core/captcha/turnstile_captcha.dart`,
   package `webview_flutter` 4.14.1: a 1-pixel web view that loads Cloudflare's script and may open only `challenges.cloudflare.com` and its own page, `https://azmm.pages.dev/`; iOS reports loading that page as a navigation, and blocking it left the join waiting for the 20 s timeout).
   - Cloudflare → Turnstile → the widget's **Domains** must include
     `azmm.pages.dev` (the app uses it as the widget's origin).
   - Put the **site key** (publishable) in every env file the build uses
     (`TURNSTILE_SITE_KEY` in `env/staging.json`, `env/prod.json`, and the
     `ENV_*_JSON` secrets). Put the **secret** only in Supabase → Authentication →
     Attack Protection (Captcha provider: Turnstile). Never in an env file.
   - **Order matters:** with captcha protection on in Supabase, a build without
     `TURNSTILE_SITE_KEY` cannot sign in anonymously (joining fails). With the
     key set and protection off, tokens are simply ignored.
   - Invisible mode requires the privacy policy to reference Cloudflare's
     Turnstile Privacy Addendum: done in `website/privacy.html` (EN + AR),
     pinned by `store_pages_test.dart`. Keep it if you change the page.
   - The widget should be an *invisible* (or non-interactive) type: it runs
     without UI, so a Managed widget that decides to show a challenge cannot be
     completed and the join fails after 20 seconds. Check on the first staging
     build; if it happens, change the widget's mode in Cloudflare.
   - Without captcha, anonymous sign-in is open to scripts (Supabase limits it
     to 30 per hour per IP by default).
2. **Camera strings.** `ios/Runner/{en,ar}.lproj/InfoPlist.strings` and
   `Info.plist` (`NSCameraUsageDescription`) hold the text App Review sees
   (decision doc §8). Edit all three together; `platform_config_test.dart`
   pins them.
3. **Store forms** (full answers: `store/privacy_forms.md`, 2026-11-04). Apple App Privacy: Name, User ID, Health & Fitness, Diagnostics,
   none used for tracking; Google Data safety: Personal info (name), Health and
   fitness, App activity, Device or other IDs (the install id), encrypted in
   transit, deletion URL `https://azmm.pages.dev/delete-account.html`
   (updated in PR C). The camera is used on the device only.
   Gym-chosen exercise pictures (2026-11-03): the app downloads them from
   Cloudinary, which sees the device's IP address while serving the file, as
   any CDN does. Nothing is sent by us and nothing personal is stored. Apple:
   not "collected" (served in real time, not kept by us); Google: "ephemeral
   processing" (in the form, not shown on the listing). Owner's call whether
   to declare it anyway; the privacy policy names Cloudinary.
   How-to videos (2026-11-03): the card loads the title (oEmbed) and the
   thumbnail from YouTube when an exercise opens, so Google sees the device's
   IP address; playing happens in YouTube's own player. We collect nothing
   from it and send nothing personal. Same reading as above for both forms
   (served in real time, not kept by us). The privacy policy and the terms
   name YouTube with the links YouTube's Developer Policies require.
4. **App size.** `mobile_scanner` bundles the ML Kit barcode model on Android
   (about +3–10 MB); the unbundled variant is a one-line
   `android/gradle.properties` change (`dev.steenbakker.mobile_scanner.useUnbundled=true`)
   at the cost of a Play-services download on first scan.
5. **First CI build.** `flutter_secure_storage` 11 raises Android `minSdk` to 24
   (ours is 26) and asks for `compileSdk` 37; open the Runner target once in
   Xcode and check `InfoPlist.strings` is listed under Resources.
6. A real phone: scan a card from `scripts/make_invites` (staging), join, see
   Today, switch, sign out, delete the throwaway account.

#### Website texts that must match the app (PR C)
`website/privacy.html`, `terms.html` and `delete-account.html` (English and
Arabic, "Last updated" 2026-11-02) describe gym accounts: no-email sign-in, the
camera, hashed codes, hashed attempt logs kept 30 days, leaving a gym, deletion,
minors, Cloudflare and **Turnstile**. The policy says Turnstile protects joining,
so **turn Turnstile on before the `gym_join` flag** (step 1 above).
`test/security/store_pages_test.dart` pins the promises. Cloudflare Pages deploys
`website/` when this merges, so the texts are live before the flag: they describe
a feature users cannot see yet, which is the safe order (never the reverse).

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
   The demo code is a *reusable* code (kind `demo`): it needs the same attempt
   throttling as every code and must never be pasted into a PR, an issue, a chat,
   a log or the repo; if it leaks, run the script again (it rotates).
4. The demo member is a trainee with all three permissions; its sessions and
   plans are wiped every night (`wipe_demo_data()`), so keep nothing real there.
5. Schedule the nightly jobs once `pg_cron` is on (Database → Extensions →
   `pg_cron`, or `create extension pg_cron with schema pg_catalog;`, Supabase
   Cron guide read 2026-11-02): run `select public.schedule_maintenance();` in
   the SQL editor as the project owner. It returns `scheduled`, or says that
   `pg_cron` is not enabled and does nothing. This also schedules the purge of
   invite attempts older than 30 days.

#### App Review notes and screen recording (Guideline 2.1)
The first submission (Nov 2026) came back with **Guideline 2.1 – Information
Needed**: Apple wants six answers in App Review → Notes.
`store/ios/review_information/notes.txt` holds five of them (purpose and
audience, how to use, external services, regions, regulated content) and
describes the recording. Keep it accurate when a feature, service or menu
label changes. Before each submission:
1. Record the screen on a **physical iPhone on the latest iOS**, starting
   from launching the app: solo plan → workout → log → finish, library and a
   video, a Move game, join the demo gym with its code, *My account* →
   *Delete account*. Account deletion must be in it: joining creates an
   account.
2. Run **Store listing** (it uploads the notes only when the `APP_REVIEW_*`
   secrets are set; without them it logs a warning and leaves the Notes as
   they are, so paste `notes.txt` by hand). Then in App Store Connect →
   App Review Information:
   - **Recording:** the notes start with its YouTube link (the 2026-11-19
     recording: iPhone 13, iOS 27). Keep that video online (unlisted or
     public) until the app is approved. For a new recording, update the
     link, phone and iOS version in `notes.txt` (the iOS version must be the
     latest release), and also attach the file here. Never put the video
     in the repo.
   - **Notes:** add `DEMO GYM CODE: <code>` (step 3 above) at the end.
   A later Store listing run overwrites the Notes, so add the code again
   after it.
3. No tester screen may show in the store build (Guideline 2.2). The pose
   check (Settings → *Pose check (testing)*) is already hidden in prod builds
   by code (`moveCheckAllowed` checks the flavor), whatever
   `move_games_debug` says. The flag's prod condition is at 0 % anyway
   (2026-11-18), so neither safeguard depends on the other.

#### Account deletion (store requirement)
`delete-account` is the server half of Profile → Delete account (app step).
It hard-deletes the auth user (`auth.admin.deleteUser(id, false)`,
`@supabase/auth-js` 2.118.0 docs, read 2026-11-02) and everything of that
person cascades. A sole owner of a gym with members gets `409 last_owner` and
must hand over or empty the gym first. After the deploy, smoke test with a
throwaway anonymous user: `POST` without a token → `401`.

## Store listing
Texts and images in `store/`, uploaded by Actions → **Store listing**
(fastlane supply/deliver) — see `store/README.md`.
- **iOS:** the job writes a `Deliverfile` before `fastlane deliver`.
  Without one (and without a `./metadata` folder) deliver asks "Do you want
  to setup deliver?" and crashes in CI. It also passes
  `--ignore_language_directory_validation`, because `store/ios/` holds the
  `screenshots/` folder next to the locale folders.
  `store/ios/review_information/notes.txt` (App Review notes) must be
  filled: deliver reads the version's App Review Information while
  uploading and crashes with "No data" when the version has none; with the
  notes it creates it. Once a version has App Review Information, Apple
  refuses an update without the contact (name, email, phone), so the
  `Deliverfile` sends it from the `APP_REVIEW_*` secrets (read from the
  environment, never written to disk). Without those secrets the notes are
  skipped with a warning and the contact stays as set in App Store Connect.
- **Android:** the edit is saved with `--changes_not_sent_for_review true`
  (changes wait in Play Console → **Publishing overview** → **Send changes
  for review**), so the service account needs no production permission.
  The Play images (feature graphic, icon, tablet screenshots) are uploaded
  when `featureGraphic.png` exists.
- **What's new:** `store/ios/<locale>/release_notes.txt` and
  `store/android/<locale>/changelogs/default.txt` are uploaded too; on Play
  they go on the latest release of `PLAY_TRACK` (default `internal`). A
  track can hold several releases ("More than one release found"), so the
  job first reads the newest version code there
  (`google_play_track_version_codes`) and passes it to supply; it fails with
  a clear error when the track is empty. Run Store listing after the release
  build is on Play. On the App Store, What's new is skipped for the app's
  first version (Apple has no field for it on 1.0).
- **Play service account permissions** (Play Console → Users and
  permissions → the service account → App permissions, for the app and the
  `.stg` app), found with Azm's Store listing on 2026-11-15:
  - Release apps to testing tracks; Manage testing tracks and edit tester
    lists (the release and staging uploads).
  - **Manage store presence** (texts, images).
  - **Edit and delete draft apps**: needed while the app is still a draft
    (never published to production); without it the listing commit fails
    with "The caller does not have permission". It can't publish anything.
    After the first production release, check whether Store presence alone
    is enough and drop it.
  - Not needed: Admin, Release to production, financial data.

## Store requirements (check each year)
| Store | Requirement | Where it's handled |
|---|---|---|
| App Store | Built with **Xcode 26+** / iOS 26 SDK (since 28 Apr 2026) | iOS jobs pick the newest Xcode on the runner, or fail with a clear message |
| Google Play | New apps and updates target **Android 16 (API 36)** (since 31 Aug 2026) | `targetSdk = flutter.targetSdkVersion` (36 in Flutter 3.47) |
| App Store | **Privacy manifest** for the app and every SDK that collects data or uses a required-reason API | `ios/Runner/PrivacyInfo.xcprivacy` (in Runner's Resources; generated from the app's options — update it with App Store Connect → App Privacy when the app collects something new); SDKs ship their own. Check the merged report: Xcode → Archive → Generate Privacy Report |

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

- **Release name.** The app reports `<package or bundle id>@<version>+<build>`
  (sentry_flutter's `LoadReleaseIntegration`), e.g. `com.mohager.azm@0.16.0+33`.
  The upload uses the same name: `release.yml` passes `SENTRY_APP_ID` with
  `VERSION` and `BUILD`, and the script sets `SENTRY_RELEASE` / `SENTRY_DIST`.
  Before 2026-11-03 the plugin fell back to the pubspec (`gym_tracker@0.1.0+1`),
  a release that never received an event (Sentry's Releases page and release
  health). Debug files are found by their debug id, so symbolication itself was
  likely not affected.
- **Readable issue titles.** Obfuscated builds also write
  `build/app/obfuscation.map.json` (`--extra-gen-snapshot-options=--save-obfuscation-map`).
  The plugin uploads it (`dart_symbol_map_path`, plugin ≥ 3.2.0), so exception
  class names in issue titles are readable. The map is **not** kept in the
  `symbols-*` artifact: it undoes the obfuscation.
- Docs read 2026-11-03: Sentry "Dart Plugin" (Flutter debug symbols) and
  "Releases & Health"; Flutter "Obfuscate Dart code"; the plugin's source
  (3.4.0) and sentry_flutter 10.2.0 (`load_release_integration.dart`).

## iOS signing hangs
Release run 33 (2026-11-03) found the profiles and then waited on App Store
Connect with no output until the 60-minute job timeout; the run before took
6 seconds with the same code. `scripts/fetch_signing_files.sh` now stops an
attempt after `SIGNING_TIMEOUT_SECONDS` (180) and the whole process group with
it, retries up to `SIGNING_TRIES` (3), and the step has `timeout-minutes: 12`.
It also passes `--strict-match-identifier`: without it `com.mohager.azm` also
matched `com.mohager.azm.stg` and fetched the staging profile too
(codemagic-cli-tools 0.70.2, latest on PyPI 2026-10-29, `fetch-signing-files`
docs read 2026-11-03). If all attempts fail, re-run the job; check App Store
Connect's status page and the API key's role.

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
| EGM plugin (`google/elephant-goldfish-model`) | `.claude/settings.json` (`ref`), design reviews | v0.1.1 |
| `camera`, `google_mlkit_pose_detection` (native code, ML Kit models) | `pubspec.yaml` (exact), Move games; bump by hand, re-check app size, the merged Android manifest and OSV for the Android libraries (`docs/security.md` → Move games) | 0.12.2, 1.0.2 |
| `flutter_tts` (native speech on Android and iOS) | `pubspec.yaml` (exact), Move games' spoken count; bump by hand, then check on a phone that a count is spoken in Arabic and English, music keeps playing, and the manifest still only queries `TTS_SERVICE` | 4.2.5 |
| ML Kit iOS model bundles (`ios/Runner/MLKit/`, Google's `MLKitPoseDetection` 1.0.0-beta16 files) | `scripts/ios_mlkit_bundles.sh` (pinned SHA-256); bump with `google_mlkit_pose_detection` when its `google-mlkit-swiftpm` version changes: update `VERSION`, the archive paths (podspecs on cdn.cocoapods.org) and the pins in the script and `platform_config_test.dart`, then `--fetch` | 1.0.0-beta16 |
| `flame`, `flame_audio` (brings `audioplayers` and its native code) | `pubspec.yaml` (exact), the Move games' Stack game and its sounds; bump by hand, then run the Move tests (the engine must still pause itself when idle) and check that the sounds still mix with music (`FlameMoveSounds.context`) | 1.38.2, 2.12.2 |

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
| `APP_REVIEW_FIRST_NAME`, `APP_REVIEW_LAST_NAME`, `APP_REVIEW_EMAIL`, `APP_REVIEW_PHONE` | App Review contact for Store listing (phone as `+<country> …`); without them the review notes aren't uploaded |
| `CLAUDE_CODE_OAUTH_TOKEN` | Social posts: Claude writes them on your Pro/Max plan (`claude setup-token`, valid a year); without it, templates write them |
| `FB_PAGE_ID`, `FB_PAGE_TOKEN` | Social posts: Facebook Page (long-lived Page token; for Instagram it also needs `instagram_basic` and `instagram_content_publish`) |
| `IG_USER_ID` | Social posts: Instagram professional account linked to the Page (Reels) |
| `LINKEDIN_TOKEN`, `LINKEDIN_AUTHOR_URN`, `LINKEDIN_ORG_URN` | Social posts: LinkedIn as you and/or the company page |
| `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_REFRESH_TOKEN` | Social posts: LinkedIn token expiry check and automatic refresh (optional) |
| `YT_CLIENT_ID`, `YT_CLIENT_SECRET`, `YT_REFRESH_TOKEN` | Social posts: YouTube upload |
| `TIKTOK_CLIENT_KEY`, `TIKTOK_CLIENT_SECRET`, `TIKTOK_REFRESH_TOKEN` | Social posts: TikTok inbox draft (the workflow keeps the refresh token current) |
| `SOCIAL_SECRETS_TOKEN` | Social posts: fine-grained GitHub token (app repos, *Secrets: read and write*) that saves TikTok's rotated refresh token |

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

## Captain dashboard (Cloudflare Pages)
`dashboard/` (a Vite + Preact web app, [feature doc](features/dashboard.md))
is deployed by Cloudflare Pages' own Git integration, like the website:
project `azmm-dash` (https://azmm-dash.pages.dev), production branch `main`,
build command `npm run build`, output directory `dist`, **root directory
`dashboard`**, Build watch paths include `dashboard/*`. Environment variables
for Production and Preview (publishable values only): `VITE_SUPABASE_URL`,
`VITE_SUPABASE_PUBLISHABLE_KEY`; the build fails if they are missing or the
key looks secret. Node comes from `dashboard/.node-version` (22). No GitHub
workflow, no Cloudflare API token, **no GitHub secret**. Supabase side: the
Magic Link email template must contain `{{ .Token }}` (not
`{{ .ConfirmationURL }}`), Email OTP expiry 3600 and length 6, and custom SMTP
before real use (built-in: 2 emails per hour). Click-by-click steps (read from
the docs on 2026-11-04) and the first-owner SQL runbook are in the feature doc.
Commits that change only `dashboard/` do not make a store release
(`scripts/next_version.sh`).
**D1 (members and invite codes) needs nothing new from you:** no new
environment variable, secret, migration or Cloudflare setting (it uses
migrations 0005, 0006 and 0008 that are already applied). The one step that is
yours: trainees can only join with the cards once the app's PostHog flag
`gym_join` is on, so turn it on when D1 is live, staging first, after the
checklist in [Gym accounts in the app](#gym-accounts-in-the-app-gym_join-flag)
(see also [features/gym_join.md](features/gym_join.md)). Until then the cards
open the join page, but the app does not show the join screens.
**Turnstile:** when CAPTCHA protection is on in Supabase it covers the
dashboard's sign-in too. Before turning it on, add `azmm-dash.pages.dev` to the
Turnstile widget's Domains and set `VITE_TURNSTILE_SITE_KEY` (site key,
publishable) in the Pages project, then redeploy (feature doc → Deploy → C).

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

### iOS build: `Unable to write file: build/app/obfuscation.map.json`
The release passes `--save-obfuscation-map=build/app/obfuscation.map.json`.
`build/app/` is made by the Android (Gradle) build only, so on the macOS
runner the folder is missing and the AOT snapshot fails (seen 2026-11-04,
release after #40; Android shipped, iOS didn't, no tag). `release.yml`
creates the folder before `flutter build ipa`.

## Backup flag (`training_backup`)
Backing up a member's training (docs/features/backup.md) ships dark: the PostHog
flag `training_backup` is **off**. Before turning it on, the Supabase settings
in "Before the flag goes on" of that page must be done (sign-up by email, the
`{{ .Token }}` templates, SMTP, CAPTCHA). Migration 0022 deploys on merge and
is safe before the app versions that use it.


## Gym logos flag (`gym_logos`)
Gym logos in the app (docs/designs/gym_logo.md) ship dark: the PostHog flag
**`gym_logos`** is off, and the tiles show letters.
- **Order.** Migration 0023 (`logo_updated_at`) must be deployed (**Supabase
  deploy** green) **before** the app PR merges: the app selects that column,
  and an older database refuses the select. Old app versions are not
  affected.
- **Turn on for staging.** PostHog → Feature flags → New, key `gym_logos`,
  condition `app = gym_tracker` **and** `environment = staging`, 100 %. Upload
  a logo in the staging dashboard, then bring the app back to the front: the
  tiles show it.
- **Then prod:** the same condition with `environment = prod`.

## Gym history restore flag (`gym_history_restore`)
After a recovery code, the member's workouts on the server come back onto
the phone (docs/designs/gym_history_restore.md).
- It is off by default.
- It needs the fix in 3shmawi/gym_tracker#113 (the restore asks by person),
  which ships with or before it.
- No backend change.
- **Turn on for staging:** PostHog → Feature flags → New, key
  `gym_history_restore`, condition `app = gym_tracker` **and**
  `environment = staging`, 100 %. Try it: log a workout in a gym, delete
  the app, install it again, use a recovery code from the dashboard, then
  check the toast and the history.
- **Then prod:** the same condition with `environment = prod`.

## Move games flags (`move_games`, `move_games_debug`)
Move games (docs/features/move_games.md) ship dark: every screen, the Today
card and the menu row are behind the PostHog flag **`move_games`** (off).
The pose check for testers is behind **`move_games_debug`**, and a prod build
never shows it whatever the flag says.

**Turn on for staging** (PostHog → Feature flags → New, for each of the two
keys): release condition `app = gym_tracker` **and** `environment = staging`,
100 %. Nothing in prod changes. Testers then see the Move card on Today and
*Pose check (testing)* in Settings → About.

**Before `move_games` goes on in prod** (in this order):
1. The website with the updated **privacy policy and terms** (2026-11-13:
   Move games, Google ML Kit, training safely) is live at
   `https://azmm.pages.dev/privacy.html`. It deploys with the merge; the app
   then asks every member to agree again (`ConsentStore.current`).
2. **Store forms** updated as in `store/privacy_forms.md` → "Move games and
   Google ML Kit": App Store Connect → App Privacy (add *Other Diagnostic
   Data*, add *Analytics* to *Performance Data*, ML Kit as a source of
   *Device ID*); Play Console → Data safety (no new type; check that
   *Diagnostics* and *Device or other IDs* are still declared). Submit them
   with the next release, before the flag.
3. **Speed measured** on the cheapest Android at hand and a mid-range one
   with the pose check (`docs/performance.md` → Move games → frames per
   second). Below 8 frames/s a phone gets the manual counter.
4. **Real recordings** (decision 9 of the spec) replayed by the tests.
5. **iOS:** the model is in the app (2026-11-13), but it has only been built
   in CI, never run on an iPhone. Check it with the pose check on a real
   iPhone (`docs/features/move_games.md` → Platforms) and measure the IPA
   growth (`docs/performance.md`); until then add the release condition
   `$os = Android` to the prod rollout.
6. Roll out in steps (for example 10 % → 50 % → 100 %) and watch
   `move_unsupported` (`too_slow`, `model_failed`) and Sentry.

Turning it off again hides everything at once; saved rounds stay in history
as ordinary workouts.
