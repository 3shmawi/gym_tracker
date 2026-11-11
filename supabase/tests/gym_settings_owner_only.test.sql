-- Gym settings are owner-only (migration 0020): gyms update and gym-logos writes (pgTAP).
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

insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.png');

-- No write policy on gyms or gym-logos still uses private.i_manage.
select is(
  (select count(*)::int from pg_policies
    where ((schemaname = 'public' and tablename = 'gyms') or (schemaname = 'storage' and tablename = 'objects' and coalesce(qual, with_check) like '%gym-logos%'))
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
      and coalesce(qual, '') || coalesce(with_check, '') like '%i_manage%'),
  0, 'no gyms or gym-logos write policy is left for managers');
select results_eq($$ select policyname::text from pg_policies where schemaname = 'public' and tablename = 'gyms' order by 1 $$, $$ values ('members read their gyms'), ('owners update their gym') $$, 'gyms has exactly the read and owner-update policies');
select is(has_function_privilege('anon', 'private.i_own(uuid)', 'execute'), false, 'anon cannot call private.i_own');

-- owner of gym A on an anonymous session: nothing
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';
select results_eq($$ with c as (update public.gyms set name = 'Anon owner' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'an owner on an anonymous session cannot change the gym');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpg') $$, '42501', null, 'an owner on an anonymous session cannot upload a logo');
reset role;
reset request.jwt.claims;

-- owner of gym A, permanent: everything on gym A, nothing on gym B
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set name = 'Owned', logo_path = 'd0000000-0000-4000-8000-00000000000a/logo.png', history_after_end = 'locked' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner changes name, logo and history setting');
select results_eq($$ with c as (update public.gyms set name = 'Not mine' where id = 'd0000000-0000-4000-8000-00000000000b' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'the owner of gym A cannot change gym B');
select throws_ok($$ update storage.objects set name = 'd0000000-0000-4000-8000-00000000000b/logo.png' where bucket_id = 'gym-logos' and name = 'd0000000-0000-4000-8000-00000000000a/logo.png' $$, '42501', null, 'the owner cannot move gym A''s logo into gym B''s folder');
reset role;
reset request.jwt.claims;

-- captain of gym A: reads, writes nothing
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((select name from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), 'Owned', 'the captain reads the owner''s change');
select is((select count(*)::int from storage.objects where bucket_id = 'gym-logos' and name = 'd0000000-0000-4000-8000-00000000000a/logo.png'), 1, 'the captain still reads the logo');
reset role;
reset request.jwt.claims;

-- an owner whose membership ended: nothing
-- A gym always keeps an active owner: make trainee 2 an owner first.
update public.memberships set role = 'owner' where id = 'e0000000-0000-4000-8000-000000000004';
update public.memberships set status = 'ended' where id = 'e0000000-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set name = 'Former owner' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'an owner whose membership ended cannot change the gym');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpg') $$, '42501', null, 'an owner whose membership ended cannot upload a logo');
reset role;
reset request.jwt.claims;

select * from finish();
rollback;
