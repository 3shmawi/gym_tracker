-- Row Level Security tests for gyms (pgTAP).
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

select plan(25);


select ok(
  (select relrowsecurity from pg_class where oid = 'public.gyms'::regclass),
  'RLS is enabled on gyms'
);

-- anon: nothing at all ------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.gyms $$, '42501', null, 'anon cannot read gyms');
select throws_ok($$ insert into public.gyms (name) values ('x') $$, '42501', null, 'anon cannot create a gym');
select throws_ok($$ update public.gyms set name = 'x' $$, '42501', null, 'anon cannot update a gym');
reset role;
reset request.jwt.claims;

-- trainee 1 (gym A) -----------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select name from public.gyms $$, $$ values ('Gym A') $$, 'a trainee sees only the gym they belong to');
select is((select count(*)::int from public.gyms where id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'a trainee cannot read another gym');
select results_eq($$ with c as (update public.gyms set name = 'Hacked' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot rename the gym');

select throws_ok($$ insert into public.gyms (name) values ('Mine') $$, '42501', null, 'a trainee cannot create a gym');
select throws_ok($$ delete from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'a trainee cannot delete a gym');
reset role;
reset request.jwt.claims;

-- captain of gym B ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select results_eq($$ select name from public.gyms $$, $$ values ('Gym B') $$, 'a captain sees only their own gym');
select results_eq($$ with c as (update public.gyms set name = 'Hacked', history_after_end = 'locked' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain of another gym cannot change gym A');

reset role;
reset request.jwt.claims;

-- captain of gym A ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select results_eq($$ with c as (update public.gyms set name = 'Gym A 2', history_after_end = 'locked' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the captain can change name and history setting of their gym');

select throws_ok($$ update public.gyms set deleted_at = now() where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'a captain cannot soft-delete the gym (column not granted)');
select throws_ok($$ update public.gyms set is_demo = true where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'a captain cannot mark the gym as demo');
select throws_ok($$ insert into public.gyms (name) values ('Second gym') $$, '42501', null, 'a captain cannot create a gym');
select throws_ok($$ delete from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'a captain cannot delete a gym');
select throws_ok($$ update public.gyms set name = repeat('x', 61) where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'a name over 60 characters is refused');
select throws_ok($$ update public.gyms set history_after_end = 'forever' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'an unknown history setting is refused');
select throws_ok($$ update public.gyms set logo_path = '../../etc/passwd' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'a logo path outside <gym_id>/logo.png is refused');
select lives_ok($$ update public.gyms set logo_path = 'd0000000-0000-4000-8000-00000000000a/logo.png' where id = 'd0000000-0000-4000-8000-00000000000a' $$, 'a proper logo path is accepted');
reset role;
reset request.jwt.claims;

-- the same captain on an anonymous session manages nothing --------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select results_eq($$ with c as (update public.gyms set name = 'Anon edit' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'an anonymous session cannot manage the gym, even for a captain');

reset role;
reset request.jwt.claims;

-- owner -----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select results_eq($$ with c as (update public.gyms set name = 'Gym A 3' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner can rename the gym');

select throws_ok($$ insert into public.gyms (name) values ('Second gym') $$, '42501', null, 'the owner cannot create gyms through the API either (done by the developer)');
reset role;
reset request.jwt.claims;

-- ended members and deleted gyms ----------------------------------------------
update public.memberships set status = 'ended', ended_at = now() where id = 'e0000000-0000-4000-8000-000000000004';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), 1, 'a member whose membership ended still sees the gym name');
reset role;
reset request.jwt.claims;

update public.gyms set deleted_at = now() where id = 'd0000000-0000-4000-8000-00000000000a';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.gyms), 0, 'a deleted gym is hidden from its members');
reset role;
reset request.jwt.claims;


select * from finish();
rollback;
