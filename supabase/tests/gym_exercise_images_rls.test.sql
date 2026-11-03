-- Row Level Security and limits for gym_exercise_images (pgTAP).
-- Run: supabase test db   (pgTAP; docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

-- Fixture ---------------------------------------------------------------
--   gym A: owner (01), captain (02), active trainee (03), ended trainee (04),
--          captain signed in anonymously (07)
--   gym B: captain (05), trainee (06)
-- Owners and captains have permanent sessions; trainees are anonymous users.
insert into auth.users (id, is_anonymous) values
  ('a0000000-0000-4000-8000-000000000001', false),
  ('a0000000-0000-4000-8000-000000000002', false),
  ('a0000000-0000-4000-8000-000000000003', true),
  ('a0000000-0000-4000-8000-000000000004', true),
  ('a0000000-0000-4000-8000-000000000005', false),
  ('a0000000-0000-4000-8000-000000000006', true),
  ('a0000000-0000-4000-8000-000000000007', true);

insert into public.gyms (id, name) values
  ('d0000000-0000-4000-8000-00000000000a', 'Gym A'),
  ('d0000000-0000-4000-8000-00000000000b', 'Gym B');

insert into public.people (id, auth_user_id, display_name) values
  ('c0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Owner A'),
  ('c0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'Captain A'),
  ('c0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Trainee A'),
  ('c0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004', 'Ended A'),
  ('c0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000005', 'Captain B'),
  ('c0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000006', 'Trainee B'),
  ('c0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000007', 'Anon Captain A');

insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at) values
  ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000001', 'Owner A', 'owner', 'active', now()),
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'Captain A', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 'Trainee A', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000004', 'Ended A', 'trainee', 'ended', now()),
  ('e0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000005', 'Captain B', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000006', 'Trainee B', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000007', 'Anon Captain A', 'captain', 'active', now());

-- Gym A: two frames for flat_db_press. Gym B: one.
insert into public.gym_exercise_images (id, gym_id, exercise_id, public_id, position) values
  ('f2000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0001-tension', 1),
  ('f2000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0001-relaxation', 2),
  ('f2000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000b', 'flat_db_press', 'exercises/ek-0001-tension', 1);

select plan(55);

-- Shape ---------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = 'public.gym_exercise_images'::regclass),
  'RLS is enabled on gym_exercise_images');
select is((select proconfig from pg_proc where oid = 'private.gym_exercise_images_guard()'::regprocedure),
  array['search_path=""'], 'the trigger function pins its search_path');
select is((select proconfig from pg_proc where oid = 'public.set_gym_exercise_images(uuid, text, text[])'::regprocedure),
  array['search_path=""'], 'the save function pins its search_path');
select is((select prosecdef from pg_proc where oid = 'public.set_gym_exercise_images(uuid, text, text[])'::regprocedure),
  false, 'the save function runs as the caller (RLS applies)');
select ok(not has_function_privilege('anon', 'public.set_gym_exercise_images(uuid, text, text[])', 'execute'),
  'anon cannot call the save function');

-- anon ----------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select * from public.gym_exercise_images $$, '42501', null, 'anon cannot read gym pictures');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'exercises/ek-0002-tension', 1) $$,
  '42501', null, 'anon cannot add a picture');
reset role;
reset request.jwt.claims;

-- active trainee of gym A ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select results_eq($$ select id from public.gym_exercise_images order by position $$,
  $$ values ('f2000000-0000-4000-8000-000000000001'::uuid), ('f2000000-0000-4000-8000-000000000002'::uuid) $$,
  'an active trainee reads their gym''s pictures, and only those');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'exercises/ek-0002-tension', 1) $$,
  '42501', null, 'a trainee cannot add a picture');
select results_eq($$ with c as (update public.gym_exercise_images set position = 3 where id = 'f2000000-0000-4000-8000-000000000001' returning 1) select count(*)::int from c $$,
  $$ values (0) $$, 'a trainee cannot reorder');
select results_eq($$ with c as (delete from public.gym_exercise_images returning 1) select count(*)::int from c $$,
  $$ values (0) $$, 'a trainee cannot remove pictures');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', array['exercises/ek-0002-tension']) $$,
  '42501', null, 'a trainee cannot save a list');
reset role;
reset request.jwt.claims;

-- ended trainee of gym A ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.gym_exercise_images), 0, 'an ended member reads nothing');
reset role;
reset request.jwt.claims;

-- captain of gym B ----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';
select results_eq($$ select id from public.gym_exercise_images $$,
  $$ values ('f2000000-0000-4000-8000-000000000003'::uuid) $$, 'another gym''s captain reads only their own gym');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'exercises/ek-0002-tension', 1) $$,
  '42501', null, 'another gym''s captain cannot add to gym A');
select results_eq($$ with c as (delete from public.gym_exercise_images where gym_id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$,
  $$ values (0) $$, 'another gym''s captain cannot remove gym A''s pictures');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', array[]::text[]) $$,
  '42501', null, 'another gym''s captain cannot save gym A''s list');
reset role;
reset request.jwt.claims;

-- trainee of gym B ----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000006","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.gym_exercise_images where gym_id = 'd0000000-0000-4000-8000-00000000000a'), 0,
  'another gym''s trainee reads nothing of gym A');
reset role;
reset request.jwt.claims;

-- captain of gym A with an anonymous session ----------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000007","role":"authenticated","is_anonymous":true}';
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'exercises/ek-0002-tension', 1) $$,
  '42501', null, 'a captain without a permanent session cannot add');
reset role;
reset request.jwt.claims;

-- captain of gym A ----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.gym_exercise_images), 2, 'the captain reads the gym''s pictures');
select lives_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0002-tension', 3) $$,
  'the captain adds a picture');
select is((select updated_by from public.gym_exercise_images where public_id = 'exercises/ek-0002-tension' and gym_id = 'd0000000-0000-4000-8000-00000000000a'),
  'c0000000-0000-4000-8000-000000000002'::uuid, 'updated_by is stamped by the database');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position, updated_by) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'exercises/ek-0002-tension', 1, 'c0000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'updated_by cannot be forged');
select throws_ok($$ update public.gym_exercise_images set gym_id = 'd0000000-0000-4000-8000-00000000000b' where id = 'f2000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'a picture cannot be moved to another gym');
select throws_ok($$ update public.gym_exercise_images set exercise_id = 'pec_deck' where id = 'f2000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'a picture cannot be moved to another exercise');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000b', 'pec_deck', 'exercises/ek-0002-tension', 1) $$,
  '42501', null, 'the captain cannot add to another gym');

-- Limits, order, ids.
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0002-relaxation', 2) $$,
  '23505', null, 'a duplicate position is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0001-tension', 4) $$,
  '23505', null, 'the same picture twice is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-9999-tension', 4) $$,
  '23503', null, 'an unknown picture is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'https://evil.example/x.png', 4) $$,
  '23503', null, 'a URL instead of a public id is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0002-relaxation', 0) $$,
  '23514', null, 'position 0 is refused');
select lives_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values
    ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0002-relaxation', 4),
    ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0004-tension', 5),
    ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0004-relaxation', 6) $$,
  'six pictures are allowed');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'exercises/ek-0005-tension', 7) $$,
  '23514', null, 'the 7th picture is refused');
select lives_ok($$ update public.gym_exercise_images set position = case position when 1 then 2 else 1 end
    where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'flat_db_press' and position in (1, 2) $$,
  'two pictures swap places in one statement');
select is((select public_id from public.gym_exercise_images where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'flat_db_press' and position = 1),
  'exercises/ek-0001-relaxation', 'the swap took effect');

select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', '../plans', 'exercises/ek-0005-tension', 1) $$,
  '23514', null, 'a path-like exercise id is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'Flat_DB_Press', 'exercises/ek-0005-tension', 1) $$,
  '23514', null, 'an upper-case exercise id is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'x''; drop table public.gyms; --', 'exercises/ek-0005-tension', 1) $$,
  '23514', null, 'an injection-like exercise id is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', chr(1077) || chr(1093) || '_press', 'exercises/ek-0005-tension', 1) $$,
  '23514', null, 'a Cyrillic look-alike exercise id is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', repeat('a', 65), 'exercises/ek-0005-tension', 1) $$,
  '23514', null, 'an exercise id over 64 characters is refused');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'ex-', 'exercises/ek-0005-tension', 1) $$,
  '23514', null, 'an empty plan id is refused');
select lives_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values
    ('d0000000-0000-4000-8000-00000000000a', 'ex-m3k9w2a1b', 'exercises/ek-0005-tension', 1),
    ('d0000000-0000-4000-8000-00000000000a', 'ex-m3k9w2a1b-2', 'exercises/ek-0005-tension', 1) $$,
  'plan exercise ids (with and without the clash suffix) are accepted');

-- The save function.
select lives_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'pec_deck',
    array['exercises/ek-0008-tension', 'exercises/ek-0008-relaxation']) $$, 'the captain saves a list');
select results_eq($$ select public_id, position::int from public.gym_exercise_images
    where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'pec_deck' order by position $$,
  $$ values ('exercises/ek-0008-tension', 1), ('exercises/ek-0008-relaxation', 2) $$, 'the list is stored in order from 1');
select lives_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'pec_deck',
    array['exercises/ek-0008-relaxation']) $$, 'saving again replaces the list');
select is((select count(*)::int from public.gym_exercise_images where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'pec_deck'),
  1, 'the old rows are gone');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'pec_deck',
    array['exercises/ek-0001-tension', 'exercises/ek-0001-relaxation', 'exercises/ek-0002-tension', 'exercises/ek-0002-relaxation',
          'exercises/ek-0004-tension', 'exercises/ek-0004-relaxation', 'exercises/ek-0005-tension']) $$,
  '23514', 'too_many_pictures', 'a list of 7 is refused');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'pec_deck',
    array['exercises/ek-0008-tension', 'exercises/ek-0008-tension']) $$,
  '22023', 'duplicate_picture', 'a list with the same picture twice is refused');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'pec_deck',
    array['exercises/ek-0008-tension', null]) $$,
  '22023', 'invalid_list', 'a list with a null is refused');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'pec_deck',
    array[array['exercises/ek-0008-tension'], array['exercises/ek-0008-relaxation']]) $$,
  '22023', 'invalid_list', 'a nested list is refused');
select throws_ok($$ select public.set_gym_exercise_images('d0000000-0000-4000-8000-00000000000a', 'DROP TABLE',
    array['exercises/ek-0008-tension']) $$,
  '23514', null, 'the save function refuses a crafted exercise id');
select is((select count(*)::int from public.gym_exercise_images where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'pec_deck'),
  1, 'a refused save leaves the old list');
reset role;
reset request.jwt.claims;

-- owner of gym A ------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (delete from public.gym_exercise_images where exercise_id = 'pec_deck' returning 1) select count(*)::int from c $$,
  $$ values (1) $$, 'the owner removes a picture');
select lives_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position)
    select 'd0000000-0000-4000-8000-00000000000a', 'cap_' || e, 'exercises/ek-0001-tension', 1
    from generate_series(1, 1200 - (select count(*)::int from public.gym_exercise_images where gym_id = 'd0000000-0000-4000-8000-00000000000a')) as e $$,
  'a gym may hold 1200 pictures');
select throws_ok($$ insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position) values ('d0000000-0000-4000-8000-00000000000a', 'one_more', 'exercises/ek-0001-tension', 1) $$,
  '23514', 'too_many_pictures_in_gym', 'the 1201st picture of a gym is refused');
reset role;
reset request.jwt.claims;

select * from finish();
rollback;
