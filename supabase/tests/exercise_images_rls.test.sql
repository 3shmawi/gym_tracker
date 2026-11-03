-- Row Level Security tests for exercise_images (pgTAP).
-- Run: supabase test db   (needs `supabase init` once + Docker)
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.exercise_images'::regclass),
  'RLS is enabled on exercise_images'
);

-- The seed (0014) is there and every row is usable in a commercial app.
select cmp_ok(
  (select count(*) from public.exercise_images), '>=', 500::bigint,
  'the library is filled'
);
select is(
  (select count(*) from public.exercise_images
    where license not in ('CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-3.0', 'CC-BY-SA-4.0')),
  0::bigint,
  'no picture has a licence we may not use'
);
select cmp_ok(
  (select count(*) from public.exercise_images where keywords && array['صدر']),
  '>', 0::bigint,
  'an Arabic word finds pictures'
);

-- The table refuses what the licence rules refuse, even for its owner.
select throws_ok(
  $$ insert into public.exercise_images
       (public_id, exercise_key, frame, title_en, keywords, source_url,
        source_commit, license, author, attribution)
     values ('exercises/ek-9999-tension', 'ek-9999', 'tension', 'x',
             array['x'], 'https://example.org', 'c', 'CC-BY-NC-4.0', 'a', 'b') $$,
  '23514',
  null,
  'a non-commercial licence is refused'
);
select throws_ok(
  $$ insert into public.exercise_images
       (public_id, exercise_key, frame, title_en, keywords, source_url,
        source_commit, license, author, attribution)
     values ('../../evil', 'ek-9999', 'tension', 'x', array['x'],
             'https://example.org', 'c', 'CC0-1.0', 'a', 'b') $$,
  '23514',
  null,
  'a crafted public id is refused'
);

set local role anon;

select lives_ok(
  $$ select public_id from public.exercise_images where keywords && array['chest'] $$,
  'anon can search the library'
);
select throws_ok(
  $$ insert into public.exercise_images
       (public_id, exercise_key, frame, title_en, keywords, source_url,
        source_commit, license, author, attribution)
     values ('exercises/ek-9999-tension', 'ek-9999', 'tension', 'x',
             array['x'], 'https://example.org', 'c', 'CC0-1.0', 'a', 'b') $$,
  '42501',
  null,
  'anon cannot add a picture'
);
select throws_ok(
  $$ update public.exercise_images set title_en = 'hacked' $$,
  '42501',
  null,
  'anon cannot change a picture'
);

set local role authenticated;

select throws_ok(
  $$ delete from public.exercise_images $$,
  '42501',
  null,
  'a signed-in user cannot delete pictures'
);
select throws_ok(
  $$ update public.exercise_images set license = 'CC0-1.0' $$,
  '42501',
  null,
  'a signed-in user cannot change a licence'
);

select * from finish();
rollback;
