-- Row Level Security + complete_session tests for the workout tables (pgTAP).
-- Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

-- Fixtures (as the postgres owner) ------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'member-a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'member-b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'coach@test.local');

update public.profiles set role = 'coach' where id = '33333333-3333-3333-3333-333333333333';

insert into public.exercises (id, name_en, name_ar) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Chest Press', 'صدر'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Leg Press', 'رجل');

insert into public.plans (id, coach_id, name) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'Test plan');

insert into public.plan_days (id, plan_id, day_order, name_en, name_ar) values
  ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 1, 'Upper', 'علوي'),
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001', 2, 'Lower', 'سفلي');

insert into public.plan_exercises (plan_day_id, exercise_id, position) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 1),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 1);

insert into public.plan_assignments (plan_id, member_id) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

select is(
  (select count(*)::int from pg_class
   where relnamespace = 'public'::regnamespace
     and relname in ('profiles', 'exercises', 'plans', 'plan_days', 'plan_exercises',
                     'plan_assignments', 'sessions', 'set_logs')
     and relrowsecurity),
  8,
  'RLS is enabled on every workout table'
);

select is(
  (select role from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  'member',
  'sign-up creates a member profile'
);

-- Anonymous -------------------------------------------------------------------
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is(
  (select count(*)::int from public.exercises) + (select count(*)::int from public.plans),
  0,
  'anon cannot read exercises or plans'
);

-- Member A --------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.plan_days),
  2,
  'member reads the days of their assigned plan'
);

select is(
  (select count(*)::int from public.plan_exercises),
  2,
  'member reads the exercises of their assigned plan'
);

select results_eq(
  $$ with changed as (
       update public.plan_assignments set next_day_order = 2 returning 1
     ) select count(*)::int from changed $$,
  $$ values (0) $$,
  'member cannot move their plan by hand'
);

select throws_ok(
  $$ update public.profiles set role = 'coach'
     where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501', null,
  'member cannot promote themselves to coach'
);

select lives_ok(
  $$ insert into public.sessions (id, plan_day_id)
     values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001') $$,
  'member starts a session'
);

select lives_ok(
  $$ insert into public.set_logs (session_id, exercise_id, set_number, weight_kg, reps, logged_at) values
       ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 1, 40, 10, now() - interval '2 minutes'),
       ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 2, 40, 9, now() - interval '1 minute') $$,
  'member logs sets in their session'
);

select results_eq(
  $$ with changed as (
       update public.sessions set status = 'completed' returning 1
     ) select count(*)::int from changed $$,
  $$ values (0) $$,
  'member cannot complete a session without complete_session()'
);

select is(
  public.complete_session('dddddddd-0000-0000-0000-000000000001'),
  2,
  'complete_session moves the plan to day 2'
);

select is(
  public.complete_session('dddddddd-0000-0000-0000-000000000001'),
  2,
  'completing the same session again does not skip a day'
);

insert into public.sessions (id, plan_day_id)
values ('dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002');

select is(
  public.complete_session('dddddddd-0000-0000-0000-000000000002'),
  1,
  'after the last day the plan wraps to day 1'
);

select results_eq(
  $$ select set_number, weight_kg, reps from public.exercise_last_sets
     where exercise_id = 'aaaaaaaa-0000-0000-0000-000000000001' order by set_number $$,
  $$ values (1, 40.00::numeric(6, 2), 10), (2, 40.00::numeric(6, 2), 9) $$,
  'exercise_last_sets returns the sets of the last session for that exercise'
);

-- Member B (no plan) ----------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.plans) + (select count(*)::int from public.plan_days),
  0,
  'another member cannot read a plan not assigned to them'
);

select is(
  (select count(*)::int from public.sessions)
    + (select count(*)::int from public.set_logs)
    + (select count(*)::int from public.exercise_last_sets),
  0,
  'another member cannot read someone else''s sessions or sets'
);

select throws_ok(
  $$ insert into public.set_logs (session_id, member_id, exercise_id, set_number, weight_kg, reps)
     values ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
             'aaaaaaaa-0000-0000-0000-000000000001', 3, 100, 1) $$,
  '42501', null,
  'another member cannot log sets for someone else'
);

select throws_ok(
  $$ select public.complete_session('dddddddd-0000-0000-0000-000000000001') $$,
  'P0002', null,
  'another member cannot complete someone else''s session'
);

-- Coach -----------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);

select results_eq(
  $$ with changed as (
       update public.plan_assignments set next_day_order = 2 returning 1
     ) select count(*)::int from changed $$,
  $$ values (1) $$,
  'coach can adjust assignments of their own plan'
);

select * from finish();
rollback;
