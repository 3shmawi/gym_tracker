-- Tests for the demo gym invite, its reuse, rotation and the nightly wipe (pgTAP).
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

select plan(38);


insert into auth.users (id, is_anonymous) values
  ('b1000000-0000-4000-8000-000000000001', true),
  ('b1000000-0000-4000-8000-000000000002', true),
  ('b1000000-0000-4000-8000-000000000003', true),
  ('b1000000-0000-4000-8000-000000000004', true),
  ('b1000000-0000-4000-8000-000000000005', true);
insert into public.gyms (id, name, is_demo) values ('d0000000-0000-4000-8000-0000000000dd', 'Azm Demo Gym', true);
-- a captain of the demo gym (captain B)
insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at)
  values ('e0000000-0000-4000-8000-0000000000dd', 'd0000000-0000-4000-8000-0000000000dd', 'c0000000-0000-4000-8000-000000000005', 'Demo captain', 'captain', 'active', now());

-- who can make a demo code ------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select public.admin_create_demo_invite('d0000000-0000-4000-8000-0000000000dd') $$, '42501', null, 'anon cannot make a demo code');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.admin_create_demo_invite('d0000000-0000-4000-8000-0000000000dd') $$, '42501', null, 'not even an owner can (secret key only)');
reset role;
reset request.jwt.claims;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select throws_ok($$ select public.admin_create_demo_invite('d0000000-0000-4000-8000-00000000000a') $$, '22023', null, 'only a gym marked as demo can have one');
select throws_ok($$ select public.admin_create_demo_invite('00000000-0000-0000-0000-000000000000') $$, '22023', null, 'an unknown gym is refused');
create temp table demo1 as select public.admin_create_demo_invite('d0000000-0000-4000-8000-0000000000dd') as j;
grant all on demo1 to authenticated, service_role;
select matches((select j ->> 'code' from demo1), '^[A-HJKMNP-Z2-9]{6}$', 'the demo code has the same format as any invite');
reset role;
reset request.jwt.claims;

select throws_ok($$ insert into public.invites (gym_id, kind, code_hmac) values ('d0000000-0000-4000-8000-00000000000a', 'demo', private.hash_invite_code('ZZZZZZ')) $$, '23514', null, 'a demo invite cannot be attached to a real gym');
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac) values ('d0000000-0000-4000-8000-0000000000dd', 'e0000000-0000-4000-8000-000000000003', 'demo', private.hash_invite_code('YYYYYY')) $$, '23514', null, 'a demo invite cannot belong to a member');
select throws_ok($$ insert into public.invites (gym_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-0000000000dd', 'demo', private.hash_invite_code('XXXXXX'), now() + interval '1 day') $$, '23514', null, 'a demo invite has no expiry');
select throws_ok($$ insert into public.invites (gym_id, kind, code_hmac) values ('d0000000-0000-4000-8000-0000000000dd', 'join', private.hash_invite_code('WWWWWW')) $$, '23514', null, 'a join invite still needs a member and an expiry');
select is((select used_at is null and bound_install_id is null from public.invites where gym_id = 'd0000000-0000-4000-8000-0000000000dd' and kind = 'demo' and revoked_at is null), true, 'a demo invite is never used up');
select throws_ok($$ update public.invites set used_at = now(), bound_install_id = gen_random_uuid() where gym_id = 'd0000000-0000-4000-8000-0000000000dd' and kind = 'demo' $$, '23514', null, 'and cannot be marked used');

-- reviewers redeem it: reusable, each gets an all-permissions trainee ---------------------------
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

create temp table r1 as select public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select j ->> 'code' from demo1), '51000000-0000-4000-8000-000000000001', '203.0.113.9') as r;
create temp table r2 as select public.redeem_invite_core('b1000000-0000-4000-8000-000000000002', (select j ->> 'code' from demo1), '51000000-0000-4000-8000-000000000002', '203.0.113.9') as r;
grant all on r1, r2 to service_role;
select results_eq($$ select r ->> 'ok', r #>> '{gym,name}', r ->> 'role', r #>> '{permissions,edit_targets}', r #>> '{permissions,edit_plan}', r #>> '{permissions,build_own_plan}' from r1 $$, $$ values ('true', 'Azm Demo Gym', 'trainee', 'true', 'true', 'true') $$, 'the demo code joins the demo gym as a trainee with every permission');
select is((select r ->> 'ok' from r2), 'true', 'a second reviewer can use the same code');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select j ->> 'code' from demo1), '51000000-0000-4000-8000-000000000001', '203.0.113.9') ->> 'membership_id', (select r ->> 'membership_id' from r1), 'the same reviewer again gets the same membership');
reset role;
reset request.jwt.claims;

select is((select count(*)::int from public.memberships where gym_id = 'd0000000-0000-4000-8000-0000000000dd' and role = 'trainee'), 2, 'two reviewers, two memberships, no duplicates');
select is((select used_at is null from public.invites where gym_id = 'd0000000-0000-4000-8000-0000000000dd' and kind = 'demo' and revoked_at is null), true, 'the code is still unused');
select is((select count(*)::int from public.invite_attempts where ok and auth_user_id in ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002')), 3, 'every use is recorded (no code in it)');
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.memberships), 1, 'the reviewer sees only their own membership');
select is((select count(*)::int from public.invites), 0, 'and no invites');
reset role;
reset request.jwt.claims;

-- the demo gym's captain sees the demo invite, not its hash ------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.invites where kind = 'demo'), 1, 'the captain of the demo gym sees the demo invite');
select throws_ok($$ select code_hmac from public.invites $$, '42501', null, 'and never its hash');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.invites where kind = 'demo'), 0, 'the captain of another gym does not');
reset role;
reset request.jwt.claims;

-- ended reviewer: the code re-activates them -----------------------------------------------------------
update public.memberships set status = 'ended', ended_at = now() where id = (select (r ->> 'membership_id')::uuid from r1);
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select j ->> 'code' from demo1), '51000000-0000-4000-8000-000000000001', '203.0.113.9') ->> 'ok', 'true', 'an ended reviewer can come back');
reset role;
reset request.jwt.claims;

select is((select status from public.memberships where id = (select (r ->> 'membership_id')::uuid from r1)), 'active', 'and is active again');

-- rotating: the old code stops, the new one works ------------------------------------------------------------
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

create temp table demo2 as select public.admin_create_demo_invite('d0000000-0000-4000-8000-0000000000dd') as j;
grant all on demo2 to service_role;
select isnt((select j ->> 'code' from demo2), (select j ->> 'code' from demo1), 'a rotated code is a new code');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000003', (select j ->> 'code' from demo1), '51000000-0000-4000-8000-000000000003', '203.0.113.9') ->> 'reason', 'revoked', 'the old demo code is revoked');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000003', (select j ->> 'code' from demo2), '51000000-0000-4000-8000-000000000003', '203.0.113.9') ->> 'ok', 'true', 'the new one works');
reset role;
reset request.jwt.claims;

select is((select count(*)::int from public.invites where gym_id = 'd0000000-0000-4000-8000-0000000000dd' and kind = 'demo' and revoked_at is null), 1, 'only one demo code is live');
-- a demo code does not work for a gym that stopped being a demo
update public.gyms set is_demo = false where id = 'd0000000-0000-4000-8000-0000000000dd';
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000004', (select j ->> 'code' from demo2), '51000000-0000-4000-8000-000000000004', '203.0.113.9') ->> 'reason', 'not_found', 'a gym that is no longer a demo does not accept the code');
reset role;
reset request.jwt.claims;

update public.gyms set is_demo = true where id = 'd0000000-0000-4000-8000-0000000000dd';

-- nightly wipe ------------------------------------------------------------------------------------------------------
insert into public.workout_sessions (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets) values
  ('demo-s', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-0000000000dd', (select (r ->> 'membership_id')::uuid from r1), 'd1', now(), '[]'),
  ('real-s', 'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000003', 'd1', now(), '[]'),
  ('solo-s', 'c0000000-0000-4000-8000-000000000003', null, null, 'd1', now(), '[]');
insert into public.plans (membership_id, body) values
  ((select (r ->> 'membership_id')::uuid from r1), '{"days":[]}'), ('e0000000-0000-4000-8000-000000000003', '{"days":[]}');
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select public.wipe_demo_data() $$, '42501', null, 'a trainee cannot run the wipe');
reset role;
reset request.jwt.claims;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select results_eq($$ select r ->> 'sessions', r ->> 'plans' from (select public.wipe_demo_data() as r) s $$, $$ values ('1', '1') $$, 'the wipe removes the demo gym''s sessions and plans');
select results_eq($$ select r ->> 'sessions', r ->> 'plans' from (select public.wipe_demo_data() as r) s $$, $$ values ('0', '0') $$, 'and running it again finds nothing');
reset role;
reset request.jwt.claims;

select is((select count(*)::int from public.workout_sessions where client_id in ('real-s', 'solo-s')), 2, 'real and solo sessions are untouched');
select is((select count(*)::int from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003'), 1, 'a real gym''s plan is untouched');
select is((select count(*)::int from public.plans where membership_id = (select (r ->> 'membership_id')::uuid from r1)), 0, 'the demo plan is gone');

-- scheduling ---------------------------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.schedule_maintenance() $$, '42501', null, 'an owner cannot schedule jobs');
reset role;
reset request.jwt.claims;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select throws_ok($$ select public.schedule_maintenance() $$, '42501', null, 'not even the secret key: the project owner runs it in the SQL editor');
reset role;
reset request.jwt.claims;

select ok(public.schedule_maintenance() in ('scheduled', 'pg_cron is not enabled: nothing scheduled'), 'it schedules when pg_cron is on, and says so when it is not');

select * from finish();
rollback;
