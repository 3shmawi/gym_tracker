-- Row Level Security tests for personal_plans (pgTAP).
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

select plan(12);


select ok((select relrowsecurity from pg_class where oid = 'public.personal_plans'::regclass), 'RLS is enabled on personal_plans');
insert into public.personal_plans (person_id, body) values ('c0000000-0000-4000-8000-000000000003', '{"days":[]}'), ('c0000000-0000-4000-8000-000000000004', '{"days":[]}');
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.personal_plans $$, '42501', null, 'anon cannot read personal plans');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select person_id from public.personal_plans $$, $$ values ('c0000000-0000-4000-8000-000000000003'::uuid) $$, 'a person reads only their own personal plan');
select throws_ok($$ insert into public.personal_plans (person_id, body) values ('c0000000-0000-4000-8000-000000000003', '{"days":[]}') $$, '42501', null, 'no direct insert');
select throws_ok($$ update public.personal_plans set body = '{}' $$, '42501', null, 'no direct update');
select throws_ok($$ delete from public.personal_plans $$, '42501', null, 'no direct delete');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.personal_plans), 0, 'a captain cannot read members'' personal plans');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.personal_plans), 0, 'the owner cannot read members'' personal plans either');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.personal_plans), 0, 'a captain of another gym reads none');
reset role;
reset request.jwt.claims;

select throws_ok($$ insert into public.personal_plans (person_id, body) values ('c0000000-0000-4000-8000-000000000003', '{"days":[]}') $$, '23505', null, 'one personal plan per person');
select throws_ok($$ insert into public.personal_plans (person_id, body) values ('c0000000-0000-4000-8000-000000000005', '[]') $$, '23514', null, 'the body must be an object');
delete from public.people where id = 'c0000000-0000-4000-8000-000000000003';
select is((select count(*)::int from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000003'), 0, 'deleting the person deletes the personal plan');

select * from finish();
rollback;
