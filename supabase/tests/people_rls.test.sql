-- Row Level Security tests for people (pgTAP).
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

select plan(19);


select ok(
  (select relrowsecurity from pg_class where oid = 'public.people'::regclass),
  'RLS is enabled on people'
);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.people $$, '42501', null, 'anon cannot read people');
select throws_ok($$ update public.people set display_name = 'x' $$, '42501', null, 'anon cannot update people');
reset role;
reset request.jwt.claims;

-- trainee 1 -------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.people $$, $$ values ('c0000000-0000-4000-8000-000000000003'::uuid) $$, 'a trainee sees only their own person row');
select is((select count(*)::int from public.people where id = 'c0000000-0000-4000-8000-000000000004'), 0, 'trainee 1 cannot read trainee 2');
select results_eq($$ with c as (update public.people set display_name = 'Mo' where id = 'c0000000-0000-4000-8000-000000000003' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'a person can rename themselves');

select results_eq($$ with c as (update public.people set display_name = 'Hacked' where id = 'c0000000-0000-4000-8000-000000000004' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'trainee 1 cannot rename trainee 2');

select throws_ok($$ update public.people set auth_user_id = 'a0000000-0000-4000-8000-000000000001' where id = 'c0000000-0000-4000-8000-000000000003' $$, '42501', null, 'a person cannot re-point their row to another auth user');
select throws_ok($$ insert into public.people (auth_user_id) values ('a0000000-0000-4000-8000-000000000099') $$, '42501', null, 'a person row cannot be created through the API');
select throws_ok($$ delete from public.people where id = 'c0000000-0000-4000-8000-000000000003' $$, '42501', null, 'a person row cannot be deleted through the API');
select throws_ok($$ update public.people set display_name = repeat('x', 41) where id = 'c0000000-0000-4000-8000-000000000003' $$, '23514', null, 'a display name over 40 characters is refused');
select throws_ok($$ update public.people set display_name = '' where id = 'c0000000-0000-4000-8000-000000000003' $$, '23514', null, 'an empty display name is refused');
select throws_ok($$ update public.people set locale = 'xx' where id = 'c0000000-0000-4000-8000-000000000003' $$, '23514', null, 'an unknown locale is refused');
select lives_ok($$ update public.people set display_name = '''; drop table people; --', locale = 'ar' where id = 'c0000000-0000-4000-8000-000000000003' $$, 'hostile-looking text is only ever stored as text');
reset role;
reset request.jwt.claims;

-- staff cannot read trainees' person rows ---------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select results_eq($$ select id from public.people $$, $$ values ('c0000000-0000-4000-8000-000000000002'::uuid) $$, 'a captain sees only their own person row, not their trainees''');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.people where id <> 'c0000000-0000-4000-8000-000000000001'), 0, 'the owner sees no other person rows either');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.people where id = 'c0000000-0000-4000-8000-000000000003'), 0, 'a captain of another gym cannot read gym A people');
reset role;
reset request.jwt.claims;

-- deleting the auth user removes the person (account deletion) ------------------
delete from auth.users where id = 'a0000000-0000-4000-8000-000000000006';
select is((select count(*)::int from public.people where id = 'c0000000-0000-4000-8000-000000000006'), 0, 'deleting the auth user deletes the person (cascade)');
select is((select count(*)::int from public.memberships where id = 'e0000000-0000-4000-8000-000000000006'), 0, 'and their memberships');

select * from finish();
rollback;
