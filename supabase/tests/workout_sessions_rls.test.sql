-- Row Level Security tests for workout_sessions (pgTAP).
-- Run: supabase test db   (pgTAP; docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

-- Fixture ---------------------------------------------------------------
--   gym A: owner (01), captain (02), trainee 1 (03), trainee 2 (04),
--          a pending trainee without a person (membership 07)
--   gym B: captain (05), trainee (06)
-- auth users a0..0NN, people c0..0NN, memberships e0..0NN, gyms d0..0a / d0..0b.
-- Owners and captains have permanent sessions; trainees are anonymous users.
insert into auth.users (id, is_anonymous) values
  ('a0000000-0000-4000-8000-000000000001', false),
  ('a0000000-0000-4000-8000-000000000002', false),
  ('a0000000-0000-4000-8000-000000000003', true),
  ('a0000000-0000-4000-8000-000000000004', true),
  ('a0000000-0000-4000-8000-000000000005', false),
  ('a0000000-0000-4000-8000-000000000006', true);

insert into public.gyms (id, name) values
  ('d0000000-0000-4000-8000-00000000000a', 'Gym A'),
  ('d0000000-0000-4000-8000-00000000000b', 'Gym B');

insert into public.people (id, auth_user_id, display_name) values
  ('c0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Owner A'),
  ('c0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'Captain A'),
  ('c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Trainee 1'),
  ('c0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004', 'Trainee 2'),
  ('c0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000005', 'Captain B'),
  ('c0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000006', 'Trainee B');

insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at) values
  ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000001', 'Owner A', 'owner', 'active', now()),
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'Captain A', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 'Trainee 1', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000004', 'Trainee 2', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000005', 'Captain B', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000006', 'Trainee B', 'trainee', 'active', now());
insert into public.memberships (id, gym_id, display_name, role, status) values
  ('e0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-00000000000a', 'Pending Trainee', 'trainee', 'pending');

select plan(50);


select ok((select relrowsecurity from pg_class where oid = 'public.workout_sessions'::regclass), 'RLS is enabled on workout_sessions');

-- trainee 1: S1 solo, S2 in gym A. trainee 2: S3 in gym A, S5 solo. gym B trainee: S4. captain A: S6.
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000003', null, null, 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000004', 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-000000000006', 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000005', 'f1000000-0000-4000-8000-000000000005', 'c0000000-0000-4000-8000-000000000004', null, null, 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb);
insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000006', 'f1000000-0000-4000-8000-000000000006', 'c0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000002', 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.workout_sessions $$, '42501', null, 'anon cannot read sessions');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('x', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[]') $$, '42501', null, 'anon cannot log sessions');
reset role;
reset request.jwt.claims;

-- trainee 1 -----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.workout_sessions order by id $$, $$ values ('f1000000-0000-4000-8000-000000000001'::uuid), ('f1000000-0000-4000-8000-000000000002'::uuid) $$, 'a trainee reads only their own sessions (solo and gym)');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000004'), 0, 'trainee 1 cannot read trainee 2''s sessions');
select results_eq($$ with c as (update public.workout_sessions set sets = '[]'::jsonb where id = 'f1000000-0000-4000-8000-000000000003' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'trainee 1 cannot edit trainee 2s session');

select results_eq($$ with c as (update public.workout_sessions set sets = '[]'::jsonb where id = 'f1000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'a trainee edits their own session');

select throws_ok($$ update public.workout_sessions set person_id = 'c0000000-0000-4000-8000-000000000004' where id = 'f1000000-0000-4000-8000-000000000001' $$, '42501', null, 'a session cannot be handed to someone else');
select throws_ok($$ update public.workout_sessions set gym_id = 'd0000000-0000-4000-8000-00000000000a' where id = 'f1000000-0000-4000-8000-000000000001' $$, '42501', null, 'a solo session cannot be moved into a gym');
select throws_ok($$ update public.workout_sessions set client_id = 'other' where id = 'f1000000-0000-4000-8000-000000000001' $$, '42501', null, 'the client id is fixed');
select lives_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('new-solo', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, 'a trainee logs a solo session');
select lives_ok($$ insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('new-gym', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, 'a trainee logs a session in a gym where they are active');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('forge', 'c0000000-0000-4000-8000-000000000004', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '42501', null, 'a session cannot be logged for someone else');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('wrong-gym', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-000000000006', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '42501', null, 'a session cannot be logged in a gym the person is not in');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('mismatch', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '42501', null, 'the membership must belong to the gym');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('hijack', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000004', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '42501', null, 'a session cannot use another member''s membership');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, membership_id, day_id, finished_at, sets) values ('nogym', 'c0000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, null, null, 'a membership without a gym is refused');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '23505', null, 'the same client id twice is refused');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('../x', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '23514', null, 'a client id with odd characters is refused');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('c1', 'c0000000-0000-4000-8000-000000000003', 'd 1; --', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '23514', null, 'a day id with odd characters is refused');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad0', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '{}'::jsonb) $$, 'invalid_session: %', 'refused: an object instead of a list');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad1', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '"x"'::jsonb) $$, 'invalid_session: %', 'refused: a string');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad2', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 1, "reps": 1, "note": "x"}]'::jsonb) $$, 'invalid_session: %', 'refused: a set with an extra key');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad3', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 1}]'::jsonb) $$, 'invalid_session: %', 'refused: a set with a missing key');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad4', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": -1, "reps": 1}]'::jsonb) $$, 'invalid_session: %', 'refused: a negative weight');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad5', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 1001, "reps": 1}]'::jsonb) $$, 'invalid_session: %', 'refused: a weight over 1000');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad6', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": "60", "reps": 1}]'::jsonb) $$, 'invalid_session: %', 'refused: weight as a string');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad7', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 1, "reps": 1001}]'::jsonb) $$, 'invalid_session: %', 'refused: reps over 1000');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad8', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 1, "reps": 2.5}]'::jsonb) $$, 'invalid_session: %', 'refused: reps = 2.5');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad9', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e 1", "weight": 1, "reps": 1}]'::jsonb) $$, 'invalid_session: %', 'refused: an exercise id with spaces');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad10', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1''; drop table x;--", "weight": 1, "reps": 1}]'::jsonb) $$, 'invalid_session: %', 'refused: an injection-like exercise id');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad11', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), (select jsonb_agg(jsonb_build_object('exercise','e1','weight',1,'reps',1)) from generate_series(1,501))) $$, 'invalid_session: %', 'refused: 501 sets');
select throws_like($$ insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values ('bad12', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), (select jsonb_agg(jsonb_build_object('exercise','e1','weight',1,'reps',1,'x',repeat('y',200))) from generate_series(1,400))) $$, 'invalid_session: %', 'refused: a body over 64 KB');
select results_eq($$ with c as (delete from public.workout_sessions where id = 'f1000000-0000-4000-8000-000000000003' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'trainee 1 cannot delete trainee 2s session');

select results_eq($$ with c as (delete from public.workout_sessions where id = 'f1000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'a trainee deletes their own session');

reset role;
reset request.jwt.claims;

-- captain of gym A: own + trainees' gym sessions, never solo ones ----------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select results_eq($$ select id from public.workout_sessions where id in ('f1000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000004','f1000000-0000-4000-8000-000000000005','f1000000-0000-4000-8000-000000000006') order by id $$, $$ values ('f1000000-0000-4000-8000-000000000002'::uuid), ('f1000000-0000-4000-8000-000000000003'::uuid), ('f1000000-0000-4000-8000-000000000006'::uuid) $$, 'the captain reads their gym''s sessions, not solo sessions and not another gym''s');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('by-captain', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '42501', null, 'staff cannot log sessions for a member');
select results_eq($$ with c as (update public.workout_sessions set sets = '[]'::jsonb where id = 'f1000000-0000-4000-8000-000000000002' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'staff cannot edit a members session');

select results_eq($$ with c as (delete from public.workout_sessions where id = 'f1000000-0000-4000-8000-000000000002' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'staff cannot delete a members session');

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.workout_sessions where id in ('f1000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000006') $$, $$ values ('f1000000-0000-4000-8000-000000000006'::uuid) $$, 'an anonymous session reads only its own, even for a captain');
reset role;
reset request.jwt.claims;

-- captain of gym B and owner of gym A -------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select results_eq($$ select id from public.workout_sessions order by id $$, $$ values ('f1000000-0000-4000-8000-000000000004'::uuid) $$, 'a captain of another gym reads only their own gym''s sessions');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select results_eq($$ select id from public.workout_sessions where id in ('f1000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000003','f1000000-0000-4000-8000-000000000004','f1000000-0000-4000-8000-000000000005','f1000000-0000-4000-8000-000000000006') order by id $$, $$ values ('f1000000-0000-4000-8000-000000000002'::uuid), ('f1000000-0000-4000-8000-000000000003'::uuid), ('f1000000-0000-4000-8000-000000000006'::uuid) $$, 'the owner reads the gym''s sessions, not solo ones');
reset role;
reset request.jwt.claims;

-- ended membership + history_after_end ---------------------------------------------------
update public.memberships set status = 'ended', ended_at = now() where id = 'e0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.workout_sessions order by id $$, $$ values ('f1000000-0000-4000-8000-000000000003'::uuid), ('f1000000-0000-4000-8000-000000000005'::uuid) $$, 'readable: a person who left still reads the gym''s history');
select throws_ok($$ insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('after-end', 'c0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000004', 'd1', now(), '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]') $$, '42501', null, 'an ended member cannot log into the gym');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.workout_sessions where id = 'f1000000-0000-4000-8000-000000000003'), 0, 'staff no longer read an ended member''s sessions');
reset role;
reset request.jwt.claims;

update public.gyms set history_after_end = 'locked' where id = 'd0000000-0000-4000-8000-00000000000a';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.workout_sessions order by id $$, $$ values ('f1000000-0000-4000-8000-000000000005'::uuid) $$, 'locked: the gym''s sessions are hidden, solo ones stay');
select results_eq($$ with c as (update public.workout_sessions set sets = '[]'::jsonb where id = 'f1000000-0000-4000-8000-000000000003' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'locked sessions cannot be edited either');

reset role;
reset request.jwt.claims;

select is((select count(*)::int from public.workout_sessions where id = 'f1000000-0000-4000-8000-000000000003'), 1, 'locked hides, it never deletes');
update public.gyms set history_after_end = 'readable' where id = 'd0000000-0000-4000-8000-00000000000a';

-- the same client id may exist for two people ------------------------------------------------
select lives_ok($$ insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000007', 'shared', 'c0000000-0000-4000-8000-000000000005', null, null, 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb); insert into public.workout_sessions (id, client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values ('f1000000-0000-4000-8000-000000000008', 'shared', 'c0000000-0000-4000-8000-000000000006', null, null, 'd1', '2026-10-01T10:00:00Z', '[{"exercise": "e1", "weight": 60, "reps": 10}, {"exercise": "e2", "weight": 22.5, "reps": 12}]'::jsonb); $$, 'two people can have the same client id');
-- deleting the person deletes their history ----------------------------------------------------
delete from public.people where id = 'c0000000-0000-4000-8000-000000000006';
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000006'), 0, 'deleting a person deletes their sessions');

select * from finish();
rollback;
