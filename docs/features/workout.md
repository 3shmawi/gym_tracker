# Feature: workout (MVP)

## What it does
The member's plan advances **by session, not by calendar day**: a missed day
never skips a workout. The next day only moves when the member marks a
session Complete. Each exercise shows the last weight/reps and a suggested
next weight; sets are logged with one tap; a rest timer starts after each set.

## Screen (`/`, `WorkoutPage`)
- Header: today's day name, "Day x of n", and "saved on this phone" while
  writes are waiting to sync. Pull to refresh.
- One card per exercise: target sets × reps, last time, suggested weight
  (arrow up / flat / down), superset badge.
- Start workout → each card gets big − / + steppers for weight and reps
  (prefilled with the suggestion) and one big "Log set N" button. Logged
  sets show as chips (tap × to delete).
- Finish workout → confirm → the plan moves to the next day; a "well done,
  next time: <day>" message replaces the session.
- States: loading, error with retry (first launch offline), empty (no plan).
- `WorkoutView` is pure UI; `WorkoutPage` connects it to
  `WorkoutController` (Riverpod `AsyncNotifier`).

## Sign-in (trial)
Anonymous Supabase sign-in (`lib/core/auth/app_auth.dart`), done silently
before the first sync. `ensure_trial_plan()` gives every new user the
default plan (`plans.is_default`, migration 0003). **Enable it on the hosted
project:** Supabase dashboard → Authentication → Sign In / Providers →
"Allow anonymous sign-ins" (local `supabase/config.toml` already has it).
Uninstalling the app loses an anonymous account; linking an email comes
later.

## Backend (Supabase) — `supabase/migrations/0002_workout.sql`
| Table | Purpose |
|---|---|
| `profiles` | one per auth user, `role` = member / coach / admin (created by trigger on sign-up; users can't change their role) |
| `exercises` | catalog, names in English + Arabic |
| `plans` → `plan_days` (`day_order`) → `plan_exercises` (sets, target reps, rest, weight step) | the plan |
| `plan_assignments` | which member follows which plan, `next_day_order` (one active per member) |
| `sessions` | one gym visit; `in_progress` → `completed` |
| `set_logs` | every logged set |

- `exercise_last_sets` (view): the sets of the member's last session for each
  exercise — by exercise, not machine unit.
- `complete_session(session_id)` (RPC): completes the session and moves the
  plan to the next day (wraps after the last day). Idempotent, so an offline
  retry never skips a day. Members can't edit `next_day_order` or session
  status directly.
- Session and set ids are client-generated uuids, so offline logs sync with
  an upsert.
- `day_order` must be contiguous (1..n) within a plan.
- Suggested weight is computed in the app (domain use case), not in SQL.

## App architecture (layered, Riverpod)
- Domain: `lib/features/workout/domain/` — entities (`AssignedPlan`,
  `PlanDay`, `PlanExercise`, `WorkoutSession`, `LoggedSet`),
  `WorkoutRepository`, use case `SuggestNextWeight`.
- Data: `lib/features/workout/data/`
  - `WorkoutDatabase` (drift, on the device): cached plan, sessions, sets,
    and the **outbox** of writes waiting for the server.
  - `SupabaseWorkoutRemote`: plan (nested select), `exercise_last_sets`,
    sessions/sets upserts, `complete_session` RPC.
  - `OfflineWorkoutRepository`: every write goes to the device + outbox in
    one transaction and returns at once; `sync()` replays the outbox in
    order. A network failure stops the sync and keeps the queue; a write the
    server keeps rejecting is dropped after 5 tries (reported to Sentry).
  - `WorkoutSync`: syncs whenever the device comes back online (started in
    `bootstrap.dart`).
- After editing the drift tables: `dart run build_runner build` and commit
  `workout_database.g.dart`; bump `schemaVersion` with a migration.

## Suggested weight (`SuggestNextWeight`)
Double progression on the heaviest weight of the last session:
- every planned set reached the target reps → + one step (default 2.5 kg)
- average reps below 70% of the target → − one step
- otherwise → same weight; no history → no suggestion

## Tests
- RLS + RPC: `supabase/tests/workout_rls.test.sql`, `trial_plan.test.sql`
  (`supabase test db`)
- Controller + screen (a11y, RTL, offline error):
  `test/features/workout/presentation/`
- Use case: `test/features/workout/domain/`
- Repository (offline queue, sync order, wrap-around, history):
  `test/features/workout/data/`

## The plan
The coach's 5-day plan is in `supabase/migrations/0003_trial_plan.sql`
(default plan). Sets/reps default to 3 x 12 until the coach confirms them.
