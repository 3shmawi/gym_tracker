-- Gym brand colour (migration 0021): the value rule, who reads and writes it, the join answer (pgTAP).
-- Run: supabase test db   (pgTAP; docs/security.md)
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



select plan(62);

-- The rule itself: the shared vectors (docs/features/brand_colour_vectors.json).
select is(private.brand_color_ok(E'#22c55e'), true, E'valid: #22c55e');
select is(private.brand_color_ok(E'#000028'), true, E'valid: #000028');
select is(private.brand_color_ok(E'#280000'), true, E'valid: #280000');
select is(private.brand_color_ok(E'#ffffd7'), true, E'valid: #ffffd7');
select is(private.brand_color_ok(E'#facc15'), true, E'valid: #facc15');
select is(private.brand_color_ok(E'#000000'), false, E'refused: #000000');
select is(private.brand_color_ok(E'#ffffff'), false, E'refused: #ffffff');
select is(private.brand_color_ok(E'#808080'), false, E'refused: #808080');
select is(private.brand_color_ok(E'#1f2937'), false, E'refused: #1f2937');
select is(private.brand_color_ok(E'#272727'), false, E'refused: #272727');
select is(private.brand_color_ok(E'#FACC15'), false, E'refused: #FACC15');
select is(private.brand_color_ok(E'#facc1'), false, E'refused: #facc1');
select is(private.brand_color_ok(E'#facc155'), false, E'refused: #facc155');
select is(private.brand_color_ok(E'facc15'), false, E'refused: facc15');
select is(private.brand_color_ok(E'#gggggg'), false, E'refused: #gggggg');
select is(private.brand_color_ok(E' #facc15'), false, E'refused:  #facc15');
select is(private.brand_color_ok(E'#facc15 '), false, E'refused: #facc15 ');
select is(private.brand_color_ok(E'#fff'), false, E'refused: #fff');
select is(private.brand_color_ok(E'rgb(1,2,3)'), false, E'refused: rgb(1,2,3)');
select is(private.brand_color_ok(E''), false, E'refused: ');
select is(private.brand_color_ok(E'#facc15\n'), false, E'refused: #facc15 + newline');
select is(private.brand_color_ok(E'#facc15''; drop table gyms;--'), false, E'refused: #facc15''; drop table gyms;--');
select is(private.brand_color_ok(E'#٢٢c55e'), false, E'refused: #٢٢c55e');
select is(private.brand_color_ok(null), false, 'null is not a colour (the column allows null by itself)');
select is(private.brand_color_ok(repeat('#facc15', 100000)), false, 'refused: a very long text');
select is(has_function_privilege('anon', 'private.brand_color_ok(text)', 'execute'), false, 'anon cannot call private.brand_color_ok');
select is(has_function_privilege('authenticated', 'private.redeem_payload(public.gyms, public.memberships)', 'execute'), false, 'redeem_payload stays closed to clients');

-- Grants: exactly the four setting columns are writable, by authenticated only.
select is(
  (select array_agg(column_name::text collate "C" order by column_name::text collate "C") from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'gyms' and privilege_type = 'UPDATE' and grantee = 'authenticated'),
  array['brand_color', 'history_after_end', 'logo_path', 'name']::text[],
  'authenticated may update only name, logo_path, history_after_end and brand_color');
select is(has_table_privilege('anon', 'public.gyms', 'select'), false, 'anon cannot read gyms');
select is(has_column_privilege('anon', 'public.gyms', 'brand_color', 'update'), false, 'anon cannot write the colour');
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), null, 'a gym starts with no colour (Azm colours)');

-- anon: nothing
set local role anon;
select throws_ok($$ select brand_color from public.gyms $$, '42501', null, 'anon cannot select the colour');
select throws_ok($$ update public.gyms set brand_color = '#facc15' $$, '42501', null, 'anon cannot update the colour');
reset role;

-- owner of gym A, permanent session
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set brand_color = '#facc15' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner sets the colour');
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '#facc15', 'the owner reads it back');
select results_eq($$ with c as (update public.gyms set brand_color = '#1e3a8a' where id = 'd0000000-0000-4000-8000-00000000000b' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'the owner of gym A cannot colour gym B');
select throws_ok($$ update public.gyms set brand_color = '#FACC15' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'upper case is refused by the table');
select throws_ok($$ update public.gyms set brand_color = '#808080' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'a grey is refused by the table');
select throws_ok($$ update public.gyms set brand_color = 'red' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'a colour name is refused by the table');
select throws_ok($$ update public.gyms set brand_color = '#facc15''; drop table gyms;--' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'injection-like text is refused by the table');
select throws_ok($$ update public.gyms set brand_color = repeat('a', 1000000) where id = 'd0000000-0000-4000-8000-00000000000a' $$, '23514', null, 'a huge text is refused by the table');
select throws_ok($$ update public.gyms set is_demo = true where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'the owner still cannot write other columns');
select throws_ok($$ update public.gyms set deleted_at = now(), brand_color = '#facc15' where id = 'd0000000-0000-4000-8000-00000000000a' $$, '42501', null, 'not even together with the colour');
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '#facc15', 'refused writes left the colour as it was');
reset role;
reset request.jwt.claims;

-- captain of gym A: reads, cannot write
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '#facc15', 'a captain reads the colour');
select results_eq($$ with c as (update public.gyms set brand_color = '#dc2626' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain cannot change the colour');
select results_eq($$ with c as (update public.gyms set brand_color = null where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a captain cannot reset the colour');
reset role;
reset request.jwt.claims;

-- trainee of gym A (anonymous session): reads own gym only, cannot write
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '#facc15', 'a trainee reads their gym''s colour');
select is((select count(*)::int from public.gyms where id = 'd0000000-0000-4000-8000-00000000000b'), 0, 'a trainee of gym A does not see gym B at all');
select results_eq($$ with c as (update public.gyms set brand_color = '#dc2626' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'a trainee cannot change the colour');
reset role;
reset request.jwt.claims;

-- captain of gym B: nothing of gym A
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), 0, 'another gym''s captain does not see gym A');
select results_eq($$ with c as (update public.gyms set brand_color = '#dc2626' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'another gym''s captain cannot change gym A''s colour');
reset role;
reset request.jwt.claims;

-- owner of gym A on an anonymous session: reads, cannot write
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';
select results_eq($$ with c as (update public.gyms set brand_color = '#dc2626' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'an owner on an anonymous session cannot change the colour');
reset role;
reset request.jwt.claims;

-- a signed-in user with no person: nothing
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-0000000000ff","role":"authenticated","is_anonymous":false}';
select is((select count(*)::int from public.gyms), 0, 'a user with no membership sees no gym');
select results_eq($$ with c as (update public.gyms set brand_color = '#dc2626' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'and changes none');
reset role;
reset request.jwt.claims;

-- the join answer carries the colour
select is((select private.redeem_payload(g, m) -> 'gym' ->> 'brand_color' from public.gyms g, public.memberships m where g.id = 'd0000000-0000-4000-8000-00000000000a' and m.id = 'e0000000-0000-4000-8000-000000000003'), '#facc15', 'redeem_payload returns the gym''s colour');
select is((select private.redeem_payload(g, m) -> 'gym' -> 'brand_color' from public.gyms g, public.memberships m where g.id = 'd0000000-0000-4000-8000-00000000000b' and m.id = 'e0000000-0000-4000-8000-000000000006'), 'null'::jsonb, 'and null for a gym without one');
select is((select private.redeem_payload(g, m) -> 'gym' ->> 'name' from public.gyms g, public.memberships m where g.id = 'd0000000-0000-4000-8000-00000000000a' and m.id = 'e0000000-0000-4000-8000-000000000003'), 'Gym A', 'the rest of the answer is unchanged');

-- an ended member still reads the gym row (its name), so also the colour; the app ignores it
update public.memberships set status = 'ended' where id = 'e0000000-0000-4000-8000-000000000003';
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":true}';
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), '#facc15', 'an ended member can still read the colour');
select results_eq($$ with c as (update public.gyms set brand_color = '#dc2626' where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (0) $$, 'an ended member cannot change it');
reset role;
reset request.jwt.claims;

-- the owner resets to Azm colours
set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
select results_eq($$ with c as (update public.gyms set brand_color = null where id = 'd0000000-0000-4000-8000-00000000000a' returning 1) select count(*)::int from c $$, $$ values (1) $$, 'the owner resets the colour');
select is((select brand_color from public.gyms where id = 'd0000000-0000-4000-8000-00000000000a'), null, 'reset means null');
reset role;
reset request.jwt.claims;

select * from finish();
rollback;
