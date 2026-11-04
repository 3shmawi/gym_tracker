-- Row Level Security and limits for gym_exercise_videos (pgTAP, migration 0017).
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

-- Gym A: a video for flat_db_press. Gym B: another.
insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values
  ('d0000000-0000-4000-8000-00000000000a', 'flat_db_press', 'mCEIUZySRPY'),
  ('d0000000-0000-4000-8000-00000000000b', 'flat_db_press', 'amgXq2ThD0c');

select plan(34);

select ok((select relrowsecurity from pg_class where oid = 'public.gym_exercise_videos'::regclass), 'RLS is enabled on gym_exercise_videos');
select is((select proconfig from pg_proc where oid = 'private.gym_exercise_videos_guard()'::regprocedure), array['search_path=""'], 'the trigger function pins its search_path');
select ok(not has_table_privilege('anon', 'public.gym_exercise_videos', 'select'), 'anon has no grant');
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select * from public.gym_exercise_videos $$, '42501', null, 'anon cannot read gym videos');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select results_eq($$ select video_id from public.gym_exercise_videos $$, $$ values ('mCEIUZySRPY') $$, 'an active trainee reads their gym''s video, and only that');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'amgXq2ThD0c') $$, '42501', null, 'a trainee cannot add a video');
select results_eq($$ with c as (update public.gym_exercise_videos set video_id = 'amgXq2ThD0c' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot change a video');
select results_eq($$ with c as (delete from public.gym_exercise_videos returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot remove a video');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.gym_exercise_videos), 0, 'an ended member reads nothing');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';
select results_eq($$ select video_id from public.gym_exercise_videos $$, $$ values ('amgXq2ThD0c') $$, 'another gym''s captain reads only their own gym');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'amgXq2ThD0c') $$, '42501', null, 'another gym''s captain cannot add to gym A');
select results_eq($$ with c as (delete from public.gym_exercise_videos where gym_id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'another gym''s captain cannot remove gym A''s video');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000007","role":"authenticated","is_anonymous":true}';
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'amgXq2ThD0c') $$, '42501', null, 'a captain without a permanent session cannot add');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select lives_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id, start_seconds, end_seconds) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'amgXq2ThD0c', 10, 70) $$, 'the captain adds a video with start and end');
select is((select updated_by from public.gym_exercise_videos where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'pec_deck'), 'c0000000-0000-4000-8000-000000000002'::uuid, 'updated_by is stamped by the database');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'pec_deck', 'mCEIUZySRPY') $$, '23505', null, 'a second video for the same exercise is refused');
select lives_ok($$ update public.gym_exercise_videos set video_id = 'mCEIUZySRPY', start_seconds = null, end_seconds = null where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'pec_deck' $$, 'the captain replaces the video in place');
select throws_ok($$ update public.gym_exercise_videos set gym_id = 'd0000000-0000-4000-8000-00000000000b' where gym_id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'a video cannot be moved to another gym');
select throws_ok($$ update public.gym_exercise_videos set exercise_id = 'leg_press' where gym_id = 'd0000000-0000-4000-8000-00000000000a' and exercise_id = 'pec_deck' $$, '42501', null, 'a video cannot be moved to another exercise');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id, updated_by) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRPY', 'c0000000-0000-4000-8000-000000000001') $$, '42501', null, 'updated_by cannot be forged');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'https://youtu.be/mCEIUZySRPY') $$, '23514', null, 'video id refused: a URL instead of an id');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRP') $$, '23514', null, 'video id refused: 10 characters');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRPYx') $$, '23514', null, 'video id refused: 12 characters');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'x'';drop--x') $$, '23514', null, 'video id refused: injection-like text');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRP%') $$, '23514', null, 'video id refused: a percent sign');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', '') $$, '23514', null, 'video id refused: an empty id');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id, start_seconds, end_seconds) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRPY', 90, 30) $$, '23514', null, 'start after end is refused');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id, start_seconds) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRPY', -1) $$, '23514', null, 'a negative start is refused');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id, end_seconds) values ('d0000000-0000-4000-8000-00000000000a', 'leg_press', 'mCEIUZySRPY', 43201) $$, '23514', null, 'an end past 12 h is refused');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', '../plans', 'mCEIUZySRPY') $$, '23514', null, 'a path-like exercise id is refused');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000b', 'leg_press', 'mCEIUZySRPY') $$, '42501', null, 'the captain cannot add to another gym');
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (delete from public.gym_exercise_videos where exercise_id = 'pec_deck' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner removes a video');
select lives_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) select 'd0000000-0000-4000-8000-00000000000a', 'cap_' || e, 'mCEIUZySRPY' from generate_series(1, 300 - (select count(*)::int from public.gym_exercise_videos where gym_id = 'd0000000-0000-4000-8000-00000000000a')) as e $$, 'a gym may hold 300 videos');
select throws_ok($$ insert into public.gym_exercise_videos (gym_id, exercise_id, video_id) values ('d0000000-0000-4000-8000-00000000000a', 'one_more', 'mCEIUZySRPY') $$, '23514', 'too_many_videos_in_gym', 'the 301st video of a gym is refused');
reset role;
reset request.jwt.claims;

select * from finish();
rollback;
