# Design: never lose your training (local database, backup, restore)

> **Status: proposed. No code is written until the owner approves this spec.**
> `CLAUDE.md` asks for an EGM-reviewed spec. The EGM plugin is loaded, but its
> `/egm:` commands can only be started by a person, not by the agent that
> wrote this. So this spec was written by hand with the same sections and has
> **not** had an EGM review yet. To get one, run
> `/egm:egm-review docs/designs/never_lose_history.md`, then `/egm:egm-resolve`.

Mockup (offer, email, code, backup status, restore, plan question, done;
English and Arabic, light and dark):
https://claude.ai/artifact/8DJpFAuuoKEokauww4oXo9
It has not been looked at by a person yet.

## Goal
1. The phone keeps the **whole** history, not the last 200 workouts.
2. Any member, solo or in a gym, can back up to their account and get
   everything back on a new phone.
3. Training signed out, with no account, works exactly as today.

## What exists today (checked 2026-11-11, `main` at d16b783)
- **On the phone:** `LocalWorkoutRepository` keeps the plan, history, draft,
  chosen day and best level as JSON strings in `SharedPreferences`. History
  is one list, rewritten whole on every save and cut to the last 200
  (`maxHistory`). Gym workouts are in the same list, tagged `membershipId`.
- **Workouts have no id on the phone.** The server id is
  `client_id = sha256(day_id|finished_at|sets)` (`ImportSession`), used by
  the solo import and the gym outbox.
- **Workouts are never edited and never deleted one by one.** The only
  delete is `clearHistory()` from "Delete account → also erase this phone".
- **Server:** `workout_sessions` (`gym_id` null = solo; staff never see
  solo). A person may already **insert their own solo rows directly** (policy
  "log own sessions"); there is **no cap** on direct inserts. The 1000 cap is
  only inside `import_solo_data`. `personal_plans` is read-only for clients.
  `delete-account` cascades `auth.users → people → memberships,
  workout_sessions, personal_plans`.
- **A `people` row is made only when an invite is redeemed.** A solo member
  cannot have one.
- **Sessions:** trainees are anonymous Supabase users. "Add email" calls
  `updateUser(email)` but the app has no screen to type a code, and no way
  to sign back in. The dashboard signs in by email code
  (`signInWithOtp` + `verifyOtp`, `shouldCreateUser: false`), with
  Turnstile when configured.
- **Gym uploads:** `SessionOutbox` (in preferences) + `UploadSessions`
  (chunks of 50, back-off, idempotent). A workout of an ended membership is
  refused by the server and stays queued for ever.
- **Phone backups:** the Android manifest sets no `allowBackup`, so Android
  Auto Backup is on by default and already includes shared preferences and
  databases (up to 25 MB, about nightly, only if the user has backup on).
  The session lives in Keychain / Keystore and is not restored. This helps
  some users today but is not something to rely on.
- **Packages:** `sqflite` 2.4.5 is already in the lock file (through
  `flutter_cache_manager`); latest is 2.4.6.

## Decisions

### 1. Local storage: SQLite through `sqflite`
`sqflite` becomes a direct dependency. Not `drift`: it adds code generation
(`build_runner`, `drift_dev`) and a second SQLite binding for a schema of
three tables whose queries are a handful of lines. Tests use
`sqflite_common_ffi` (dev dependency).

```
sessions(client_id TEXT PRIMARY KEY,   -- the content hash, as on the server
         day_id TEXT, finished_at INTEGER, started_at INTEGER NULL,
         membership_id TEXT NULL,      -- null = solo
         sets TEXT,                    -- JSON, same shape as today
         synced_at INTEGER NULL,       -- null = not backed up yet
         sync_problem TEXT NULL)       -- why the server refused it, if it did
  index (finished_at)
kv(key TEXT PRIMARY KEY, value TEXT)   -- plan, draft, chosen day, best level,
                                       -- markers, the plan's sync state
quarantine(id INTEGER PRIMARY KEY, kind TEXT, raw TEXT, at INTEGER)
```

- **No cap on history.** One workout is about 1–2 KB; five a week for ten
  years is about 2,600 rows, under 6 MB. A sanity limit of 100,000 rows only
  stops a runaway bug.
- The primary key is the content hash, so the same workout can never be
  stored twice: by the migration, by a restore, or by two phones.
- `WorkoutRepository` keeps its interface in PR 1 (`loadHistory()` returns
  everything), so screens do not change. The repository keeps the parsed
  history in memory and drops it on a write.
- **Targets** (5,000 workouts, a mid-range Android phone, measured by a new
  case in the existing performance test): saving a workout ≤ 50 ms (today it
  rewrites the whole list); first history read ≤ 300 ms off the UI thread;
  Today, Progress and an exercise's history open ≤ 100 ms slower than with
  200 workouts. If a target is missed, sets move to their own indexed table
  in a later schema version; not before it is needed.
- The database file is in the app's normal data folder, so phone backups
  (Android Auto Backup, iCloud / computer backups on iOS) carry it as they
  carry the preferences today.

**One-time move from preferences (nothing can be lost):**

| Step / case | What happens |
|---|---|
| Normal | In **one transaction**: every workout inserted (`insert or ignore`), the plan, draft, chosen day and level copied as their raw strings, then the marker `migrated_v1`. Before committing, the number of rows must equal the number of distinct workouts read. |
| The old keys | **Not deleted.** They stay untouched as a fallback and are removed only by a later release, after the migration has run in the field. |
| Crash or kill halfway | The transaction rolls back; the next start does it again. |
| No free space, or the database cannot be opened | This run uses the old preferences repository, the error goes to monitoring, the next start tries again. No error screen. |
| History JSON unreadable as a whole | The raw string goes to `quarantine`; the app starts with an empty history (today it shows an error for ever). |
| One bad workout inside the list | The good ones are moved; the bad item's raw JSON goes to `quarantine`. |
| Plan or draft unreadable | Copied raw; reading it fails the same way as today. |
| Database file later found corrupt | It is renamed aside, a new one is made, and the move runs again from the old keys (while they exist) and then from the account backup. |
| App downgraded | The old version still finds its keys; workouts logged since are in the database and come back on the next upgrade. |

### 2. Accounts for solo members
- Entry: "Back up my training" → email → 6-digit code. One screen serves
  new and returning people: `signInWithOtp(email, shouldCreateUser: true)`
  then `verifyOtp(type: email)`. An existing account signs in and restores; a
  new email makes an account. The app never says whether an email is known.
- Turnstile token through the existing `TurnstileCaptcha` seam.
- **Person without a gym:** new RPC `ensure_person()`: returns the caller's
  person, creating it if missing. Allowed only for a **permanent** session
  (`private.is_permanent()`), so anonymous sign-ins cannot fill `people`.
- **Anonymous gym member** (already has a person): the same button runs
  `updateUser(email)`, then the same code screen with
  `verifyOtp(type: emailChange)`. The account keeps its id, memberships and
  history (Supabase anonymous sign-ins guide). This also finishes the
  half-built "Add email".
- **The email already belongs to another account** (for example: backed up
  solo before, later joined a gym on a new phone without signing in).
  Supabase offers no automatic merge. v1 does not merge accounts: the app
  says the email already has an account and offers to sign in to it, warning
  that the gym on this phone then needs a new code from the captain. Nothing
  on the phone is deleted. See "Decisions needed" 3.
- No Apple or Google sign-in: App Review 4.8 does not require another
  login service when the app uses only its own account system.
- Signed out stays the default. Nothing in this feature runs without an
  explicit "Back up my training" (App Review 5.1.1(v): apps without
  significant account features must work without a login; here the account
  is only for backup and gyms).

### 3. Continuous backup
Backup is **on** when the member chose it and has a person. It needs an
email to be *restorable*; an anonymous gym member who turns it on is told
to add an email.

- **Workouts:** rows with `synced_at` null are the queue (this replaces the
  preferences outbox; its waiting entries are moved in). Sent after every
  finished workout and at start, on resume, when the network returns and on
  the existing back-off, 50 at a time, oldest first, through the existing
  upsert (`on conflict (person_id, client_id) do nothing`). Solo rows carry
  `gym_id` null.
- **A gym workout the server refuses because the membership ended** is sent
  again as a solo row. The member keeps it; the gym does not see it.
- **A workout the server's rules refuse** (finish time before 2020 or more
  than a day ahead, more than 500 sets, over 64 KB) stays on the phone with
  `sync_problem`; the status says how many could not be backed up.
- **Conflicts for workouts: none.** They are immutable and keyed by content,
  so two phones simply add up. There is no delete to sync. If deleting one
  workout is added later it needs a tombstone; out of scope.
- **Plan:** new RPC `save_personal_plan(p_base_version, p_body)`: the same
  body check as gym plans (`private.plan_problem`, 64 KB), writes only when
  `p_base_version` equals the stored version (0 = none), else `plan_changed`.
  Rule for two phones: **the plan saved first wins**; the other phone takes
  it and shows "Your plan was changed on another phone". Its own unsent
  version is kept on the phone for 30 days and can be chosen in Settings.
  The same rule as gym plans (decision doc §11), so one rule to learn.
- **Best level and chosen day:** new table `personal_state(person_id,
  best_level, chosen_day, updated_at)`, own row only. Best level only goes
  up (`greatest`), so it cannot conflict; chosen day is last write.
- **Not backed up:** the workout in progress, picture choices made solo,
  language and theme.
- **Cap:** 20,000 workouts per person, enforced for every insert by a
  statement-level trigger (one count per request), and `import_solo_data`
  raised from 1000 to the same number. Reason: one workout a day for 54
  years; with the 64 KB limit per workout it bounds what one account can
  store. Today direct inserts have no limit at all.

### 4. Restore
After the code is accepted on a phone:
1. `ensure_person()`.
2. **If the phone already has workouts or a plan** made while signed out,
   one question first: "Add this phone's training to your account?" Yes
   merges; No cancels the sign-in and the phone stays as it was. (A phone
   can hold only one person's training.)
3. Workouts come down 200 at a time, ordered by finish time and id, with the
   position saved, so a dropped connection carries on where it stopped.
   `insert or ignore` by `client_id`; rows arrive already marked as backed
   up, with their gym tag. The app is usable meanwhile.
4. Plan: the phone has none → the account's. Both, and equal → nothing.
   Both, and different → one question (mockup, screen 6); the other is kept
   30 days.
5. Best level = the higher of the two. Chosen day = the account's if the
   phone has none.
6. Gym history comes back with its gym tag. History of a gym that hides it
   from former members is not sent by the server and is not restored.
7. **Sign out:** "Keep my training on this phone" (default) or "Remove it
   from this phone" (offered only when everything is backed up).

### 5. Gym members
Nothing changes in who sees what: staff read only rows of their gym for
active members; solo rows (`gym_id` null) are never visible to them,
including gym workouts that fell back to solo. pgTAP proves it again with
the new write paths.

### 6. Privacy and stores
- **Stored on the server when backup is on:** the email, workouts (exercise
  ids, weights, reps, times), the plan (it contains names the member typed),
  best level, chosen day. Host: Supabase, as for gym accounts.
- **Privacy policy** (English and Arabic): a section "Backing up your
  training"; the sentence "your workouts stay on your phone" becomes true
  "unless you turn on backup". `website/delete-account.html` and
  `store/privacy_forms.md`: email and fitness data are already declared;
  the texts change from "gym members" to "members who back up or join a
  gym".
- **Deletion:** the existing `delete-account` already removes workouts and
  the personal plan; `personal_state` cascades from `people`. A pgTAP case
  and a Deno case prove a solo-only account is fully removed.
- **Erase the backup but keep the account:** new RPC `delete_my_backup()`
  (solo workouts, personal plan, personal state), for a gym member who
  turns backup off. For a solo-only account "Delete account" does the same.
- **Export:** not in this version. The data is in a standard SQLite file
  and a JSON export button is small; proposed as a follow-up.
- **Events** (no email, id, name or count beyond a bucket):
  `local_db_migrated` `{sessions: 0|1-50|51-200, ms: bucket}`,
  `local_db_migration_failed` `{reason}`, `backup_offer_shown` `{place}`,
  `backup_offer_dismissed`, `backup_sign_in_started`, `backup_code_failed`
  `{reason}`, `backup_enabled`, `backup_synced`, `backup_failed` `{reason}`,
  `backup_disabled`, `restore_started`, `restore_done` `{sessions: bucket}`,
  `restore_failed` `{reason}`.

### 7. UX
- **Offer:** on the summary of the **3rd** finished workout (mockup 1). "Not
  now" → once more after the 10th, then only in Settings. Never at first
  launch.
- **Settings → Backup** (mockup 4): off / backed up + when / waiting for
  internet + how many / failed + Retry / "add an email to restore on a new
  phone" / "sign in again" when the session ended. The training is safe on
  the phone in every state, and the card says so.
- **First screen:** a link "I already have an account" → email → code →
  restore.
- **Code screen:** six boxes, paste and autofill, wrong / expired / too many
  tries / offline, "send a new code" after 60 s (Supabase's own limit).

### 8. Rollout
- Flag `training_backup` (PostHog, off): hides the offer, the Settings card
  and the first-screen link. The local database (PR 1) is not behind a flag:
  a flag evaluated after start-up cannot choose the storage engine; its
  safety is the fallback and the untouched old keys.
- Order: PR 1 any time; PR 2 (migrations deploy on merge) before the app
  versions of PR 3–5 reach the stores; flag on after PR 5.
- **Owner's manual steps before the flag goes on** (Supabase dashboard):
  new users may sign up by email (the dashboard never creates users, so
  check this is on); the "Confirm signup" and "Change email address"
  templates contain `{{ .Token }}` like the Magic Link one; custom SMTP
  (already required for the dashboard); CAPTCHA on with the app's Turnstile
  site key.
- Old app versions: unaffected (new RPCs and a new table; the session cap
  is far above anything they send).

### 9. PR split (each safe alone)
1. **Local database + move**, no visible change, cap removed.
2. **Backend:** `ensure_person`, `save_personal_plan`, `personal_state`,
   `delete_my_backup`, the cap trigger, `import_solo_data` cap; pgTAP.
3. **Sign-in by code + continuous backup** (workouts, plan, state), a
   minimal Settings card; the link-email path for gym members. Behind the
   flag.
4. **Restore:** download, merge rules, plan question, first-screen link.
5. **Offer, full status card, sign-out choices, privacy policy, website,
   store forms, docs.**

### 10. Tests
- **PR 1:** move with 0 / 1 / 200 workouts; duplicates; crash at each step
  (a factory that throws mid-transaction); disk full; unreadable history,
  one bad item, unreadable plan; a 50,000-workout history; fallback to the
  old repository; a second run changes nothing; every existing workout test
  runs against the new repository; performance case.
- **Backend (pgTAP):** anon nothing; the person; another person cannot read
  or change; gym staff never see solo rows or fallen-back rows;
  `ensure_person` refused for anonymous sessions and idempotent;
  `save_personal_plan` versions, limits, hostile bodies; the cap at 20,000
  and 20,001 and inside a 50-row batch; `delete_my_backup` leaves gym rows;
  account deletion removes everything.
- **App:** sync and conflict rules as unit tests with a fake server,
  including random interleavings of two phones (as `solo_import_test` does);
  replayed and duplicated uploads; huge payloads, crafted ids and
  injection-like strings from the server on restore; restore interrupted at
  every page; `screensUiTests` for every new screen and state; an
  integration test written as a demo: log workouts → back up → erase the
  app's data → sign in → everything is back.

### 11. Docs to update with the code
`docs/features/workout.md`, `gym_account_app.md`, `gym_accounts_backend.md`,
a new `docs/features/backup.md`, `docs/security.md`, `docs/release.md`
(deploy order, the Supabase settings), `docs/decisions/gym_accounts.md`
(§6, §10), `website/privacy.html` (both languages),
`website/delete-account.html`, `store/privacy_forms.md`, `docs/README.md`.

## Official docs checked (2026-11-11)
- Supabase Auth, anonymous sign-ins: an anonymous user becomes permanent
  with `updateUser({email})` and then the email link **or the 6-digit code**;
  an email that belongs to another user gives an error and conflicts are
  resolved by the app; 30 anonymous sign-ins per hour per address; no
  automatic clean-up.
- Supabase Auth, passwordless email: `signInWithOtp` creates the user unless
  `shouldCreateUser` is false; the template needs `{{ .Token }}` for a code;
  codes last 1 hour by default (configurable); one request per 60 s.
- App Store Review Guidelines 5.1.1(v) and 4.8 (quoted in section 2).
- Android Auto Backup: on by default from API 23, shared preferences and
  databases included, 25 MB, about every 24 h when idle on Wi-Fi.
- pub.dev: `sqflite` 2.4.6 (transactions, batches, `onUpgrade`, tests through
  `sqflite_common_ffi`); `drift` 2.35.4.
- **Not re-read in this session, to read before the PR that uses them:**
  Apple's page on what iOS backups include, Google Play's account-deletion
  policy page, the Supabase session and refresh-token settings.

## Decisions needed from the owner
1. `sqflite` and not `drift`. *Recommended: `sqflite`.*
2. Keep the old preferences data untouched for a few releases as the
   fallback. *Recommended: yes.*
3. The email already has another account: no automatic merge in this
   version (explain and offer to sign in). *Recommended: yes; merging two
   people is a separate design.*
4. Two phones change the plan: the one saved first wins, the other is kept
   30 days on its phone. *Recommended: yes (same as gym plans).*
5. Cap of 20,000 workouts per person, also on direct inserts.
   *Recommended: yes.*
6. A gym workout refused because the membership ended is backed up as solo.
   *Recommended: yes.*
7. Signing in on a phone that has training: ask "add it to your account?";
   No cancels the sign-in. *Recommended: yes.*
8. The offer after the 3rd workout, again after the 10th, then only
   Settings. *Recommended: yes.*
9. Code lifetime: the mockup says 10 minutes. The setting is shared with the
   dashboard, which uses 1 hour today. *Recommended: 10 minutes for both.*
10. `delete_my_backup()` for gym members who turn backup off.
    *Recommended: yes.*
11. Data export: later. *Recommended: later.*
12. Run the EGM review yourself before approving, or approve without it.
