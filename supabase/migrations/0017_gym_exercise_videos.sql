-- A gym's own how-to video per exercise (docs/features/exercise_videos.md,
-- stage V-B).
--
-- A gym's owner or captain sets one YouTube video for an exercise (only the
-- 11-character id and optional start/end seconds, never a URL); the gym's
-- active members read it. The app shows it before the library's video.
-- Captains manage it in the web dashboard; the dashboard turns a pasted link
-- into the id with the shared parser rules (youtube_link_vectors.json).
--
-- Backward compatible: a new table and a trigger. Nothing that exists
-- changes, so the published app keeps working when this deploys.
--
-- Same rules as 0015 (gym_exercise_images):
--   * RLS on; anon and authenticated lose the default grants, then get back
--     only the columns they need.
--   * Authorization is by gym_id only (private.i_manage / private.my_role_in).
--   * The limits live here: one video per exercise, at most 300 per gym.

create table public.gym_exercise_videos (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  -- Same ids as gym_exercise_images (a library id or a plan editor id).
  exercise_id text not null
    constraint gym_exercise_videos_exercise_id_format check (
      char_length(exercise_id) <= 64
      and exercise_id ~ '^(?:[a-z][a-z0-9_]*|ex-[a-z0-9]{1,20}(?:-[0-9]{1,4})?)$'
    ),
  -- The YouTube video id: exactly 11 of [A-Za-z0-9_-]. Never a URL.
  video_id text not null
    constraint gym_exercise_videos_video_id_format check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  -- Optional, in seconds: 0 <= start < end <= 12 h (as the app's parser).
  start_seconds integer
    constraint gym_exercise_videos_start_range check (start_seconds between 0 and 43200),
  end_seconds integer
    constraint gym_exercise_videos_end_range check (end_seconds between 1 and 43200),
  constraint gym_exercise_videos_start_before_end check (
    start_seconds is null or end_seconds is null or start_seconds < end_seconds
  ),
  updated_by uuid references public.people (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gym_exercise_videos_one_per_exercise unique (gym_id, exercise_id)
);

create index gym_exercise_videos_updated_by_idx on public.gym_exercise_videos (updated_by)
  where updated_by is not null;

comment on table public.gym_exercise_videos is
  'A gym''s own YouTube video (id only) for an exercise, one per exercise. Read: the gym''s active members. Write: owner/captain.';

-- Stamps updated_by / updated_at, keeps a gym under 300 videos.
create function private.gym_exercise_videos_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtextextended('gym_exercise_videos:' || new.gym_id::text, 0));
    if (select count(*) from public.gym_exercise_videos g where g.gym_id = new.gym_id) >= 300 then
      raise exception 'too_many_videos_in_gym' using errcode = '23514';
    end if;
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  new.updated_by := (select private.current_person_id());
  return new;
end;
$$;

create trigger gym_exercise_videos_guard
  before insert or update on public.gym_exercise_videos
  for each row execute function private.gym_exercise_videos_guard();

revoke all on function private.gym_exercise_videos_guard() from public, anon, authenticated;

alter table public.gym_exercise_videos enable row level security;
revoke all on table public.gym_exercise_videos from anon, authenticated;
grant select, delete on table public.gym_exercise_videos to authenticated;
grant insert (gym_id, exercise_id, video_id, start_seconds, end_seconds)
  on table public.gym_exercise_videos to authenticated;
-- Another video for the same exercise is an update in place.
grant update (video_id, start_seconds, end_seconds)
  on table public.gym_exercise_videos to authenticated;

create policy "members read their gym's exercise videos" on public.gym_exercise_videos
  for select to authenticated
  using ((select private.my_role_in(gym_id)) is not null);

create policy "managers add exercise videos" on public.gym_exercise_videos
  for insert to authenticated
  with check ((select private.i_manage(gym_id)));

create policy "managers change exercise videos" on public.gym_exercise_videos
  for update to authenticated
  using ((select private.i_manage(gym_id)))
  with check ((select private.i_manage(gym_id)));

create policy "managers remove exercise videos" on public.gym_exercise_videos
  for delete to authenticated
  using ((select private.i_manage(gym_id)));
