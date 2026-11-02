-- Tests for account deletion: blockers, cascade and the last-owner guard (pgTAP).
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

select plan(22);


-- gym B: owner = captain B promoted? Use a fresh single-owner gym C with one other member.
insert into auth.users (id, is_anonymous) values ('b1000000-0000-4000-8000-000000000001', false), ('b1000000-0000-4000-8000-000000000002', false), ('b1000000-0000-4000-8000-000000000003', true);
insert into public.gyms (id, name) values ('d0000000-0000-4000-8000-0000000000c1', 'Gym C'), ('d0000000-0000-4000-8000-0000000000c2', 'Gym D');
insert into public.people (id, auth_user_id, display_name) values
  ('c0000000-0000-4000-8000-0000000000c1', 'b1000000-0000-4000-8000-000000000001', 'Owner C'),
  ('c0000000-0000-4000-8000-0000000000c2', 'b1000000-0000-4000-8000-000000000002', 'Owner D2'),
  ('c0000000-0000-4000-8000-0000000000c3', 'b1000000-0000-4000-8000-000000000003', 'Member C');
insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at) values
  ('e0000000-0000-4000-8000-0000000000c1', 'd0000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-0000000000c1', 'Owner C', 'owner', 'active', now()),
  ('e0000000-0000-4000-8000-0000000000c3', 'd0000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-0000000000c3', 'Member C', 'trainee', 'active', now()),
  -- gym D has two owners
  ('e0000000-0000-4000-8000-0000000000d1', 'd0000000-0000-4000-8000-0000000000c2', 'c0000000-0000-4000-8000-0000000000c1', 'Owner C at D', 'owner', 'active', now()),
  ('e0000000-0000-4000-8000-0000000000d2', 'd0000000-0000-4000-8000-0000000000c2', 'c0000000-0000-4000-8000-0000000000c2', 'Owner D2', 'owner', 'active', now());

-- who may call the check
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select public.account_deletion_blockers('b1000000-0000-4000-8000-000000000001') $$, '42501', null, 'anon cannot ask');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.account_deletion_blockers('b1000000-0000-4000-8000-000000000001') $$, '42501', null, 'an owner cannot ask through the API either');
reset role;
reset request.jwt.claims;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select results_eq($$ select (r ->> 'blocked')::boolean, r #>> '{gyms,0,name}', jsonb_array_length(r -> 'gyms') from (select public.account_deletion_blockers('b1000000-0000-4000-8000-000000000001') as r) s $$, $$ values (true, 'Gym C', 1) $$, 'the only owner of a gym that has members is blocked (gym D has another owner)');
select is(public.account_deletion_blockers('b1000000-0000-4000-8000-000000000002'), '{"blocked": false, "gyms": []}'::jsonb, 'an owner of a gym with another owner is free to go');
select is(public.account_deletion_blockers('b1000000-0000-4000-8000-000000000003'), '{"blocked": false, "gyms": []}'::jsonb, 'a trainee is free to go');
select is(public.account_deletion_blockers('a0000000-0000-4000-8000-000000000003'), '{"blocked": false, "gyms": []}'::jsonb, 'trainee 1 of the standard fixture is free to go');
select is(public.account_deletion_blockers('a0000000-0000-4000-8000-0000000000ff'), '{"blocked": false, "gyms": []}'::jsonb, 'an auth user with no person is free to go');
select is(public.account_deletion_blockers(null), '{"blocked": false, "gyms": []}'::jsonb, 'null is free to go (nothing to block)');
reset role;
reset request.jwt.claims;

-- a sole owner of a gym with nobody else is free too (the gym is just left empty)
update public.memberships set status = 'ended', ended_at = now() where id = 'e0000000-0000-4000-8000-0000000000c3';
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is((public.account_deletion_blockers('b1000000-0000-4000-8000-000000000001') ->> 'blocked')::boolean, false, 'when the other members have left, the owner may go');
reset role;
reset request.jwt.claims;

update public.memberships set status = 'active', ended_at = null where id = 'e0000000-0000-4000-8000-0000000000c3';

-- the database refuses even if something deletes the auth user directly
select throws_ok($$ delete from auth.users where id = 'b1000000-0000-4000-8000-000000000001' $$, '23514', 'last_owner', 'the last owner of a gym with members cannot be cascaded away');
select is((select count(*)::int from public.people where id = 'c0000000-0000-4000-8000-0000000000c1'), 1, 'and nothing was deleted');

-- a normal deletion cascades everything of that person and nothing else -------------------------------------------
insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets) values
  ('mine', 'c0000000-0000-4000-8000-000000000003', 'd1', now(), '[]'), ('theirs', 'c0000000-0000-4000-8000-000000000004', 'd1', now(), '[]');
insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values
  ('mine-gym', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[]');
insert into public.personal_plans (person_id, body) values ('c0000000-0000-4000-8000-000000000003', '{"days":[]}'), ('c0000000-0000-4000-8000-000000000004', '{"days":[]}');
insert into public.plans (membership_id, body, updated_by) values ('e0000000-0000-4000-8000-000000000003', '{"days":[]}', 'e0000000-0000-4000-8000-000000000002');
insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at, created_by)
  values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', private.hash_invite_code('ABCDEF'), now() + interval '1 day', 'c0000000-0000-4000-8000-000000000002');
update public.memberships set created_by = 'c0000000-0000-4000-8000-000000000002' where id = 'e0000000-0000-4000-8000-000000000007';

delete from auth.users where id = 'a0000000-0000-4000-8000-000000000003';
select is((select count(*)::int from public.people where id = 'c0000000-0000-4000-8000-000000000003'), 0, 'the person is gone');
select is((select count(*)::int from public.memberships where person_id = 'c0000000-0000-4000-8000-000000000003'), 0, 'their memberships are gone');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000003'), 0, 'their sessions are gone (solo and gym)');
select is((select count(*)::int from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000003'), 0, 'their personal plan is gone');
select is((select count(*)::int from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003'), 0, 'their gym plan is gone');
select is((select count(*)::int from public.workout_sessions where person_id = 'c0000000-0000-4000-8000-000000000004'), 1, 'another trainee''s session stays');
select is((select count(*)::int from public.personal_plans where person_id = 'c0000000-0000-4000-8000-000000000004'), 1, 'another trainee''s personal plan stays');
select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-00000000000a'), 4, 'the gym and its other members stay');

-- deleting a captain keeps the audit rows, without the person ---------------------------------------------------------------
delete from auth.users where id = 'a0000000-0000-4000-8000-000000000002';
select is((select created_by from public.memberships where id = 'e0000000-0000-4000-8000-000000000007'), null, 'created_by is set to null, the row stays');
select is((select created_by from public.invites where membership_id = 'e0000000-0000-4000-8000-000000000007'), null, 'an invite they made stays, without its creator');
-- deleting a whole gym still works even though it has an owner and members
delete from public.gyms where id = 'd0000000-0000-4000-8000-0000000000c1';
select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-0000000000c1'), 0, 'a gym can still be removed with its members');

select * from finish();
rollback;
