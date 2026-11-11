# Gym accounts — design decision

Date: 2026-11-02 · Status: **accepted** — design approved 2026-11-02; the backend (delivery step 2) is built, see §15. Items 4–8 of §2 are confirmed when their implementation PR starts · Owner: Mohamed

Design board (Claude Design, approved; linked from `docs/design.md`):
https://claude.ai/artifact/XjCnp9ZLUVZ57o7pJ7odBu

Azm today is solo: no account, everything on the phone. This adds *gyms*: a
captain creates trainee accounts, the trainee joins by scanning a QR, and the
captain can shape the trainee's plan. Solo mode stays exactly as it is.

## 1. Decided (by the product owner)

- **Solo mode stays**: no account, on-device, as today.
- **Captain/owner creates the trainee account.** The trainee never gets a
  password. The QR holds an invite link
  `https://azmm.pages.dev/join/<code>`: single use, expires in 7 days,
  revocable, bound to the first device. The same 6-character code is printed
  under the QR for manual entry. The gym logo sits in the QR centre
  (error correction **H**, logo ≤ 20 %).
- **Links**: the https link opens the app when installed (Universal Links /
  App Links); otherwise `website/join.html` shows the store buttons and the
  code. `azm://join/<code>` is the custom-scheme fallback.
- **Roles**: `owner`, `captain`, `trainee`. A captain grants each trainee
  permissions: *edit targets* / *edit the whole plan* / *build own plan*.
- **Several gyms** per trainee, one active at a time; **history belongs to
  the person**.
- **Captain's plan change wins**; the trainee sees a toast "Your captain
  updated your plan".
- **Membership ended**: a gym setting (owner/captain) decides: history stays
  **readable** or is **locked**.
- **Two surfaces** (added after design review): the **mobile app is for
  trainees**; owners and captains run the gym from a **web dashboard**
  (members, permissions, plans, invites, QR cards, gym settings). ~~The phone
  keeps only a small captain companion~~ **Changed 2026-11-03 (product
  owner): the app has no captain tools at all.** Everything a captain needs,
  including the QR cards and plan sharing (§20), is in the dashboard.

## 2. Things in the brief that need a decision or conflict with the repo

| # | Point | Recommendation (used in this doc) |
|---|---|---|
| 1 | **Scheme** — resolved by #18: the app now registers `azm://`. | Nothing to do. |
| 2 | **Host** — resolved by #18: the site is on Cloudflare Pages, `https://azmm.pages.dev`, with `.well-known` at the root. | Nothing to do. |
| 3 | **Link shape** — decided: follow `main`. The invite link is the **path** `https://azmm.pages.dev/join/<code>` (and `azm://join/<code>`), exactly what #18 ships (AASA `/join/*`, Android `pathPrefix="/join/"`). No query string, so no config change. | Nothing to do. The earlier brief wrote `?c=<code>`; that spelling is dropped everywhere. |
| 4 | **"Logo ≤ 20 %"** is ambiguous. 20 % of the *area* (≈ 45 % of the width) is too near the limit of level H (30 % recoverable). | Logo box side ≤ 20 % of the QR side (≈ 4 % of the area). CI renders the QR with the logo at three sizes and decodes it (zxing). |
| 5 | **6-character code = the secret.** A 31-letter alphabet (no `0 O 1 I L`) gives ≈ 8.9 × 10⁸ codes (≈ 29.7 bits). Fine with throttling, weak without. | Throttle redeem attempts (§5), store only an HMAC of the code, keep it single-use and 7 days. If throttling proves too weak, the *link* (not the typed code) can carry a longer token — no UI change. |
| 6 | **Who creates a gym / who signs the owner and captain in?** The brief covers trainees only. An owner on an anonymous session loses the gym with the phone. | Owners sign in with **email one-time code**. A captain is invited like a trainee, then must **add an email** before issuing invites. Gyms are created by the developer for pilot gyms (no self-service gym creation in v1). **Needs your OK.** |
| 7 | **"Locked" history vs. the person owning it** (and privacy law access rights). | Locked hides the gym's sessions from the app and RLS; it never deletes them. The person can still export or delete everything (account deletion) and ask by email. **Needs your OK.** |
| 8 | **Minors.** Gyms may enrol under-18s. The policy says the app is not directed at children under 13. | The gym is responsible for guardian consent; the privacy policy says so. **Needs your OK.** |

## 3. Supabase tables

All in `public`, RLS **enabled on every table**, created in new migration
files (`supabase/migrations/0005_gym_accounts.sql` onward), each with a pgTAP
file in `supabase/tests/`. Ids are `uuid` (`gen_random_uuid()`), times are
`timestamptz`.

| Table | Columns (main) | Notes |
|---|---|---|
| `gyms` | `id`, `name` (≤ 60), `logo_path`, `history_after_end` (`readable`\|`locked`, default `readable`), `is_demo`, `created_at`, `deleted_at` | Logo in Storage bucket `gym-logos` (`<gym_id>/logo.png`, ≤ 512 KB, png/jpeg). |
| `people` | `id`, `auth_user_id` (unique, → `auth.users` **on delete cascade**), `display_name` (≤ 40), `locale`, `created_at` | The **person**. History hangs on `people.id`, not on the auth user, so a lost phone can be re-bound (§6). |
| `memberships` | `id`, `gym_id`, `person_id` (null until the invite is redeemed), `display_name` (typed by the captain), `role` (`owner`\|`captain`\|`trainee`), `status` (`pending`\|`active`\|`ended`), `can_edit_targets`, `can_edit_plan`, `can_build_own_plan`, `created_by`, `joined_at`, `ended_at`, `ended_by` | `unique (gym_id, person_id)`. Created by the captain *before* the trainee exists: that is "the captain creates the account". Permission booleans are meaningful for trainees only (`can_edit_plan` implies `can_edit_targets`; a check constraint enforces it). |
| `invites` | `id`, `gym_id`, `membership_id`, `kind` (`join`\|`recover`\|`demo`), `code_hmac`, `expires_at` (= created + 7 days), `used_at`, `bound_install_id`, `revoked_at`, `created_by`, `created_at` | Only the HMAC of the code is stored (pepper in Vault, §5). `demo` is the only reusable kind and only for `gyms.is_demo`. |
| `invite_attempts` | `id`, `auth_user_id`, `ip_hash`, `ok`, `at` | Throttle + audit; rows older than 30 days are purged. No RLS policies at all (only the `redeem_invite` function touches it). |
| `plans` | `id`, `membership_id` (unique), `body` (jsonb, same shape as the on-device plan), `version` (int), `updated_by` (membership id), `updated_at` | One plan per membership. Written **only** through `save_plan` (§4). |
| `workout_sessions` | `id`, `client_id` (unique per person, idempotent upload), `person_id`, `gym_id` (null = solo), `membership_id` (null = solo), `day_id`, `started_at`, `finished_at`, `sets` (jsonb), `created_at` | Same shape as `WorkoutSession`. `gym_id` is the *active workspace when it was logged*. |

Not stored: the camera image, the typed code in plain text, any hardware id.
`install_id` is a random UUID generated at first launch and kept in secure
storage; it is not a device identifier.

Helper functions (`security definer`, `stable`, `set search_path = ''`, owned
by a role that cannot log in; execute granted to `authenticated` only):
`current_person_id()`, `my_role_in(gym_id)`, `i_manage(gym_id)` (active owner
or captain), `i_manage_person(person_id)`.

RPCs (the only way to do the things RLS alone cannot express):
`redeem_invite(code, install_id)`, `create_invite(membership_id, kind)`
(returns the plain code once), `revoke_invite(id)`, `end_membership(id)`,
`leave_gym(id)`, `save_plan(membership_id, base_version, body)`,
`import_solo_data(sessions, plan)`. Edge Function: `delete-account` (needs the
service key, §8).

## 4. RLS rules — who reads and writes what

Every policy is `to authenticated`. Remember: **anonymous Supabase users get
the `authenticated` role** (their JWT has `is_anonymous = true`), so no policy
may rely on the role alone — each one is tied to a membership. The `anon` key
role gets **nothing** on any new table.

| Table | trainee (own rows) | captain | owner |
|---|---|---|---|
| `gyms` | read gyms where they have a membership; if `ended` and `history_after_end = locked`, name only (no sessions, §below) | read own gym; update `history_after_end`, `name`, `logo_path` only (column grants) | same + soft-delete |
| `people` | read/update own row (`auth_user_id = auth.uid()`) | cannot read (they see `memberships.display_name`) | same |
| `memberships` | read own; no direct writes (`leave_gym` RPC) | read the gym's; update **trainees'** permission flags and `status` | read the gym's; update anyone's role/flags/status except demoting the last owner |
| `invites` | none | read/insert/revoke for **trainee** memberships in their gym | all invites in their gym, including captain invites |
| `plans` | read own membership's plan; **no direct write** | read the gym's plans; no direct write | same |
| `workout_sessions` | read/insert/update/delete own (`person_id = current_person_id()`); sessions of an ended gym hidden when `locked`; insert only with `gym_id` null or a gym where the membership is `active` | read sessions with `gym_id` = their gym **and** the person's membership there `active` (never solo sessions, never other gyms') | same |
| `invite_attempts` | none | none | none |

- **Plan writes** go through `save_plan(membership_id, base_version, body)`:
  1. caller is the membership's person *or* a manager of that gym;
  2. `base_version` must equal the stored `version`, else it fails with
     `plan_changed` (the client refetches and shows the toast);
  3. validates `PlanLimits` server-side (same limits as the app: 1–14 days,
     ≤ 30 exercises a day, names 1–40, sets 1–10, reps 1–100, rest 0–600 s,
     step 0 < x ≤ 50, body ≤ 64 KB);
  4. for a trainee it diffs old vs new: only target fields changed →
     needs `can_edit_targets`; days/exercises added, renamed, removed or
     reordered → needs `can_edit_plan`; a membership with no plan yet →
     needs `can_build_own_plan`. Day and exercise **ids are never reused**;
  5. a manager's write always succeeds (captain wins) and stores
     `updated_by`; the trainee's next sync sees `version` / `updated_by`
     change and shows "Your captain updated your plan".
- **Ending a membership** (`end_membership`): `status = ended`, `ended_at`.
  The plan is no longer readable by the person; managers lose access to that
  person's sessions at once. Whether the *person* still reads the gym's
  sessions follows `gyms.history_after_end`.
- **Owner/captain management writes** also carry a restrictive policy
  `(auth.jwt()->>'is_anonymous')::boolean is not true`, so a management
  action needs a permanent (email) session. (Supabase docs: pair every
  restrictive policy with a permissive one.)
- **Storage** `gym-logos`: members read `<gym_id>/*`, managers write; nobody
  lists the bucket.
- pgTAP files prove: anon role gets nothing; trainee A cannot read or change
  trainee B's sessions, membership, plan; a trainee of gym 1 cannot read gym 2;
  a captain cannot edit another captain or the owner; a captain cannot read
  solo sessions; `locked` hides sessions; a used / expired / revoked / wrong
  install code fails; `save_plan` rejects structure edits without
  `can_edit_plan`; an anonymous session cannot manage a gym.

## 5. Invite flow, step by step

**Captain (permanent session)**
1. Gym → Members → **Add trainee**: types the name, picks permissions
   (edit targets / edit whole plan / build own plan), optionally a starting
   plan. This inserts a `memberships` row (`pending`, no person).
2. `create_invite(membership_id, 'join')` generates a 6-character code
   (alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, from `gen_random_bytes`),
   stores `HMAC-SHA256(pepper, code)` and `expires_at = now() + 7 days`,
   and returns the plain code **once**. The app builds the QR from
   `https://azmm.pages.dev/join/<code>` (level H, logo ≤ 20 % of the side)
   and prints the code under it. Share sheet: image / PDF / copy link.
   Lost the printout? **Revoke and re-issue** (the code cannot be shown again).
3. Revoke any time (`revoke_invite`). Pending invites show "expires in n days".

**Trainee**
4. Scans the QR with the camera or in-app scanner, taps the link, or types the
   code. The link opens the app (Universal/App Link), else `azm://join/<code>`,
   else `join.html` (store buttons + the code, §7).
   - A **link** opens the *Enter code* screen with the code prefilled — it
     never redeems by itself. The in-app **scanner** submits at once (the
     person deliberately scanned).
   - `join.html` and link-preview bots only read a static page: they cannot
     consume a code.
5. The app ensures a session: if there is none, `signInAnonymously()` (§6)
   with a CAPTCHA token; it keeps the existing one if the person is already
   signed in (second gym).
6. `redeem_invite(code, install_id)` (one transaction, `security definer`):
   1. throttle: ≤ 10 failed attempts per hour per `auth.uid()`, ≤ 30 per hour
      per IP hash (`request.headers` → `x-forwarded-for`), and a global
      breaker (> 200 failures in 10 min → CAPTCHA required for everyone);
   2. look up the HMAC; row-lock it;
   3. reject, with distinct reasons, `not_found`, `expired`, `revoked`,
      `used` (the same `install_id` retrying is idempotent success);
   4. get-or-create `people` for `auth.uid()`;
   5. set `memberships.person_id`, `status = active`, `joined_at`;
      `used_at = now()`, `bound_install_id = install_id`;
   6. return `{gym, role, permissions}`; the app shows **Joined <gym>**,
      makes it the active workspace and offers to bring solo data (§9).
7. Errors are shown as: invalid, expired, already used, offline, camera
   denied. The message never says whether a code ever existed.

**Recover (lost phone / reinstall)**: captain → member → **New code for
<name>** → `create_invite(membership_id, 'recover')` → the trainee redeems on
the new phone → `people.auth_user_id` moves to the new auth user. RLS keys on
`people.auth_user_id`, so the old session is cut off the moment the row
changes. Allowed only if the person has **no other active gym** (otherwise a
captain could take over data from another gym); in that case the person
re-joins through the invite of any gym and the captains of the others are
unaffected. An optional "add email" (v2) lets a person recover without a
captain.

## 6. How the sign-in session is created

**Choice: Supabase Auth anonymous sign-ins** (`signInAnonymously()`), then
the invite is redeemed with the RPC above. Owners/captains use email OTP.

Why: the trainee must have a real, persistent, refreshable session with a
stable `auth.uid()` and the `authenticated` role (so RLS works), but no
email, password or phone. Anonymous users give exactly that. Alternatives
rejected:
- *Edge Function creating a user with the admin API and minting a session*:
  needs the service key in a function on the hot path and hand-made
  sessions; more code and more risk for the same result.
- *Email/phone for every trainee*: contradicts "the trainee never gets a
  password" and collects personal data we don't need.
- *Custom JWT signed by us*: bypasses Auth's refresh, revocation and logs.

Facts used (docs **supabase/supabase** `apps/docs/content/guides/auth/auth-anonymous.mdx`,
`master`, read **2026-11-02**; the page shows no version number):
- Enable *Anonymous Sign-Ins* in the project's Auth providers; call
  `signInAnonymously()`.
- Anonymous users get the `authenticated` role; the JWT carries
  `is_anonymous`; this differs from the `anon` API key.
- RLS can read `is_anonymous` from `auth.jwt()`; use restrictive policies
  paired with permissive ones.
- They can later be made permanent with `updateUser()` (email/phone) or
  `linkIdentity()` after enabling manual linking.
- Abuse: the docs recommend CAPTCHA / Turnstile; an IP limit of **30
  anonymous sign-ins per hour** applies by default.
- No automatic cleanup: delete stale anonymous users (e.g. > 30 days without
  a membership) with a scheduled SQL job.

**Not verified in this session** (supabase.com and support.google.com were
not reachable from the cloud environment): token/refresh lifetime settings,
the `auth.admin.deleteUser` reference, `pg_cron` availability on our plan,
the current `supabase_flutter` and scanner package versions, and Google
Play's account-deletion page. **Read them before implementing** (CLAUDE.md →
"check first, then build") and fix this section if anything differs.

Session details:
- Anonymous sign-in happens **only when the person redeems a code**, never at
  launch, so solo users never create an auth user.
- The refresh token lives in the platform secure storage (supabase_flutter
  default); **sign out of an anonymous account is irreversible on that phone**
  — the profile screen warns and says to ask the captain for a new code.
- CAPTCHA: Cloudflare Turnstile (Cloudflare Pages is already the host). Its
  site key is publishable; its secret goes in Supabase Auth settings only.
- The HMAC pepper is a Supabase Vault secret; no secret is added to the app
  or `env/*.json`.

## 7. Links, website and platform setup

- Already shipped by #18: scheme `azm://`, `applinks:azmm.pages.dev`
  (`Runner.entitlements`), AASA + `assetlinks.json` (Play fingerprints in),
  `website/_headers` (JSON content types, strict CSP, `Referrer-Policy`,
  `Permissions-Policy: camera=()` for the website), `well_known_test.dart`.
  Still to change for invites: the app-side handler (today `/join/<code>`
  just opens Home and reads nothing; it must open the Enter-code screen with
  the code filled in, and never join by itself).
- Apple caches the AASA through its CDN, so test on a real build, not only
  the simulator.
- `website/join.html` (EN + AR like the other pages): "Open in Azm", App
  Store, Google Play, and "Your code: ABC123". It must fit the site's CSP
  (`default-src 'none'; script-src 'self'; connect-src 'none'`): **no inline
  script or style**, one external `assets/join.js`. It reads the code, accepts
  only `^[A-HJ-KM-NP-Z2-9]{6}$` (uppercased), writes it with `textContent`
  (never `innerHTML`), loads no third-party script, never calls the backend,
  and adds `<meta name="robots" content="noindex">`. The existing
  `strict-origin-when-cross-origin` referrer policy already sends only the
  origin to other sites; a `/join*` override to `no-referrer` is optional.
  Because the site CSP has `connect-src 'none'`, the page cannot check a code,
  which is what we want.
- `docs/deep_links.md` gets the final `/join` shape, and
  `test/security/deep_link_test.dart` gets: no code (`/join`), empty, too long,
  lower case, injection-like (`<script>`, `'; drop`, `javascript:`), unicode,
  extra segments (`/join/ABC123/extra`), a trailing slash, an `https://evil.example` as the code, percent-encoded characters.
  A link can only open the Enter-code screen.
- **Dashboard hosting**: the marketing site's CSP is `connect-src 'none'`
  and must stay that way, so the dashboard is a **separate web app on its own
  origin** (its own Cloudflare Pages project, e.g. `azmm-dash.pages.dev`) with
  its own CSP that allows only our Supabase project and Turnstile. It never
  shares an origin with `join.html`. Stack: **decided, a plain web app, not
  Flutter web**; it is **not built yet** (delivery step 0). The rules are the
  same RLS and RPCs, and its sign-in is email one-time code
  (permanent session, as §4 requires). Boards 10–12 in the design.
- App route `/join` (name `join`), `/join/scan` (`join_scan`), `/gym` switcher,
  `/profile`. Screen names feed analytics.

## 8. Store requirements

- **In-app account deletion (Apple 5.1.1(v), Google Play).** Apple's
  guideline (read 2026-11-02): "If your app supports account creation, you
  must also offer account deletion within the app." Anonymous accounts are
  accounts, so Profile → **Delete account** exists for everyone with an
  account. Flow: warning with what is deleted → confirm (type the gym name
  for owners) → Edge Function `delete-account` (service key only in the
  function's secrets) verifies the JWT, then `people` → cascades sessions,
  memberships, plans (`invites.created_by` set null), then
  `auth.admin.deleteUser`. An owner who is the only owner of a gym with
  members must transfer ownership or delete the gym first. Solo data on the
  phone is separate: "Also erase workouts on this phone" is a checkbox.
- **`website/delete-account.html`** is updated: path Profile → Delete
  account; trainees without email can request deletion by writing from the
  email of their gym owner (we confirm with the gym); permanent, within
  30 days. Google Play needs this URL in the Data safety form.
- **Demo gym for App Review** (Apple 2.1: "include demo account info … a
  sample QR code"): gym "Azm Demo Gym" (`is_demo`), an invite of kind `demo`
  — reusable, no expiry, only valid for that gym, trainee role with all three
  permissions on, fake data, no personal data, sessions of demo members
  wiped nightly. The code and a QR image go in App Store Connect → App
  Review notes and Play Console → App access. Rotate it each submission.
  The app is usable without any account (solo), which keeps 5.1.1 satisfied.
- **Camera permission texts** (asked only when the scanner opens, with a
  line of context first; manual entry is always offered):
  - iOS `NSCameraUsageDescription`
    - en: "Azm uses the camera only to scan your gym's QR code. Nothing is recorded or saved."
    - ar: "يستخدم عزم الكاميرا فقط لقراءة رمز QR الخاص بالجيم. لا يتم تسجيل أو حفظ أي صور."
    Localised through `en.lproj` / `ar.lproj` `InfoPlist.strings` and
    `CFBundleLocalizations`.
  - Android: `CAMERA` permission and
    `<uses-feature android:name="android.hardware.camera" android:required="false"/>`
    so the app installs on devices without a camera; the system dialog is
    localised by the OS, and the in-app rationale is in both ARB files.
- **Sign in with Apple (4.8)** does not apply: we use no third-party or
  social login. If one is added later, revisit.
- **Store forms**: Apple App Privacy — Name, User ID, Health & Fitness
  (workout data), Diagnostics; none used for tracking. Google Data safety —
  Personal info (name), Health and fitness, App activity, Device or other IDs
  (install id); data encrypted in transit; deletion requested via the web URL.
- Update `docs/release.md` (Associated Domains, Turnstile, demo code
  rotation) and `docs/security.md` in the implementation PRs.

## 9. Privacy policy changes (`website/privacy.html`, EN + AR)

Add, and move "Last updated" to the release date:
- **Gym accounts**: when you join a gym we process the display name your
  gym gives you, your role and permissions, your plan and your workout logs.
  The gym's owner and captains can see your name and the workouts you log
  while you are an active member of that gym, and can change your plan.
  They cannot see workouts you logged on your own or in another gym.
- **Sign-in without email**: a random account id and a random install id;
  no password, email or phone for trainees.
- **Camera**: used on the device to read a QR code; images are not recorded,
  stored or sent.
- **Invite codes**: stored only as a one-way hash, expire in 7 days.
- **When you leave a gym**: your data stays with you; the gym's setting
  decides whether you can still open that gym's history in the app; deleting
  your account removes it.
- **Logs**: failed code attempts keep a hashed network address for 30 days
  to stop guessing.
- **Retention and deletion**: link to Delete account (updated).
- **Minors**: gyms are responsible for guardian consent for under-18s.
- Providers: Supabase, PostHog, Sentry as before, plus Cloudflare (hosting
  the website, Turnstile).
- Analytics (`Analytics.capture`) gets no names, codes or ids:
  `gym_join_started`, `gym_joined` (`via: scan|link|code`),
  `gym_join_failed` (`reason`), `gym_switched`, `plan_updated_by_captain`
  shown, `account_deleted`.

## 10. Solo data → account

The device holds: the plan, up to 200 sessions, the chosen day, the level, a
draft (SharedPreferences JSON).

- After **Joined <gym>** the app asks once: **Keep my solo data** (default),
  **Add my solo history to my account**, or **Skip**.
- Solo and each gym are **workspaces**. The active workspace decides which
  plan the Home screen shows and which `gym_id` new sessions get. Solo
  remains available in the switcher forever.
- *Keep*: nothing leaves the phone; solo is a local-only workspace.
- *Add history*: `import_solo_data` uploads the sessions with
  `gym_id = null` (so gym staff never see them) and the solo plan as the
  person's personal plan. Idempotent through `client_id` (the existing
  session id), chunks of 50, resumable. Local data is kept until the server
  count matches, then marked `migrated_at`; it is deleted only after the
  user confirms or after 30 days. Offline: queued.
- The gym's plan never overwrites the solo plan; a captain's plan is a
  separate `plans` row for that membership.
- Level (`GetLevel`) is computed from all of the person's sessions.
- Deleting the account offers to erase the local copy too.

## 11. Plan conflicts

`plans.version` is the only truth. The app stores the last version it saw. On
sync, if `version` grew and `updated_by` is a manager, the app replaces its
copy and shows the toast "Your captain updated your plan" (once per version).
A trainee edit made on an older `base_version` is rejected (`plan_changed`);
it is dropped, not merged, because the captain wins. A workout in progress
keeps working (sessions point at day/exercise ids, which are never reused);
if its day was removed, it can be finished and stays in history.

## 12. Edge cases

| Case | What happens |
|---|---|
| **Shared QR photo** (someone else redeems first) | Single use + bound to the first `install_id`: the second person gets "already used". The captain's member row shows "Joined <time> · device 1"; if that is not their trainee they **End membership**, then issue a new invite. A photo of a code that already worked is useless; one that has not been used is valid for 7 days, so tell trainees not to post it. |
| **Lost phone** | Captain issues a *recover* code (§5). The old session loses access immediately (RLS follows `people.auth_user_id`). Not possible while the person has another active gym — then they join again through a normal invite (the old person row is merged by the owner of that gym or by support). Optional email (v2) removes the dependency. |
| **Reinstall** (same phone) | New `install_id`, no session → same as a lost phone. |
| **Membership ended** | Status `ended`; workspace falls back to solo; plan hidden; managers lose access to that person's sessions. Gym setting **readable**: the person keeps reading that gym's history; **locked**: those sessions are hidden (not deleted) until they re-join. Re-adding = a new invite on the same membership → history re-links. |
| **Several gyms** | One `people` row, many memberships. Switcher shows Solo + gyms; the active workspace is stored on the device and sets `gym_id` of new sessions. A captain sees only sessions with their `gym_id`. Redeeming in a second gym keeps the current session. |
| **Offline** | Redeeming needs the network: scanner/entry show "You're offline" with Retry; the code is not consumed. Already-joined people log offline as today and sync later (idempotent `client_id`). A trainee's offline plan edit that loses to a captain change is dropped with the toast. |
| **App Review** | Solo needs no account. Demo code + sample QR in the review notes; manual entry works without the camera; the demo gym is reset nightly. |
| **Camera denied** | Explain, offer **Enter code** and **Open settings**; never a dead end. |
| **Code expired / revoked / wrong** | Distinct, friendly messages; expired and revoked say "ask your captain for a new code". Attempts are throttled (§5). |
| **Link opened without the app** | `join.html` shows the store buttons and the code; after installing, the code is typed or the QR is scanned again (no deferred deep link in v1). |
| **Link opened while signed in as another person** | Enter-code screen asks to confirm; the join attaches a new membership to the current person. |
| **Captain removed / demoted** | Their issued invites stay valid until revoked; plans they made stay; `created_by` is kept for audit. |
| **Owner deletes account** | Blocked while they are the only owner with members. |
| **Brute-force guessing** | Throttles + global breaker + CAPTCHA + hashed single-use codes (§5). Residual risk: a valid code is guessable at ≈ 1 in 9 × 10⁸ per attempt. |
| **Tampered client** | RLS and `save_plan` enforce everything; the app UI is only a mirror of the rules. |
| **Clock skew** | Expiry is checked with the server's `now()`. |

## 13. Delivery plan (after the design is approved)

0. Dashboard: a plain web app on its own origin (§7, stack decided); build it after step 4
   (it needs the same tables and RPCs; the phone needs it only for the QR).
1. Website: `join.html`, `_headers`, `.well-known`, `delete-account.html`,
   `privacy.html` (docs + security tests).
2. Supabase migration + pgTAP + RPCs.
3. App: `/join` (link, scanner, code), session, workspaces + switcher, profile
   with sign out / delete.
4. Captain tools (members, permissions, QR) and `save_plan` sync + toast.
5. Solo-data import; demo gym; store forms.
Each step is its own PR with tests, feature doc (`docs/features/gym.md`),
analytics list and the demo test required by `CLAUDE.md`.

## 14. Revisit when

- Gyms ask for self-service creation, payments, or many captains per member.
- Throttling is not enough against code guessing (then: longer link token).
- Apple/Google change account deletion or anonymous-account rules.

## 15. Backend as built (delivery step 2) — where it differs from §3–§6

Feature doc: [`features/gym_accounts_backend.md`](../features/gym_accounts_backend.md).
Docs read before building, 2026-11-02, from the `supabase/supabase` repository
on GitHub (`master`; supabase.com was not reachable from the build
environment): Edge Functions *Securing Edge Functions*, *Environment
variables*, *Testing your Edge Functions*, *Managing dependencies*;
*Row Level Security*; *Vault*; *Testing your database*; and the
`@supabase/server` **1.9.2** package docs. Tooling versions: Supabase CLI
2.120.0 (pinned in CI), Deno 2.9.6, Postgres 16 for the local checks.

| Point | Decision / difference |
|---|---|
| Link shape | The invite link is the **path** `https://azmm.pages.dev/join/<code>`, as §2 #3 says. The task text that started this step wrote `/join?c=<code>`; the path form is what the apps claim, so it is what the QR holds. |
| `redeem_invite` | An **Edge Function** (rate limit, input checks, no logging) that calls the SQL function `redeem_invite_core` with the secret key. The core function is `service_role`-only because it receives the verified user id and address; one transaction, same rules as §5 step 6. It returns `{ok:false, reason}` instead of raising so the attempt row survives. |
| Session | As §6: the function does **not** mint a session; the app signs in anonymously first. "Creates or links the user" = get-or-create the `people` row for that auth user (or, for a `recover` invite, move it). |
| Helpers | `current_person_id`, `my_role_in`, `i_manage`, … live in the unexposed **`private`** schema (Supabase docs: no `security definer` function in an exposed schema unless it is meant to be called). RPCs meant for clients stay in `public` and check the caller. |
| Anonymous managers | Instead of restrictive policies, `private.i_manage()` itself requires a permanent JWT, so an anonymous session is never a manager anywhere (policies, RPCs, Storage). Same effect, one place. |
| `invites` writes | No direct insert/update for anyone (stricter than §4, which lists captain insert/revoke): codes can only be made by `create_invite` / `admin_create_invites`, revoked by `revoke_invite`. The hash column has no `select` grant. |
| `demo` kind | Not built; the `kind` check allows `join` and `recover` until delivery step 5 widens it. |
| `workout_sessions`, `import_solo_data`, `delete-account` | Later steps. |
| Throttle | As §5, in SQL. The global breaker **pauses** redeeming (429) instead of requiring a CAPTCHA, because the Turnstile secret is not set up; revisit with the app step. |
| Pepper | Generated by migration `0006` into Vault (`gen_random_bytes`), so no human ever holds it. |
| Plans | `save_plan` implements §4 items 1–5 except "ids never reused": the server keeps no id history. Plans allow exactly the keys of the on-device JSON (`days` only); a new key needs a migration. |
| Logo bucket | `gym-logos` (private, 512 KB, png/jpeg); members read their gym's folder, managers write `<gym_id>/logo.png`, `.jpg` or `.jpeg`. |
| QR cards | `scripts/make_invites` (Python, hash-pinned). The logo box is 18 % of the QR symbol's side (never above 20 %); every QR is decoded again with zxing before it is printed. |
| Still unverified (needs supabase.com) | Token/refresh lifetimes, `auth.admin.deleteUser`, `pg_cron` on our plan, `supabase_flutter` and scanner package versions, the Google Play deletion page. |

## 16. Account model confirmed (2026-11-02, product owner)

Trainees stay on **anonymous sign-in**; nothing changes in §6. Added:
1. **CAPTCHA (Cloudflare Turnstile) on anonymous sign-in is required before
   the app step ships**; it also becomes the fallback for the global breaker
   in `redeem_invite_core` (§15).
2. **Optional email upgrade** in Profile ("Secure your account"): the
   anonymous user is made permanent with `updateUser({email})`, so
   `auth.uid()`, `people`, memberships and history are unchanged and no
   migration is needed. It lets a person recover a lost phone without a
   captain. Delivery step 3/4 of §13.
3. Owners and captains keep **email one-time code** (permanent session).
4. Email is **not** mandatory for trainees (it would slow joining and widen
   the privacy policy and store forms).

Still open (needs a decision): a trainee active in **two gyms** who loses
their phone cannot be recovered by one captain (§5), so re-joining creates a
second person. Proposal: an owner-approved merge RPC, plus the email upgrade
above as the self-service route.

## 17. Backend part 2 as built (migrations 0009–0011)

| Point | Decision / difference |
|---|---|
| `workout_sessions.started_at` | Does not exist. The on-device `WorkoutSession` is `{day_id, finished_at, sets}` (no id, no start time), so `client_id` is a deterministic hash of the session's content, which makes `import_solo_data` idempotent. |
| Personal plan | New table `personal_plans` (one per person); a gym's plan stays in `plans`. Written only by `import_solo_data` for now. |
| Solo cap | 1000 solo sessions per person (the phone keeps ≤ 200). |
| Demo invite | `invites.membership_id` and `expires_at` are nullable for kind `demo` (constraints keep every other kind as before); a trigger allows it only for `gyms.is_demo`. |
| Last owner | `account_deletion_blockers()` plus a `BEFORE DELETE` trigger on `memberships`; deleting a whole gym still works. |
| `pg_cron` | Not created by a migration (unverified on our plan); `schedule_maintenance()` schedules the jobs when the extension is on. |

## 18. The app as built (delivery step 3, PR B) — where it differs from §5–§12

Feature doc: [`features/gym_account_app.md`](../features/gym_account_app.md).

| Point | Decision / difference |
|---|---|
| Switcher | A **sheet** (board 4), not a `/gym` route (§7). The only new routes are `/welcome`, `/join/scan`, `/join/joined`, `/profile`, `/profile/delete`. |
| Join routes | `/join/<code>`, `/join/scan`, `/join/joined` are top-level routes (not children of `/join`): a child stacks on an empty enter-code screen and both react to the same result. `scan` and `joined` precede `:code`; paths are case sensitive. |
| First screen | Only the choose-your-path page of board 1 is built; pages 1–3 do not exist in the app. Shown once, never to people with a plan or an account. |
| Session storage | `SecureLocalStorage` (Keychain `first_unlock_this_device` / Android Keystore); a Keychain session of an earlier install is dropped on a fresh install (§12 "Reinstall"). |
| Captain name, logo | Not shown: RLS gives a trainee no read on the captain's row and `redeem_invite` does not return it; the logo is not downloaded (initials tile). Both need a small backend addition. |
| Workspaces | Stored and refreshed, but **Today still shows the on-device plan** for every workspace and new workouts carry no `gym_id` yet (§13 step 4). A missing or ended active membership → solo. |
| Email upgrade | "Add email" calls `updateUser(email)` (§16 #2). Signing back in with that email needs an email one-time-code screen, not built yet. |
| Turnstile | Seam only (`captchaToken`, `null`); required before the flag goes on. |
| Last-owner delete | An owner types the name of the first gym they own (alphabetical); the server decides about the rest (`409 last_owner`). |

## 19. Solo data import as built (delivery step 5, PR C) — where it differs from §10

| Point | Decision / difference |
|---|---|
| Choices | *Keep* (default, never asked again), *Add my solo history to my account*, and a third, *Decide later* (asked again at the next join; always in My account). |
| Resume | Not a stored cursor: a run always restarts from the first workout and the server skips what it has (`client_id` is content-derived), so a stale cursor cannot lose a workout. |
| Filter | Workouts the server's validation would refuse are kept on the phone and not sent, so one bad workout never blocks its chunk. |
| Confirmation | `done` when `solo_total` ≥ the number of workouts sent. |
| Local copy | **Never deleted automatically** (§10 said "after the user confirms or after 30 days"): not built; the person can erase it with Delete account. |
| Offline | Retry; no background queue (§10 said "queued"). |

## 20. Exercise library and plan sharing (2026-11-03)
The app is for trainees only; the dashboard is where captains work.

**In the app (built, `docs/features/exercise_library.md`):** a shared exercise
library (stable ids, names in both languages, muscle, equipment, 2–3 steps,
a placeholder picture until session 8). The plan editor's "Add an exercise"
offers *Pick from the library* or *Write your own*. A member can add
exercises only if the gym lets them (`edit_plan`, or `build_own_plan` for the
first plan); the library never changes a gym plan by itself.

**In the dashboard (specified here, not built; design boards "Dashboard 5, 6"
of https://claude.ai/artifact/26EDAr572B4Qr8eBLB4D75):**
- **Copy a member's plan to other members.** Each gets an independent copy
  (later edits to one never change the others). A member who already has a
  plan has it replaced, after a clear warning; history is never touched and
  exercise ids stay as they are. Uses the existing `save_plan` per target
  (a manager's write always wins and the member sees the toast), so no new
  right is needed, only a loop in the dashboard.
- **Gym templates.** "Save as a gym template" stores a plan body for every
  captain of the gym to start from; "Replace with a template" applies one to a
  member (same copy rule). **Needs a backend step:** a `plan_templates` table
  (gym_id, name, body, created_by; RLS: the gym's managers read and write,
  nobody else), the same body limits as `plans` (`private.plan_problem`), and
  pgTAP.
- **Change one exercise for one member.** The member's plan is edited in place
  through `save_plan`; the dashboard shows what differs from the template the
  plan started from. **Needs a backend step:** `plans.template_id` and
  `plans.template_version` (nullable) set when a template is applied, so the
  dashboard can diff and offer *Reset* per exercise. "Apply a change to
  everyone on this template" is a loop over those plans, each through
  `save_plan`, behind a confirmation that lists the members.
- Library content in the dashboard (the same catalog) is read from the app's
  list until it moves to the server; `ExerciseLibrary` is the seam.
- **As built (D3, 2026-11-10):** copy works as described, from the member's
  *saved* plan. One difference: `save_plan` checks `base_version` for trainees
  only, so a manager's save would silently overwrite a change made meanwhile;
  the dashboard reads the version just before saving and shows what changed
  instead. The remaining window (between that read and the save) needs a
  server-side check for managers too; proposed with the D4 migration.
  Feature doc: [`features/dashboard.md`](../features/dashboard.md) → "D3".


## 21. Captain dashboard D0 as built (2026-11-04)
Feature doc: [`features/dashboard.md`](../features/dashboard.md). Board:
https://claude.ai/artifact/8dPMf6CPxewxFRgtjovg1P (D0 + D1, approved
2026-11-04; boards 10–12 of the gym-accounts board could not be opened, so it
was drawn from the Design System and the exercise media board).

| Point | Decision / difference |
|---|---|
| Deploy | Cloudflare Pages' own **Git integration** (project `azmm-dash`, root `dashboard`), like the website: no deploy workflow and no Cloudflare token in GitHub. |
| Turnstile (§7) | Optional: used only when `VITE_TURNSTILE_SITE_KEY` is set. Supabase CAPTCHA protection covers sign-in, so the key must be set before protection is turned on; the CSP adds `challenges.cloudflare.com` only then. |
| `end_membership` (§3) | There is no such RPC. Ending a membership is `update memberships set status = 'ended'`, which the column grant, the "managers update members" policy and `memberships_guard` already allow (D1). |
| First owner | No RPC creates an owner. A runbook in the feature doc: the owner adds the auth user in Supabase and runs two inserts in the SQL editor by hand. Captains join in the app, add an email, then sign in to the dashboard. |
| Unknown email | `shouldCreateUser: false`; Supabase answers 422 `otp_disabled`, and the dashboard shows the same "check your email" screen (no enumeration). |
| Members page | D0 ships the shell with a placeholder; the list comes with D1. |
| Release | `scripts/next_version.sh` ignores commits that touch only `dashboard/`. |
