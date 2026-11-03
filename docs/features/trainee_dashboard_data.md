# Feature: trainee dashboard data (backend only)

What the gym captain's web dashboard (design board 12) will read for each
trainee. **No dashboard UI here**: this step stores and exposes the numbers,
tells the trainee, and proves who can read them. Migration
`supabase/migrations/0012_trainee_dashboard_data.sql`, tests
`supabase/tests/trainee_dashboard_views.test.sql`. In Supabase, not PostHog.

## Design: views, not new tracking
Everything is a SQL view over `workout_sessions` (+ the plan in `plans`).
Views are `security_invoker`: they run as the reader, so the existing RLS
decides access. One new column, `workout_sessions.started_at` (the app already
knows it from the workout in progress), for duration.

| View | One row per | Gives |
|---|---|---|
| `member_session_stats` | gym workout | `week_start`, `duration_seconds`, `sets_done`, `sets_logged`, `planned_sets`, `planned_exercises`, `skipped_exercises`, `skipped_exercise_ids` |
| `member_weekly_attendance` | member + gym week | `workouts`, `training_days`, `sets_done`, `planned_sets`, `minutes`, `active_week` (≥ 3) |
| `member_exercise_progress` | workout + exercise | `top_weight`, `reps_at_top`, `is_record` (weight progress = this ordered by `finished_at`) |
| `member_progress_summary` | active membership | `level`, `best_level`, `streak_weeks`, `comeback`, `weeks_to_next`, `workouts_total`, first/last workout |

Rules: the gym week is Saturday–Friday in `Africa/Cairo`, numbered like the
app. A set with 0 reps is a skipped set (not "done"). A record is heavier than
every earlier weight of that exercise; first times are not records (same as
the app). Level and streak are `private.member_level`, a copy of the app's
`GetLevel`; pgTAP checks the same five cases as the Dart tests — change both
together.

## Who can read (and cannot)
The trainee: their own gym rows. Owner: all members'. Captain: trainees' only.
Only while the membership is active. Never: solo workouts (`gym_id is null`),
another gym, an ended member, `anon`, another trainee. See `security.md`.

## What is NOT stored yet, and why
- **Rest overruns.** The app keeps only "when the rest ends", not when the next
  set was actually logged, so an overrun cannot be told from the data. It
  needs a timestamp per set (a change of the session format and of
  `sets_problem`); recommended as a separate step once the dashboard is
  designed.
- **Planned vs done is approximate**: plans keep no history, so an old workout
  is compared with the day as it is now (null when the day was removed).
- **Level/streak count gym workouts only** (the server never sees solo ones),
  so it can differ from what the trainee sees in the app.
- Workouts logged before this release (and imported ones) have no start time:
  `duration_seconds` is null and they do not add to `minutes`.

## Client change
`WorkoutSession.startedAt` (JSON `started_at`) is set when a workout finishes
and uploaded with the gym queue; the uploader sends it only if the server would
accept it (not after the end, ≤ 24 h before). **Deploy migration 0012 before
the app version that sends `started_at`** (Supabase deploy runs on merge of
`supabase/`; this PR is stacked on the plan-sync PR).

## Telling the trainee
- In the app: the *Welcome to {gym}* screen says the captain sees the workouts
  logged in this gym and what is worked out from them (attendance, time, sets,
  records, weights, level, streak), and that other workouts stay private
  (`joinedPrivacy`, English + Arabic).
- Privacy policy (`website/privacy.html`, both languages, dated 2026-11-03):
  new item "Progress your captain sees"; `test/security/store_pages_test.dart`
  checks it.

## Analytics
None added (no new events; nothing about this is sent to PostHog).

## Performance
`member_progress_summary` runs `member_level` for each visible membership
(a gym's captain: all trainees). Fine for a gym; if a dashboard lists
thousands of members, store a nightly snapshot instead.

## Tests
pgTAP (38 checks, also run on Postgres 16 locally with a shim): RLS for anon,
the trainee, another trainee, captain A, captain B, an ended member; numbers
for every column above; level/streak cases. Dart: `started_at` JSON and the
uploader guard; privacy text; joined screen (`screensUiTests`, goldens).
