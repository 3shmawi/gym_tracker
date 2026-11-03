-- Gym-chosen exercise pictures (docs/features/gym_exercise_images.md).
--
-- A gym's owner or captain picks up to 6 pictures of the shared library
-- (`exercise_images`, 0013/0014) for an exercise; the gym's active members
-- read them. The app only shows them; captains manage them in the web
-- dashboard (docs/decisions/gym_accounts.md §20).
--
-- Backward compatible: a new table, a trigger and a function. Nothing that
-- exists changes, so the published app keeps working when this deploys.
--
-- Rules (same as 0005-0012):
--   * RLS on; anon and authenticated lose the default grants, then get back
--     only the columns they need.
--   * Authorization is by gym_id only (private.i_manage / private.my_role_in).
--     exercise_id is never used to decide who may read or write.
--   * The limits live here, not only in the dashboard: positions 1-6 and
--     unique per exercise (= at most 6 pictures), at most 1200 rows per gym.

-- ---------------------------------------------------------------------------
-- gym_exercise_images
-- ---------------------------------------------------------------------------
create table public.gym_exercise_images (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  -- A library id (`flat_db_press`, snake_case, PlanTemplates/exercise_catalog)
  -- or an id the plan editor made (`newPlanId('ex', …)`: `ex-<base36 time>`,
  -- plus `-<n>` after a clash). Anything else is refused.
  exercise_id text not null
    constraint gym_exercise_images_exercise_id_format check (
      char_length(exercise_id) <= 64
      and exercise_id ~ '^(?:[a-z][a-z0-9_]*|ex-[a-z0-9]{1,20}(?:-[0-9]{1,4})?)$'
    ),
  -- A picture of the library. If the library ever drops a picture, the gym's
  -- choice of it goes too (the app then shows the next one).
  public_id text not null
    references public.exercise_images (public_id) on update restrict on delete cascade,
  -- 1-based order; 1 is the cover. With the unique key below this also caps
  -- an exercise at 6 pictures. Gaps are allowed: readers sort by position.
  position smallint not null
    constraint gym_exercise_images_position_range check (position between 1 and 6),
  -- Who changed it last: set by the trigger, never by the client.
  updated_by uuid references public.people (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gym_exercise_images_one_per_picture unique (gym_id, exercise_id, public_id),
  -- Deferrable so one UPDATE statement can swap two positions.
  constraint gym_exercise_images_one_per_position unique (gym_id, exercise_id, position)
    deferrable initially immediate
);

-- The unique keys already index (gym_id, …), which the policies filter on.
-- These two keep the foreign-key actions (a library picture removed, a person
-- deleted) from scanning the table.
create index gym_exercise_images_public_id_idx on public.gym_exercise_images (public_id);
create index gym_exercise_images_updated_by_idx on public.gym_exercise_images (updated_by)
  where updated_by is not null;

comment on table public.gym_exercise_images is
  'Pictures a gym chose for an exercise (max 6, ordered). Read: the gym''s active members. Write: owner/captain.';

-- Stamps updated_by / updated_at and keeps a gym under 1200 rows (200
-- exercises x 6). The advisory lock makes the count exact under concurrent
-- inserts for the same gym. Security definer so the count is one index scan,
-- not a policy check per row; it only reads the row count of new.gym_id, and
-- the insert policy still decides whether the caller may add the row.
create function private.gym_exercise_images_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtextextended('gym_exercise_images:' || new.gym_id::text, 0));
    if (select count(*) from public.gym_exercise_images g where g.gym_id = new.gym_id) >= 1200 then
      raise exception 'too_many_pictures_in_gym' using errcode = '23514';
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

create trigger gym_exercise_images_guard
  before insert or update on public.gym_exercise_images
  for each row execute function private.gym_exercise_images_guard();

revoke all on function private.gym_exercise_images_guard() from public, anon, authenticated;

alter table public.gym_exercise_images enable row level security;
revoke all on table public.gym_exercise_images from anon, authenticated;
grant select, delete on table public.gym_exercise_images to authenticated;
grant insert (gym_id, exercise_id, public_id, position)
  on table public.gym_exercise_images to authenticated;
-- Only the order changes in place; another picture = delete + insert.
grant update (position) on table public.gym_exercise_images to authenticated;

-- Active members of the gym (any role; trainees may be anonymous users).
-- Ended or pending members, other gyms and anon read nothing.
create policy "members read their gym's exercise pictures" on public.gym_exercise_images
  for select to authenticated
  using ((select private.my_role_in(gym_id)) is not null);

create policy "managers add exercise pictures" on public.gym_exercise_images
  for insert to authenticated
  with check ((select private.i_manage(gym_id)));

create policy "managers reorder exercise pictures" on public.gym_exercise_images
  for update to authenticated
  using ((select private.i_manage(gym_id)))
  with check ((select private.i_manage(gym_id)));

create policy "managers remove exercise pictures" on public.gym_exercise_images
  for delete to authenticated
  using ((select private.i_manage(gym_id)));

-- ---------------------------------------------------------------------------
-- Replace an exercise's pictures in one transaction (the dashboard's "save").
-- Security invoker: the policies above still decide; this only makes the
-- delete + insert atomic, so readers never see half a list.
-- ---------------------------------------------------------------------------
create function public.set_gym_exercise_images(
  p_gym_id uuid,
  p_exercise_id text,
  p_public_ids text[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_gym_id is null or not private.i_manage(p_gym_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_exercise_id is null or p_public_ids is null
     or coalesce(array_ndims(p_public_ids), 1) <> 1
     or array_position(p_public_ids, null) is not null then
    raise exception 'invalid_list' using errcode = '22023';
  end if;
  if cardinality(p_public_ids) > 6 then
    raise exception 'too_many_pictures' using errcode = '23514';
  end if;
  if (select count(distinct x) from unnest(p_public_ids) as x) <> cardinality(p_public_ids) then
    raise exception 'duplicate_picture' using errcode = '22023';
  end if;

  delete from public.gym_exercise_images
   where gym_id = p_gym_id and exercise_id = p_exercise_id;

  insert into public.gym_exercise_images (gym_id, exercise_id, public_id, position)
  select p_gym_id, p_exercise_id, t.public_id, t.ord::smallint
    from unnest(p_public_ids) with ordinality as t (public_id, ord);
end;
$$;

revoke all on function public.set_gym_exercise_images(uuid, text, text[]) from public, anon;
grant execute on function public.set_gym_exercise_images(uuid, text, text[]) to authenticated;
