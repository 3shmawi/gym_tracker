-- Tests for redeem_invite_core, the transaction behind the Edge Function (pgTAP).
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

select plan(46);


-- Fresh anonymous auth users that will redeem codes, and 8 invites for gym A
-- made the way scripts/make_invites makes them (secret key only).
insert into auth.users (id, is_anonymous) values
  ('b1000000-0000-4000-8000-000000000001', true),
  ('b1000000-0000-4000-8000-000000000002', true),
  ('b1000000-0000-4000-8000-000000000003', true),
  ('b1000000-0000-4000-8000-000000000004', true),
  ('b1000000-0000-4000-8000-000000000005', true),
  ('b1000000-0000-4000-8000-000000000006', true),
  ('b1000000-0000-4000-8000-000000000007', true),
  ('b1000000-0000-4000-8000-000000000008', true),
  ('b1000000-0000-4000-8000-000000000009', true),
  ('b1000000-0000-4000-8000-000000000010', true),
  ('b1000000-0000-4000-8000-000000000011', true),
  ('b1000000-0000-4000-8000-000000000012', true),
  ('b1000000-0000-4000-8000-000000000013', true),
  ('b1000000-0000-4000-8000-000000000014', true),
  ('b1000000-0000-4000-8000-000000000015', true);

create temp table codes (n int, code text, membership_id uuid, invite_id uuid);
grant all on codes to authenticated, service_role;
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

insert into codes
  select ord::int, e ->> 'code', (e ->> 'membership_id')::uuid, (e ->> 'invite_id')::uuid
  from jsonb_array_elements(public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 8, null, true, false, true))
       with ordinality as t (e, ord);
reset role;
reset request.jwt.claims;


-- Only the secret key may call the core function ---------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000001', '203.0.113.5') $$, '42501', null, 'anon cannot call redeem_invite_core');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select throws_ok($$ select public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000001', '203.0.113.5') $$, '42501', null, 'a trainee cannot call redeem_invite_core directly (identity would be forgeable)');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000001', '203.0.113.5') $$, '42501', null, 'an owner cannot call redeem_invite_core directly');
reset role;
reset request.jwt.claims;


set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

-- Missing values ------------------------------------------------------------------------
select is(public.redeem_invite_core(null, (select code from codes where n = 1), '51000000-0000-4000-8000-000000000001', '203.0.113.5') ->> 'reason', 'invalid', 'no user -> invalid');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', null, '51000000-0000-4000-8000-000000000001', '203.0.113.5') ->> 'reason', 'invalid', 'no code -> invalid');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), null, '203.0.113.5') ->> 'reason', 'invalid', 'no install id -> invalid');

-- Happy path ------------------------------------------------------------------------------
create temp table first_join as select public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000001', '203.0.113.5') as r;
grant all on first_join to authenticated, service_role;
select is((select r ->> 'ok' from first_join), 'true', 'a valid code is accepted');
select results_eq($$ select r #>> '{gym,name}', r ->> 'role', r #>> '{permissions,edit_targets}', r #>> '{permissions,edit_plan}', r #>> '{permissions,build_own_plan}' from first_join $$,
  $$ values ('Gym A', 'trainee', 'true', 'false', 'true') $$, 'the answer carries the gym, the role and the permissions');
select is((select r ->> 'membership_id' from first_join), (select membership_id::text from codes where n = 1), 'and the membership id');
select is((select count(*)::int from public.people where auth_user_id = 'b1000000-0000-4000-8000-000000000001'), 1, 'the auth user is linked to a new person');
select results_eq($$ select status, person_id = (select id from public.people where auth_user_id = 'b1000000-0000-4000-8000-000000000001'), joined_at is not null from public.memberships where id = (select membership_id from codes where n = 1) $$,
  $$ values ('active', true, true) $$, 'the pending membership is now active and linked');
select results_eq($$ select used_at is not null, bound_install_id from public.invites where id = (select invite_id from codes where n = 1) $$,
  $$ values (true, '51000000-0000-4000-8000-000000000001'::uuid) $$, 'the invite is used and bound to the first install');

-- Replay ----------------------------------------------------------------------------------
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000002', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000002', '203.0.113.5') ->> 'reason', 'used', 'the same code from another phone is refused (single use)');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000009', '203.0.113.5') ->> 'reason', 'used', 'the same user with another install id is refused');
select is((select (public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 1), '51000000-0000-4000-8000-000000000001', '203.0.113.5')) ->> 'ok'), 'true', 'the same phone retrying after a lost answer is a success');
select is((select count(*)::int from public.people where auth_user_id = 'b1000000-0000-4000-8000-000000000001'), 1, 'and creates no second person');
select is((select count(*)::int from public.memberships where person_id = (select id from public.people where auth_user_id = 'b1000000-0000-4000-8000-000000000001')), 1, 'and no second membership');

-- Hostile input ------------------------------------------------------------------------------
select is((select bool_and(public.redeem_invite_core('b1000000-0000-4000-8000-000000000003', s, '51000000-0000-4000-8000-000000000003', '198.51.100.1') ->> 'reason' = 'not_found')
  from (values ('ABC'), (''), (repeat('A', 100000)), ('''; drop table public.gyms; --'), ('<script>alert(1)</script>'),
        ('ÄÖÜÄÖÜ'), ('abcdef'), ((select code from codes where n = 2) || chr(10))) as t (s)),
  true, 'short, empty, huge, SQL-like, HTML-like, unicode, lower-case and newline-padded codes are all just "not found"');
select is((select count(*)::int from public.gyms), 2, 'and nothing was dropped');
select is((select count(*)::int from public.invites where id = (select invite_id from codes where n = 2) and used_at is null), 1, 'a code with a newline appended did not consume the real one');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000003', 'ZZZZZZ', '51000000-0000-4000-8000-000000000003', '198.51.100.2') ->> 'reason', 'not_found', 'an unknown but well-formed code is "not found"');
select lives_ok($$ select public.redeem_invite_core('b1000000-0000-4000-8000-000000000004', 'ZZZZZZ', '51000000-0000-4000-8000-000000000004', repeat('1', 5000)) $$, 'a huge address does not break the function');
select lives_ok($$ select public.redeem_invite_core('b1000000-0000-4000-8000-000000000004', 'ZZZZZZ', '51000000-0000-4000-8000-000000000004', null) $$, 'a missing address does not break the function');

-- Expired, revoked, deleted gym, conflict -----------------------------------------------------
reset role;
reset request.jwt.claims;

update public.invites set created_at = now() - interval '8 days', expires_at = now() - interval '1 day' where id = (select invite_id from codes where n = 2);
update public.invites set revoked_at = now() where id = (select invite_id from codes where n = 3);
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000005', (select code from codes where n = 2), '51000000-0000-4000-8000-000000000005', '203.0.113.5') ->> 'reason', 'expired', 'an expired code is refused');
select is((select status from public.memberships where id = (select membership_id from codes where n = 2)), 'pending', 'and the member stays pending');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000005', (select code from codes where n = 3), '51000000-0000-4000-8000-000000000005', '203.0.113.5') ->> 'reason', 'revoked', 'a revoked code is refused');
reset role;
reset request.jwt.claims;

update public.gyms set deleted_at = now() where id = 'd0000000-0000-4000-8000-00000000000a';
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000005', (select code from codes where n = 4), '51000000-0000-4000-8000-000000000005', '203.0.113.5') ->> 'reason', 'not_found', 'a code of a deleted gym is "not found"');
reset role;
reset request.jwt.claims;

update public.gyms set deleted_at = null where id = 'd0000000-0000-4000-8000-00000000000a';
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select code from codes where n = 5), '51000000-0000-4000-8000-000000000001', '203.0.113.5') ->> 'reason', 'conflict', 'joining a gym you are already in through another membership is refused');
select is((select used_at is null from public.invites where id = (select invite_id from codes where n = 5)), true, 'and the code is not consumed');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000005', (select code from codes where n = 5), '51000000-0000-4000-8000-000000000005', '203.0.113.5') ->> 'ok', 'true', 'so the right person can still use it');

-- Recover: a new phone for a person --------------------------------------------------------------
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

create temp table recover as select (public.create_invite('e0000000-0000-4000-8000-000000000004', 'recover')) as j;
grant all on recover to authenticated, service_role;
reset role;
reset request.jwt.claims;

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000001', (select j ->> 'code' from recover), '51000000-0000-4000-8000-000000000001', '203.0.113.5') ->> 'reason', 'conflict', 'a user who already has another person cannot take over someone else''s account');
select is((select used_at is null from public.invites where id = (select (j ->> 'invite_id')::uuid from recover)), true, 'and the recover code is not consumed');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000009', (select j ->> 'code' from recover), '51000000-0000-4000-8000-000000000009', '203.0.113.5') ->> 'ok', 'true', 'a fresh phone recovers the person');
select is((select auth_user_id from public.people where id = 'c0000000-0000-4000-8000-000000000004'), 'b1000000-0000-4000-8000-000000000009'::uuid, 'the person now belongs to the new auth user');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.memberships), 0, 'the old session is cut off at once');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1000000-0000-4000-8000-000000000009","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.memberships where id = 'e0000000-0000-4000-8000-000000000004'), 1, 'and the new session sees the membership');
reset role;
reset request.jwt.claims;


-- Brute force: 40 guesses from one user ------------------------------------------------------------
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

create temp table guesses as
  select g, public.redeem_invite_core('b1000000-0000-4000-8000-000000000011', 'Q' || lpad(g::text, 5, '2'), '51000000-0000-4000-8000-000000000011', '192.0.2.11') ->> 'reason' as reason
  from generate_series(1, 40) g;
select results_eq($$ select reason, count(*)::int from guesses group by reason order by reason $$,
  $$ values ('not_found', 10), ('throttled', 30) $$, 'after 10 wrong guesses in an hour the user is throttled');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000011', (select code from codes where n = 6), '51000000-0000-4000-8000-000000000011', '203.0.113.5') ->> 'reason', 'throttled', 'a throttled user is refused even with a valid code');
select is((select used_at is null from public.invites where id = (select invite_id from codes where n = 6)), true, 'and the valid code is not consumed');
select is((select count(*)::int from public.invite_attempts where auth_user_id = 'b1000000-0000-4000-8000-000000000011'), 10, 'throttled calls are not recorded, so the lock ends after an hour');

-- Brute force: many users from one address ------------------------------------------------------------
reset role;
reset request.jwt.claims;

insert into public.invite_attempts (auth_user_id, ip_hash, ok)
  select gen_random_uuid(), private.hash_ip('192.0.2.77'), false from generate_series(1, 30);
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000012', (select code from codes where n = 6), '51000000-0000-4000-8000-000000000012', '192.0.2.77') ->> 'reason', 'throttled', 'an address with 30 failures in an hour is throttled for new users too');
select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000012', (select code from codes where n = 6), '51000000-0000-4000-8000-000000000012', '192.0.2.78') ->> 'ok', 'true', 'another address is not affected');

-- Global breaker ---------------------------------------------------------------------------------------
reset role;
reset request.jwt.claims;

insert into public.invite_attempts (auth_user_id, ip_hash, ok)
  select gen_random_uuid(), 'bot-' || g, false from generate_series(1, 201) g;
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000013', (select code from codes where n = 7), '51000000-0000-4000-8000-000000000013', '203.0.113.5') ->> 'reason', 'throttled', 'more than 200 failures in 10 minutes pauses redeeming for everybody');
reset role;
reset request.jwt.claims;

delete from public.invite_attempts where at > now() - interval '10 minutes' and not ok and ip_hash like 'bot-%';
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(public.redeem_invite_core('b1000000-0000-4000-8000-000000000013', (select code from codes where n = 7), '51000000-0000-4000-8000-000000000013', '203.0.113.5') ->> 'ok', 'true', 'and it recovers once the burst is over');
reset role;
reset request.jwt.claims;


-- Plain codes are nowhere ------------------------------------------------------------------------------------
select is((select count(*)::int from public.invite_attempts a where a::text ilike '%' || (select code from codes where n = 1) || '%'), 0, 'attempt rows hold no code');
select is((select count(*)::int from public.invites i where i::text ilike '%' || (select code from codes where n = 1) || '%'), 0, 'invite rows hold no code');

select * from finish();
rollback;
