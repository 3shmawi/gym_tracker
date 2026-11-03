-- Row Level Security and numbers for the trainee dashboard views (pgTAP).
-- Run: supabase test db   (pgTAP; docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

-- Fixture ---------------------------------------------------------------
--   gym A: owner (01), captain (02), trainee 1 (03), trainee 2 (04)
--   gym B: captain (05), trainee (06)
insert into auth.users (id, is_anonymous) values
  ('a0000000-0000-4000-8000-000000000001', false),
  ('a0000000-0000-4000-8000-000000000002', false),
  ('a0000000-0000-4000-8000-000000000003', true),
  ('a0000000-0000-4000-8000-000000000004', true),
  ('a0000000-0000-4000-8000-000000000005', false),
  ('a0000000-0000-4000-8000-000000000006', true);

insert into public.gyms (id, name) values ('d0000000-0000-4000-8000-00000000000a', 'Gym A'), ('d0000000-0000-4000-8000-00000000000b', 'Gym B');

insert into public.people (id, auth_user_id, display_name) values
  ('c0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Person 1'),
  ('c0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'Person 2'),
  ('c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Person 3'),
  ('c0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004', 'Person 4'),
  ('c0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000005', 'Person 5'),
  ('c0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000006', 'Person 6');

insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at) values
  ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000001', 'Owner A', 'owner', 'active', now()),
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'Captain A', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 'Trainee 1', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000004', 'Trainee 2', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000005', 'Captain B', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000006', 'Trainee B', 'trainee', 'active', now());

-- Trainee 1's plan: day d1 = e1 x3, e2 x2, e3 x3 (8 sets, 3 exercises).
insert into public.plans (membership_id, body, version, updated_by) values
  ('e0000000-0000-4000-8000-000000000003', '{"days":[{"id":"d1","name":{"ar":"ا","en":"A"},"exercises":[{"id":"e1","name":{"ar":"ا","en":"E1"},"sets":3,"reps":10,"rest":60,"step":2.5,"superset":false},{"id":"e2","name":{"ar":"ب","en":"E2"},"sets":2,"reps":10,"rest":60,"step":2.5,"superset":false},{"id":"e3","name":{"ar":"ج","en":"E3"},"sets":3,"reps":10,"rest":60,"step":2.5,"superset":false}]}]}'::jsonb, 1, 'e0000000-0000-4000-8000-000000000002');

-- Trainee 1, gym A, week of Saturday 2026-10-03:
--   f1: 3 sets done (e1 x2, e2), e3 skipped, 1 hour long
--   f2: e1 heavier (a record), a skipped set of e2 (0 reps), e3 done, no start time
-- Trainee 1 also has a SOLO session, and trainee B one in gym B.
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, started_at, finished_at, sets) values ('f2000000-0000-4000-8000-000000000001', 'c1', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', '2026-10-03T09:00:00Z', '2026-10-03T10:00:00Z', '[{"exercise":"e1","weight":60,"reps":10},{"exercise":"e1","weight":60,"reps":10},{"exercise":"e2","weight":20,"reps":12}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, started_at, finished_at, sets) values ('f2000000-0000-4000-8000-000000000002', 'c2', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', null, '2026-10-05T10:00:00Z', '[{"exercise":"e1","weight":62.5,"reps":8},{"exercise":"e2","weight":0,"reps":0},{"exercise":"e3","weight":40,"reps":10}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, started_at, finished_at, sets) values ('f2000000-0000-4000-8000-000000000003', 'c3', 'c0000000-0000-4000-8000-000000000003', null, null, 'd1', null, '2026-10-06T10:00:00Z', '[{"exercise":"e1","weight":200,"reps":1}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, started_at, finished_at, sets) values ('f2000000-0000-4000-8000-000000000004', 'c4', 'c0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-000000000006', 'd1', null, '2026-10-05T10:00:00Z', '[{"exercise":"e1","weight":80,"reps":5}]'::jsonb);

select plan(38);

select ok((select relrowsecurity from pg_class where oid = 'public.workout_sessions'::regclass), 'RLS stays on under the views');
select ok((select bool_and(coalesce(reloptions, '{}') @> array['security_invoker=true'])
           from pg_class where oid in ('public.member_session_stats'::regclass,
             'public.member_weekly_attendance'::regclass, 'public.member_exercise_progress'::regclass,
             'public.member_progress_summary'::regclass)), 'every dashboard view runs as the person asking');

-- anon ----------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select * from public.member_session_stats $$, '42501', null, 'anon cannot read session stats');
select throws_ok($$ select * from public.member_weekly_attendance $$, '42501', null, 'anon cannot read attendance');
select throws_ok($$ select * from public.member_exercise_progress $$, '42501', null, 'anon cannot read progress');
select throws_ok($$ select * from public.member_progress_summary $$, '42501', null, 'anon cannot read the summary');
reset role;
reset request.jwt.claims;

-- trainee 1 (anonymous user, authenticated role) ------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select session_id from public.member_session_stats order by finished_at $$,
  $$ values ('f2000000-0000-4000-8000-000000000001'::uuid), ('f2000000-0000-4000-8000-000000000002'::uuid) $$,
  'a trainee sees their own gym workouts, never the solo one');
select results_eq($$ select sets_done, sets_logged, planned_sets, planned_exercises, skipped_exercises, duration_seconds, week_start
    from public.member_session_stats where session_id = 'f2000000-0000-4000-8000-000000000001' $$,
  $$ values (3, 3, 8, 3, 1, 3600, date '2026-10-03') $$,
  'workout 1: sets done vs planned, one skipped exercise, an hour, gym week');
select results_eq($$ select sets_done, sets_logged, skipped_exercises, skipped_exercise_ids, duration_seconds
    from public.member_session_stats where session_id = 'f2000000-0000-4000-8000-000000000002' $$,
  $$ values (2, 3, 1, array['e2'], null::int) $$,
  'workout 2: a 0-rep set is not done; its exercise counts as skipped; no start = no duration');
select results_eq($$ select workouts, training_days, sets_done, planned_sets, minutes, active_week
    from public.member_weekly_attendance $$,
  $$ values (2, 2, 5, 16, 60, false) $$, 'attendance per week');
select results_eq($$ select exercise_id, top_weight, reps_at_top, is_record
    from public.member_exercise_progress where exercise_id = 'e1' order by finished_at $$,
  $$ values ('e1', 60::numeric, 10, false), ('e1', 62.5::numeric, 8, true) $$,
  'weight progress: the first time is not a record, the heavier one is');
select is((select count(*)::int from public.member_exercise_progress where exercise_id = 'e2'), 1,
  'a 0-rep set never counts toward progress');
select results_eq($$ select workouts_total, level, streak_weeks from public.member_progress_summary $$,
  $$ values (2, 'beginner', 0) $$, 'the summary counts only gym workouts');
select is((select count(*)::int from public.member_progress_summary), 1, 'a trainee sees only their own summary row');

-- trainee 2: nothing of trainee 1's -------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.member_session_stats), 0, 'trainee 2 sees no stats of trainee 1');
select is((select count(*)::int from public.member_weekly_attendance), 0, 'trainee 2 sees no attendance of trainee 1');
select is((select count(*)::int from public.member_exercise_progress), 0, 'trainee 2 sees no progress of trainee 1');
select is((select count(*)::int from public.member_progress_summary where membership_id = 'e0000000-0000-4000-8000-000000000003'), 0, 'trainee 2 cannot read trainee 1''s summary');

-- captain A (permanent session): trainees of gym A, not gym B, not solo ---------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.member_session_stats), 2, 'a captain reads the trainee''s two gym workouts');
select is((select count(*)::int from public.member_session_stats where session_id = 'f2000000-0000-4000-8000-000000000003'), 0, 'a captain never sees a solo workout');
select is((select count(*)::int from public.member_session_stats where gym_id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'a captain never sees another gym');
select is((select count(*)::int from public.member_exercise_progress where top_weight = 200), 0, 'solo weights never reach the progress view');
select ok((select count(*) from public.member_progress_summary where membership_id = 'e0000000-0000-4000-8000-000000000003') = 1, 'the captain sees the trainee in the summary');
select is((select count(*)::int from public.member_progress_summary where gym_id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'no summary rows of another gym');

-- captain B: nothing of gym A ---------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.member_session_stats where gym_id = 'd0000000-0000-4000-8000-00000000000a'), 0, 'another gym''s captain sees nothing of gym A');
select is((select count(*)::int from public.member_progress_summary where gym_id = 'd0000000-0000-4000-8000-00000000000a'), 0, 'nor its summary');
select is((select count(*)::int from public.member_session_stats), 1, 'only gym B''s own workout');

-- the views cannot be written ---------------------------------------------------------
select throws_ok($$ insert into public.member_session_stats (session_id) values (gen_random_uuid()) $$, null, null, 'stats are read-only (not even updatable views)');
select throws_ok($$ delete from public.member_weekly_attendance $$, null, null, 'attendance is read-only');

-- A trainee who left is no longer visible to the captain ----------------------------------
reset role;
update public.memberships set status = 'ended', ended_at = now() where id = 'e0000000-0000-4000-8000-000000000003';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.member_session_stats), 0, 'an ended member''s workouts are no longer read by the captain');
select is((select count(*)::int from public.member_progress_summary where membership_id = 'e0000000-0000-4000-8000-000000000003'), 0, 'nor their summary row');
reset role;
update public.memberships set status = 'active', ended_at = null where id = 'e0000000-0000-4000-8000-000000000003';

-- An anonymous (trainee-style) session is never a manager, even for its own gym's data ---
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.member_session_stats), 0, 'a trainee session cannot read colleagues');
reset role;

-- Level and streak: the same cases as get_level_test.dart (GetLevel) ---------------------
-- weeks start on Saturday 2026-01-03 + 7k; three workouts per active week.
create function pg_temp.fill(p_weeks int[], p_per int default 3) returns void language plpgsql as $f$
declare k int; i int; n int := 0;
begin
  delete from public.workout_sessions where membership_id = 'e0000000-0000-4000-8000-000000000004';
  foreach k in array p_weeks loop
    for i in 0..p_per - 1 loop
      n := n + 1;
      insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets)
      values ('lv' || n, 'c0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000004', 'd1', timestamptz '2026-01-03 10:00+00' + ((7 * k + i) || ' days')::interval, '[]');
    end loop;
  end loop;
end $f$;

select pg_temp.fill(array[0,1,2,3]);
select results_eq($$ select level, best_level, streak_weeks, comeback, weeks_to_next from private.member_level('e0000000-0000-4000-8000-000000000004', timestamptz '2026-02-02 12:00+00') $$,
  $$ values ('intermediate', 'intermediate', 4, false, 8) $$, 'four active weeks: intermediate');
select results_eq($$ select level, best_level, streak_weeks, comeback, weeks_to_next from private.member_level('e0000000-0000-4000-8000-000000000004', timestamptz '2026-02-16 12:00+00') $$,
  $$ values ('beginner', 'intermediate', 0, true, 2) $$, 'a break drops a level; coming back is faster');
select pg_temp.fill(array[0,1,2,3,4,5,6,7,8,9,10,11]);
select results_eq($$ select level, best_level, streak_weeks, comeback, weeks_to_next from private.member_level('e0000000-0000-4000-8000-000000000004', timestamptz '2026-03-30 12:00+00') $$,
  $$ values ('pro', 'pro', 12, false, null::int) $$, 'twelve active weeks: pro');
select pg_temp.fill(array[0,1,2,3,4], 2);
select results_eq($$ select level, best_level, streak_weeks, comeback, weeks_to_next from private.member_level('e0000000-0000-4000-8000-000000000004', timestamptz '2026-02-09 12:00+00') $$,
  $$ values ('beginner', 'beginner', 0, false, 4) $$, 'two workouts a week is not an active week');
select pg_temp.fill(array[0,1,2,3,5,6]);
select results_eq($$ select level, best_level, streak_weeks, comeback, weeks_to_next from private.member_level('e0000000-0000-4000-8000-000000000004', timestamptz '2026-02-20 12:00+00') $$,
  $$ values ('intermediate', 'intermediate', 2, false, 8) $$, 'back to intermediate after two active weeks (comeback)');
select results_eq($$ select level, streak_weeks from private.member_level(gen_random_uuid()) $$,
  $$ values ('beginner', 0) $$, 'no workouts: beginner');

select * from finish();
rollback;
