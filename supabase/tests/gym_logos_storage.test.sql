-- Storage policy tests for the gym-logos bucket (pgTAP).
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


select is((select public from storage.buckets where id = 'gym-logos'), false, 'the gym-logos bucket is private');
select results_eq($$ select file_size_limit, allowed_mime_types from storage.buckets where id = 'gym-logos' $$,
  $$ values (524288::bigint, array['image/png', 'image/jpeg']) $$, 'it holds png/jpeg up to 512 KB');

insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.png'), ('gym-logos', 'd0000000-0000-4000-8000-00000000000b/logo.png');

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is((select count(*)::int from storage.objects where bucket_id = 'gym-logos'), 0, 'anon sees no logo');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpg') $$, '42501', null, 'anon cannot upload a logo');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select results_eq($$ select name from storage.objects where bucket_id = 'gym-logos' $$, $$ values ('d0000000-0000-4000-8000-00000000000a/logo.png') $$, 'a trainee reads only their own gym''s logo');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpg') $$, '42501', null, 'a trainee cannot upload a logo');
select ok((select qual like '%i_manage%' and roles = '{authenticated}' from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'managers delete their gym logo'), 'deleting a logo (through the Storage API, which blocks direct SQL deletes) needs a manager of that gym');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';

select results_eq($$ select name from storage.objects where bucket_id = 'gym-logos' $$, $$ values ('d0000000-0000-4000-8000-00000000000b/logo.png') $$, 'a captain of gym B reads only gym B''s logo');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpg') $$, '42501', null, 'a captain of another gym cannot upload to gym A''s folder');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000b/logo.jpg') $$, 'a captain uploads to their own gym''s folder');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000b/evil.php') $$, '42501', null, 'only logo.png / logo.jpg / logo.jpeg are accepted names');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000b/../d0000000-0000-4000-8000-00000000000a/logo.png') $$, '42501', null, 'path tricks are refused');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'logo.png') $$, '42501', null, 'a file outside a gym folder is refused');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}';

select throws_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpeg') $$, '42501', null, 'an anonymous session cannot upload, even for a captain');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';

select lives_ok($$ insert into storage.objects (bucket_id, name) values ('gym-logos', 'd0000000-0000-4000-8000-00000000000a/logo.jpg') $$, 'the captain of gym A uploads a logo');
reset role;
reset request.jwt.claims;

update public.memberships set status = 'ended', ended_at = now() where id = 'e0000000-0000-4000-8000-000000000003';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';

select is((select count(*)::int from storage.objects where name = 'd0000000-0000-4000-8000-00000000000a/logo.png'), 1, 'a member whose membership ended still sees the gym logo');
reset role;
reset request.jwt.claims;


select * from finish();
rollback;
