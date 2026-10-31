# Feature: workout (MVP)

## What it does
The member's plan advances **by session, not by calendar day**: a missed day
never skips a workout. The next day only moves when the member marks a
session Complete. Each exercise shows the last weight/reps and a suggested
next weight; sets are logged with one tap; a rest timer starts after each set.

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

## Tests
- RLS + RPC: `supabase/tests/workout_rls.test.sql` (`supabase test db`)

## Local data
`supabase/seed.sql` has a placeholder push/pull/legs plan — replace it with
the coach's real plan.
