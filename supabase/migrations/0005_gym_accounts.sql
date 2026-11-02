-- Gym accounts, part 1: gyms, people, memberships (docs/decisions/gym_accounts.md §3-§4).
--
-- Rules used everywhere in 0005-0008:
--   * RLS is enabled on every table; grants to anon/authenticated are revoked
--     first and only the needed ones are given back (Supabase docs, "Row Level
--     Security": policies do not remove default grants).
--   * The `anon` role gets nothing. Anonymous *users* get the `authenticated`
--     role, so every policy is tied to a membership, never to the role alone.
--   * Helpers used by policies live in the unexposed `private` schema
--     (security definer, search_path = ''). Functions in `public` are callable
--     over the Data API, so each one checks the caller itself.
--   * Management (owner / captain) needs a permanent session: a JWT with
--     is_anonymous = true never counts as a manager.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- gyms
-- ---------------------------------------------------------------------------
create table public.gyms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60 and name = btrim(name)),
  -- Storage object path in bucket gym-logos: <gym_id>/logo.png|jpg|jpeg.
  logo_path text check (
    logo_path is null
    or logo_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo\.(png|jpe?g)$'
  ),
  -- What a person who left (or was removed) can still read of the gym's history.
  history_after_end text not null default 'readable'
    check (history_after_end in ('readable', 'locked')),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.gyms enable row level security;
revoke all on table public.gyms from anon, authenticated;
grant select on table public.gyms to authenticated;
grant update (name, logo_path, history_after_end) on table public.gyms to authenticated;

-- ---------------------------------------------------------------------------
-- people: the person. History hangs on people.id, not on the auth user.
-- ---------------------------------------------------------------------------
create table public.people (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 40),
  locale text check (locale is null or locale in ('en', 'ar')),
  created_at timestamptz not null default now()
);

alter table public.people enable row level security;
revoke all on table public.people from anon, authenticated;
grant select on table public.people to authenticated;
grant update (display_name, locale) on table public.people to authenticated;

-- ---------------------------------------------------------------------------
-- memberships
-- ---------------------------------------------------------------------------
create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  -- Null until the invite is redeemed: the captain creates the account first.
  person_id uuid references public.people (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40 and display_name = btrim(display_name)),
  role text not null default 'trainee' check (role in ('owner', 'captain', 'trainee')),
  status text not null default 'pending' check (status in ('pending', 'active', 'ended')),
  can_edit_targets boolean not null default false,
  can_edit_plan boolean not null default false,
  can_build_own_plan boolean not null default false,
  created_by uuid references public.people (id) on delete set null,
  created_at timestamptz not null default now(),
  joined_at timestamptz,
  ended_at timestamptz,
  ended_by uuid references public.people (id) on delete set null,
  unique (gym_id, person_id),
  -- Editing the whole plan includes editing targets.
  constraint memberships_plan_implies_targets check (not can_edit_plan or can_edit_targets),
  -- Permissions are meaningful for trainees only.
  constraint memberships_flags_trainee_only check (
    role = 'trainee' or not (can_edit_targets or can_edit_plan or can_build_own_plan)
  ),
  -- Active means someone joined; pending means nobody did yet.
  constraint memberships_person_matches_status check (
    (status <> 'active' or person_id is not null)
    and (status <> 'pending' or person_id is null)
  )
);

create index memberships_person_id_idx on public.memberships (person_id);
create index memberships_gym_id_idx on public.memberships (gym_id);

alter table public.memberships enable row level security;
revoke all on table public.memberships from anon, authenticated;
grant select on table public.memberships to authenticated;
grant insert (gym_id, display_name, role, can_edit_targets, can_edit_plan,
              can_build_own_plan, created_by)
  on table public.memberships to authenticated;
grant update (display_name, role, status, can_edit_targets, can_edit_plan,
              can_build_own_plan)
  on table public.memberships to authenticated;

-- ---------------------------------------------------------------------------
-- Helpers (private). They read the tables as their owner, so policies on
-- one table can look at another without recursion.
-- ---------------------------------------------------------------------------
create function private.is_permanent()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
$$;

create function private.current_person_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id from public.people p where p.auth_user_id = (select auth.uid())
$$;

-- The caller's role in a gym, or null. Only an active membership counts.
create function private.my_role_in(p_gym_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.memberships m
  join public.gyms g on g.id = m.gym_id
  where m.gym_id = p_gym_id
    and m.person_id = private.current_person_id()
    and m.status = 'active'
    and g.deleted_at is null
$$;

-- Active owner or captain of the gym, signed in with a permanent session.
create function private.i_manage(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_permanent()
    and coalesce(private.my_role_in(p_gym_id) in ('owner', 'captain'), false)
$$;

-- May the caller change a row about a member with this role? Owners may
-- touch anyone; captains only trainees.
create function private.i_manage_role(p_gym_id uuid, p_target_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.i_manage(p_gym_id)
    and (private.my_role_in(p_gym_id) = 'owner' or p_target_role = 'trainee')
$$;

revoke all on function private.is_permanent(), private.current_person_id(),
  private.my_role_in(uuid), private.i_manage(uuid), private.i_manage_role(uuid, text)
  from public, anon;
grant execute on function private.is_permanent(), private.current_person_id(),
  private.my_role_in(uuid), private.i_manage(uuid), private.i_manage_role(uuid, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------

-- gyms: members read their gyms (an ended member still sees the gym's name).
create policy "members read their gyms" on public.gyms
  for select to authenticated
  using (
    deleted_at is null
    and exists (
      select 1 from public.memberships m
      where m.gym_id = gyms.id and m.person_id = (select private.current_person_id())
    )
  );

create policy "managers update their gym" on public.gyms
  for update to authenticated
  using ((select private.i_manage(id)))
  with check ((select private.i_manage(id)));

-- people: each person reads and edits only their own row.
create policy "read own person" on public.people
  for select to authenticated
  using (auth_user_id = (select auth.uid()));

create policy "update own person" on public.people
  for update to authenticated
  using (auth_user_id = (select auth.uid()))
  with check (auth_user_id = (select auth.uid()));

-- memberships: read your own; managers read the gym's.
create policy "read own memberships" on public.memberships
  for select to authenticated
  using (person_id = (select private.current_person_id()));

create policy "managers read gym memberships" on public.memberships
  for select to authenticated
  using ((select private.i_manage(gym_id)));

-- "Add trainee": a pending row without a person. Only owners add captains.
create policy "managers add pending members" on public.memberships
  for insert to authenticated
  with check (
    status = 'pending'
    and person_id is null
    and role in ('trainee', 'captain')
    and created_by = (select private.current_person_id())
    and (select private.i_manage_role(gym_id, role))
  );

create policy "managers update members" on public.memberships
  for update to authenticated
  using ((select private.i_manage_role(gym_id, role)))
  with check ((select private.i_manage_role(gym_id, role)));

-- ---------------------------------------------------------------------------
-- Triggers on memberships
-- ---------------------------------------------------------------------------
-- Stamps who ended a membership, and keeps clients inside the allowed
-- transitions. Code that runs as the table owner (the redeem function) is
-- not restricted; the Data API roles are.
create function private.memberships_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if current_user in ('anon', 'authenticated') then
      -- Joining is only done by redeem_invite; a client may only end a membership.
      if new.status is distinct from old.status
         and not (old.status in ('pending', 'active') and new.status = 'ended') then
        raise exception 'invalid status change' using errcode = '42501';
      end if;
    end if;
    if new.status = 'ended' and old.status <> 'ended' then
      new.ended_at := now();
      new.ended_by := (select private.current_person_id());
    end if;
    -- The gym must always keep an active owner.
    if old.role = 'owner' and old.status = 'active'
       and (new.role <> 'owner' or new.status <> 'active')
       and not exists (
         select 1 from public.memberships o
         where o.gym_id = old.gym_id and o.id <> old.id
           and o.role = 'owner' and o.status = 'active'
       ) then
      raise exception 'a gym needs at least one active owner' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger memberships_guard
  before update on public.memberships
  for each row execute function private.memberships_guard();

-- A person's own way out: end my membership.
create function public.leave_gym(p_membership_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person uuid := private.current_person_id();
  v_updated int;
begin
  if v_person is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.memberships
     set status = 'ended'
   where id = p_membership_id
     and person_id = v_person
     and status = 'active';
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'forbidden' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.leave_gym(uuid) from public, anon;
grant execute on function public.leave_gym(uuid) to authenticated;
