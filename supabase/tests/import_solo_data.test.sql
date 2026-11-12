-- Tests for import_solo_data: moving solo history and plan into the account (pgTAP).
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

select plan(39);


-- people without a person cannot import
insert into auth.users (id, is_anonymous) values ('b1000000-0000-4000-8000-000000000001', true);
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, null) $$, '42501', null, 'anon cannot import');
reset role;
reset request.jwt.claims;


set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';
select throws_ok($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, null) $$, '42501', null, 'a user who has not joined a gym (no person) cannot import yet');
reset role;
reset request.jwt.claims;


-- trainee 1 moves three sessions and the plan
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

create temp table first as select public.import_solo_data('[{"client_id": "c1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c2", "day_id": "d1", "finished_at": "2026-10-02T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c3", "day_id": "d2", "finished_at": "2026-10-03T10:00:00.123Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, '{"days": [{"id": "d1", "name": {"ar": "\u0635\u062f\u0631", "en": "Chest"}, "exercises": [{"id": "e1", "name": {"ar": "\u0628\u0646\u0634", "en": "Bench"}, "sets": 3, "reps": 10, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r;
grant all on first to authenticated;
select results_eq($$ select r ->> 'imported', r ->> 'skipped', r ->> 'plan_saved', r ->> 'solo_total' from first $$, $$ values ('3', '0', 'true', '3') $$, 'three sessions and the plan are imported');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000003' and gym_id is null), 3, 'they are solo sessions (no gym)');
select results_eq($$ select (sets -> 0 ->> 'weight')::numeric, day_id from public.workout_sessions where client_id = 'c3' $$, $$ values (60::numeric, 'd2') $$, 'content is kept as sent');
select is((select body from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000003'), '{"days": [{"id": "d1", "name": {"ar": "\u0635\u062f\u0631", "en": "Chest"}, "exercises": [{"id": "e1", "name": {"ar": "\u0628\u0646\u0634", "en": "Bench"}, "sets": 3, "reps": 10, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb, 'the plan is stored as sent');

-- sending the same chunk again changes nothing (a lost answer is safe)
select results_eq($$ select r ->> 'imported', r ->> 'skipped', r ->> 'plan_saved', r ->> 'solo_total' from (select public.import_solo_data('[{"client_id": "c1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c2", "day_id": "d1", "finished_at": "2026-10-02T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c3", "day_id": "d2", "finished_at": "2026-10-03T10:00:00.123Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, '{"days": [{"id": "d1", "name": {"ar": "\u0635\u062f\u0631", "en": "Chest"}, "exercises": [{"id": "e1", "name": {"ar": "\u0628\u0646\u0634", "en": "Bench"}, "sets": 3, "reps": 10, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r) s $$, $$ values ('0', '3', 'false', '3') $$, 'a retry imports nothing and loses nothing');
-- a resumed chunk: two already there, one new
select results_eq($$ select r ->> 'imported', r ->> 'skipped', r ->> 'solo_total' from (select public.import_solo_data('[{"client_id": "c2", "day_id": "d1", "finished_at": "2026-10-02T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c4", "day_id": "d1", "finished_at": "2026-10-04T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, null) as r) s $$, $$ values ('1', '1', '4') $$, 'a resumed chunk adds only what is new');
-- the plan is never overwritten
select results_eq($$ select r ->> 'plan_saved' from (select public.import_solo_data('[]'::jsonb, '{"days": [{"id": "d9", "name": {"ar": "x", "en": "x"}, "exercises": []}]}'::jsonb) as r) s $$, $$ values ('false') $$, 'an existing personal plan is not overwritten');
select is((select body -> 'days' -> 0 ->> 'id' from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000003'), 'd1', 'it is still the first plan');
select results_eq($$ select r ->> 'imported' from (select public.import_solo_data('[]'::jsonb, 'null'::jsonb) as r) s $$, $$ values ('0') $$, 'an empty chunk and a JSON null plan are fine');

-- hostile input: nothing is half written
select throws_like($$ select public.import_solo_data('{}'::jsonb) $$, 'invalid_import: %', 'refused: sessions is an object');
select throws_like($$ select public.import_solo_data(null::jsonb) $$, 'invalid_import: %', 'refused: sessions is null');
select throws_like($$ select public.import_solo_data('[{"client_id": "c0", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c2", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c3", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c4", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c5", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c6", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c7", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c8", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c9", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c10", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c11", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c12", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c13", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c14", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c15", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c16", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c17", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c18", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c19", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c20", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c21", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c22", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c23", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c24", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c25", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c26", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c27", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c28", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c29", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c30", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c31", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c32", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c33", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c34", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c35", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c36", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c37", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c38", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c39", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c40", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c41", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c42", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c43", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c44", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c45", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c46", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c47", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c48", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c49", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "c50", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: 51 sessions');
select throws_like($$ select public.import_solo_data('[{"client_id": "same", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "same", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: duplicate client ids in one call');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z"}]'::jsonb) $$, 'invalid_import: %', 'refused: a session with a missing key');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}], "gym_id": "x"}]'::jsonb) $$, 'invalid_import: %', 'refused: a session with an extra key');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day": 0, "finished_at": "2026-10-01T10:00:00Z", "sets": []}]'::jsonb) $$, 'invalid_import: %', 'refused: the legacy shape (day as a number)');
select throws_like($$ select public.import_solo_data('[{"client_id": "", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: an empty client id');
select throws_like($$ select public.import_solo_data('[{"client_id": "ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: a client id of 65 characters');
select throws_like($$ select public.import_solo_data('[{"client_id": "../x", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: a client id with ../');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1''; drop table plans;--", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: an injection-like day id');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "yesterday", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: a finish time that is not a time');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2019-12-31T23:59:59Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: a finish time before 2020');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2099-01-01T00:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: a finish time two days ahead');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: a date without a time');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": -5, "reps": 1}]}]'::jsonb) $$, 'invalid_import: %', 'refused: sets with a negative weight');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 5, "reps": 1001}]}]'::jsonb) $$, 'invalid_import: %', 'refused: sets with reps 1001');
select throws_like($$ select public.import_solo_data('[{"client_id": "a", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": {"a": 1}}]'::jsonb) $$, 'invalid_import: %', 'refused: sets that are not a list');
select throws_like($$ select public.import_solo_data('[{"client_id": "g1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "g2", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}, {"client_id": "bad", "day_id": "d1", "finished_at": "nope", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb) $$, 'invalid_import: %', 'refused: one bad session among good ones');
select throws_like($$ select public.import_solo_data('[{"client_id": "p1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, '{"days": []}'::jsonb) $$, 'invalid_import: plan: %', 'refused: a plan with no days');
select throws_like($$ select public.import_solo_data('[{"client_id": "p1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, '[]'::jsonb) $$, 'invalid_import: plan: %', 'refused: a plan that is a list');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000003' and gym_id is null), 4, 'rejected chunks left nothing behind');
reset role;
reset request.jwt.claims;


-- nobody else sees them
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.workout_sessions where client_id in ('c1','c2','c3','c4')), 0, 'trainee 2 cannot read trainee 1''s imported sessions');
select results_eq($$ select r ->> 'imported' from (select public.import_solo_data('[{"client_id": "c1", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, null) as r) s $$, $$ values ('1') $$, 'the same client id from another person is that person''s own session');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.workout_sessions where client_id in ('c1','c2','c3','c4')), 0, 'a captain never reads imported solo sessions');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.workout_sessions where client_id in ('c1','c2','c3','c4')), 0, 'neither does the owner');
reset role;
reset request.jwt.claims;


-- the solo cap
insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
  select 'fill' || g, 'c0000000-0000-4000-8000-000000000005', 'd1', now(), '[]' from generate_series(1, 20000) g;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select throws_like($$ select public.import_solo_data('[{"client_id": "one-too-many", "day_id": "d1", "finished_at": "2026-10-01T10:00:00Z", "sets": [{"exercise": "e1", "weight": 60, "reps": 10}]}]'::jsonb, null) $$, 'invalid_import: too many solo sessions', 'at most 20000 solo sessions per person');
reset role;
reset request.jwt.claims;

-- roles that must not call it
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select public.import_solo_data('[]'::jsonb) $$, '42501', null, 'anon has no execute on import_solo_data');
reset role;
reset request.jwt.claims;


select * from finish();
rollback;
