-- Exercise picture library: one row per picture hosted on Cloudinary, with
-- the words people search by (English + Arabic), its source and its licence.
-- A captain adding an exercise picks one of these (web dashboard). The rows
-- are filled by 0014 (generated) and the workflow "Exercise images"; the files
-- are public CDN links built from `public_id`: https://res.cloudinary.com/
-- <cloud name>/image/upload/<public_id>.png (the cloud name is not secret).
-- Everyone may read; nobody but the service role may write.
create table if not exists public.exercise_images (
  public_id text primary key
    check (public_id ~ '^azm/exercises/[a-z0-9-]+$'),
  exercise_key text not null check (exercise_key ~ '^ek-[0-9]{4}$'),
  frame text not null check (frame in ('tension', 'relaxation')),
  title_en text not null check (char_length(title_en) between 1 and 120),
  keywords text[] not null check (cardinality(keywords) between 1 and 60),
  muscle_groups text[] not null default '{}',
  muscles text[] not null default '{}',
  equipment text[] not null default '{}',
  exercise_type text not null default '',
  source_url text not null check (source_url ~ '^https://'),
  source_commit text not null,
  -- Only licences we may use in a commercial app (no NC, no ND).
  license text not null
    check (license in ('CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-3.0', 'CC-BY-SA-4.0')),
  author text not null check (char_length(author) > 0),
  attribution text not null check (char_length(attribution) > 0),
  created_at timestamptz not null default now()
);

-- Search: `keywords && array['chest', 'دمبل']` (any word) or `@>` (all words).
create index if not exists exercise_images_keywords_idx
  on public.exercise_images using gin (keywords);
create index if not exists exercise_images_exercise_key_idx
  on public.exercise_images (exercise_key);

alter table public.exercise_images enable row level security;

drop policy if exists "Anyone can read exercise images" on public.exercise_images;
create policy "Anyone can read exercise images"
  on public.exercise_images for select
  using (true);

revoke all on table public.exercise_images from anon, authenticated;
grant select on table public.exercise_images to anon, authenticated;
