-- Row Level Security tests for plans and save_plan (pgTAP).
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

select plan(80);


select ok(
  (select relrowsecurity from pg_class where oid = 'public.plans'::regclass),
  'RLS is enabled on plans'
);

-- Membership 3 (trainee 1) gets a plan from the table owner; membership 4 has none.
insert into public.plans (membership_id, body, version, updated_by)
  values ('e0000000-0000-4000-8000-000000000003', '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb, 1, 'e0000000-0000-4000-8000-000000000002');
-- a plan for the gym B trainee
insert into public.plans (membership_id, body, version, updated_by)
  values ('e0000000-0000-4000-8000-000000000006', '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb, 1, 'e0000000-0000-4000-8000-000000000005');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.plans $$, '42501', null, 'anon cannot read plans');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'anon cannot save plans');
reset role;
reset request.jwt.claims;

-- reads ----------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select membership_id from public.plans $$, $$ values ('e0000000-0000-4000-8000-000000000003'::uuid) $$, 'a trainee reads only their own plan');
select throws_ok($$ insert into public.plans (membership_id, body) values ('e0000000-0000-4000-8000-000000000004', '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a trainee cannot write plans directly');
select throws_ok($$ update public.plans set body = '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb $$, '42501', null, 'a trainee cannot update plans directly');
select throws_ok($$ delete from public.plans $$, '42501', null, 'a trainee cannot delete plans');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003'), 0, 'trainee 2 cannot read trainee 1''s plan');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000006","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003'), 0, 'a trainee of gym B cannot read a gym A plan');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select results_eq($$ select membership_id from public.plans $$, $$ values ('e0000000-0000-4000-8000-000000000006'::uuid) $$, 'a captain of gym B reads only gym B plans');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select results_eq($$ select membership_id from public.plans $$, $$ values ('e0000000-0000-4000-8000-000000000003'::uuid) $$, 'a captain reads the plans of their gym');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.plans), 0, 'an anonymous session cannot read gym plans, even for a captain');
reset role;
reset request.jwt.claims;


-- hostile plans (every one is refused with invalid_plan) ------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '[]'::jsonb) $$, 'invalid_plan: %', 'refused: a list instead of an object');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '"plan"'::jsonb) $$, 'invalid_plan: %', 'refused: a string');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}], "admin": true}'::jsonb) $$, 'invalid_plan: %', 'refused: an extra top-level key');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": []}'::jsonb) $$, 'invalid_plan: %', 'refused: no days');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d0", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d2", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d3", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d4", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d5", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d6", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d7", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d8", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d9", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d10", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d11", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d12", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d13", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d14", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: 15 days');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}, {"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: duplicate day ids');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1; drop table plans", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a day id with spaces and SQL');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a day id that is 65 characters');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: an empty day id');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days":[{"id":1,"name":{"ar":"a","en":"a"},"exercises":[]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a numeric day id');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "", "en": ""}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: an empty name');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "en": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a 41-character name');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "a\nb", "en": "a\nb"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a name with a new line');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "a‮b", "en": "a‮b"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a name with a bidi override');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "a  b", "en": "a  b"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a name with two spaces');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": " a", "en": " a"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a name with a leading space');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days":[{"id":"d1","name":{"ar":1,"en":2},"exercises":[]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a name that is a number');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days":[{"id":"d1","name":{"en":"a"},"exercises":[]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a name with a missing language');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e0", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e2", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e3", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e4", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e5", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e6", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e7", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e8", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e9", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e10", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e11", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e12", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e13", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e14", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e15", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e16", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e17", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e18", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e19", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e20", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e21", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e22", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e23", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e24", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e25", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e26", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e27", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e28", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e29", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e30", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: 31 exercises');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: duplicate exercise ids');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 0, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: sets = 0');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 11, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: sets = 11');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3.5, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: sets = 3.5');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": "3", "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: sets as a string');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 101, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: reps = 101');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 0, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: reps = 0');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": -1, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: rest = -1');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 601, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: rest = 601');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 0, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: step = 0');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 50.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: step = 50.5');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": "2.5", "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: step as a string');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": "yes"}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: superset as a string');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false, "weight": 100}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: an unknown exercise field');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a missing exercise field');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, '{"days":[{"id":"d1","name":{"ar":"a","en":"a"}}]}'::jsonb) $$, 'invalid_plan: %', 'refused: a day with a missing field');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, jsonb_build_object('days', jsonb_build_array(jsonb_build_object('id', 'd1', 'name', jsonb_build_object('ar', 'a', 'en', 'a'), 'exercises', '[]'::jsonb)), 'pad', repeat('x', 70000))) $$, 'invalid_plan: %', 'refused: a body over 64 KB');
select throws_like($$ select public.save_plan('e0000000-0000-4000-8000-000000000007', 0, null) $$, 'invalid_plan: %', 'refused: null');
reset role;
reset request.jwt.claims;


-- a trainee without permissions -------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a trainee without can_build_own_plan cannot create a plan');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'trainee 2 cannot write trainee 1''s plan');
reset role;
reset request.jwt.claims;

update public.memberships set can_build_own_plan = true where id = 'e0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 2, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a first plan must start from base_version 0');
select results_eq($$ select (r ->> 'version')::int, r ->> 'updated_by' from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r) s $$, $$ values (1, 'e0000000-0000-4000-8000-000000000004') $$, 'with can_build_own_plan a trainee creates their plan (version 1)');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'but cannot then change targets without can_edit_targets');
reset role;
reset request.jwt.claims;

update public.memberships set can_edit_targets = true where id = 'e0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select (r ->> 'version')::int from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) as r) s), 2, 'with can_edit_targets a trainee changes sets, reps, rest and step (version 2)');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 2, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Incline", "en": "Incline"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'renaming an exercise needs can_edit_plan');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 2, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e2", "name": {"ar": "Fly", "en": "Fly"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'adding an exercise needs can_edit_plan');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, 'P0001', 'plan_changed', 'a stale base_version is refused as plan_changed');
select is((select (r ->> 'version')::int from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 2, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) as r) s), 2, 'saving the same plan again changes nothing (no version bump)');
reset role;
reset request.jwt.claims;

update public.memberships set can_edit_plan = true where id = 'e0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select (r ->> 'version')::int from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 2, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e2", "name": {"ar": "Fly", "en": "Fly"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r) s), 3, 'with can_edit_plan a trainee adds an exercise');
select is((select (r ->> 'version')::int from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 3, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e2", "name": {"ar": "Fly", "en": "Fly"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r) s), 4, 'and reorders them');
select is((select (r ->> 'version')::int from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 4, '{"days": [{"id": "d1", "name": {"ar": "Push day", "en": "Push day"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r) s), 5, 'and renames, removes (structure edits)');
reset role;
reset request.jwt.claims;


-- the captain wins ------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select results_eq($$ select (r ->> 'version')::int, r ->> 'updated_by' from (select public.save_plan('e0000000-0000-4000-8000-000000000004', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Incline", "en": "Incline"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) as r) s $$, $$ values (6, 'e0000000-0000-4000-8000-000000000002') $$, 'a captain saves over the trainee''s plan even with an old base_version');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 5, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, 'P0001', 'plan_changed', 'the trainee''s next edit on the old version is dropped (plan_changed)');
select results_eq($$ select version, updated_by <> membership_id from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000004' $$, $$ values (6, true) $$, 'the app can tell the captain changed it: version grew and updated_by is not the trainee');
reset role;
reset request.jwt.claims;


-- other staff -----------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a captain of another gym cannot save a gym A plan');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000001', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a captain cannot save the owner''s plan');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000002', 0, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a captain cannot save a captain''s plan, their own included');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 1, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'an anonymous session cannot save plans, even for a captain');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select is((select (r ->> 'version')::int from (select public.save_plan('e0000000-0000-4000-8000-000000000003', 9, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) as r) s), 2, 'the owner can save any plan of the gym');
reset role;
reset request.jwt.claims;


-- hostile text is stored as text ---------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select lives_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 2, '{"days": [{"id": "d1", "name": {"ar": "''; drop table plans; --", "en": "''; drop table plans; --"}, "exercises": [{"id": "e1", "name": {"ar": "<script>alert(1)</script>", "en": "<script>alert(1)</script>"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'injection-like names are accepted as plain text');
select lives_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 3, '{"days": [{"id": "d1", "name": {"ar": "صدر وترايسبس", "en": "صدر وترايسبس"}, "exercises": [{"id": "e1", "name": {"ar": "ضغط بنش 🏋️", "en": "ضغط بنش 🏋️"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb) $$, 'Arabic and emoji names are accepted');
reset role;
reset request.jwt.claims;

select is((select count(*)::int from public.plans), 3, 'no plan row was lost or duplicated');

-- ended members and deleted gyms -------------------------------------------------------------------
update public.memberships set status = 'ended', ended_at = now() where id = 'e0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.plans), 0, 'an ended member can no longer read their plan');
select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000004', 6, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'an ended member cannot save it');
reset role;
reset request.jwt.claims;

update public.gyms set deleted_at = now() where id = 'd0000000-0000-4000-8000-00000000000a';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 3, '{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb) $$, '42501', null, 'a deleted gym accepts no plan changes, not even from its owner');
reset role;
reset request.jwt.claims;


-- the helper functions behind it --------------------------------------------------------------
select is(private.plan_structure('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 4, "reps": 10, "rest": 120, "step": 5, "superset": false}]}]}'::jsonb), private.plan_structure('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb), 'changing targets does not change the structure');
select isnt(private.plan_structure('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Incline", "en": "Incline"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb), private.plan_structure('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb), 'renaming changes the structure');
select isnt(private.plan_structure('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e2", "name": {"ar": "Fly", "en": "Fly"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb), private.plan_structure('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}, {"id": "e2", "name": {"ar": "Fly", "en": "Fly"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb), 'reordering changes the structure');
select is(private.plan_problem('{"days": [{"id": "d1", "name": {"ar": "Push", "en": "Push"}, "exercises": [{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}]}]}'::jsonb), null, 'the baseline plan is valid');

select * from finish();
rollback;
