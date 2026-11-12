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
| PR 3b | Sign-in by code, the minimal Settings card, the link-email path for gym members (behind `training_backup`) | not started |
| PR 4 | Restore on a new phone | not started |
| PR 5 | Offer after the 3rd workout, full status card, sign-out choices, privacy texts | not started |

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

