-- Row Level Security tests for invite_attempts (pgTAP).
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

select plan(16);


select ok(
  (select relrowsecurity from pg_class where oid = 'public.invite_attempts'::regclass),
  'RLS is enabled on invite_attempts'
);
select is((select count(*)::int from pg_policy where polrelid = 'public.invite_attempts'::regclass), 0, 'invite_attempts has no policies at all');

insert into public.invite_attempts (auth_user_id, ip_hash, ok, at) values
  ('a0000000-0000-4000-8000-000000000003', 'hash-1', false, now()),
  ('a0000000-0000-4000-8000-000000000003', 'hash-1', false, now() - interval '31 days');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.invite_attempts $$, '42501', null, 'anon cannot read attempts');
select throws_ok($$ insert into public.invite_attempts (auth_user_id, ip_hash, ok) values ('a0000000-0000-4000-8000-000000000003', 'x', true) $$, '42501', null, 'anon cannot write attempts');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select * from public.invite_attempts $$, '42501', null, 'a trainee cannot read attempts, not even their own');
select throws_ok($$ insert into public.invite_attempts (auth_user_id, ip_hash, ok) values ('a0000000-0000-4000-8000-000000000003', 'x', true) $$, '42501', null, 'a trainee cannot reset their own throttle by writing rows');
select throws_ok($$ delete from public.invite_attempts $$, '42501', null, 'a trainee cannot delete attempts');
select throws_ok($$ select public.purge_invite_attempts() $$, '42501', null, 'a trainee cannot run the purge');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select * from public.invite_attempts $$, '42501', null, 'a captain of another gym cannot read attempts');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select * from public.invite_attempts $$, '42501', null, 'a captain cannot read attempts');
select throws_ok($$ delete from public.invite_attempts $$, '42501', null, 'a captain cannot delete attempts');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select * from public.invite_attempts $$, '42501', null, 'the owner cannot read attempts through the API either');
select throws_ok($$ update public.invite_attempts set ok = true $$, '42501', null, 'the owner cannot edit attempts');
reset role;
reset request.jwt.claims;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.purge_invite_attempts(), 1::bigint, 'the purge removes rows older than 30 days');
reset role;
reset request.jwt.claims;

select is((select count(*)::int from public.invite_attempts), 1, 'recent attempts are kept');
select is((select count(*)::int from information_schema.columns where table_name = 'invite_attempts' and table_schema = 'public' and column_name ~* 'code|token|secret'), 0, 'no column could hold a code or a token');

select * from finish();
rollback;
