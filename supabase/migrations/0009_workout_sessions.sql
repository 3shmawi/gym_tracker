-- Gym accounts, part 5: workout history in the account, the personal plan, and
-- the "move my solo data" import (docs/decisions/gym_accounts.md §3, §4, §10).
--
-- History belongs to the PERSON (people.id). gym_id says which workspace it was
-- logged in (null = solo): a captain reads only sessions of their own gym, only
-- while that person's membership there is active, and never solo ones.
--
-- On-device sessions have no id and no start time (WorkoutSession is
-- {day_id, finished_at, sets}), so the app sends a deterministic client_id
-- (a hash of the session's content); sending the same session twice is a no-op.

-- ---------------------------------------------------------------------------
-- Validation of the `sets` array (same limits as the app): used by the table
-- trigger and by import_solo_data. Returns null when fine, else a short reason.
-- ---------------------------------------------------------------------------
create function private.sets_problem(p_sets jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_set jsonb;
begin
  if p_sets is null or jsonb_typeof(p_sets) <> 'array' then return 'sets is not a list'; end if;
  if jsonb_array_length(p_sets) > 500 then return 'too many sets'; end if;
  if octet_length(p_sets::text) > 65536 then return 'sets too large'; end if;
  for v_set in select value from jsonb_array_elements(p_sets) loop
    if jsonb_typeof(v_set) <> 'object'
       or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_set) k)
          is distinct from array['exercise', 'reps', 'weight'] then
      return 'bad set';
    end if;
    if jsonb_typeof(v_set -> 'exercise') <> 'string'
       or (v_set ->> 'exercise') !~ '^[A-Za-z0-9_-]{1,64}$' then
      return 'bad exercise id';
    end if;
    if jsonb_typeof(v_set -> 'weight') <> 'number'
       or (v_set ->> 'weight')::numeric < 0 or (v_set ->> 'weight')::numeric > 1000 then
      return 'weight out of range';
    end if;
    if not private.plan_int_ok(v_set -> 'reps', 0, 1000) then return 'reps out of range'; end if;
  end loop;
  return null;
end;
$$;

-- One session as the app sends it: {client_id, day_id, finished_at, sets}.
create function private.session_problem(p_session jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_finished timestamptz;
begin
  if p_session is null or jsonb_typeof(p_session) <> 'object'
     or (select array_agg(k order by k collate "C") from jsonb_object_keys(p_session) k)
        is distinct from array['client_id', 'day_id', 'finished_at', 'sets'] then
    return 'bad session';
  end if;
  if jsonb_typeof(p_session -> 'client_id') <> 'string'
     or (p_session ->> 'client_id') !~ '^[A-Za-z0-9_-]{1,64}$' then
    return 'bad client id';
  end if;
  if jsonb_typeof(p_session -> 'day_id') <> 'string'
     or (p_session ->> 'day_id') !~ '^[A-Za-z0-9_-]{1,64}$' then
    return 'bad day id';
  end if;
  if jsonb_typeof(p_session -> 'finished_at') <> 'string'
     or (p_session ->> 'finished_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
    return 'bad finish time';
  end if;
  begin
    v_finished := (p_session ->> 'finished_at')::timestamptz;
  exception when others then
    return 'bad finish time';
  end;
  if v_finished < timestamptz '2020-01-01' or v_finished > now() + interval '1 day' then
    return 'finish time out of range';
  end if;
  return private.sets_problem(p_session -> 'sets');
end;
$$;

-- ---------------------------------------------------------------------------
-- workout_sessions
-- ---------------------------------------------------------------------------
create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  client_id text not null check (client_id ~ '^[A-Za-z0-9_-]{1,64}$'),
  person_id uuid not null references public.people (id) on delete cascade,
  -- The workspace it was logged in; null = solo (never visible to any gym).
  gym_id uuid references public.gyms (id) on delete set null,
  membership_id uuid references public.memberships (id) on delete set null,
  day_id text not null check (day_id ~ '^[A-Za-z0-9_-]{1,64}$'),
  finished_at timestamptz not null,
  sets jsonb not null,
  created_at timestamptz not null default now(),
  unique (person_id, client_id),
  constraint workout_sessions_membership_needs_gym check (membership_id is null or gym_id is not null)
);

create index workout_sessions_person_idx on public.workout_sessions (person_id, finished_at desc);
create index workout_sessions_gym_idx on public.workout_sessions (gym_id, finished_at desc)
  where gym_id is not null;

create function private.workout_sessions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_problem text := private.sets_problem(new.sets);
begin
  if v_problem is not null then
    raise exception 'invalid_session: %', v_problem using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger workout_sessions_guard
  before insert or update on public.workout_sessions
  for each row execute function private.workout_sessions_guard();

-- The caller's own membership in [p_gym_id] is active (and the gym is live).
create function private.active_membership_matches(p_membership_id uuid, p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.gyms g on g.id = m.gym_id
    where m.id = p_membership_id
      and m.gym_id = p_gym_id
      and m.person_id = private.current_person_id()
      and m.status = 'active'
      and g.deleted_at is null
  )
$$;

-- May the person still read this session? Gym sessions of an ended
-- membership are hidden (never deleted) when the gym says `locked`.
create function private.own_session_visible(p_gym_id uuid, p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_gym_id is null then true
    else not exists (
      select 1
      from public.memberships m
      join public.gyms g on g.id = m.gym_id
      where m.id = p_membership_id
        and m.status = 'ended'
        and g.history_after_end = 'locked'
    )
  end
$$;

-- Staff read a member's gym sessions while that membership is active, and
-- only as far as they may manage that member (a captain: trainees only).
create function private.can_read_member_sessions(p_gym_id uuid, p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m.status = 'active'
            and m.gym_id = p_gym_id
            and private.i_manage_role(m.gym_id, m.role)
     from public.memberships m
     where m.id = p_membership_id),
    false
  )
$$;

revoke all on function private.sets_problem(jsonb), private.session_problem(jsonb),
  private.active_membership_matches(uuid, uuid), private.own_session_visible(uuid, uuid),
  private.can_read_member_sessions(uuid, uuid) from public, anon;
grant execute on function private.sets_problem(jsonb), private.session_problem(jsonb),
  private.active_membership_matches(uuid, uuid), private.own_session_visible(uuid, uuid),
  private.can_read_member_sessions(uuid, uuid) to authenticated, service_role;

alter table public.workout_sessions enable row level security;
revoke all on table public.workout_sessions from anon, authenticated;
grant select, delete on table public.workout_sessions to authenticated;
grant insert (client_id, person_id, gym_id, membership_id, day_id, finished_at, sets)
  on table public.workout_sessions to authenticated;
-- Who, where and which session never change; only the content may.
grant update (day_id, finished_at, sets) on table public.workout_sessions to authenticated;

create policy "read own sessions" on public.workout_sessions
  for select to authenticated
  using (
    person_id = (select private.current_person_id())
    and (select private.own_session_visible(gym_id, membership_id))
  );

create policy "staff read their gym's sessions" on public.workout_sessions
  for select to authenticated
  using (
    gym_id is not null and membership_id is not null
    and (select private.can_read_member_sessions(gym_id, membership_id))
  );

create policy "log own sessions" on public.workout_sessions
  for insert to authenticated
  with check (
    person_id = (select private.current_person_id())
    and (
      (gym_id is null and membership_id is null)
      or (select private.active_membership_matches(membership_id, gym_id))
    )
  );

create policy "edit own sessions" on public.workout_sessions
  for update to authenticated
  using (
    person_id = (select private.current_person_id())
    and (select private.own_session_visible(gym_id, membership_id))
  )
  with check (person_id = (select private.current_person_id()));

create policy "delete own sessions" on public.workout_sessions
  for delete to authenticated
  using (person_id = (select private.current_person_id()));

-- ---------------------------------------------------------------------------
-- personal_plans: the person's own plan (the solo plan moved into the
-- account). A gym's plan for a member stays in `plans`. Read-only for clients:
-- it is written by import_solo_data (and by a later save function).
-- ---------------------------------------------------------------------------
create table public.personal_plans (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null unique references public.people (id) on delete cascade,
  body jsonb not null check (jsonb_typeof(body) = 'object' and octet_length(body::text) <= 65536),
  version int not null default 1 check (version >= 1),
  updated_at timestamptz not null default now()
);

alter table public.personal_plans enable row level security;
revoke all on table public.personal_plans from anon, authenticated;
grant select on table public.personal_plans to authenticated;

create policy "read own personal plan" on public.personal_plans
  for select to authenticated
  using (person_id = (select private.current_person_id()));

-- ---------------------------------------------------------------------------
-- import_solo_data(sessions, plan)
--   * the caller needs a person (they joined a gym or were linked);
--   * at most 50 sessions per call (the app sends chunks and resumes);
--   * all-or-nothing per call: one bad session rejects the chunk, nothing is
--     half written; sessions already there (same client_id) are skipped, so a
--     retry after a dropped answer is safe;
--   * imported sessions are SOLO (gym_id null): staff never see them;
--   * the plan is stored only if the person has none yet (never overwritten);
--   * returns {imported, skipped, plan_saved, solo_total}: the app keeps its
--     local copy until solo_total matches.
-- Errors: forbidden (42501), invalid_import: <why> (22023).
-- ---------------------------------------------------------------------------
create function public.import_solo_data(p_sessions jsonb, p_plan jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_solo constant int := 1000;
  v_person uuid := private.current_person_id();
  v_session jsonb;
  v_problem text;
  v_count int;
  v_inserted int := 0;
  v_rows int;
  v_plan_saved boolean := false;
  v_total int;
begin
  if v_person is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_sessions is null or jsonb_typeof(p_sessions) <> 'array' then
    raise exception 'invalid_import: sessions is not a list' using errcode = '22023';
  end if;
  v_count := jsonb_array_length(p_sessions);
  if v_count > 50 then
    raise exception 'invalid_import: at most 50 sessions per call' using errcode = '22023';
  end if;
  if p_plan is not null and jsonb_typeof(p_plan) <> 'null' then
    v_problem := private.plan_problem(p_plan);
    if v_problem is not null then
      raise exception 'invalid_import: plan: %', v_problem using errcode = '22023';
    end if;
  end if;
  for v_session in select value from jsonb_array_elements(p_sessions) loop
    v_problem := private.session_problem(v_session);
    if v_problem is not null then
      raise exception 'invalid_import: %', v_problem using errcode = '22023';
    end if;
  end loop;
  if (select count(distinct s ->> 'client_id') from jsonb_array_elements(p_sessions) s) <> v_count then
    raise exception 'invalid_import: duplicate client ids' using errcode = '22023';
  end if;

  -- One import at a time per person, so the counts are exact.
  perform pg_advisory_xact_lock(hashtextextended(v_person::text, 1));

  select count(*) into v_total
    from public.workout_sessions where person_id = v_person and gym_id is null;
  if v_total + v_count > c_max_solo then
    raise exception 'invalid_import: too many solo sessions' using errcode = '22023';
  end if;

  for v_session in select value from jsonb_array_elements(p_sessions) loop
    insert into public.workout_sessions (client_id, person_id, day_id, finished_at, sets)
    values (
      v_session ->> 'client_id', v_person, v_session ->> 'day_id',
      (v_session ->> 'finished_at')::timestamptz, v_session -> 'sets'
    )
    on conflict (person_id, client_id) do nothing;
    get diagnostics v_rows = row_count;
    v_inserted := v_inserted + v_rows;
  end loop;

  if p_plan is not null and jsonb_typeof(p_plan) <> 'null' then
    insert into public.personal_plans (person_id, body) values (v_person, p_plan)
    on conflict (person_id) do nothing;
    get diagnostics v_rows = row_count;
    v_plan_saved := v_rows = 1;
  end if;

  select count(*) into v_total
    from public.workout_sessions where person_id = v_person and gym_id is null;
  return jsonb_build_object(
    'imported', v_inserted,
    'skipped', v_count - v_inserted,
    'plan_saved', v_plan_saved,
    'solo_total', v_total
  );
end;
$$;

revoke all on function public.import_solo_data(jsonb, jsonb) from public, anon;
grant execute on function public.import_solo_data(jsonb, jsonb) to authenticated;
