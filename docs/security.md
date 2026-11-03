# Security

Security is tested, not assumed. Three layers run on every pull request.

## 1. App tests (`flutter test`, folder `test/security/`)
| Test | Guards against |
|---|---|
| `secrets_test.dart` | private keys, Supabase secret/service-role keys, AWS/Stripe/GitHub/Google keys or hard-coded keystore passwords in `lib/`, `android/`, `ios/`, `website/`, `supabase/`, `env/`; non-empty `env/example.json`; `.gitignore` missing env/signing entries |
| `platform_config_test.dart` | camera permission without `required=false`, any other sensor/storage/location permission, a missing or untranslated `NSCameraUsageDescription`, `ar` missing from the iOS regions, cleartext HTTP, debuggable releases, the `azm://` scheme and an https App Link that is not exactly `azmm.pages.dev/join/` (Android + iOS entitlements, both flavors), extra exported Android activities, disabled iOS App Transport Security; notifications: only `SCHEDULE_EXACT_ALARM` (no `USE_EXACT_ALARM`, full-screen intent or boot receiver), the receiver not exported, the icon kept from R8, the iOS delegate set |
| `workflow_secrets_test.dart` | secrets pasted into CI scripts, a key written to a file without `scripts/mask_secrets.sh`, `set -x`, actions not pinned to a commit |
| `well_known_test.dart` | `.well-known` files holding anything but app ids, package names and SHA-256 fingerprints (no secrets); wrong paths (only `/join/*`) or hosts; missing `application/json` headers; website, store texts, docs and app pointing to a host other than `azmm.pages.dev` (or still to the old one) |
| `join_page_test.dart` | `website/join.html` using `innerHTML`/`document.write`/`eval`/navigation from the address, inline script or style, a third party or tracker, a store link different from the home page, a missing `/join/*` rewrite or `no-store` header, a `?c=` link |
| `supabase_backend_test.dart` | a table without RLS or without its pgTAP file, a table that keeps `anon`/`authenticated` grants, a `security definer` function without a fixed `search_path` or open to `anon`, a literal (non-random) Vault secret in a migration, a plain `code` column on `invites`, the Edge Function logging request data / reading secrets / losing JWT verification or pinned dependencies, invite PDFs or function `.env` files not git-ignored |
| `exercise_image_library_test.dart` | the picture table losing RLS or gaining a write policy or a licence outside the commercial list (no NC/ND), a seed row without its reviewed commit, author or attribution, SQL smuggled into the seed data, the upload script printing or hard-coding the Cloudinary secret, reading the unreviewed source folders, or accepting a crafted public id, a banned licence, a duplicate, a missing file or a cloud name that is not a plain name; the workflow's upload job not manual or not in the `cloudinary` environment |
| `deep_link_test.dart` | crafted/unknown deep links crashing the app or reaching unexpected screens; open redirects via query parameters; a tapped notification opens only `/workout` (its payload is never read); the gym account screens: flag off → home, signed out → `/welcome`, a link never joins, signs out or deletes, `/join/joined` cannot be faked, `scan`/`joined` are never codes |
| `gym_account_app_test.dart` | the session outside secure storage, a secret besides the session and install id, a `print` in gym code, an analytics event or property beyond the agreed ones (codes, names, ids, emails), the scanner opening a URL or returning the camera image, `signInAnonymously` outside redeem (never at launch), the router joining/signing out/deleting |

### Join page (`website/join.html`, `/join/<code>`)
It is shown to people who scan an invite QR without the app, and its address
holds a one-time code, so it only **displays** it:
- Only the path is read (never query, hash or referrer), checked with
  `^[A-HJKMNP-Z2-9]{6}$` after an ASCII-only check, written with `textContent`.
  `join-code.js` is pure and tested in Node (`test/website/join_code.test.js`,
  run in CI) against hostile addresses; `join_page_test.dart` bans
  `innerHTML`, `document.write`, `eval`, `location =`, `fetch` and trackers.
- No third-party request: Inter and Cairo are served from the site, so the CSP
  `font-src` is `'self'` plus the existing Google Fonts host (other pages). The
  page sends no referrer (`<meta name="referrer">`, `rel="noopener noreferrer"`
  on store links), is `no-store` and `noindex`.
- The app side: a link only pre-fills the field; joining needs the member's tap
  (`joinSubmitProvider`), and the whole route is behind the `gym_join` flag.

### Join page (`website/join.html`, `/join/<code>`)
It is shown to people who scan an invite QR without the app, and its address
holds a one-time code, so it only **displays** it:
- Only the path is read (never query, hash or referrer), checked with
  `^[A-HJKMNP-Z2-9]{6}$` after an ASCII-only check, written with `textContent`.
  `join-code.js` is pure and tested in Node (`test/website/join_code.test.js`,
  run in CI) against hostile addresses; `join_page_test.dart` bans
  `innerHTML`, `document.write`, `eval`, `location =`, `fetch` and trackers.
- No third-party request: Inter and Cairo are served from the site, so the CSP
  `font-src` is `'self'` plus the existing Google Fonts host (other pages). The
  page sends no referrer (`<meta name="referrer">`, `rel="noopener noreferrer"`
  on store links), is `no-store` and `noindex`.
- The app side: a link only pre-fills the field; joining needs the member's tap
  (`joinSubmitProvider`), and the whole route is behind the `gym_join` flag.

### Links that open the app
- `azm://` is a custom scheme: **any app can register it**, so treat every
  link as untrusted input. Routes only open screens; nothing in a link's
  path or query changes data (`deep_link_test.dart`, incl. `/join/<code>`,
  where the code only fills the enter-code screen and never joins).
- **Links that cannot be decoded are dropped** (`lib/core/router/link_guard.dart`,
  docs read 2026-11-03 in go_router 18.1.2 and Flutter 3.47.8 sources). A link
  with broken percent-encoding (`?day=%FF`, `/plan/%FF`) makes go_router, and
  Flutter's default `WidgetsBindingObserver.didPushRouteInformation`, throw a
  `FormatException`: no route can catch it. `LinkGuard.install()` (first thing
  in `bootstrap`, before any observer) adds an observer that sees every link
  first and consumes an unsafe one, so the app stays where it is and nothing
  else sees it; the link that starts the app goes through
  `LinkGuard.initialLocation` (unsafe: home). Every other
  `WidgetsBindingObserver` in `lib/` mixes in `IgnoresLinks` (a test fails
  otherwise). Tests: `test/core/router/link_guard_test.dart`.
- https links are verified by Apple/Google against
  `https://azmm.pages.dev/.well-known/` (HTTPS, no redirect, JSON) and only
  `/join/*` is claimed. Whoever can change `website/` on `main` controls
  which apps may open them, so `main` stays protected (PR + green checks)
  and the Cloudflare project has no other deploy path. The Android file
  lists *public* certificate fingerprints only.
- Staging bundle ids are listed next to prod in the same files; the staging
  apps are signed by the same team and are never public.
- `website/_headers` sets a strict CSP (no inline script/style, no framing,
  no third parties besides Google Fonts), nosniff and HSTS on every page.

## 2. CI `security` job
- **gitleaks** — scans the whole git history for committed secrets.
- **OSV-Scanner** — checks `pubspec.lock` against known vulnerabilities.
- **zizmor** — audits `.github/workflows/`: actions pinned to a commit,
  read-only tokens unless a job needs more, no credentials left after
  checkout, no untrusted text run as shell code, no risky triggers.
- **Supabase RLS tests** — `supabase test db` runs `supabase/tests/*.sql`
  (pgTAP) against a local database built from the migrations. Enable once:
  `supabase init` (creates `supabase/config.toml`), commit it.
- **Edge Function tests** (Deno, `denoland/deno:2.9.6`) and **invite tooling
  tests** (Python, hash-pinned packages) run when a PR touches
  `supabase/functions/` or `scripts/make_invites/`, and on every push to
  `main`.

## 3. Rules for new code (also in CLAUDE.md)
- New route → add hostile paths to `deep_link_test.dart`.
- New table → RLS on + `supabase/tests/<table>_rls.test.sql`.
- New input → tests for empty, huge, injection-like and malformed values.
- Auth → signed-out redirect tests + "user A can't touch user B's rows" RLS tests.
- Notifications are local only (no push token, nothing sent). Ask for a
  permission at the moment it is needed, never at launch; declare the
  least Android permission that works and test it in
  `platform_config_test.dart`. Never route on a notification's payload.
- Only publishable keys in the app. Server secrets live in Supabase
  (Edge Function secrets / Vault).

## 4. CI and secrets
Treat every CI log and artifact as public: in a public repo they are.
The Dart obfuscation map (`build/app/obfuscation.map.json`) goes to Sentry
only and is never kept as an artifact: it would undo the obfuscation. The
`symbols-*` artifacts hold only `build/symbols` (split debug info).
GitHub hides a secret only where its **exact stored text** appears; a key
decoded from base64 or read out of a JSON secret is different text and
would be printed in full by any tool that echoes it in an error.

- Secrets reach scripts through `env:` only, never `${{ secrets.X }}` inside
  `run:`.
- A key written to a file (`.p8`, `.pem`, a service-account `.json`) is
  passed to `./scripts/mask_secrets.sh` right after it's written, before any
  tool reads it.
- Never `set -x`, `curl -v` or "print the config to debug" in CI.
- Env files are checked by `./scripts/check_env.sh`, which prints key
  **names** only (empty / wrong kind), never values.
- `POSTHOG_PERSONAL_API_KEY` (scope `project:read`) stays in
  `~/.app-secrets/shared.env` on your Mac; it is never uploaded to CI or put
  in `env/*.json`. Only the project key (`phc_…`, publishable) goes there.
- A secret's value must not be a common word: GitHub stars out that text
  everywhere in every log. That's why new Android keystores use the alias
  `<repo>-upload`, not `upload` (which turned "Keep the AAB for a manual
  upload" into "… manual ***").
- Pass passwords through environment variables the tool reads, not as
  command-line arguments.
- Workflows start with `permissions: contents: read`; a job that must write
  asks for exactly that. `actions/checkout` uses
  `persist-credentials: false`.
- Third-party actions are pinned to a full commit SHA with a `# vX.Y.Z`
  comment (Dependabot updates both). Tools installed in CI are pinned to a
  version: Codemagic CLI, fastlane, zizmor, gitleaks, OSV-Scanner (see
  `docs/release.md` → "Pinned tools").
- Caches: release and staging builds (signed, uploaded to the stores) don't
  restore a Gradle cache, so a cache written by a PR run can't change what
  ships. Only PR / check jobs use `gradle-cache: 'true'` in
  `.github/actions/setup-flutter`. The repo's composite actions follow the
  same rules as workflows (pinned SHAs, zizmor, `workflow_secrets_test`).
- No `pull_request_target`. Anything a PR can control (titles, branch or
  file names, step outputs) goes through `env:` and is quoted.

## 5. Gym accounts: invites, secrets and where they live
Design: [`decisions/gym_accounts.md`](decisions/gym_accounts.md); feature:
[`features/gym_accounts_backend.md`](features/gym_accounts_backend.md).

| Secret / sensitive value | Where it lives | Where it must never be |
|---|---|---|
| **Invite pepper** (HMAC key for codes and address hashes) | Supabase **Vault**, secret `invite_pepper`, generated *inside Postgres* by migration `0006` (`gen_random_bytes`). Nobody types or sees it. | repo, env files, CI, app, logs. Read only by `security definer` functions in the unexposed `private` schema. |
| **Secret key** (`sb_secret_…`) for `scripts/make_invites` | your password manager → the shell environment of your own computer for that one command (`SUPABASE_SECRET_KEY`, with `SUPABASE_URL`) | `env/*.json`, any workflow, the app, a flag on the command line, shell history, the repo. The script refuses to run when `CI` / `GITHUB_ACTIONS` is set. |
| **Secret key inside the Edge Function** | injected by the Supabase platform (`@supabase/server` reads it); our code never reads an env var | our source (a test fails if the function touches `Deno.env`) |
| **Invite codes** | printed on the cards only (and in the owner's hands). The database keeps `HMAC-SHA256(pepper, code)` and shows a code once, to whoever created it. | logs, analytics, the invites table, the PDF's file name, chat. A PDF of live cards is not written inside the repo and is created with mode 0600. |
| Addresses of failed attempts | `invite_attempts.ip_hash` = HMAC with the pepper, purged after 30 days | plain text anywhere |

How the invite path is protected (each item has a test):
- **Single use, 7 days, revocable, bound to the first install id**; a replay
  from another phone gets `used`; the same phone retrying gets the same
  success. Expired and revoked codes are refused. All checks and the update
  happen in one transaction with the invite row locked.
- **Brute force:** ≤ 10 failed attempts / hour / user, ≤ 30 / hour / address,
  and a global pause above 200 failures in 10 minutes. Residual risk: a valid
  code is ≈ 1 in 9 × 10⁸ per guess (29.7 bits) — fine with this throttling, and
  the *link* can carry a longer token later without UI change.
- **Who may call what:** `redeem_invite_core` and `admin_create_invites` are
  executable by `service_role` only; the Edge Function passes the user id it
  verified from the JWT, so a client can neither forge identity nor address.
  `create_invite`, `revoke_invite`, `save_plan`, `leave_gym` check the caller
  themselves and are closed to `anon`.
- **Anonymous Supabase users have the `authenticated` role**, so no policy
  relies on the role alone; managers additionally need a permanent session.
- **The function** accepts only POST + JSON ≤ 1 KB, exactly
  `{code, install_id}`, ASCII-only codes from the 31-letter alphabet; adds no
  CORS header; answers with fixed bodies; logs no request data.
- **Hostile input:** wrong types, huge strings, unicode look-alikes
  (`ſ`, `ß`, full-width), SQL/HTML-like text, newline-padded codes, a
  `__proto__` key, replay, expiry, revocation and 40-guess brute force are in
  the Deno and pgTAP tests.
- **Known, accepted risks** (decision doc §5/§12): a *recover* code lets
  the gym's captain move a trainee's identity to a phone they hold, so only
  captains you trust should hold the role, and it is refused while the person
  is active in another gym. The throttle's address comes from
  `cf-connecting-ip`, else the last `x-forwarded-for` hop; I could not verify
  which header the Supabase gateway sets, so treat the per-address limit as
  best-effort (the per-user limit, Supabase's own 30 anonymous sign-ins/hour
  per IP and the global pause still apply). The dependency trees of the Edge
  Function were not checked against OSV (not reachable from the build
  environment); the Python packages were (`pip-audit`, clean).
- `scripts/make_invites` never follows HTTP redirects (urllib would re-send
  the secret key to the redirect target); tested.
- **Needs the project to use the new API keys and JWT signing keys:**
  `@supabase/server` rejects legacy `anon`/`service_role` keys and legacy
  HS256 user JWTs (its docs, read 2026-11-02). Check before the first deploy
  (docs/release.md).

Part 2 (sessions, solo import, demo, deletion):
- **History is the person's:** staff read a member's gym sessions only while the
  membership is active, only for members they may manage, never solo sessions
  or another gym's (`workout_sessions` RLS, pgTAP). `locked` hides, never deletes.
- **`import_solo_data`** validates every session and the plan on the server
  (same limits as the app), is atomic per call, idempotent and capped; imported
  sessions are solo, so no captain ever sees them.
- **The demo code** is reusable by design, so it is limited: only a gym marked
  `is_demo`, trainee role, wiped nightly, rotated per submission, stored only as
  an HMAC, shown once to the owner's script. It is the one code that can be
  guessed more than once, so it stays under the same attempt throttling.
- **`delete-account`** deletes only the verified caller (the id never comes from
  the body, which is exactly `{"confirm":"delete"}`); it logs no id, token or
  gym name; a sole owner is refused (and the database refuses too).
- Known, accepted: a deleted user's access token keeps passing JWT checks until
  it expires (Auth does not check the database), but every row policy keys on
  `people.auth_user_id`, which is gone, so it can read and write nothing.

### Gym accounts in the app (join, switch, profile)
Design: [`features/gym_account_app.md`](features/gym_account_app.md).
- **The session** (refresh token) is in the Keychain / Keystore through
  `SecureLocalStorage`, never in `shared_preferences`. iOS items are
  `first_unlock_this_device`; a Keychain session left by an earlier install is
  dropped on a fresh install. An unreadable store means "no session".
- **Anonymous sign-in happens only when a code is redeemed**, never at launch
  (solo users make no account), and with a Cloudflare Turnstile token when
  `TURNSTILE_SITE_KEY` is set (`lib/core/captcha/`). The site key is publishable
  and lives in the env files; the **secret** is only in Supabase's Auth settings
  (`gym_account_app_test.dart` fails on a `0x4…` key in `lib/` and keeps the
  widget's origin to the website host without opening the site's CSP). A widget
  that does not answer within 20 s fails the join (never a silent skip).
- **A QR is untrusted input.** The scanner takes text only through
  `InviteCode.fromScan`: `https://azmm.pages.dev/join/<code>`,
  `azm://join/<code>` or the bare code; another host, a port, user info, a query,
  a fragment, extra path pieces or text over 200 characters is "invalid" and is
  never sent. It never opens a URL, never returns the camera image
  (`returnImage` off) and the camera is asked for only when the scanner opens.
- **A link never joins; a scan joins at once** (the person deliberately scanned).
  Double taps and repeated camera frames start one try. Errors say what to do
  next and nothing about whether a code ever existed.
- **What is stored on the phone** (shared preferences, not secret): the active
  workspace, gym names/roles/permission flags, "first screen answered". What is
  in secure storage: the Supabase session and the random install id.
- **Analytics** carries only `via`, `reason` and `to`: never a code, name, id or
  email. Sign out and delete reset the analytics identity.
- **Sign out** is one-way for an anonymous account (the dialog says so);
  **Delete account** sends exactly `{"confirm":"delete"}`, an owner types the
  gym's name first, and a sole owner is refused with the gym names.
- **Add email** checks the address shape on the phone (ASCII, ≤ 254) and leaves
  the rest to Auth; the account keeps its id, so RLS and history are unchanged.
- **Solo import** sends only workouts and the plan, in chunks of 50, with a
  `client_id` that is a hash of the workout's own content (no device or account
  id). The server validates everything again; imported workouts are solo, so no
  captain sees them. The phone keeps its data; the import marks `done` only when
  the server's total covers what was sent. `test/security/store_pages_test.dart`
  checks the privacy/terms/delete pages keep promising what the app does.
- Known, accepted: gym logos are initials only (no image request); the captain's
  name is not shown (RLS); `mobile_scanner` bundles the ML Kit model.

Running `scripts/make_invites` follows the CI rules above even though it is
local: secrets only through the environment, no `set -x` / verbose flags, no
key written to a file (so there is nothing for `scripts/mask_secrets.sh` to
mask; if you ever run it where logs are collected, mask the key first), tools
pinned (Python packages with hashes, `requirements.txt`).

### Exercise library (app)
New routes `/library` and `/library/<id>` take an exercise id and a day id from
the link: both are only compared with known ids (the bundled catalog and the
member's own plan), encoded when built (`AppRoutes.libraryFor` /
`libraryExercise`), and a link can read but never add
(`test/security/deep_link_test.dart`). The search box text is cleaned, cut to
60 characters and only compared; hostile text is covered by tests. The library
has no network, storage or secret access and sends fixed words to analytics
(`test/security/exercise_library_test.dart`). Finding (go_router 18.1.2): a link
whose query has invalid percent-encoding made go_router throw before our code
ran, for every route. Solved by `LinkGuard` (`lib/core/router/link_guard.dart`):
such links are dropped before go_router and Flutter see them.

### Exercise picture library (migrations 0013/0014, Cloudinary)
Docs read 2026-11-03: Cloudinary "Signed uploads / authentication signatures",
"Upload images", "Transformation URL structure" and "Pricing"
(`docs/features/exercise_image_library.md`). Map of what is secret:
- `CLOUDINARY_API_SECRET` (signs uploads) and `CLOUDINARY_API_KEY`: GitHub
  secrets of the `cloudinary` environment, read by `tool/exercise_images/upload.py`
  through `env:` only, masked, never printed or put in a URL, an artifact, the
  database, the app or the web page. If one leaks: rotate it in the Cloudinary
  console first (see "If a key leaks").
- `CLOUDINARY_CLOUD_NAME`: not secret (it is in every public picture URL).
- The table `exercise_images` is public to read and writable only by the
  service role; the pictures are public CC BY-SA files.
No personal data is stored or sent. The package is built from one reviewed
commit of `everkinetic/data` (`SOURCE_COMMIT`); the unreviewed folders
(`images-png-unknown`, `images-ai`) are never read.

### Gym-chosen exercise pictures (migration 0015)
Docs read 2026-11-03 (Supabase RLS, PostgreSQL 17 constraints/policies,
PostgREST errors; read from their repositories, the sites were unreachable):
`docs/features/gym_exercise_images.md`. `gym_exercise_images` is readable by
the gym's active members only and writable by its owner/captain with a
permanent session (`private.i_manage(gym_id)`); never by `anon`, an ended
member or another gym. `exercise_id` is format-checked and never used for
authorization. Limits live in the database: 6 pictures per exercise, 1200 per
gym, `public_id` must be a library picture (FK), `updated_by` is stamped by a
trigger. `public.set_gym_exercise_images` is `security invoker` (RLS applies)
and closed to `anon`. No secrets, no personal data beyond `people.id`.
`supabase/tests/gym_exercise_images_rls.test.sql` proves each rule.

### Gym-chosen pictures in the app
`CLOUDINARY_CLOUD_NAME` is publishable (it is in every picture URL) and goes
in `env/<flavor>.json` like the other public keys; empty turns the feature
off. Picture URLs are built only from a library public id
(`exercises/[a-z0-9-]`) and a checked cloud name, with fixed transformation
words; anything else is refused before a request is made
(`test/core/media/cloudinary_url_test.dart`: `../`, URLs, `javascript:`,
upper case, look-alike letters, percent-encoding, long ids). The cache fetches
only https on `res.cloudinary.com` (no port, no user info), keeps files only
(no personal data, at most 400 × 2 MB). Cloudinary sees the device's IP when a
picture loads; the privacy policy says so (EN + AR).

### Trainee dashboard views (migration 0012)
Docs read 2026-11-03: Supabase "Row Level Security" and Postgres 15+
`security_invoker` views. The four `member_*` views run **as the person
asking**, so `workout_sessions`, `plans` and `memberships` policies decide who
sees what: the trainee their own gym rows; an owner everyone's, a captain
trainees', only while the membership is active; never solo sessions, another
gym, an ended member or `anon` (grants are `select` to `authenticated` only).
`supabase/tests/trainee_dashboard_views.test.sql` proves each of these.
Anything new that reads these views must stay `security_invoker`.

## If a key leaks (log, chat, commit)
1. **Revoke or rotate it first**, then clean up. Logs can be copied in the
   minutes they are public.
2. Delete the logs: Actions → the run → ⋯ → **Delete all logs**.
3. Replace it everywhere it's used (`~/.app-secrets/shared.env` is shared by
   all your apps) and re-run `tool/setup_secrets.sh` in each app.

| Leaked | Do this |
|---|---|
| Apple Distribution certificate / .p12 | Create a new certificate first, export a new `.p12`, update secrets in every app, then revoke the old one (apps already on the store keep working) |
| App Store Connect API key (.p8) | App Store Connect → Users and Access → Integrations → revoke, create a new key |
| Play service-account JSON | Google Cloud → IAM → Service accounts → Keys → delete the key, create a new one |
| Android upload keystore | Play Console → App integrity → request an upload key reset |
| Supabase secret key / DB password / access token | Supabase dashboard → rotate it |
| An invite card (photo, PDF, chat) | Revoke that invite (`revoke_invite`, or dashboard) and issue a new one; a code that was already used is harmless |
| The invite pepper | Replace the Vault secret `invite_pepper` (a new random value). Every unused invite stops working: revoke and re-issue them. Used invites and memberships are unaffected |
| Sentry auth token, GitHub token | Revoke in Sentry / GitHub settings, create a new one |

## If a scan fails
- Secret found → **rotate the key first**, then remove it from history.
- Vulnerable package → `flutter pub upgrade <package>`; if no fix exists,
  document the risk in `docs/decisions/`.
