# Feature: gym accounts — backend

> Step 2 of the delivery plan in [`../decisions/gym_accounts.md`](../decisions/gym_accounts.md) §13.
> No screen yet: this is the database, the Edge Function and the owner's
> invite tool the app and the dashboard will use.

## What it does
- **Gyms, people, memberships, plans, invites** with Row Level Security on
  every table, so a trainee reads only their own rows, a captain only their
  own gym's, and the `anon` role nothing.
- **`redeem_invite`** (Edge Function): the trainee's app sends the code from
  the QR (or typed) together with its install id; the function checks it and
  links the trainee to the gym.
- **`scripts/make_invites`** (run by the owner on their own computer): creates
  N invites for a gym and prints a PDF of QR cards.

## Files
| What | Where |
|---|---|
| Tables, helpers, RLS: gyms, people, memberships, `leave_gym` | `supabase/migrations/0005_gym_accounts.sql` |
| Invites, attempts, pepper, `create_invite`, `revoke_invite`, `admin_create_invites`, `redeem_invite_core` | `supabase/migrations/0006_gym_invites.sql` |
| Plans and `save_plan` (server-side `PlanLimits`) | `supabase/migrations/0007_gym_plans.sql` |
| The 5-day template's real days 4 and 5: stored plans whose days 4/5 are still untouched copies of days 1/2 get them (`private.template_days_upgrade`, one-off update, version + 1) | `supabase/migrations/0018_template_days_4_5.sql`, `supabase/tests/template_days_4_5.test.sql` |
| `gym-logos` Storage bucket and its policies | `supabase/migrations/0008_gym_logos_storage.sql` |
| pgTAP, one file per table (+ redeem and storage) | `supabase/tests/*_rls.test.sql`, `redeem_invite.test.sql`, `gym_logos_storage.test.sql` |
| Edge Function | `supabase/functions/redeem_invite/` (`index.ts` wiring, `handler.ts` HTTP layer, `validate.ts` input checks, Deno tests next to them) |
| Invite tool | `scripts/make_invites/` (`run.sh`, `make_invites.py`, tests, hash-pinned `requirements.txt`) |
| Static guards | `test/security/supabase_backend_test.dart` |

## Data model (short; the full table is in the decision doc §3)
- `gyms` — name, `logo_path` (`<gym_id>/logo.png|jpg|jpeg` in `gym-logos`),
  `history_after_end` (`readable` | `locked`), `is_demo`, `deleted_at`.
- `people` — one per auth user (`auth_user_id`, cascade on user deletion).
- `memberships` — gym, person (null until redeemed), role, status
  (`pending` → `active` → `ended`), three permission flags (trainees only;
  *edit plan* implies *edit targets*).
- `invites` — **`code_hmac` only** (HMAC-SHA256 with a pepper in Supabase
  Vault; the column that would hold a code does not exist), kind `join` |
  `recover`, `expires_at` ≤ 7 days, `used_at`, `bound_install_id`,
  `revoked_at`, `created_by`. Managers can list invites but the hash column
  is not granted to anyone: use explicit column lists, not `select *`.
- `invite_attempts` — throttle and audit rows (hashed address). No policies:
  nobody reads it through the API. Purged after 30 days.
- `plans` — one per membership: `body` (the on-device `WorkoutPlan` JSON),
  `version`, `updated_by` (a membership id).

## Who can do what
| | anon | trainee | captain of **another** gym | captain / owner |
|---|---|---|---|---|
| read gyms, memberships, plans | nothing | own | nothing of this gym | their gym's |
| change permissions, end a member | no | no (only `leave_gym` on themselves) | no | trainees (captain) / anyone but the last owner (owner) |
| invites | no | no | no | list, `create_invite`, `revoke_invite` for trainees (owner: also captains) |
| save a plan | no | `save_plan` within their flags | no | `save_plan`, always succeeds (captain wins) |

- Anonymous **sessions** (trainees) never count as managers: `private.i_manage`
  requires a permanent JWT (`is_anonymous` not true). A captain must add an
  email first.
- Everything is proven by pgTAP: anon, a trainee, another trainee of the same
  gym, a captain of another gym, the same captain on an anonymous session and
  the owner.

## RPCs
| Function | Who | Does |
|---|---|---|
| `create_invite(membership_id, kind)` | manager (permanent session) | returns `{invite_id, code, expires_at}`; **the code is shown once**; unused older invites of that member are revoked |
| `revoke_invite(invite_id)` | manager | sets `revoked_at` |
| `leave_gym(membership_id)` | the member | ends their own membership |
| `save_plan(membership_id, base_version, body)` | member (with flags) or manager | validates `PlanLimits`; errors `forbidden` (42501), `invalid_plan: <why>` (22023), `plan_changed` (P0001) |
| `admin_create_invites(gym, count, names, flags…)` | **secret key only** | N pending trainee memberships + N invites in one transaction |
| `redeem_invite_core(auth_user, code, install_id, ip)` | **secret key only** (the Edge Function) | the single transaction behind `redeem_invite` |
| `purge_invite_attempts()` | secret key only | deletes attempts older than 30 days |

## Edge Function `redeem_invite`
`POST /functions/v1/redeem_invite`, `Authorization: Bearer <the user's access
token>` (anonymous or permanent), `Content-Type: application/json`:
```json
{ "code": "ABC234", "install_id": "<uuid generated at first launch>" }
```
Exactly these two fields; anything else is `400`. The code is trimmed and
upper-cased; only the 31-letter alphabet (`A-H J K M N P-Z 2-9`) is accepted.

The session is **not** minted here (gym_accounts.md §6): the app calls
`signInAnonymously()` first (with a CAPTCHA token), keeps that session, and
redeems with it. The function links *that* auth user to a `people` row (or
reuses the existing one) and activates the membership.

| Status | Body | Meaning |
|---|---|---|
| 200 | `{ok:true, gym:{id,name,logo_path,history_after_end}, membership_id, role, permissions:{edit_targets,edit_plan,build_own_plan}}` | joined (the same phone retrying gets the same 200) |
| 400 | `invalid_request` | wrong types, extra fields, bad characters or length |
| 401 | `unauthorized` | no valid session |
| 404 | `not_found` | unknown code (or deleted gym, or a code that no longer fits its member) |
| 409 | `used` / `conflict` | already used by another phone / this person is already in this gym or has another identity |
| 410 | `revoked` / `expired` | ask the captain for a new code |
| 413 / 415 / 405 | | body over 1 KB / not JSON / not POST |
| 429 | `throttled` + `Retry-After: 600` | too many wrong attempts |
| 500 | `server_error` | nothing else is revealed |

The app shows friendly messages; none says whether a code ever existed beyond
these reasons.

**Rate limit** (in Postgres, so it is shared by every function instance): ≤ 10
failed attempts per hour per auth user, ≤ 30 per hour per address (HMAC of the
address, kept 30 days), and a global pause when more than 200 attempts fail in
10 minutes. Throttled calls are not recorded, so a lock ends by itself. With
a 29.7-bit code, one address gets ≤ 30 guesses an hour (≈ 3 × 10⁻⁸ of the
space); a botnet is stopped by the global breaker. The breaker is a
deliberate trade-off: someone can pause joining for ten minutes by failing
200 times; the decision doc's CAPTCHA fallback needs a Turnstile secret that
is not set up yet (see "Not done").

**Never logged:** codes, install ids, tokens, addresses. The only log lines
are fixed texts and a database error *code* (tested).

## Make the QR cards (owner, on your computer)
```bash
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_SECRET_KEY=…          # from your password manager
scripts/make_invites/run.sh --gym <gym-uuid> --count 20 --edit-targets
```
- `--names names.txt` (one name per line), `--logo logo.png` (else the gym's
  logo from Storage), `--out cards.pdf` (default `~/azm-invites/…`, mode 0600,
  refused inside the repo), `--edit-targets` / `--edit-plan` /
  `--build-own-plan` for the permissions.
- `--dry-run --count 6` draws sample cards without touching any server.
- Four cards per A4 page: QR (error correction **H**, logo box ≤ 20 % of the
  QR's side, checked by decoding every QR again), the manual code, the link
  `https://azmm.pages.dev/join/<code>` and English + Arabic instructions.
- The link is the **path** form `https://azmm.pages.dev/join/<code>` that the
  apps already claim (decision doc §2 #3); the earlier `?c=<code>` spelling
  is not used.
- Codes exist only on the PDF. Print it, delete it, never send or upload it.
  Lost a card: revoke that invite and make another.
- It refuses to run when `CI` or `GITHUB_ACTIONS` is set and never prints the
  key or a code. Details: `docs/security.md`.

## Tests
- `supabase test db` — pgTAP (CI `security` job): 313 assertions across
  `gyms`, `people`, `memberships`, `invites`, `invite_attempts`, `plans`,
  `redeem_invite_core` (hostile codes, replay, expiry, revoke, conflict,
  recover, 40-guess brute force, per-address and global breaker) and the
  logo bucket.
- `deno test` in `supabase/functions/redeem_invite/` — input parsing (wrong
  types, huge strings, unicode look-alikes, `__proto__`), the HTTP layer
  (statuses, replay, brute force, methods, auth), and that nothing secret
  reaches the log.
- `python -m unittest discover -s scripts/make_invites` — QR decodes with the
  logo at three sizes, refuses > 20 %, hostile arguments/logos/names, no
  secret printed, invites revoked if the PDF cannot be made.
- `flutter test test/security/supabase_backend_test.dart` — RLS on every
  table, a pgTAP file for each, definer functions pin `search_path` and are
  closed to anon, no literal Vault secret, the function logs nothing.

## Part 2: sessions, solo import, demo gym, account deletion
Migrations 0009–0011, Edge Function `delete-account`, `make_invites --demo`.

| Piece | What it does |
|---|---|
| `workout_sessions` | A person's history: `client_id` (unique per person), `gym_id` / `membership_id` (null = solo), `day_id`, `finished_at`, `sets` (validated: ≤ 500 sets, weight 0–1000, reps 0–1000, ids `[A-Za-z0-9_-]{1,64}`, ≤ 64 KB). RLS: a person reads, logs, edits and deletes their own; **staff read only their gym's sessions, only while that member is active, never solo ones**; a `locked` gym hides an ended member's gym sessions from them (never deletes). The app has no session id or start time, so `client_id` is a hash of the session's content and `started_at` does not exist. |
| `personal_plans` | The person's own plan (the solo plan moved into the account). Read-only for clients. |
| `import_solo_data(sessions, plan)` | Moves solo data in chunks of ≤ 50: all-or-nothing per call, idempotent (same `client_id` = skipped), sessions stay solo, the plan is never overwritten, ≤ 1000 solo sessions per person. Returns `{imported, skipped, plan_saved, solo_total}`; the app keeps its local copy until `solo_total` matches. Needs a person (the member has joined a gym). |
| Demo gym | `invites.kind = 'demo'`: reusable, no expiry, only for a gym with `is_demo`, gives a trainee membership with all permissions; `admin_create_demo_invite(gym)` (secret key) makes and **rotates** it; `wipe_demo_data()` clears the demo gym's sessions and plans nightly; `schedule_maintenance()` schedules both daily jobs once `pg_cron` is on. |
| `delete-account` | `POST /functions/v1/delete-account` with `{"confirm": "delete"}` and the user's token: deletes the caller (never an id from the body). `409 last_owner` (with the gym names) while they are the only owner of a gym with members; `200` also when already deleted (a retry is safe). Cascade: `auth.users → people → memberships, workout_sessions, personal_plans`; audit columns (`created_by`, `ended_by`) are set to null. A database trigger refuses to cascade away the last owner as a second line of defense. |

Making the demo card (App Review notes need a code and a sample QR):
```bash
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_SECRET_KEY=…
scripts/make_invites/run.sh --demo --gym <demo-gym-uuid>
```
It writes one PDF (never in the repo), revokes the previous demo code and
prints no code. Procedure and rotation: `docs/release.md` → "Demo gym for App Review".

Tests: `supabase/tests/workout_sessions_rls`, `personal_plans_rls`,
`import_solo_data` (hostile chunks, retry, resume, atomicity, cap),
`demo_invites`, `account_deletion` (161 assertions); Deno `delete-account`
(12); Python `--demo` (4).

## Not done in this step (see the decision doc)
- The app screens, the dashboard.
- A CAPTCHA fallback for the global breaker (needs Cloudflare Turnstile keys).
- Server-side "ids are never reused": the server keeps no id history; the app
  creates fresh ids.
- Deleting stale anonymous users (no automatic cleanup in Supabase; a job for
  users older than 30 days without a person). `pg_cron` on the plan is still
  unverified: `schedule_maintenance()` says so instead of failing.

## Analytics
None from the backend. The app step adds `gym_join_started`, `gym_joined`,
`gym_join_failed` (decision doc §9).
