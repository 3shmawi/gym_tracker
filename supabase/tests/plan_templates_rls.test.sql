-- Gym plan templates: RLS, limits, stamps and apply_plan_template (pgTAP, migration 0019).
-- Run: supabase test db   (pgTAP; docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

-- Fixture ---------------------------------------------------------------
--   gym A: owner (01), captain (02), active trainee (03), ended trainee (04),
--          captain signed in anonymously (07), second trainee (08), second captain (09)
--   gym B: captain (05), trainee (06)
insert into auth.users (id, is_anonymous) values
  ('a0000000-0000-4000-8000-000000000001', false),
  ('a0000000-0000-4000-8000-000000000002', false),
  ('a0000000-0000-4000-8000-000000000003', true),
  ('a0000000-0000-4000-8000-000000000004', true),
  ('a0000000-0000-4000-8000-000000000005', false),
  ('a0000000-0000-4000-8000-000000000006', true),
  ('a0000000-0000-4000-8000-000000000007', true),
  ('a0000000-0000-4000-8000-000000000008', true),
  ('a0000000-0000-4000-8000-000000000009', false);

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
  ('c0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000007', 'Anon Captain A'),
  ('c0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000008', 'Trainee A2'),
  ('c0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000009', 'Captain A2');

insert into public.memberships (id, gym_id, person_id, display_name, role, status, joined_at) values
  ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000001', 'Owner A', 'owner', 'active', now()),
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000002', 'Captain A', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 'Trainee A', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000004', 'Ended A', 'trainee', 'ended', now()),
  ('e0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000005', 'Captain B', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-000000000006', 'Trainee B', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000007', 'Anon Captain A', 'captain', 'active', now()),
  ('e0000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000008', 'Trainee A2', 'trainee', 'active', now()),
  ('e0000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000009', 'Captain A2', 'captain', 'active', now());

-- A valid body and a name.
create temp table fx as select
  '{"days":[{"id":"day-1","name":{"ar":"صدر","en":"Chest"},"exercises":[{"id":"flat_db_press","name":{"ar":"دفع دمبل مستوي","en":"Flat Dumbbell Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false}]}]}'::jsonb as body,
  '{"ar":"دفع وسحب","en":"Push / Pull"}'::jsonb as name;
grant select on fx to authenticated, anon;

-- Templates as the service role (bypasses RLS) for the read tests.
insert into public.plan_templates (id, gym_id, name, body) values
  ('f0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000a', (select name from fx), (select body from fx)),
  ('f0000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-00000000000b', (select name from fx), (select body from fx));

select plan(56);

-- Structure -------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = 'public.plan_templates'::regclass), 'RLS is enabled on plan_templates');
select is((select proconfig from pg_proc where oid = 'private.plan_templates_guard()'::regprocedure), array['search_path=""'], 'the trigger function pins its search_path');
select is((select proconfig from pg_proc where oid = 'public.apply_plan_template(uuid, uuid, int)'::regprocedure), array['search_path=""'], 'apply_plan_template pins its search_path');
select ok(not has_table_privilege('anon', 'public.plan_templates', 'select'), 'anon has no grant on templates');
select ok(not has_function_privilege('anon', 'public.apply_plan_template(uuid, uuid, int)', 'execute'), 'anon cannot run apply_plan_template');
select ok(not has_column_privilege('authenticated', 'public.plan_templates', 'created_by', 'insert'), 'created_by cannot be written');
select ok(not has_column_privilege('authenticated', 'public.plan_templates', 'gym_id', 'update'), 'a template cannot move to another gym');
select ok(not has_column_privilege('authenticated', 'public.plan_templates', 'version', 'update'), 'version cannot be written');
select ok(not has_column_privilege('authenticated', 'public.plans', 'template_id', 'update'), 'plans.template_id cannot be written by clients');

-- anon ------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$ select * from public.plan_templates $$, '42501', null, 'anon cannot read templates');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-00000000000a', 0) $$, '42501', null, 'anon cannot apply a template');
reset role;

-- A trainee of the gym ------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.plan_templates), 0, 'a trainee sees no templates');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, body from fx $$, '42501', null, 'a trainee cannot add a template');
select results_eq($$ with c as (update public.plan_templates set name = '{"ar":"x","en":"x"}' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot rename a template');
select results_eq($$ with c as (delete from public.plan_templates returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot delete a template');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-00000000000a', 0) $$, '42501', 'forbidden', 'a trainee cannot apply a template to themselves');
reset role;

-- A captain of another gym --------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.plan_templates), 1, 'gym B''s captain sees only gym B''s template');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, body from fx $$, '42501', null, 'gym B''s captain cannot add to gym A');
select results_eq($$ with c as (delete from public.plan_templates where gym_id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'gym B''s captain cannot delete gym A''s template');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000006', 'f0000000-0000-4000-8000-00000000000a', 0) $$, '42501', 'forbidden', 'a template of another gym cannot be applied');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-00000000000b', 0) $$, '42501', 'forbidden', 'gym B''s template cannot be applied to gym A''s member');
reset role;

-- A captain signed in anonymously --------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000007","role":"authenticated","is_anonymous":true}';
select is((select count(*)::int from public.plan_templates), 0, 'an anonymous-session captain sees no templates');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, body from fx $$, '42501', null, 'an anonymous-session captain cannot add');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-00000000000a', 0) $$, '42501', 'forbidden', 'an anonymous-session captain cannot apply');
reset role;

-- The gym's captain ------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.plan_templates), 1, 'the captain reads the gym''s template');
select lives_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', '{"ar":"تجربة","en":"Trial"}', body from fx $$, 'the captain adds a template');
select throws_ok($$ insert into public.plan_templates (id, gym_id, name, body) select gen_random_uuid(), 'd0000000-0000-4000-8000-00000000000a', name, body from fx $$, '42501', null, 'the id cannot be chosen by the client');
select is((select created_by from public.plan_templates where id = (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New'))), 'e0000000-0000-4000-8000-000000000002'::uuid, 'created_by is stamped with the captain''s membership');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body, created_by) select 'd0000000-0000-4000-8000-00000000000a', name, body, 'e0000000-0000-4000-8000-000000000001' from fx $$, '42501', null, 'created_by cannot be forged');
select lives_ok($$ update public.plan_templates set name = '{"ar":"جديد","en":"New"}' where id = (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New')) $$, 'the captain renames a template');
select is((select version from public.plan_templates where id = (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New'))), 1, 'a rename does not change the version');
select lives_ok($$ update public.plan_templates set body = jsonb_set(body, '{days,0,exercises,0,sets}', '4') where id = (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New')) $$, 'the captain changes a template''s body');
select is((select version from public.plan_templates where id = (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New'))), 2, 'a body change bumps the version');
select throws_ok($$ update public.plan_templates set gym_id = 'd0000000-0000-4000-8000-00000000000b' where id = (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New')) $$, '42501', null, 'a template cannot move to another gym');

-- Body and name rules (the same as plans) -------------------------------------
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, '{"days":[]}' from fx $$, '23514', null, 'a body with no days is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, jsonb_set(body, '{extra}', '1') from fx $$, '23514', null, 'an unknown key in the body is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, jsonb_set(body, '{days,0,exercises,0,sets}', '11') from fx $$, '23514', null, 'sets out of range is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, jsonb_set(body, '{days,0,id}', '"../x"') from fx $$, '23514', null, 'a path-like day id is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', name, jsonb_build_object('days', jsonb_build_array(jsonb_build_object('id','d','name',jsonb_build_object('ar','x','en','x'),'exercises',jsonb_build_array(jsonb_build_object('id','e','name',jsonb_build_object('ar',repeat('x',40),'en',repeat('x',40)),'sets',3,'reps',12,'rest',90,'step',2.5,'superset',false,'note',repeat('y',70000)))))) from fx $$, '23514', null, 'a body over 64 KB is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', '{"ar":"","en":"x"}', body from fx $$, '23514', null, 'an empty name is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', jsonb_build_object('ar', repeat('س', 41), 'en', 'x'), body from fx $$, '23514', null, 'a 41-character name is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', jsonb_build_object('ar', 'a' || chr(8238) || 'b', 'en', 'x'), body from fx $$, '23514', null, 'a direction override in the name is refused');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', '"Push"', body from fx $$, '23514', null, 'a name that is not {ar, en} is refused');
select lives_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000a', '{"ar":"''; drop table plans; --","en":"<script>x</script>"}', body from fx $$, 'injection-like names are stored as text');

-- Apply ------------------------------------------------------------------------
select is((public.apply_plan_template('e0000000-0000-4000-8000-000000000003', (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New')), 0) ->> 'version')::int, 1, 'the captain applies a template to a trainee with no plan');
select results_eq($$ select template_id, template_version, body -> 'days' -> 0 -> 'exercises' -> 0 ->> 'sets' from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003' $$,
  $$ select (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New')), 2, '4' $$, 'the plan holds the template''s body, id and version');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000003', (select t.id from public.plan_templates t where t.name ->> 'en' in ('Trial', 'New')), 0) $$, 'P0001', 'plan_changed', 'an old base version is refused (plan_changed)');
select is((public.apply_plan_template('e0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-00000000000a', 1) ->> 'version')::int, 2, 're-applying with the right version replaces the plan');
select lives_ok($$ select public.save_plan('e0000000-0000-4000-8000-000000000003', 2, jsonb_set((select body from fx), '{days,0,exercises,0,reps}', '8')) $$, 'save_plan still works on a plan made from a template');
select is((select template_id from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003'), 'f0000000-0000-4000-8000-00000000000a'::uuid, 'save_plan keeps the template link (the dashboard diffs against it)');
select throws_ok($$ select public.apply_plan_template('e0000000-0000-4000-8000-000000000009', 'f0000000-0000-4000-8000-00000000000a', 0) $$, '42501', 'forbidden', 'a captain cannot apply to another captain');
reset role;

-- The owner -----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select is((public.apply_plan_template('e0000000-0000-4000-8000-000000000009', 'f0000000-0000-4000-8000-00000000000a', 0) ->> 'template_version')::int, 1, 'the owner applies to a captain');
select lives_ok($$ delete from public.plan_templates where id = 'f0000000-0000-4000-8000-00000000000a' $$, 'the owner deletes a template');
select results_eq($$ select template_id is null, (body -> 'days' -> 0 ->> 'id') from public.plans where membership_id = 'e0000000-0000-4000-8000-000000000003' $$, $$ values (true, 'day-1') $$, 'deleting a template keeps the plans made from it, without the link');
reset role;

-- The 50-per-gym limit ---------------------------------------------------------------
select lives_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000b', name, body from fx, generate_series(1, 49) $$, 'a gym may hold 50 templates');
select throws_ok($$ insert into public.plan_templates (gym_id, name, body) select 'd0000000-0000-4000-8000-00000000000b', name, body from fx $$, '23514', 'too_many_templates_in_gym', 'the 51st template of a gym is refused');

select * from finish();
rollback;
