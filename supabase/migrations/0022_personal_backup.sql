-- "Never lose your training", PR 2: the backend for backing up a member's
-- own training (docs/designs/never_lose_history.md §2, §3, §6, §9).
--
--   * ensure_person()        a permanent session without a gym gets its person
--   * save_personal_plan()   the member's own plan, versioned (first save wins)
--   * personal_state         best level + chosen day, saved by save_personal_state()
--   * delete_my_backup()     erase the solo backup but keep the account and the gym
--   * a cap of 20,000 workouts per person for EVERY insert (a statement-level
--     trigger), and import_solo_data raised from 1000 to the same number
--
-- Nothing here changes what staff can see: solo rows (gym_id null) stay
-- invisible to every gym, including gym workouts that were sent again as solo
-- because the membership ended.

-- ---------------------------------------------------------------------------
-- 1. A person for a member without a gym
--    Only a PERMANENT session (an email account) may create one, so anonymous
--    sign-ins cannot fill `people`. Idempotent: a second call returns the same
--    person. An anonymous session is always refused: a gym member who adds an
--    email first becomes permanent (updateUser + verifyOtp), then calls this.
-- ---------------------------------------------------------------------------
create function public.ensure_person()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_person uuid;
begin
  if v_user is null or not private.is_permanent() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v_person := private.current_person_id();
  if v_person is not null then
    return v_person;
  end if;
  insert into public.people (auth_user_id) values (v_user)
  on conflict (auth_user_id) do nothing
  returning id into v_person;
  return coalesce(v_person, private.current_person_id());
end;
$$;

revoke all on function public.ensure_person() from public, anon;
grant execute on function public.ensure_person() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The member's own plan: save_personal_plan(base_version, body)
--    The same body check as a gym plan (private.plan_problem, 64 KB). It
--    writes only when p_base_version is the stored version (0 = none yet);
--    otherwise `plan_changed` (P0001): the plan saved first wins and the
--    other phone takes it. Same body again = no new version.
--    Errors: forbidden (42501), invalid_plan: <why> (22023), plan_changed.
-- ---------------------------------------------------------------------------
create function public.save_personal_plan(p_base_version int, p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person uuid := private.current_person_id();
  v_problem text;
  v_plan public.personal_plans;
begin
  if v_person is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_base_version is null or p_base_version < 0 then
    raise exception 'invalid_plan: bad version' using errcode = '22023';
  end if;
  v_problem := private.plan_problem(p_body);
  if v_problem is not null then
    raise exception 'invalid_plan: %', v_problem using errcode = '22023';
  end if;

  -- One writer at a time per person, so two phones cannot both win.
  perform pg_advisory_xact_lock(hashtextextended(v_person::text, 2));
  select * into v_plan from public.personal_plans where person_id = v_person for update;

  if not found then
    if p_base_version <> 0 then
      raise exception 'plan_changed' using errcode = 'P0001';
    end if;
    insert into public.personal_plans (person_id, body, version)
    values (v_person, p_body, 1)
    returning * into v_plan;
  else
    if p_base_version <> v_plan.version then
      raise exception 'plan_changed' using errcode = 'P0001';
    end if;
    if v_plan.body is distinct from p_body then
      update public.personal_plans
         set body = p_body, version = version + 1, updated_at = now()
       where id = v_plan.id
       returning * into v_plan;
    end if;
  end if;
  return jsonb_build_object('version', v_plan.version, 'updated_at', v_plan.updated_at);
end;
$$;

revoke all on function public.save_personal_plan(int, jsonb) from public, anon;
grant execute on function public.save_personal_plan(int, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Best level and chosen day
--    best_level only goes up (so two phones cannot conflict); chosen_day is
--    the last write. Read by the person; written only through the function.
-- ---------------------------------------------------------------------------
create function private.chosen_day_ok(p_day jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_day is null
      or (
        jsonb_typeof(p_day) = 'object'
        and octet_length(p_day::text) <= 256
        and (select coalesce(bool_and(k in ('id', 'by_edit')), true) from jsonb_object_keys(p_day) k)
        and jsonb_typeof(p_day -> 'id') = 'string'
        and (p_day ->> 'id') ~ '^[A-Za-z0-9_-]{1,64}$'
        and (not (p_day ? 'by_edit') or jsonb_typeof(p_day -> 'by_edit') = 'boolean')
      )
$$;

create table public.personal_state (
  person_id uuid primary key references public.people (id) on delete cascade,
  best_level text not null default 'beginner'
    check (best_level in ('beginner', 'intermediate', 'pro')),
  chosen_day jsonb check (private.chosen_day_ok(chosen_day)),
  updated_at timestamptz not null default now()
);

alter table public.personal_state enable row level security;
revoke all on table public.personal_state from anon, authenticated;
grant select on table public.personal_state to authenticated;

create policy "read own personal state" on public.personal_state
  for select to authenticated
  using (person_id = (select private.current_person_id()));

create function public.save_personal_state(p_best_level text, p_chosen_day jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person uuid := private.current_person_id();
  v_row public.personal_state;
begin
  if v_person is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_best_level is null or p_best_level not in ('beginner', 'intermediate', 'pro') then
    raise exception 'invalid_state: bad level' using errcode = '22023';
  end if;
  if p_chosen_day is not null and jsonb_typeof(p_chosen_day) = 'null' then
    p_chosen_day := null;
  end if;
  if not private.chosen_day_ok(p_chosen_day) then
    raise exception 'invalid_state: bad chosen day' using errcode = '22023';
  end if;

  insert into public.personal_state (person_id, best_level, chosen_day)
  values (v_person, p_best_level, p_chosen_day)
  on conflict (person_id) do update
    set best_level = case
          when array_position(array['beginner', 'intermediate', 'pro'], excluded.best_level)
             > array_position(array['beginner', 'intermediate', 'pro'], public.personal_state.best_level)
          then excluded.best_level
          else public.personal_state.best_level
        end,
        chosen_day = excluded.chosen_day,
        updated_at = now()
  returning * into v_row;
  return jsonb_build_object(
    'best_level', v_row.best_level, 'chosen_day', v_row.chosen_day, 'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.save_personal_state(text, jsonb) from public, anon;
grant execute on function public.save_personal_state(text, jsonb) to authenticated;

revoke all on function private.chosen_day_ok(jsonb) from public, anon;
grant execute on function private.chosen_day_ok(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Erase the backup but keep the account (a gym member who turns backup off)
--    Solo workouts (gym_id null), the personal plan and the personal state.
--    Gym workouts stay: the gym already has them. A solo-only account uses
--    "Delete account", which removes everything.
-- ---------------------------------------------------------------------------
create function public.delete_my_backup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person uuid := private.current_person_id();
  v_sessions int;
begin
  if v_person is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_person::text, 1));
  delete from public.workout_sessions where person_id = v_person and gym_id is null;
  get diagnostics v_sessions = row_count;
  delete from public.personal_plans where person_id = v_person;
  delete from public.personal_state where person_id = v_person;
  return jsonb_build_object('sessions_deleted', v_sessions);
end;
$$;

revoke all on function public.delete_my_backup() from public, anon;
grant execute on function public.delete_my_backup() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The cap: 20,000 workouts per person, on every insert
--    One workout a day for 54 years. A statement-level trigger counts once per
--    request, not once per row, and sees the whole batch: a request that would
--    cross the cap is refused as a whole (54000, `too_many_workouts`).
-- ---------------------------------------------------------------------------
create function private.workout_sessions_cap()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from (select distinct person_id from inserted) p
    where (select count(*) from public.workout_sessions w where w.person_id = p.person_id) > 20000
  ) then
    raise exception 'too_many_workouts: at most 20000 workouts per person' using errcode = '54000';
  end if;
  return null;
end;
$$;

create trigger workout_sessions_cap
  after insert on public.workout_sessions
  referencing new table as inserted
  for each statement execute function private.workout_sessions_cap();

-- import_solo_data: the same numbers as before, with the solo cap at 20,000.
create or replace function public.import_solo_data(p_sessions jsonb, p_plan jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_solo constant int := 20000;
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
