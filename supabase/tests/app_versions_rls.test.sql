-- Row Level Security tests for app_versions (pgTAP).
-- Run: supabase test db   (needs `supabase init` once + Docker)
-- Every new table gets a file like this: what anon/authenticated can and
-- cannot do.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.app_versions'::regclass),
  'RLS is enabled on app_versions'
);

set local role anon;

select lives_ok(
  $$ select * from public.app_versions $$,
  'anon can read app versions'
);

select throws_ok(
  $$ insert into public.app_versions (platform, latest_version, min_supported_version, store_url)
     values ('android', '9.9.9', '9.9.9', 'https://evil.example.com') $$,
  '42501',
  null,
  'anon cannot insert app versions'
);

select results_eq(
  $$ with changed as (
       update public.app_versions set min_supported_version = '99.0.0' returning 1
     ) select count(*)::int from changed $$,
  $$ values (0) $$,
  'anon cannot force an update by editing versions'
);

select * from finish();
rollback;
