# Design: your gym workouts come back after a recovery code

Status: **approved by the owner on 2026-11-14**, after an EGM review (design,
code accuracy, implementation readiness) the same day. Answers: a toast at
the end; backed-up solo workouts come back too.

Owner's report: "I deleted the app while I was in a gym. When I installed it
again I used a recovery code and got back into the same gym, but I started
from zero: my old workouts were gone."

## Goal

After a member gets back into their gym with the captain's **recovery
code** (a new phone, or the app deleted and installed again), the workouts
they logged that reached the server come back onto the phone. The home
screen ("last weight"), progress, level and the exercise history then use
them again.
- No backup or email is needed.
- It survives a bad connection or a closed app, and carries on.
- Nothing new is collected: the rows are already on the server.

**Out of scope, and said in the docs:**
- **Workouts never uploaded.** A workout still waiting in the phone's upload
  queue when the app was deleted never reached the server and can't come
  back.
- **A join code on a new phone.** It makes a new person (migration 0010
  §redeem), so it has no old workouts. Only a recovery code moves the
  existing person to the new phone.

## What exists today (checked in the code, `main` at cb5d92b, 2026-11-14)

- **Gym workouts reach the server through the queue.** A workout finished
  in a gym workspace goes into `gym.session_outbox`. It is uploaded to
  `workout_sessions` at start, on resume, when the network returns, after a
  workout, and with back-off, while signed in
  (`gym_sync.dart` `uploadPending`).
- **What a recovery code does.** It moves the existing `people` row to the
  new auth user and reactivates the same membership (`0010_gym_demo.sql`
  §recover). The person's rows stay theirs. A recovery is refused
  (`conflict`) when the person is active in another gym.
- **Who can read which rows.** RLS "read own sessions" (`0009`) hides gym rows
  of an *ended* membership whose gym chose `locked`. **"Staff read their
  gym's sessions" also returns a captain's members' rows.** The restore must
  name the person: [3shmawi/gym_tracker#113](https://github.com/3shmawi/gym_tracker/pull/113)
  fixes that in `SupabaseBackupRemote.fetchSessions` and **is a
  prerequisite**.
- **The only download today is the backup restore** (`RunRestore`). It runs
  after the email sign-in, and `BackupSync` resumes it in the background —
  only while backup is on (`training_backup`, off in prod).
  - It pages 200 rows at a time, oldest first, with a cursor.
  - `RestoreSink.addBackedUp` inserts one page per transaction with
    "insert or ignore" on `client_id`, which is
    `sha256(day | finished_at | sets)`. It sets `synced_at`, so the backup
    never sends the rows again. The gym upload works only from its queue,
    so it never sends restored rows either.
  - It keeps `membership_id`; `gym_id` is fetched and dropped (the phone
    has no column for it).
  - It **throws** `StateError` above 100 000 rows, outside `Result`.
- **History is one list on the phone.** `GymWorkoutRepository.loadHistory`
  returns the whole history. Home, progress and level don't filter by gym
  or by solo. Restored rows join that one list like any other.
- **Signing out doesn't remove workouts from the phone** (only "Sign out and
  remove" in backup does). That is today's rule, and unchanged here.

## Decisions

### 1. When it runs
- **From `GymSyncHost._run`:** at start, on resume, when the network returns
  and when the active membership changes. A join or a recovery invalidates
  the gym state, the membership changes, and `_run` fires, so there is no
  extra call from `JoinController`.
- **It runs only when all of these hold:**
  - signed in;
  - the flag `gym_history_restore` is on (read again at each `_run`, so an
    empty flag cache on a fresh install only delays it to the next trigger);
  - the phone has a database (not `EmptyRestoreSink`);
  - **backup is not on.** With backup on, `BackupSync` owns the restore
    (the same rows and more), so the two never run against the same sink.
- **One run at a time.** A call while one runs joins it (the `GymSync`
  single-flight pattern).
- **No code kind needed.** For a new person (a join code), the first page
  is empty and the run ends at once, with one small request.

### 2. What comes down
- **Workouts only,** through `BackupRemote.fetchSessions` (person-filtered
  after #113) and `RestoreSink.addBackedUp`. The plan in a gym is the
  captain's, and it already comes down (`SyncGymPlan`). The level, "last
  weight" and progress are worked out from the workouts.
- **Every row of the person's that RLS sends:**
  - their gym rows;
  - rows of an ended gym that kept history `readable`;
  - solo rows, which exist on the server only if backup was on once.

  They join the phone's one history, as every workout there does today.
- **Rows the app can't read** are skipped and counted, as `RestoreRows`
  already does.

### 3. Position, done, and checking again
- **The position.** Prefs key `gym.history_restore` holds the position as
  `<finished_at>|<id>`, or `done|<when>`.
  - It is cleared by `GymLocalRepository.clear()`, which covers `SignOut`,
    `HandleSessionEnded` and `DeleteAccount`, so the next person on the
    phone starts fresh.
  - The total added so far in the run is kept beside it
    (`gym.history_restore.added`), so a run that spans several app
    sessions knows its total.
- **Checking again after `done`.** At most once a day, `_run` continues from
  the last position, which is cheap: one empty page when nothing is new.
  This brings in rows that reached the server later with a newer finish
  time. Rows uploaded late with an *older* finish time (an old phone's
  queue) are not caught. That is rare, and accepted.

### 4. Code
- **`RestoreSessions` (domain, `features/backup/domain/usecases/`).** The page
  loop moves out of `RunRestore` (`run_restore.dart:53-72`) and becomes
  `RestoreSessions(remote, sink, cursor)`, where `cursor` is a
  `RestoreCursorStore { read; write; clear }`. `RunRestore` uses it with the
  backup cursor, so there is one loop and one set of tests.
  - The sink call is wrapped in `guard`, so the 100 000-row `StateError`
    becomes a failure, the position stays, and monitoring hears of it.
- **`RestoreGymHistory` (gym domain, `features/gym/domain/usecases/`)** runs
  `RestoreSessions` with `PrefsGymHistoryCursor` (data layer, wired in
  `dependencies.dart`). It returns `added`, `skipped` and `done`. The gym
  domain imports the backup domain's interfaces, as `RunRestore`'s users do
  already.
- **`GymSync.restoreHistory()`** applies the gates in §1. After a page that
  added rows, it invalidates `nextWorkoutControllerProvider` and
  `progressOverviewProvider`. At `done` with a total above 0, it bumps
  `historyRestoredToastProvider`, sends the analytics event, and resets the
  total.

### 5. What the member sees
- **While it runs:** nothing in the way. Joining and *Welcome* are
  unchanged, and the home screen fills in as pages land.
- **At the end, when anything came back:** a toast through
  `GymSyncHost`, like "your captain updated your plan".
  - **"Your workouts are back: {count}"**, with an ICU plural in English
    and Arabic (Arabic has six forms; `arb_test.dart` checks both files).
  - No toast when nothing came back.
- **A failure:** silent. The next trigger retries from the position; a page
  is all or nothing.

### 6. Feature flag
**`gym_history_restore`**, off by default. Turn it on for staging, then for
prod. It writes many rows into the phone's database, so it has a way back.

### 7. Edge cases

| Case | Behaviour |
|---|---|
| A join code (a new person) | One empty page → `done`; no toast. |
| A recovery code, new phone | Every visible row comes down; one toast with the count. |
| The app closed or offline halfway | The next trigger continues from the position; the total is kept. |
| A row already on the phone | Ignored (`client_id` = the content hash). |
| A captain or owner recovers | Only their own rows (#113); their trainees' rows never come. |
| An ended gym, `locked` | The server doesn't send those rows. |
| Backup is on | `BackupSync` restores instead; this one doesn't run. |
| Sign out, someone else signs in | The position is cleared; RLS + #113 send only their rows. The phone may still hold the first person's workouts (today's rule). |
| No phone database | Doesn't run. |
| More than 100 000 rows | A failure through `guard`; reported; the position is kept. |

### 8. Analytics
- **`gym_history_restored`**, sent once per run at `done` when the total
  is above 0.
- **Properties:**
  - `added_bucket`: `1_10`, `11_50`, `51_200` or `200_plus`;
  - `skipped`: true if any row was skipped.
- No ids, and no count beyond the bucket.

### 9. Security and privacy
- No new table, column, grant or policy. It reads the person's own rows
  only (RLS + #113), and nothing goes to a new third party, so the privacy
  page and the store forms don't change.
- The position is not personal data. A corrupt stored position (one that
  doesn't parse, an id that isn't a UUID, a time that isn't a date) starts
  again from the beginning, and inserts ignore duplicates.
- **Tests:** another person's rows and a captain's trainees' rows never come
  down (#113 checks the request). `workout_sessions` RLS across people is
  already covered by pgTAP (`workout_sessions_rls.test.sql`).

### 10. Tests
- **Unit:**
  - `RestoreSessions`: pages, resume, a failure keeps the position, `done`,
    and the `StateError` is guarded;
  - `RunRestore` after the refactor (its tests unchanged);
  - `RestoreGymHistory`: the gates (flag, signed out, backup on, no
    database), the total across runs, the daily re-check, a corrupt
    position;
  - `GymLocalRepository.clear()` clears the position, for all three end
    paths;
  - parallel calls join one run.
- **Widget:**
  - the toast with 1 and with 3, in English and Arabic;
  - no toast at 0;
  - a join brings the rows without a restart (through `GymSyncHost`).
- **Integration (a demo with `beat`):**
  1. an in-memory `BackupRemote` holds 3 of the member's workouts;
  2. a fresh app scans the recovery QR → *Welcome* → *Start training*;
  3. the home screen shows the last weights;
  4. the toast says 3.
- **`test/l10n/arb_test.dart`:** the new plural key, in both languages.

### 11. Rollout and docs
- **One app PR** after #113 merges. Title:
  `feat(gym): bring gym workouts back after a recovery code`.
- **Docs:**
  - `docs/features/gym_account_app.md`: "Getting your workouts back", the
    two "out of scope" points, the event, and a link to this spec under
    "Decisions & edge cases";
  - `docs/release.md`: the flag;
  - `docs/security.md`: one paragraph;
  - the feature doc's "Demo & post".
- Security checks: `test/security/` and CI (gitleaks, zizmor).

## As built
- **`RestoreGymHistory` takes `pageSize`** (200 by default) so tests can
  split a run.
- **`RestoreCursor.parse` now refuses an id** with anything but letters,
  digits, `-` and `_`, and a time with a comma: both go into the server's
  filter. A refused value starts from the beginning, and rows already on
  the phone are ignored.
- **The page loop (`RestoreSessions`) wraps the sink in `guard`,** so the
  backup restore also gets the 100 000-row case as a failure, not a throw.
- **The toast count** is a `(count, seq)` record, so two runs with the same
  count each show their toast.
