# Feature: captain web dashboard (`dashboard/`)

> Step 0 of the delivery plan in [`../decisions/gym_accounts.md`](../decisions/gym_accounts.md) §13
> and the hosting rule in §7: a plain web app on **its own origin**
> (`https://azmm-dash.pages.dev`), not Flutter web. Phase **D0** is built:
> sign in, list the gyms you run, an empty members page. The rest comes in
> later phases.

## Scope

| Phase | What | State |
|---|---|---|
| **D0** | Project, build and deploy, headers/CSP, sign-in by email code, session, "my gyms", members page shell (empty state), English + Arabic (RTL), light/dark | **built (this doc)** |
| D1 | Members and invites: member list, add a trainee, QR cards, permissions, end a member | next |
| D2 | Exercise media: gym-chosen pictures and videos (table `gym_exercise_images`, see [gym_exercise_images.md](gym_exercise_images.md)) | planned |
| D3 | Plans: view and edit a trainee's plan through `save_plan` | planned |
| D4 | Plan templates (needs a **backend change**: new migration, RLS, pgTAP) | planned |
| D5 | Progress (the `member_*` views, [trainee_dashboard_data.md](trainee_dashboard_data.md)) and gym settings | planned |

D0 adds **no** migration, no RPC and no table. It only reads what migration
0005 already allows.

## Design
- Board: https://claude.ai/artifact/8dPMf6CPxewxFRgtjovg1P. D0 uses boards
  **0.1 to 0.5**; D1 will use **1.1 to 1.7**.
- Based on the Design System https://claude.ai/artifact/WUzyEppnEkcQXvVYec4m9H
  and the exercise media board https://claude.ai/artifact/VDxBpGdwNidSZgrGjfARJo
  (used from D2).
- Same rules as the app: no invented styles, Arabic and English (RTL with
  logical CSS), dark mode, loading / empty / error / offline states, touch
  targets of at least 48 px, labels for screen readers.

## Stack and pinned versions
Everything is pinned to an exact version in `dashboard/package.json` and
`dashboard/package-lock.json`. Node 22 (`dashboard/.node-version`,
`engines.node >= 22.12.0`).

| Package | Version | Why |
|---|---|---|
| `preact` | 11.0.1 | small UI library, no virtual-DOM extras |
| `@supabase/supabase-js` | 2.118.0 | Auth + PostgREST |
| `vite` | 8.3.4, `@preact/preset-vite` 2.10.6 | build and dev server |
| `typescript` | **6.0.3** | stays below 6.1: `typescript-eslint` 8.72.0 supports `<6.1.0` only |
| `eslint` 10.13.0, `typescript-eslint` 8.72.0, `@eslint/js` 10.0.1 | | lint |
| `vitest` | **4.1.12** | the first version that fixes GHSA-82fw-gwwq-j7x9 and GHSA-qxg6-89mg-rqv8 |
| `jsdom` | 30.1.3 | DOM for unit tests |
| `@playwright/test` 1.64.1, `@axe-core/playwright` 4.14.0 | | browser tests, accessibility |
| `minimatch` | **11.0.3** (npm `overrides`) | fixes GHSA-g3hv-75wg-m249 in a transitive dependency |

Lockfile note: `package-lock.json` was generated with **npm 11.21.1**,
because npm 10.9.9 crashes while resolving vitest 4.1's peer set. A plain
`npm ci` with npm 10 installs from the finished lockfile without problems
(Cloudflare's build image uses its own npm, which is fine for the same
reason). When you change dependencies, regenerate with npm 11.

## Architecture
```
dashboard/
  index.html, public/          shell (no inline script or style), icons
  build/headers.ts             writes dist/_headers (CSP and friends)
  vite.config.ts               validates the env, adds the headers plugin
  src/
    main.tsx                   start-up
    app/                       App (state wiring), router.ts
    core/                      config, supabase client, result/failure, text, prefs, online
    auth/auth.ts               email-code sign-in, session
    gyms/gyms.ts               the gyms the person manages
    i18n/                      en.ts, ar.ts
    ui/ pages/ styles/         screens and styling
  test/                        unit tests (Vitest) and e2e (Playwright)
```
- **Result / Failure.** Nothing throws to the UI. Every call goes through
  `guard()` (`core/result.ts`) and returns `Result<T>` (`ok` or
  `{ ok: false, failure }`). `core/failure.ts` turns Supabase Auth, PostgREST
  and network errors into a small set of kinds (`offline`, `forbidden`,
  `session_ended`, `not_found`, `conflict`, `invalid`, `rate_limited`,
  `code_wrong`, `code_expired`, `server`). The UI shows a message per kind,
  never the server's text. Same idea as `guard` in the Flutter app.
- **Pages are thin.** Pages wire state to views that only take data and
  callbacks.
- **Routes** (`src/app/router.ts`, a tiny History API router):

| Path | Screen |
|---|---|
| `/` | home: sends a signed-in person to `/gyms`, otherwise to `/sign-in` |
| `/sign-in` | email, then the code |
| `/gyms` | the gyms you run (owner or captain) |
| `/g/<gym-uuid>/members` | members page (`/g/<gym-uuid>` is the same) |
| anything else | not found |

  The gym id must match the UUID pattern, otherwise the route is "not found";
  trailing slashes are ignored. Cloudflare Pages serves `index.html` for
  every path (single-page-app fallback, automatic while the build has no
  top-level `404.html`).

## Contracts used (migration 0005, no new RPC)
Read through the signed-in person's session; Row Level Security decides.

| Table | Policy that lets the dashboard read it |
|---|---|
| `people` | "read own person" (`id` where `auth_user_id` is me) |
| `memberships` | "read own memberships" (status `active`, role `owner` or `captain`) and "managers read gym memberships" (for member counts; needs `private.i_manage`) |
| `gyms` | "members read their gyms" (deleted gyms are hidden) |

`src/gyms/gyms.ts` does: `people` (my person id) then `memberships` joined
with `gyms` (`role in ('owner','captain')`, `status = 'active'`), then one
head-count per gym of memberships that are not `ended`. Writes and RPCs come
with D1.

## Sign-in flow and session
1. **Ask for a code.** `signInWithOtp({ email, options: { shouldCreateUser: false } })`.
   The dashboard never creates users. An unknown address makes Supabase answer
   HTTP 422 `otp_disabled` ("Signups not allowed for otp"); the dashboard shows
   the same "check your email" screen as for a known address, so the page can't
   be used to find out who manages a gym.
2. **Type the code.** `verifyOtp({ email, token, type: 'email' })`. Six digits
   (Arabic-Indic digits are accepted and converted). Wrong or expired codes
   show their own message.
3. **Permanent session only.** `private.i_manage()` requires a permanent
   (non-anonymous) JWT. If the session is anonymous, the dashboard signs it out
   locally and shows the signed-out state; an anonymous session never manages.
4. **Session storage.** supabase-js keeps the session in `localStorage` under
   `sb-<project-ref>-auth-token`; `persistSession: true`,
   `autoRefreshToken: true`, `detectSessionInUrl: false` (a crafted address can
   never plant a session; sign-in is by typed code, never a link).
5. **Sign out** uses `scope: 'local'`: this browser only; the person's phone
   session is untouched.

Supabase behaviour (docs read **2026-11-04**,
https://supabase.com/docs/guides/auth/auth-email-passwordless and
https://supabase.com/docs/guides/auth/rate-limits):
- A **code** (not a link) is sent when the **Magic Link** email template
  contains `{{ .Token }}` and not `{{ .ConfirmationURL }}`.
- One request per address per **60 seconds**; a code expires after **1 hour**
  (Authentication > Sign In / Providers > Email > Email OTP expiration).
- Code length is 6 by default, configurable 6 to 10 (`auth.email.otp_length`).
  The dashboard expects **6** (`CODE_LENGTH` in `src/auth/auth.ts`); change
  both together.
- The built-in email service is limited to **2 emails per hour**: set up a
  custom SMTP server before real use.

## Data kept in the browser
Only two things, neither shown to anyone else:
- the supabase-js session (`sb-<project-ref>-auth-token`);
- `azm.dashboard.prefs.v1`: `{ lang, theme }`. No personal data.

Storage may be blocked (private window): the dashboard still works for that
tab; every access is guarded.

## Events
**None.** The dashboard has no analytics and no feature flags in D0 (no
PostHog, no Sentry, no cookies, no third-party requests). If that changes,
update this section, `website/privacy.html` and `store/privacy_forms.md` first.

## How to run
```bash
cd dashboard
npm ci
cp .env.example .env.local        # then fill the two publishable values
npm run dev                       # http://localhost:5173
npm run check                     # typecheck + lint + unit tests + build
npm run e2e                       # Playwright, Supabase is mocked, no network
```
`.env.local` holds `VITE_SUPABASE_URL=https://<project-ref>.supabase.co` and
`VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_…` (Supabase > Project settings >
API Keys). **Publishable values only**: they end up in the public bundle. The
build fails when either is missing, when the URL is not
`https://<20-character ref>.supabase.co`, or when the key looks secret
(`sb_secret_…`, or contains `service_role`); see `src/core/config.ts`. `.env*`
files are git-ignored except `.env.example`.

## Deploy (Cloudflare Pages, Git integration; for the owner)
Like the website, the dashboard is deployed by **Cloudflare Pages' own Git
integration**: no GitHub workflow and no Cloudflare API token in this repo.
**No GitHub secret is needed for D0.** Menu names below were read from the
docs on **2026-11-04** and may move
(https://developers.cloudflare.com/pages/configuration/git-integration/,
https://developers.cloudflare.com/pages/configuration/build-configuration/,
https://developers.cloudflare.com/pages/configuration/build-watch-paths/,
https://developers.cloudflare.com/pages/configuration/build-image/,
https://developers.cloudflare.com/pages/configuration/headers/).

**A. Create the Pages project (once)**
1. Cloudflare dashboard > **Workers & Pages** > **Create** > **Pages** >
   **Connect to Git**; pick `3shmawi/gym_tracker`.
2. **Project name:** `azmm-dash` (this gives `azmm-dash.pages.dev`; the name
   must be unique across Cloudflare, pick another and update the docs if it is
   taken).
3. **Production branch:** `main`. **Framework preset:** None.
4. **Build command:** `npm run build`. **Build output directory:** `dist`.
5. **Root directory (advanced) > Path:** `dashboard`. The output directory is
   relative to the root directory: check in the first deploy that
   `dist/_headers` and `dist/index.html` are picked up (verify in the
   dashboard preview).
6. **Environment variables**, added for **Production and Preview** (Settings >
   Variables and Secrets): `VITE_SUPABASE_URL` and
   `VITE_SUPABASE_PUBLISHABLE_KEY`. Publishable values only. Add
   `VITE_TURNSTILE_SITE_KEY` (the Turnstile **site** key, publishable) as soon
   as CAPTCHA protection is on in Supabase (see C).
7. **Save and Deploy.** Node comes from `dashboard/.node-version` (22); the
   build image v3 default is Node 22.23.4.
8. **Settings > Build > Build watch paths > Include** `dashboard/*`, so only
   dashboard commits rebuild it. Optional: in the website project (`azmm`),
   include `website/*` so dashboard commits don't rebuild the site.

Things to know:
- A repo can have at most 5 Pages projects.
- Every PR and branch gets a preview URL (`<hash>.azmm-dash.pages.dev`,
  `<branch>.azmm-dash.pages.dev`) with `X-Robots-Tag: noindex` added
  automatically. Previews are **public** unless Cloudflare Access is turned on;
  they use the same Supabase project, so don't share them around.
- `_headers` (in `dist/`) allows 100 rules and 2,000 characters per line;
  `build/headers.ts` throws if a line is too long.
- Pages adds `Access-Control-Allow-Origin: *` by default; our `_headers`
  removes it (`! Access-Control-Allow-Origin`).
- A dashboard-only commit does **not** make a store release:
  `scripts/next_version.sh` ignores commits that change only `dashboard/`
  (`test/scripts/next_version.test.mjs`).

**B. Supabase dashboard (once)**
1. **Authentication > URL Configuration:** keep **Site URL** as it is if the app
   uses it. Add the Redirect URL `https://azmm-dash.pages.dev/**`. This is
   optional for code sign-in (codes don't redirect); keep it for safety.
2. **Authentication > Emails > Templates > Magic Link:** the body must contain
   `{{ .Token }}` and must **not** contain `{{ .ConfirmationURL }}`. Suggested
   text:
   - English: `Your Azm Dashboard code: {{ .Token }}. It works for 1 hour. If you didn't ask for it, ignore this email.`
   - Arabic: `كود دخولك إلى لوحة Azm: {{ .Token }}. يشتغل لمدة ساعة. لو إنت ما طلبتوش، تجاهل الإيميل ده.`

   (A template is one text per project: put both lines in the body.)
3. **Authentication > Sign In / Providers > Email:** provider enabled, **Email
   OTP expiration** `3600`, **OTP length** `6`.
4. **Authentication > Emails > SMTP Settings:** set up **custom SMTP** before
   real use. The built-in service sends 2 emails per hour.
5. Check the CSP once: the project ref in `dist/_headers` must be the one in
   `VITE_SUPABASE_URL`.

**C. Turnstile (when CAPTCHA protection is on in Supabase)**
Supabase's CAPTCHA protection covers "sign-in, sign-up, and password reset
forms" (https://supabase.com/docs/guides/auth/auth-captcha, read 2026-11-04),
so once it is on for the app's anonymous sign-in, the dashboard's "send me a
code" needs a Turnstile token too. **Order matters**, as for the app
(`docs/release.md` → Turnstile):
1. Cloudflare > **Turnstile** > the widget > **Domains**: add
   `azmm-dash.pages.dev` (next to `azmm.pages.dev`).
2. Cloudflare Pages > `azmm-dash` > Settings > Variables and Secrets: add
   `VITE_TURNSTILE_SITE_KEY` (Production and Preview) and redeploy. The build
   then adds `https://challenges.cloudflare.com` to `script-src` and
   `frame-src` (Cloudflare's CSP guidance,
   https://developers.cloudflare.com/turnstile/reference/content-security-policy/,
   read 2026-11-04); without the key the CSP keeps `frame-src 'none'`.
3. Only then turn CAPTCHA protection on in Supabase. With protection on and no
   site key, managers cannot sign in.

## Owner bootstrap: the first owner of a pilot gym
Sign-in uses `shouldCreateUser: false`, so a person who has never been created
**cannot** sign in to create themselves. The first owner is created by hand.
This is a runbook **you** run, in the **Supabase dashboard**; never from CI or
from a script in the repo.

1. **Authentication > Users > Add user** (create new user) with the owner's
   email, with **Auto Confirm User** on. (They get no password; they sign in
   with email codes.)
2. **SQL Editor**, replace the three placeholders and run:

```sql
-- Runs with the SQL editor's privileges (it bypasses RLS and column grants).
-- Run it by hand, once per owner. Never from CI or a script.
-- <email>: the owner's email as typed in step 1. <name>: 1 to 40 characters.
-- <gym-uuid>: public.gyms.id of the pilot gym (it must already exist).
insert into public.people (auth_user_id, display_name)
select id, '<name>' from auth.users where email = '<email>'
on conflict (auth_user_id) do nothing;

insert into public.memberships
  (gym_id, person_id, display_name, role, status, joined_at)
values (
  '<gym-uuid>',
  (select id from public.people
    where auth_user_id = (select id from auth.users where email = '<email>')),
  '<name>', 'owner', 'active', now()
);
```
   - The `memberships_person_matches_status` check requires a `person_id` for
     an `active` membership, which is why the person row comes first.
   - `unique (gym_id, person_id)` makes a second run fail, not duplicate.
   - Check: sign in on the dashboard with that email; the gym opens (or shows
     on "Pick a gym" when there are several) with the role Owner.
3. **Captains** are not made by SQL. In D1 the owner adds a captain on the
   dashboard and prints the code; the captain joins in the **app** with it
   (anonymous account), then adds an email in the app's Profile ("Add email",
   `updateUser`), and from then on signs in to the dashboard with that email.
   `private.i_manage()` only counts a permanent (email) session.

## Tests
- `dashboard/test/` (Vitest + jsdom): config (missing/secret/odd keys), failure
  mapping, text cleaning (bidi and control characters, email, code), router
  (UUID only, hostile paths), auth (no enumeration, anonymous refused), gyms,
  headers (CSP exact, `_headers` limits), pages.
- `dashboard/e2e/` (Playwright + axe, Supabase mocked, no network): sign-in
  flow, wrong code, offline, Arabic RTL, dark mode.
- `test/security/dashboard_test.dart` (Flutter side, static guards) and the
  OSV scan of `dashboard/package-lock.json`; see
  [`../security.md`](../security.md) → "Captain dashboard".

## Demo & post
- **Hook:** "Your gym, from your laptop: sign in with a code, no password."
- **Scenario** (the Playwright sign-in flow, Supabase mocked): open the
  dashboard, type the owner's email, get the code, type it, land on "My gyms"
  with the gym card and its member count, open it, switch to Arabic (the page
  flips to RTL) and to dark mode.
- **Caption (EN):** "Azm now has a captain dashboard. Sign in with a one-time
  code, see your gyms, and soon invite members with a QR card. No passwords."
- **Caption (AR, Egyptian):** "لوحة الكابتن بتاعة Azm وصلت! تدخل بكود على
  إيميلك من غير باسورد، وتشوف جيماتك، وقريب تدعو الأعضاء بكارت QR."
- **Hashtags:** #Azm #GymApp #BuildInPublic #Supabase #Preact #Egypt

## What's next
D1 (members and invites: boards 1.1 to 1.7), then D2 to D5 as in the table
above. D4 needs a backend change, so it gets its own migration, RLS and pgTAP
file first.
