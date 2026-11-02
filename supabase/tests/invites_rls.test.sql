-- Row Level Security tests for invites (pgTAP).
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

select plan(58);


select ok(
  (select relrowsecurity from pg_class where oid = 'public.invites'::regclass),
  'RLS is enabled on invites'
);

-- two invites made by the table owner: one for the pending trainee (M7), one for the captain (M2)
insert into public.invites (id, gym_id, membership_id, kind, code_hmac, expires_at) values
  ('f0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', private.hash_invite_code('ABCDEF'), now() + interval '7 days'),
  ('f0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000002', 'recover', private.hash_invite_code('GHJKMN'), now() + interval '7 days');

-- constraints ---------------------------------------------------------------------
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', private.hash_invite_code('PQRSTU'), now() + interval '8 days') $$, '23514', null, 'an invite cannot live longer than 7 days');
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', private.hash_invite_code('ABCDEF'), now() + interval '1 day') $$, '23505', null, 'two invites cannot share a code hash');
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', '\x00'::bytea, now() + interval '1 day') $$, '23514', null, 'the stored value must be a 32-byte hash, not a code');
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'demo', private.hash_invite_code('VWXYZ2'), now() + interval '1 day') $$, '23514', null, 'the demo kind is not available yet');
select throws_ok($$ update public.invites set used_at = now() where id = 'f0000000-0000-4000-8000-000000000007' $$, '23514', null, 'a used invite must be bound to an install id');

-- anon ------------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select throws_ok($$ select * from public.invites $$, '42501', null, 'anon cannot read invites');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007') $$, '42501', null, 'anon cannot create invites');
select throws_ok($$ select public.revoke_invite('f0000000-0000-4000-8000-000000000007') $$, '42501', null, 'anon cannot revoke invites');
select throws_ok($$ select public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 1) $$, '42501', null, 'anon cannot use the admin function');
reset role;
reset request.jwt.claims;

-- trainee 1 -------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.invites), 0, 'a trainee sees no invites');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007') $$, '42501', null, 'a trainee cannot create an invite');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000003', 'recover') $$, '42501', null, 'a trainee cannot issue themselves a recover code');
select throws_ok($$ select public.revoke_invite('f0000000-0000-4000-8000-000000000007') $$, '42501', null, 'a trainee cannot revoke an invite');
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', private.hash_invite_code('AAAAAA'), now() + interval '1 day') $$, '42501', null, 'a trainee cannot insert invites directly');
select throws_ok($$ select public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 1) $$, '42501', null, 'a trainee cannot use the admin function');
reset role;
reset request.jwt.claims;

-- captain of gym B ----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.invites), 0, 'a captain of another gym sees no invites of gym A');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007') $$, '42501', null, 'a captain of another gym cannot create an invite for gym A');
select throws_ok($$ select public.revoke_invite('f0000000-0000-4000-8000-000000000007') $$, '42501', null, 'a captain of another gym cannot revoke gym A invites');
reset role;
reset request.jwt.claims;

-- captain of gym A ----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select results_eq($$ select id from public.invites $$, $$ values ('f0000000-0000-4000-8000-000000000007'::uuid) $$, 'the captain sees the trainee invites of their gym, not the captain invite');
select throws_ok($$ select code_hmac from public.invites $$, '42501', null, 'the code hash is never readable through the API');
select throws_ok($$ select * from public.invites $$, '42501', null, 'select * is refused because it includes the hash column');
select throws_ok($$ insert into public.invites (gym_id, membership_id, kind, code_hmac, expires_at) values ('d0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-000000000007', 'join', private.hash_invite_code('AAAAAA'), now() + interval '1 day') $$, '42501', null, 'a captain cannot insert invites directly');
select throws_ok($$ update public.invites set revoked_at = null where id = 'f0000000-0000-4000-8000-000000000007' $$, '42501', null, 'a captain cannot edit invites directly');
select throws_ok($$ delete from public.invites $$, '42501', null, 'a captain cannot delete invites');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000002', 'recover') $$, '42501', null, 'a captain cannot issue a code for a captain');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000001', 'recover') $$, '42501', null, 'a captain cannot issue a code for the owner');
select throws_ok($$ select public.create_invite('00000000-0000-0000-0000-000000000000') $$, '42501', null, 'an unknown membership gives the same answer as a forbidden one');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007', 'demo') $$, '22023', null, 'the demo kind cannot be requested');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007', null) $$, '22023', null, 'a missing kind is refused');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000003', 'join') $$, '22023', null, 'a join code is only for pending members');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007', 'recover') $$, '22023', null, 'a recover code is only for members that have a person');
select throws_ok($$ select public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 1) $$, '42501', null, 'a captain cannot use the admin function');
create temp table issued (code text, id uuid);
grant all on issued to authenticated;
insert into issued select (j ->> 'code'), (j ->> 'invite_id')::uuid from (select public.create_invite('e0000000-0000-4000-8000-000000000007') as j) s;
select matches((select code from issued), '^[A-HJKMNP-Z2-9]{6}$', 'the code has 6 characters from the 31-letter alphabet');
select is((select count(*)::int from public.invites where membership_id = 'e0000000-0000-4000-8000-000000000007' and used_at is null and revoked_at is null), 1, 'a new invite revokes the unused older one');
select is((select revoked_at is not null from public.invites where id = 'f0000000-0000-4000-8000-000000000007'), true, 'the older invite is revoked');
select lives_ok($$ select public.revoke_invite((select id from issued)) $$, 'the captain revokes an invite');
select is((select revoked_at is not null from public.invites where id = (select id from issued)), true, 'the invite shows as revoked');
reset role;
reset request.jwt.claims;

-- only the hash is stored ---------------------------------------------------------
select is((select count(*)::int from public.invites where code_hmac = private.hash_invite_code((select code from issued))), 1, 'the invite is found by the hash of its code');
select is((select count(*)::int from public.invites i where i::text ilike '%' || (select code from issued) || '%'), 0, 'the plain code appears nowhere in the invites row');
select isnt((select code_hmac from public.invites where id = (select id from issued)), extensions.digest((select code from issued), 'sha256'), 'the hash is keyed (HMAC with a secret pepper), not a bare SHA-256');
select is((select (expires_at - created_at) from public.invites where id = (select id from issued)), interval '7 days', 'an invite expires in 7 days');
select is((select bool_and(private.generate_invite_code() ~ '^[A-HJKMNP-Z2-9]{6}$') from generate_series(1, 2000)), true, 'generated codes never contain 0 O 1 I L');
select cmp_ok((select count(distinct private.generate_invite_code())::int from generate_series(1, 300)), '>', 295, 'generated codes do not repeat');
-- captain on an anonymous session ---------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from public.invites), 0, 'an anonymous session sees no invites, even for a captain');
select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000007') $$, '42501', null, 'an anonymous session cannot create invites, even for a captain');
select throws_ok($$ select public.revoke_invite('f0000000-0000-4000-8000-000000000007') $$, '42501', null, 'an anonymous session cannot revoke invites');
reset role;
reset request.jwt.claims;

-- owner ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select is((select count(*)::int from public.invites where membership_id = 'e0000000-0000-4000-8000-000000000002'), 1, 'the owner also sees the captain''s invite');
select lives_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000002', 'recover') $$, 'the owner can issue a recover code for a captain');
reset role;
reset request.jwt.claims;

-- A recover code is refused for a person who is active in another gym.
insert into public.memberships (gym_id, person_id, display_name, status, joined_at)
  values ('d0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000003', 'Trainee 1 at B', 'active', now());
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';

select throws_ok($$ select public.create_invite('e0000000-0000-4000-8000-000000000003', 'recover') $$, '22023', null, 'no recover code while the person is active in another gym');
reset role;
reset request.jwt.claims;

-- admin function (secret key only) ----------------------------------------------------
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(jsonb_array_length(public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 3)), 3, 'the admin function creates N invites');
select throws_ok($$ select public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 0) $$, '22023', null, 'zero invites is refused');
select throws_ok($$ select public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 201) $$, '22023', null, 'more than 200 at once is refused');
select throws_ok($$ select public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 2, array['only one']) $$, '22023', null, 'the names must match the count');
select throws_ok($$ select public.admin_create_invites('00000000-0000-0000-0000-000000000000', 1) $$, '22023', null, 'an unknown gym is refused');
select is((select count(*)::int from jsonb_array_elements(public.admin_create_invites('d0000000-0000-4000-8000-00000000000a', 2, array['Ali', 'Mona'], true, false, true)) e where e ->> 'display_name' in ('Ali', 'Mona')), 2, 'names are used for the pending members');
reset role;
reset request.jwt.claims;

select results_eq($$ select can_edit_targets, can_edit_plan, can_build_own_plan from public.memberships where display_name = 'Ali' $$, $$ values (true, false, true) $$, 'permissions are applied to the pending members');
select is((select count(*)::int from public.invites where created_by is null and kind = 'join' and used_at is null and membership_id in (select id from public.memberships where display_name in ('Ali', 'Mona'))), 2, 'admin invites are single-use join invites');

select * from finish();
rollback;
