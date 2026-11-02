-- Row Level Security tests for memberships (pgTAP).
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

select plan(53);


select ok(
  (select relrowsecurity from pg_class where oid = 'public.memberships'::regclass),
  'RLS is enabled on memberships'
);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.memberships $$, '42501', null, 'anon cannot read memberships');
select throws_ok($$ insert into public.memberships (gym_id, display_name) values ('d0000000-0000-4000-8000-00000000000a', 'x') $$, '42501', null, 'anon cannot add members');
reset role;
reset request.jwt.claims;

-- trainee 1 ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.memberships $$, $$ values ('e0000000-0000-4000-8000-000000000003'::uuid) $$, 'a trainee sees only their own membership');
select is((select count(*)::int from public.memberships where id = 'e0000000-0000-4000-8000-000000000004'), 0, 'trainee 1 cannot read trainee 2''s membership');
select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'trainee 1 cannot read gym B memberships');
select results_eq($$ with c as (update public.memberships set can_edit_plan = true, can_edit_targets = true where id = 'e0000000-0000-4000-8000-000000000003' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot grant themselves permissions');

select results_eq($$ with c as (update public.memberships set status = 'ended' where id = 'e0000000-0000-4000-8000-000000000004' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot end another trainees membership');

select throws_ok($$ insert into public.memberships (gym_id, display_name, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Friend', 'c0000000-0000-4000-8000-000000000003') $$, '42501', null, 'a trainee cannot add members');
select throws_ok($$ delete from public.memberships where id = 'e0000000-0000-4000-8000-000000000003' $$, '42501', null, 'a trainee cannot delete memberships');
select throws_ok($$ select public.leave_gym('e0000000-0000-4000-8000-000000000004') $$, '42501', null, 'a trainee cannot make another trainee leave');
select lives_ok($$ select public.leave_gym('e0000000-0000-4000-8000-000000000003') $$, 'a trainee can leave their own gym');
select results_eq($$ select status, ended_by from public.memberships $$, $$ values ('ended', 'c0000000-0000-4000-8000-000000000003'::uuid) $$, 'leaving ends the membership and records who ended it');
select throws_ok($$ select public.leave_gym('e0000000-0000-4000-8000-000000000003') $$, '42501', null, 'leaving twice fails');
reset role;
reset request.jwt.claims;

-- anon role cannot call the RPC ------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select public.leave_gym('e0000000-0000-4000-8000-000000000004') $$, '42501', null, 'anon cannot call leave_gym');
reset role;
reset request.jwt.claims;

-- captain of gym B ---------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-00000000000a'), 0, 'a captain of another gym cannot read gym A memberships');
select results_eq($$ with c as (update public.memberships set can_edit_targets = true where id = 'e0000000-0000-4000-8000-000000000004' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain of another gym cannot change a gym A trainee');

select results_eq($$ with c as (update public.memberships set status = 'ended' where id = 'e0000000-0000-4000-8000-000000000004' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain of another gym cannot end a gym A membership');

select throws_ok($$ insert into public.memberships (gym_id, display_name, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Spy', 'c0000000-0000-4000-8000-000000000005') $$, '42501', null, 'a captain of another gym cannot add members to gym A');
reset role;
reset request.jwt.claims;

-- captain of gym A ---------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-00000000000a'), 5, 'the captain reads all memberships of their gym (including pending)');
select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'the captain does not read gym B');
select results_eq($$ with c as (update public.memberships set can_edit_targets = true, can_edit_plan = true where id = 'e0000000-0000-4000-8000-000000000004' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the captain grants permissions to a trainee');

select throws_ok($$ update public.memberships set can_edit_plan = true, can_edit_targets = false where id = 'e0000000-0000-4000-8000-000000000004' $$, '23514', null, 'editing the plan without targets is refused (check)');
select throws_ok($$ update public.memberships set role = 'captain' where id = 'e0000000-0000-4000-8000-000000000004' $$, '42501', null, 'a captain cannot promote a trainee to captain');
select results_eq($$ with c as (update public.memberships set display_name = 'Owner?' where id = 'e0000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain cannot edit the owner');

select results_eq($$ with c as (update public.memberships set display_name = 'Me' where id = 'e0000000-0000-4000-8000-000000000002' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain cannot edit their own membership');

select throws_ok($$ update public.memberships set person_id = 'c0000000-0000-4000-8000-000000000001' where id = 'e0000000-0000-4000-8000-000000000007' $$, '42501', null, 'a captain cannot link a person to a membership (column not granted)');
select throws_ok($$ update public.memberships set gym_id = 'd0000000-0000-4000-8000-00000000000b' where id = 'e0000000-0000-4000-8000-000000000004' $$, '42501', null, 'a captain cannot move a member to another gym');
select throws_ok($$ update public.memberships set status = 'active' where id = 'e0000000-0000-4000-8000-000000000007' $$, '42501', null, 'a client cannot activate a pending member (only redeeming an invite does)');
select lives_ok($$ insert into public.memberships (gym_id, display_name, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'New Trainee', 'c0000000-0000-4000-8000-000000000002') $$, 'the captain adds a pending trainee');
select throws_ok($$ insert into public.memberships (gym_id, display_name, role, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Boss', 'captain', 'c0000000-0000-4000-8000-000000000002') $$, '42501', null, 'a captain cannot add a captain');
select throws_ok($$ insert into public.memberships (gym_id, display_name, role, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Boss', 'owner', 'c0000000-0000-4000-8000-000000000002') $$, '42501', null, 'nobody adds an owner through the API');
select throws_ok($$ insert into public.memberships (gym_id, display_name, status, person_id, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Ghost', 'active', 'c0000000-0000-4000-8000-000000000006', 'c0000000-0000-4000-8000-000000000002') $$, '42501', null, 'a captain cannot add an already-active member or link a person');
select throws_ok($$ insert into public.memberships (gym_id, display_name, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Forged', 'c0000000-0000-4000-8000-000000000001') $$, '42501', null, 'created_by must be the caller');
select throws_ok($$ insert into public.memberships (gym_id, display_name, created_by) values ('d0000000-0000-4000-8000-00000000000a', repeat('x', 41), 'c0000000-0000-4000-8000-000000000002') $$, '23514', null, 'a display name over 40 characters is refused');
select throws_ok($$ insert into public.memberships (gym_id, display_name, can_edit_plan, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Bad flags', true, 'c0000000-0000-4000-8000-000000000002') $$, '23514', null, 'edit-plan without edit-targets is refused on insert');
select results_eq($$ select created_by from public.memberships where display_name = 'New Trainee' $$, $$ values ('c0000000-0000-4000-8000-000000000002'::uuid) $$, 'created_by is the captain who added the member');
select throws_ok($$ delete from public.memberships where id = 'e0000000-0000-4000-8000-000000000004' $$, '42501', null, 'nobody deletes memberships through the API');
select results_eq($$ with c as (update public.memberships set status = 'ended' where id = 'e0000000-0000-4000-8000-000000000004' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the captain ends a trainees membership');

select results_eq($$ select ended_by, ended_at is not null from public.memberships where id = 'e0000000-0000-4000-8000-000000000004' $$, $$ values ('c0000000-0000-4000-8000-000000000002'::uuid, true) $$, 'ending stamps who and when');
select throws_ok($$ update public.memberships set status = 'active' where id = 'e0000000-0000-4000-8000-000000000004' $$, '42501', null, 'an ended member cannot be re-activated by hand (a new invite does that)');
select throws_ok($$ update public.memberships set status = 'pending' where id = 'e0000000-0000-4000-8000-000000000003' $$, '42501', null, 'a status cannot be set back to pending');
reset role;
reset request.jwt.claims;

-- the same captain on an anonymous session ------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select results_eq($$ select id from public.memberships $$, $$ values ('e0000000-0000-4000-8000-000000000002'::uuid) $$, 'an anonymous session reads only its own membership, even for a captain');
select results_eq($$ with c as (update public.memberships set can_edit_targets = true where id = 'e0000000-0000-4000-8000-000000000003' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'an anonymous session cannot manage members');

select throws_ok($$ insert into public.memberships (gym_id, display_name, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'Anon add', 'c0000000-0000-4000-8000-000000000002') $$, '42501', null, 'an anonymous session cannot add members');
reset role;
reset request.jwt.claims;

-- owner ------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select results_eq($$ with c as (update public.memberships set role = 'trainee' where id = 'e0000000-0000-4000-8000-000000000002' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner can demote a captain');

select throws_ok($$ update public.memberships set role = 'captain' where id = 'e0000000-0000-4000-8000-000000000001' $$, '23514', null, 'the last owner cannot be demoted');
select throws_ok($$ update public.memberships set status = 'ended' where id = 'e0000000-0000-4000-8000-000000000001' $$, '23514', null, 'the last owner cannot be ended');
select lives_ok($$ insert into public.memberships (gym_id, display_name, role, created_by) values ('d0000000-0000-4000-8000-00000000000a', 'New Captain', 'captain', 'c0000000-0000-4000-8000-000000000001') $$, 'the owner adds a pending captain');
select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'the owner of gym A does not see gym B');
reset role;
reset request.jwt.claims;

-- table constraints (as the table owner) ---------------------------------------------
select throws_ok($$ update public.memberships set can_edit_targets = true where id = 'e0000000-0000-4000-8000-000000000005' $$, '23514', null, 'permission flags are only for trainees (check)');
select throws_ok($$ insert into public.memberships (gym_id, display_name, status) values ('d0000000-0000-4000-8000-00000000000a', 'x', 'active') $$, '23514', null, 'an active membership needs a person (check)');
select throws_ok($$ insert into public.memberships (gym_id, person_id, display_name, status) values ('d0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 'dup', 'active') $$, '23505', null, 'a person joins a gym once (unique)');

select * from finish();
rollback;
