-- Gym logo version (migration 0023): the trigger, who writes and reads it, the join answer (pgTAP).
-- Run: supabase test db   (pgTAP; docs/security.md)
-- The back-fill in 0023 runs on the rows that exist when it is applied; a
-- test database has none then, so the insert case below stands in for it.
begin;
create extension if not exists pgtap with schema extensions;

-- Fixture: the same as gym_settings_owner_only.test.sql --------------------
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

select plan(24);

-- The column and who may write it ---------------------------------------
select has_column('public', 'gyms', 'logo_updated_at', 'gyms has logo_updated_at');
select col_type_is('public', 'gyms', 'logo_updated_at', 'timestamp with time zone', 'it is a timestamptz');
select is(has_column_privilege('authenticated', 'public.gyms', 'logo_updated_at', 'update'), false, 'only the trigger writes the version: not in the update grant');
select is(
  (select array_agg(column_name::text collate "C" order by column_name::text collate "C") from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'gyms' and privilege_type = 'UPDATE' and grantee = 'authenticated'),
  array['brand_color', 'history_after_end', 'logo_path', 'name']::text[],
  'the update grant is unchanged');
select is(has_function_privilege('authenticated', 'private.touch_gym_logo()', 'execute'), false, 'clients cannot call the trigger function');
select is(has_function_privilege('anon', 'private.touch_gym_logo()', 'execute'), false, 'anon cannot call the trigger function');

-- The trigger, as the database owner --------------------------------------
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), null, 'a gym without a logo has no version');
insert into public.gyms (id, name, logo_path) values ('d0000000-0000-4000-8000-00000000000c', 'Gym C', 'd0000000-0000-4000-8000-00000000000c/logo.png');
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000c'), now(), 'a gym created with a logo gets a version');

-- An old version, written past the trigger (it fires only for logo_path).
update public.gyms set logo_path = 'd0000000-0000-4000-8000-00000000000a/logo.png' where id = 'd0000000-0000-4000-8000-00000000000a';
update public.gyms set logo_updated_at = '2026-01-01T00:00:00Z' where id = 'd0000000-0000-4000-8000-00000000000a';
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '2026-01-01T00:00:00Z'::timestamptz, 'a write that does not name logo_path leaves the version alone');
update public.gyms set name = 'Gym A2' where id = 'd0000000-0000-4000-8000-00000000000a';
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '2026-01-01T00:00:00Z'::timestamptz, 'renaming the gym leaves the version alone');

-- The owner of gym A replaces the logo at the same path ------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set logo_path = 'd0000000-0000-4000-8000-00000000000a/logo.png' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner sets the same path again (a replaced logo)');
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), now(), 'the same path gets a new version');
select throws_ok($$ update public.gyms set logo_updated_at = '2000-01-01T00:00:00Z' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'the owner cannot write the version');
select throws_ok($$ update public.gyms set logo_path = 'd0000000-0000-4000-8000-00000000000a/logo.jpg', logo_updated_at = '2000-01-01T00:00:00Z' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'not even together with the path');
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), now(), 'refused writes left the version as it was');
reset role;
reset request.jwt.claims;

-- A captain cannot change the logo, so not the version either -------------
update public.gyms set logo_updated_at = '2026-01-01T00:00:00Z' where id = 'd0000000-0000-4000-8000-00000000000a';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set logo_path = 'd0000000-0000-4000-8000-00000000000a/logo.jpg' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain cannot change the logo');
reset role;
reset request.jwt.claims;
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '2026-01-01T00:00:00Z'::timestamptz, 'and the version did not move');

-- Who reads it -------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '2026-01-01T00:00:00Z'::timestamptz, 'a trainee of gym A reads the version');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000006","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), 0, 'a trainee of gym B does not see gym A at all');
reset role;
reset request.jwt.claims;
set local role anon;
select throws_ok($$ select logo_updated_at from public.gyms $$, '42501', null, 'anon cannot read the version');
reset role;

-- The join answer carries it ----------------------------------------------
select is((select (private.redeem_payload(g, m) -> 'gym' ->> 'logo_updated_at')::timestamptz from public.gyms g, public.memberships m where g.id = 'd0000000-0000-4000-8000-00000000000a' and m.id = 'e0000000-0000-4000-8000-000000000003'), '2026-01-01T00:00:00Z'::timestamptz, 'redeem_payload returns the logo version');
select is((select private.redeem_payload(g, m) -> 'gym' -> 'logo_updated_at' from public.gyms g, public.memberships m where g.id = 'd0000000-0000-4000-8000-00000000000b' and m.id = 'e0000000-0000-4000-8000-000000000006'), 'null'::jsonb, 'and null for a gym without a logo');

-- Removing the logo clears the version --------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set logo_path = null where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner removes the logo');
reset role;
reset request.jwt.claims;
select is((select logo_updated_at from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), null, 'no logo, no version');

select * from finish();
rollback;
