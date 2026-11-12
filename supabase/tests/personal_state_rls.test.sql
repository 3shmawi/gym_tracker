-- pgTAP for "never lose your training", PR 2 (migration 0022).
-- Run: supabase test db   (docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

-- Fixture ---------------------------------------------------------------
--   a1: permanent user WITHOUT a person (a solo member who just signed in)
--   a2: permanent user with a person, solo only          (person c2)
--   a3: anonymous gym trainee with a person              (person c3, gym A)
--   a4: permanent captain of gym A with a person         (person c4)
--   a5: anonymous user without a person
insert into auth.users (id, is_anonymous) values
  ('a0000000-0000-4000-8000-000000000001', false),
  ('a0000000-0000-4000-8000-000000000002', false),
  ('a0000000-0000-4000-8000-000000000003', true),
  ('a0000000-0000-4000-8000-000000000004', false),
  ('a0000000-0000-4000-8000-000000000005', true);
insert into public.gyms (id, name) values ('d0000000-0000-4000-8000-00000000000a', 'Gym A');
insert into public.people (id, auth_user_id, display_name) values
  ('c0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'Solo 2'),
  ('c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Trainee 3'),
  ('c0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004', 'Captain 4');
insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at) values
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 'Trainee 3', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000004', 'Captain 4', 'captain', 'active', now());

select plan(68);

-- ---- RLS on the new table ----------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = 'public.personal_state'::regclass), 'RLS is enabled on personal_state');
insert into public.personal_state (person_id, best_level) values
  ('c0000000-0000-4000-8000-000000000002', 'pro'), ('c0000000-0000-4000-8000-000000000003', 'intermediate');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select * from public.personal_state $$, '42501', null, 'anon cannot read personal state');
select throws_ok($$ select public.ensure_person() $$, '42501', null, 'anon cannot call ensure_person');
select throws_ok($$ select public.save_personal_plan(0, '{"days":[]}') $$, '42501', null, 'anon cannot save a personal plan');
select throws_ok($$ select public.save_personal_state('pro', null) $$, '42501', null, 'anon cannot save personal state');
select throws_ok($$ select public.delete_my_backup() $$, '42501', null, 'anon cannot delete a backup');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select results_eq($$ select person_id from public.personal_state $$, $$ values ('c0000000-0000-4000-8000-000000000002'::uuid) $$, 'a person reads only their own state');
select throws_ok($$ insert into public.personal_state (person_id) values ('c0000000-0000-4000-8000-000000000002') $$, '42501', null, 'no direct insert');
select throws_ok($$ update public.personal_state set best_level = 'beginner' $$, '42501', null, 'no direct update');
select throws_ok($$ delete from public.personal_state $$, '42501', null, 'no direct delete');
reset role;
reset request.jwt.claims;

-- ---- ensure_person -------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":true}';
select throws_ok($$ select public.ensure_person() $$, '42501', null, 'an anonymous session cannot create a person');
reset role;
reset request.jwt.claims;
select is((select count(*)::int from public.people where auth_user_id = 'a0000000-0000-4000-8000-000000000005'), 0, '... and none was made');

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select throws_ok($$ select public.ensure_person() $$, '42501', null, 'an anonymous gym trainee is refused too (they add an email first)');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select isnt(public.ensure_person(), null, 'a permanent session without a person gets one');
select is(public.ensure_person(), public.ensure_person(), 'and asking again returns the same person');
reset role;
reset request.jwt.claims;
select is((select count(*)::int from public.people where auth_user_id = 'a0000000-0000-4000-8000-000000000001'), 1, 'exactly one person row');

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is(public.ensure_person(), 'c0000000-0000-4000-8000-000000000002'::uuid, 'a permanent session with a person gets that person');
reset role;
reset request.jwt.claims;

-- ---- save_personal_plan ----------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is(
  (public.save_personal_plan(0, '{"days":[{"id":"d1","name":{"ar":"أ","en":"A"},"exercises":[]}]}'::jsonb) ->> 'version')::int,
  1, 'the first save (base 0) is version 1');
select throws_ok($$ select public.save_personal_plan(0, '{"days":[{"id":"d1","name":{"ar":"أ","en":"B"},"exercises":[]}]}') $$, 'P0001', 'plan_changed', 'base 0 when a plan exists: plan_changed (saved first wins)');
select throws_ok($$ select public.save_personal_plan(5, '{"days":[{"id":"d1","name":{"ar":"أ","en":"B"},"exercises":[]}]}') $$, 'P0001', 'plan_changed', 'a wrong base: plan_changed');
select is(
  (public.save_personal_plan(1, '{"days":[{"id":"d1","name":{"ar":"أ","en":"B"},"exercises":[]}]}'::jsonb) ->> 'version')::int,
  2, 'the right base makes version 2');
select is(
  (public.save_personal_plan(2, '{"days":[{"id":"d1","name":{"ar":"أ","en":"B"},"exercises":[]}]}'::jsonb) ->> 'version')::int,
  2, 'the same body again does not make a new version');
select throws_like($$ select public.save_personal_plan(2, '[]') $$, 'invalid_plan:%', 'a body that is not a plan is refused');
select throws_like($$ select public.save_personal_plan(2, '{"days":7}') $$, 'invalid_plan:%', 'wrong types are refused');
select throws_like($$ select public.save_personal_plan(2, '{"days":[]}') $$, 'invalid_plan:%', 'no days is refused');
select throws_like($$ select public.save_personal_plan(2, ('{"days":[{"id":"d1","name":{"ar":"أ","en":"' || repeat('x', 70000) || '"},"exercises":[]}]}')::jsonb) $$, 'invalid_plan:%', 'over 64 KB is refused');
select throws_like($$ select public.save_personal_plan(-1, '{"days":[{"id":"d1","name":{"ar":"أ","en":"B"},"exercises":[]}]}') $$, 'invalid_plan:%', 'a negative base is refused');
select lives_ok($$ select public.save_personal_plan(2, '{"days":[{"id":"d1","name":{"ar":"أ","en":"''; drop table plans;--"},"exercises":[]}]}') $$, 'an injection-like name is plain text: saved as it is, never run');
select is((select body -> 'days' -> 0 -> 'name' ->> 'en' from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000002'), '''; drop table plans;--', '... and read back unchanged');
select is((select version from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000002'), 3, 'the refused saves changed nothing: only the accepted ones made versions');
reset role;
reset request.jwt.claims;

-- another person cannot touch it, and a person without a person row is refused
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.personal_plans), 0, 'another person does not see the plan');
select is(
  (public.save_personal_plan(0, '{"days":[{"id":"x","name":{"ar":"أ","en":"Mine"},"exercises":[]}]}'::jsonb) ->> 'version')::int,
  1, 'they have their own, starting at version 1');
reset role;
reset request.jwt.claims;
select is((select version from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000002'), 3, 'the first person''s plan is untouched');

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":true}';
select throws_ok($$ select public.save_personal_plan(0, '{"days":[{"id":"x","name":{"ar":"أ","en":"N"},"exercises":[]}]}') $$, '42501', null, 'a user without a person cannot save a plan');
reset role;
reset request.jwt.claims;

-- ---- save_personal_state ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((public.save_personal_state('beginner', '{"id":"day-2","by_edit":false}') ->> 'best_level'), 'pro', 'best level only goes up (pro stays pro)');
select is((select chosen_day ->> 'id' from public.personal_state), 'day-2', 'the chosen day is the last write');
select is((public.save_personal_state('pro', null) -> 'chosen_day'), 'null'::jsonb, 'a null chosen day clears it');
select throws_like($$ select public.save_personal_state('legend', null) $$, 'invalid_state:%', 'an unknown level is refused');
select throws_like($$ select public.save_personal_state(null, null) $$, 'invalid_state:%', 'a null level is refused');
select throws_like($$ select public.save_personal_state('pro', '[]') $$, 'invalid_state:%', 'a chosen day that is a list is refused');
select throws_like($$ select public.save_personal_state('pro', '{"id":"x","extra":1}') $$, 'invalid_state:%', 'an extra key is refused');
select throws_like($$ select public.save_personal_state('pro', '{"id":"a b"}') $$, 'invalid_state:%', 'a bad id is refused');
select throws_like($$ select public.save_personal_state('pro', ('{"id":"' || repeat('a', 300) || '"}')::jsonb) $$, 'invalid_state:%', 'a too long chosen day is refused');
select throws_like($$ select public.save_personal_state('pro', '{"id":"x","by_edit":"yes"}') $$, 'invalid_state:%', 'by_edit must be a boolean');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select is((public.save_personal_state('intermediate', '{"id":"day-1"}') ->> 'best_level'), 'intermediate', 'a new person starts from what they send');
select is((public.save_personal_state('beginner', null) ->> 'best_level'), 'intermediate', 'a lower level later does not lower it');
reset role;
reset request.jwt.claims;

-- ---- the cap: 20,000 workouts per person --------------------------------------------
insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  select 'fill' || g, 'c0000000-0000-4000-8000-000000000002', 'd1', now(), '[]' from generate_series(1, 19990) g;
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000002'), 19990, '19,990 workouts fit');

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
-- a direct insert of 10 more reaches exactly 20,000: allowed
select lives_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  select 'top' || g, 'c0000000-0000-4000-8000-000000000002', 'd1', now(), '[]' from generate_series(1, 10) g $$, 'exactly 20,000 is allowed');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  values ('one-more', 'c0000000-0000-4000-8000-000000000002', 'd1', now(), '[]') $$, '54000', null, 'the 20,001st workout is refused, also as a direct insert');
reset role;
reset request.jwt.claims;
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000002'), 20000, 'nothing was added past the cap');

-- a batch that would cross the cap is refused as a whole
delete from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000002' and client_id like 'top%';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  select 'batch' || g, 'c0000000-0000-4000-8000-000000000002', 'd1', now(), '[]' from generate_series(1, 11) g $$, '54000', null, 'an 11-row batch at 19,990 crosses the cap: refused');
reset role;
reset request.jwt.claims;
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000002' and client_id like 'batch%'), 0, '... and none of its rows were kept');

-- the cap is for each person
insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  values ('mine', 'c0000000-0000-4000-8000-000000000004', 'd1', now(), '[]');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000004'), 1, 'another person is not affected by the cap');

-- import_solo_data counts the new cap (it was 1000)
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select lives_ok($$ select public.import_solo_data('[{"client_id": "imp1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": []}]'::jsonb, null) $$, 'import works for a new person');
reset role;
reset request.jwt.claims;
insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  select 'many' || g, (select id from public.people where auth_user_id = 'a0000000-0000-4000-8000-000000000001'), 'd1', now(), '[]' from generate_series(1, 1500) g;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select lives_ok($$ select public.import_solo_data('[{"client_id": "imp2", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": []}]'::jsonb, null) $$, 'a person with 1,500 workouts can import more (the old limit was 1000)');
reset role;
reset request.jwt.claims;

-- ---- staff never see solo rows, including a gym workout sent again as solo ---------------
insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  values ('fell-back-solo', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[]');
insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets)
  values ('in-the-gym', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[]');
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}';
select results_eq($$ select client_id from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000003' $$, $$ values ('in-the-gym') $$, 'the captain sees the gym workout and never the solo one');
select is((select count(*)::int from public.personal_plans), 0, 'the captain does not see personal plans');
select is((select count(*)::int from public.personal_state), 0, 'the captain does not see personal state');
reset role;
reset request.jwt.claims;

-- ---- delete_my_backup -----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select is((public.delete_my_backup() ->> 'sessions_deleted')::int, 1, 'it deletes the solo workouts');
reset role;
reset request.jwt.claims;
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000003' and gym_id is null), 0, 'no solo workout left');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000003' and gym_id is not null), 1, 'the gym workout stays');
select is((select count(*)::int from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000003'), 0, 'the personal plan is gone');
select is((select count(*)::int from public.personal_state where person_id = 'c0000000-0000-4000-8000-000000000003'), 0, 'the personal state is gone');
select is((select count(*)::int from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000002'), 1, 'another person''s backup is untouched');
select is((select count(*)::int from public.memberships where person_id = 'c0000000-0000-4000-8000-000000000003'), 1, 'the membership stays');

-- ---- deleting the account removes the rest ------------------------------------------------------
delete from auth.users where id = 'a0000000-0000-4000-8000-000000000002';
select is((select count(*)::int from public.personal_state where person_id = 'c0000000-0000-4000-8000-000000000002'), 0, 'deleting the account removes the personal state');
select is((select count(*)::int from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000002'), 0, '... and the personal plan');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000002'), 0, '... and every workout');

select * from finish();
rollback;
