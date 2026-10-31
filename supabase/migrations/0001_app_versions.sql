-- Version-update gate: one row per platform. Edit rows from the Supabase
-- dashboard (Table editor) to show an optional or forced update — no release.
--   latest_version        → users below this see "Update / Later"
--   min_supported_version → users below this must update (no "Later")
create table if not exists public.app_versions (
  platform text primary key check (platform in ('android', 'ios')),
  latest_version text not null,
  min_supported_version text not null,
  store_url text not null,
  changelog_en text not null default '',
  changelog_ar text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.app_versions enable row level security;

drop policy if exists "Anyone can read app versions" on public.app_versions;
create policy "Anyone can read app versions"
  on public.app_versions for select
  using (true);

insert into public.app_versions (platform, latest_version, min_supported_version, store_url)
values
  ('android', '1.0.0', '1.0.0', 'https://play.google.com/store/apps/details?id=com.mohager.gymtracker'),
  ('ios', '1.0.0', '1.0.0', 'https://apps.apple.com/app/idYOUR_APP_ID')
on conflict (platform) do nothing;
