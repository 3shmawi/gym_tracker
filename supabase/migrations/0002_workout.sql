-- Workout MVP: plans that advance by session (not by calendar day), sessions
-- and logged sets. A missed day never skips a workout: the member's next
-- day only moves when they mark a session Complete (complete_session).
--
-- Roles: every signed-in user is a member by default. Coaches own plans and
-- assign them; coach/gym dashboards come in a later phase.

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  role text not null default 'member' check (role in ('member', 'coach', 'admin')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Users read their own profile" on public.profiles;
create policy "Users read their own profile"
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()));

-- Users may rename themselves; the role column is protected below.
drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

revoke update on public.profiles from authenticated;
grant update (display_name) on public.profiles to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_coach()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('coach', 'admin')
  );
$$;

-- ---------------------------------------------------------------------------
-- Exercise catalog (names in both languages)
-- ---------------------------------------------------------------------------
create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null,
  muscle_group text not null default '',
  video_url text,
  created_at timestamptz not null default now()
);

alter table public.exercises enable row level security;

drop policy if exists "Signed-in users read exercises" on public.exercises;
create policy "Signed-in users read exercises"
  on public.exercises for select
  to authenticated
  using (true);

drop policy if exists "Coaches manage exercises" on public.exercises;
create policy "Coaches manage exercises"
  on public.exercises for all
  to authenticated
  using ((select public.is_coach()))
  with check ((select public.is_coach()));

-- ---------------------------------------------------------------------------
-- Plans → days → exercises
-- ---------------------------------------------------------------------------
create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid references public.profiles (id) on delete set null,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.plan_days (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans (id) on delete cascade,
  day_order int not null check (day_order >= 1),
  name_en text not null,
  name_ar text not null,
  unique (plan_id, day_order)
);

create table if not exists public.plan_exercises (
  id uuid primary key default gen_random_uuid(),
  plan_day_id uuid not null references public.plan_days (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  position int not null check (position >= 1),
  sets int not null default 3 check (sets between 1 and 20),
  target_reps int not null default 10 check (target_reps between 1 and 100),
  rest_seconds int not null default 90 check (rest_seconds between 0 and 900),
  weight_step_kg numeric(5, 2) not null default 2.5 check (weight_step_kg >= 0),
  -- Exercises sharing a number in the same day are a superset (done back to
  -- back, rest after the last one). Null = done on its own.
  superset_group int check (superset_group >= 1),
  notes_ar text not null default '',
  notes_en text not null default '',
  unique (plan_day_id, position)
);

create table if not exists public.plan_assignments (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  next_day_order int not null default 1 check (next_day_order >= 1),
  active boolean not null default true,
  assigned_at timestamptz not null default now()
);

-- One active plan per member.
create unique index if not exists plan_assignments_one_active
  on public.plan_assignments (member_id) where active;

create index if not exists plan_days_plan_id on public.plan_days (plan_id);
create index if not exists plan_exercises_day_id on public.plan_exercises (plan_day_id);
create index if not exists plan_assignments_plan_id on public.plan_assignments (plan_id);

alter table public.plans enable row level security;
alter table public.plan_days enable row level security;
alter table public.plan_exercises enable row level security;
alter table public.plan_assignments enable row level security;

-- Helper: plans the current user may read (assigned to them, or theirs as coach).
create or replace function public.can_read_plan(p_plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.plan_assignments a
    where a.plan_id = p_plan_id and a.member_id = (select auth.uid())
  ) or exists (
    select 1 from public.plans p
    where p.id = p_plan_id and p.coach_id = (select auth.uid())
  );
$$;

create or replace function public.owns_plan(p_plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.plans p
    where p.id = p_plan_id and p.coach_id = (select auth.uid())
  ) and public.is_coach();
$$;

drop policy if exists "Read assigned or own plans" on public.plans;
create policy "Read assigned or own plans"
  on public.plans for select to authenticated
  using ((select public.can_read_plan(id)));

drop policy if exists "Coaches manage own plans" on public.plans;
create policy "Coaches manage own plans"
  on public.plans for all to authenticated
  using (coach_id = (select auth.uid()) and (select public.is_coach()))
  with check (coach_id = (select auth.uid()) and (select public.is_coach()));

drop policy if exists "Read days of readable plans" on public.plan_days;
create policy "Read days of readable plans"
  on public.plan_days for select to authenticated
  using ((select public.can_read_plan(plan_id)));

drop policy if exists "Coaches manage days of own plans" on public.plan_days;
create policy "Coaches manage days of own plans"
  on public.plan_days for all to authenticated
  using ((select public.owns_plan(plan_id)))
  with check ((select public.owns_plan(plan_id)));

drop policy if exists "Read exercises of readable plans" on public.plan_exercises;
create policy "Read exercises of readable plans"
  on public.plan_exercises for select to authenticated
  using (exists (
    select 1 from public.plan_days d
    where d.id = plan_day_id and public.can_read_plan(d.plan_id)
  ));

drop policy if exists "Coaches manage exercises of own plans" on public.plan_exercises;
create policy "Coaches manage exercises of own plans"
  on public.plan_exercises for all to authenticated
  using (exists (
    select 1 from public.plan_days d
    where d.id = plan_day_id and public.owns_plan(d.plan_id)
  ))
  with check (exists (
    select 1 from public.plan_days d
    where d.id = plan_day_id and public.owns_plan(d.plan_id)
  ));

-- Members read their assignment but never edit it directly: next_day_order
-- only moves through complete_session().
drop policy if exists "Members read own assignments" on public.plan_assignments;
create policy "Members read own assignments"
  on public.plan_assignments for select to authenticated
  using (member_id = (select auth.uid()) or (select public.owns_plan(plan_id)));

drop policy if exists "Coaches manage assignments of own plans" on public.plan_assignments;
create policy "Coaches manage assignments of own plans"
  on public.plan_assignments for all to authenticated
  using ((select public.owns_plan(plan_id)))
  with check ((select public.owns_plan(plan_id)));

-- ---------------------------------------------------------------------------
-- Sessions and logged sets
-- ids are client-generated uuids, so sets logged offline sync idempotently
-- (upsert on id).
-- ---------------------------------------------------------------------------
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  plan_day_id uuid references public.plan_days (id) on delete set null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status text not null default 'in_progress'
    check (status in ('in_progress', 'completed', 'abandoned'))
);

create table if not exists public.set_logs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  member_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id),
  set_number int not null check (set_number >= 1),
  weight_kg numeric(6, 2) not null check (weight_kg >= 0),
  reps int not null check (reps between 0 and 200),
  logged_at timestamptz not null default now()
);

create index if not exists sessions_member_started on public.sessions (member_id, started_at desc);
create index if not exists set_logs_member_exercise on public.set_logs (member_id, exercise_id, logged_at desc);
create index if not exists set_logs_session_id on public.set_logs (session_id);

alter table public.sessions enable row level security;
alter table public.set_logs enable row level security;

-- Completing goes through complete_session(), so members can't edit
-- status/ended_at directly (it would skip advancing the plan).
drop policy if exists "Members read own sessions" on public.sessions;
create policy "Members read own sessions"
  on public.sessions for select to authenticated
  using (member_id = (select auth.uid()));

drop policy if exists "Members start own sessions" on public.sessions;
create policy "Members start own sessions"
  on public.sessions for insert to authenticated
  with check (member_id = (select auth.uid()) and status = 'in_progress' and ended_at is null);

drop policy if exists "Members read own sets" on public.set_logs;
create policy "Members read own sets"
  on public.set_logs for select to authenticated
  using (member_id = (select auth.uid()));

drop policy if exists "Members log sets in own open sessions" on public.set_logs;
create policy "Members log sets in own open sessions"
  on public.set_logs for insert to authenticated
  with check (
    member_id = (select auth.uid())
    and exists (
      select 1 from public.sessions s
      where s.id = session_id and s.member_id = (select auth.uid())
    )
  );

drop policy if exists "Members fix own sets" on public.set_logs;
create policy "Members fix own sets"
  on public.set_logs for update to authenticated
  using (member_id = (select auth.uid()))
  with check (member_id = (select auth.uid()));

drop policy if exists "Members delete own sets" on public.set_logs;
create policy "Members delete own sets"
  on public.set_logs for delete to authenticated
  using (member_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Last performance per exercise (by exercise, not machine unit)
-- ---------------------------------------------------------------------------
create or replace view public.exercise_last_sets
with (security_invoker = true)
as
with last_session as (
  select distinct on (l.member_id, l.exercise_id)
    l.member_id, l.exercise_id, l.session_id
  from public.set_logs l
  order by l.member_id, l.exercise_id, l.logged_at desc
)
select l.member_id, l.exercise_id, l.session_id, l.set_number, l.weight_kg, l.reps, l.logged_at
from public.set_logs l
join last_session ls
  on ls.member_id = l.member_id
 and ls.exercise_id = l.exercise_id
 and ls.session_id = l.session_id;

grant select on public.exercise_last_sets to authenticated;

-- ---------------------------------------------------------------------------
-- complete_session: close the session and move the plan to the next day
-- (wraps to day 1 after the last day). Idempotent: completing twice does
-- not advance twice, so an offline retry is safe.
-- ---------------------------------------------------------------------------
create or replace function public.complete_session(p_session_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.sessions%rowtype;
  v_plan_id uuid;
  v_day_order int;
  v_day_count int;
  v_next int;
begin
  select * into v_session from public.sessions
  where id = p_session_id and member_id = (select auth.uid())
  for update;

  if not found then
    raise exception 'session not found' using errcode = 'P0002';
  end if;

  select d.plan_id, d.day_order into v_plan_id, v_day_order
  from public.plan_days d where d.id = v_session.plan_day_id;

  if v_session.status = 'completed' then
    select next_day_order into v_next from public.plan_assignments
    where member_id = v_session.member_id and active;
    return v_next;
  end if;

  update public.sessions
  set status = 'completed', ended_at = coalesce(ended_at, now())
  where id = p_session_id;

  if v_plan_id is null then
    return null; -- free workout, not part of a plan
  end if;

  select count(*) into v_day_count from public.plan_days where plan_id = v_plan_id;
  v_next := (v_day_order % v_day_count) + 1;

  update public.plan_assignments
  set next_day_order = v_next
  where member_id = v_session.member_id and plan_id = v_plan_id and active;

  return v_next;
end;
$$;

revoke execute on function public.complete_session(uuid) from public, anon;
grant execute on function public.complete_session(uuid) to authenticated;

revoke execute on function public.is_coach() from public, anon;
revoke execute on function public.can_read_plan(uuid) from public, anon;
revoke execute on function public.owns_plan(uuid) from public, anon;
grant execute on function public.is_coach() to authenticated;
grant execute on function public.can_read_plan(uuid) to authenticated;
grant execute on function public.owns_plan(uuid) to authenticated;
