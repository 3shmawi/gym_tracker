# Backup and restore of your training

Spec (approved 2026-11-12): [`../designs/never_lose_history.md`](../designs/never_lose_history.md).
Goal: the phone keeps the whole history; any member can back up to their
account and get everything back on a new phone; training without an account
works as before.

## Status
| Step | What | State |
|---|---|---|
| PR 1 | Local database and the one-time move from preferences | built, see [workout.md → The phone's database](workout.md) |
| PR 2 | Backend: person for solo members, personal plan, personal state, erase backup, 20,000 cap | built (this page) |
| PR 3a | The backup engine: solo workouts, plan, best level and chosen day go up when backup is on (no screen yet) | built ("The backup engine" below) |
| PR 3b | Sign-in by code, the Settings card, the email path for gym trainees (behind `training_backup`) | built ("Sign in and the Settings card" below) |
| PR 4 | Restore on a new phone | built ("Restore" below) |
| PR 5 | Offer after the 3rd/10th workout, turn off + erase, privacy texts | this PR |
| PR 6 | Sign-out choices (keep/remove training on the phone), choose the kept plan again in Settings | this PR |
| PR 7 | Re-send a gym workout of an ended membership as a solo row; integration demo of offer and erase | not started |

## Backend (migration 0022)
All of it follows the spec's sections 2, 3 and 6. Clients call the functions;
nothing is written to the new table directly.

| Function / table | What it does |
|---|---|
| `ensure_person()` | Returns the caller's person, creating it when missing. **Permanent sessions only** (an email account): an anonymous session is always refused (`42501`), so anonymous sign-ins cannot fill `people`. Idempotent. |
| `save_personal_plan(base_version, body)` | The member's own plan, same body check as a gym plan (`private.plan_problem`, 64 KB). Writes only when `base_version` is the stored version (0 = none); otherwise `plan_changed` (`P0001`): **the plan saved first wins**. The same body again makes no new version. |
| `personal_state` + `save_personal_state(best_level, chosen_day)` | Best level only goes up (`beginner < intermediate < pro`), so two phones cannot conflict; chosen day is the last write (`{id, by_edit}`, 256 bytes at most). Read by the person, written only through the function. |
| `delete_my_backup()` | Deletes the person's **solo** workouts (`gym_id` null), personal plan and personal state. Gym workouts and the account stay. A solo-only account uses "Delete account" (cascade removes everything: pgTAP proves it). |
| Cap | A statement-level trigger on `workout_sessions` refuses (`54000`, `too_many_workouts`) any request that would take a person over **20,000** workouts, for every insert (direct upsert, gym upload, import); the whole request is refused. `import_solo_data` raised from 1000 to 20000. |

Who sees what did not change: solo rows are invisible to every gym, also a
gym workout later sent again as solo; pgTAP proves it with the new paths.

Errors the app will map: `forbidden` (`42501`), `invalid_plan: …` /
`invalid_state: …` (`22023`), `plan_changed` (`P0001`), `too_many_workouts`
(`54000`).

## Release order
Migration 0022 deploys on merge (before the app versions of PR 3 to 5 reach
the stores). Old app versions are unaffected: new functions and a new table,
and the cap is far above anything they send.

## The backup engine (PR 3a)
Code: `lib/features/backup/` (layered). Nothing shows on a screen yet: it runs
only for a member who **turned backup on** (`BackupSettings.enabled`, set by
PR 3b's screen) and is signed in. Spec §3.

| Part | What |
|---|---|
| `RunBackup` (domain) | One run: the waiting workouts (oldest first, 50 at a time), then the plan, then the best level and chosen day. A failure stops the run; the next trigger carries on. |
| `BackupQueue` | The solo rows of the phone's database whose `synced_at` is empty and that were not refused (`SqliteBackupQueue`). Gym workouts (`membership_id` set) still go up through the gym's outbox. Workouts moved from the preferences are waiting, so the first backup sends the whole history. |
| `BackupRemote` | `SupabaseBackupRemote`: `ensure_person` when the account has no person, direct upsert of solo rows (`on conflict do nothing`), `save_personal_plan`, `save_personal_state`. |
| `BackupSettings` | `PrefsBackupSettings`: on/off, last time, plan version and fingerprint, plan conflict, state fingerprint. |
| `BackupSync` (presentation) | Runs at app start, on resume, when the network returns and after every finished workout (through the existing `GymSync` hooks), with the same back-off (30 s to 15 min). `enable()` / `disable()` are for the screen. |

Rules the tests pin down:
- A workout the server refuses (a rule, or the 20,000 cap: `ValidationFailure`,
  never retried) is isolated: the chunk is retried one by one, the bad one is
  kept on the phone with `sync_problem`, the others go up.
- No network or a server error: the workouts wait, the status says how many.
- The session ended (`UnauthorizedFailure`): status "sign in again", nothing is lost.
- The plan saved first wins: when the account already has a newer plan this
  phone's is **not** uploaded, `planConflict` is set, and it is not tried
  again until the restore step (PR 4) asks which to keep.
- The best level only goes up on the server; the chosen day is last write; an
  unchanged plan or state is not sent again.
- Two phones, 25 random interleavings: every workout of both is on the account
  once, and the level is never lower than any phone's.

Events (a word only): `backup_enabled`, `backup_synced`, `backup_failed
{reason: network|signin|refused}`, `backup_disabled`. Flag: `training_backup`
(`trainingBackupEnabledProvider`; the screen and the offer will use it).
Security test: `test/security/backup_test.dart`.

Not in this step (spec §3, moved to PR 5): a gym workout refused because the
membership ended is not yet sent again as a solo row.

## Sign in and the Settings card (PR 3b)
Behind the `training_backup` flag (PostHog, **off**): the route `/backup`, the
Settings card and the sign-in. With the flag off `/backup` opens home. Someone
who already turned backup on keeps seeing the card (so they can turn it off).

**Screens** (`lib/features/backup/presentation/`; design board "Backup and
restore"): *Back up my training* (`backup_sign_in_view.dart`): email, then six
digits (the `AppCodeField` boxes, numeric keyboard, one-time-code autofill,
paste cleaned to digits), then "You're backed up". Settings → **Backup card**
(`backup_card.dart`): off (one row), or the status: backed up and when, how
many wait for the internet, how many could not be backed up, "sign in again",
"your plan was changed on another phone", Try again, Turn off. Every state
says the training is safe on the phone. Not built yet (PR 5): the offer after
the 3rd workout and the sign-out choices.

**How it signs in** (`AccountRepository.sendCode` / `verifyCode`):
- A signed-out member: `signInWithOtp(email, shouldCreateUser: true)` with the
  Turnstile token when configured, then `verifyOTP(type: email)`. A known email
  signs in, a new one makes an account, and the app never says which.
- A gym trainee (anonymous): `updateUser(email)` then `verifyOTP(type:
  emailChange)`: same account, same memberships and history, now permanent.
- The email already belongs to another account (`email_exists`): the screen
  says so and offers "Sign in to that account", warning that the gym on this
  phone then needs a new code from the captain. Nothing on the phone is
  deleted. No automatic merge (spec §2, decision 3).
- Rules before anything is sent: `EmailRules.clean` (one `@`, at most 254
  characters, no spaces, control or invisible characters, no markup, brackets
  or quotes) and a code of exactly six digits; a new code after 60 seconds.
- Errors a person can act on (`AuthCodeFailure`): wrong or expired code, too
  many tries, email taken; offline and anything else say so. The server's own
  text is never shown.
- On a correct code `BackupSync.enable()` turns backup on and the first run
  sends the whole history.

Events (a word only): `backup_sign_in_started`, `backup_code_failed {reason}`,
plus the four above. Deep link: `/backup` (docs/deep_links.md): the address
carries nothing and a link sends nothing.

Tests: `email_rules_test`, `backup_sign_in_controller_test`,
`backup_sign_in_view_test` and `backup_card_test` (each ends with
`screensUiTests`: 14 screens and states), `supabase_account_repository_test`
(the code methods), `test/security/deep_link_test.dart` ("backup screen"),
`test/security/backup_test.dart`, and the integration test "back up my
training: email, code, and it is on the account" (a demo: Settings, email,
code, done, the card).

### Before the flag goes on (owner, Supabase dashboard)
- Authentication → Sign In / Providers → Email: **new users may sign up** (the
  dashboard never creates users, so check it is on).
- Email templates: **Confirm signup** and **Change email address** contain
  `{{ .Token }}` (the 6-digit code), like Magic Link.
- Code lifetime: 10 minutes (the mockup says so); shared with the dashboard.
- Custom SMTP (already needed by the dashboard).
- CAPTCHA on, with the app's Turnstile site key.

## Restore (PR 4)
After the code is accepted, the account's training is brought onto the phone
(spec §4). Code: `RunRestore` (domain), `SupabaseBackupRemote.fetchSessions /
fetchPlan / fetchState`, `RestoreRows` (what is trusted), `SqliteSessionStore`
as the `RestoreSink`, the extra steps of `BackupSignInController` and view.

**What happens, in order**
1. A new phone, or a phone with no training: the account's workouts come down
   **200 at a time**, oldest first (ordered by finish time and row id), with the
   position saved after every page (`BackupSettings.restoreCursor`). A dropped
   connection stops the screen with "Try again", and the run resumes after the
   last page taken. If the app is closed meanwhile, `BackupSync` carries on in
   the background the next time it runs (a restore that was started and not
   finished). The workouts arrive already marked as backed up, with their gym
   tag, never twice (the key is their content), and nothing is uploaded again.
2. **A phone that already has training and an account that has some** (and the
   sign-in made a different account): one question first, *Add this phone's
   training to your account?* **Yes** puts them together (nothing is deleted);
   **No** signs out and the phone stays as it was. No question when the account
   is new (the phone's training simply starts backing up) or when it is the same
   account (a gym trainee who added an email). *A refinement of the spec, which
   asks whenever the phone has training: asking when there is nothing to put
   together would only be noise.*
3. The plan: the phone has none → the account's; the same → nothing; **both and
   different → the person chooses** (*Keep this phone's plan* / *Use the plan from
   my account*); nothing changes before the answer, and the plan not chosen is
   kept on the phone for 30 days (`keptPlan`; choosing it again from Settings is
   PR 5). Keeping this phone's plan makes the next backup run save it on top of
   the account's version.
4. The best level is the higher of the two (never lowered); the chosen day is
   the account's only when the phone has none.
5. Then backup is turned on and its first run sends what only this phone had.

**What is trusted:** nothing. Every row is checked by `RestoreRows` (day and
exercise ids, finish time between 2020 and a day ahead, at most 500 sets,
weight 0 to 1000, whole reps 0 to 1000, a real membership id or none). A row
that is off is skipped and counted, never an error and never stored; a plan the
editor would refuse is a failure, not a plan. A gym that hides its history from
former members sends nothing (the server's RLS), so it is not restored.

**First screen:** with the flag on, "I already have an account" (under "I have
a code") opens `/backup`; after a successful restore the first screen is
answered and the app opens on home.

Events (a word only): `restore_done`. Tests: `run_restore_test` (every rule, a
drop at every page, restoring twice, 20 random interleavings of three phones:
every phone ends with every workout), `restore_rows_test` (hostile rows and
plans), the sink tests in `backup_data_test`, the controller tests, the view
tests (5 new screens and states with `screensUiTests`; the working state has a
widget test because it loops an animation), `backup_sync_test` (background
resume), `welcome_view_test`, and the integration test "a new phone: sign in,
and the whole training comes back" (a demo).


## The offer, and turning off (PR 5)
- **Offer:** after a workout is saved, `BackupOffer.afterWorkout` counts the
  finished workouts; `shouldOfferBackup` says yes at the 3rd (nothing declined
  yet) and at the 10th (declined once), never when backup is on or the
  `training_backup` flag is off. `BackupOfferHost` (around the home screen)
  opens a sheet: "Back up my training" goes to `/backup`, "Not now" counts one
  decline (two and it only lives in Settings).
- **Turn off:** the Settings card asks: keep what is saved, or erase it
  (`delete_my_backup`: solo workouts, personal plan, personal state; gym rows
  and the account stay). Erase turns backup off only if the call worked, then
  every solo workout waits to be uploaded again if backup is turned on later.
- **Events:** `backup_offer_shown {place}`, `backup_offer_dismissed`,
  `backup_erased` (plus the earlier ones).
- **Texts:** `website/privacy.html` (en + ar) has "Backing up your training";
  `website/delete-account.html` and `store/privacy_forms.md` say backup data is
  removed with the account.

## Sign out and the other plan (PR 6)
- **Sign out:** with backup on, the question says where the training stands.
  Everything backed up → a third button "Sign out and remove my training from
  this phone" (`BackupSync.removeTrainingFromPhone`: workouts, level, chosen
  day, in-progress workout; the plan stays; backup turns off; the account is
  untouched and a restore brings it back). Something not backed up yet → no
  remove button, and the note says it stays on the phone. The default is
  always to keep the training.
- **The other plan:** the plan that lost a conflict is kept 30 days
  (`BackupSync.keptPlan`). While it exists the Settings card shows "Use my
  other plan instead": it swaps the two (so the choice can be undone) and the
  next backup saves it on top of the account's. Event: `backup_plan_swapped`.
