-- Gym accounts, part 3: one plan per membership (docs/decisions/gym_accounts.md §4, §11).
--
-- `body` has the shape of the on-device WorkoutPlan (lib/features/workout):
--   {"days":[{"id","name":{"ar","en"},"exercises":[
--     {"id","name":{"ar","en"},"sets","reps","rest","step","superset"}]}]}
-- It is written only through save_plan(), which checks the limits of
-- PlanLimits (plan_rules.dart) again on the server.

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null unique references public.memberships (id) on delete cascade,
  body jsonb not null check (jsonb_typeof(body) = 'object' and octet_length(body::text) <= 65536),
  version int not null default 1 check (version >= 1),
  -- The membership that made the last change (the trainee's own, or a manager's).
  updated_by uuid references public.memberships (id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.plans enable row level security;
revoke all on table public.plans from anon, authenticated;
grant select on table public.plans to authenticated;

-- Readable by the member while active, and by the gym's managers.
create function private.can_read_plan(p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select (m.person_id = private.current_person_id() and m.status = 'active')
            or private.i_manage_role(m.gym_id, m.role)
     from public.memberships m
     where m.id = p_membership_id),
    false
  )
$$;

revoke all on function private.can_read_plan(uuid) from public, anon;
grant execute on function private.can_read_plan(uuid) to authenticated, service_role;

create policy "read plans of my membership or my gym" on public.plans
  for select to authenticated
  using ((select private.can_read_plan(membership_id)));

-- ---------------------------------------------------------------------------
-- Validation (same limits as the app's PlanLimits / validatePlan)
-- ---------------------------------------------------------------------------

-- A name as the app stores it: 1-40 characters, one line, trimmed, no
-- control or bidi-override characters, no double spaces.
create function private.plan_name_ok(p_name jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_lang text;
  v_text text;
begin
  if jsonb_typeof(p_name) <> 'object' then return false; end if;
  if (select count(*) from jsonb_object_keys(p_name)) <> 2 then return false; end if;
  foreach v_lang in array array['ar', 'en'] loop
    if jsonb_typeof(p_name -> v_lang) <> 'string' then return false; end if;
    v_text := p_name ->> v_lang;
    if char_length(v_text) < 1 or char_length(v_text) > 40 then return false; end if;
    if v_text <> btrim(v_text) or v_text ~ '  ' then return false; end if;
    if v_text ~ '[\x01-\x1F\x7F-\x9F‎‏‪-‮⁦-⁩]' then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create function private.plan_int_ok(p_val jsonb, p_min int, p_max int)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_val) = 'number'
     and (p_val #>> '{}')::numeric = trunc((p_val #>> '{}')::numeric)
     and (p_val #>> '{}')::numeric between p_min and p_max
$$;

-- Returns null when the plan is fine, else a short reason.
create function private.plan_problem(p_body jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_day jsonb;
  v_ex jsonb;
  v_day_ids text[] := '{}';
  v_ex_ids text[];
  v_id text;
  c_id_re constant text := '^[A-Za-z0-9_-]{1,64}$';
begin
  if p_body is null or jsonb_typeof(p_body) <> 'object' then return 'not an object'; end if;
  if octet_length(p_body::text) > 65536 then return 'too large'; end if;
  if (select count(*) from jsonb_object_keys(p_body)) <> 1
     or jsonb_typeof(p_body -> 'days') <> 'array' then
    return 'bad shape';
  end if;
  if jsonb_array_length(p_body -> 'days') not between 1 and 14 then return 'bad day count'; end if;

  for v_day in select value from jsonb_array_elements(p_body -> 'days') loop
    if jsonb_typeof(v_day) <> 'object'
       or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_day) k)
          is distinct from array['exercises', 'id', 'name'] then
      return 'bad day';
    end if;
    if jsonb_typeof(v_day -> 'id') <> 'string' then return 'bad day id'; end if;
    v_id := v_day ->> 'id';
    if v_id !~ c_id_re or v_id = any (v_day_ids) then return 'bad day id'; end if;
    v_day_ids := v_day_ids || v_id;
    if not private.plan_name_ok(v_day -> 'name') then return 'bad day name'; end if;
    if jsonb_typeof(v_day -> 'exercises') <> 'array' then return 'bad day'; end if;
    if jsonb_array_length(v_day -> 'exercises') > 30 then return 'too many exercises'; end if;

    v_ex_ids := '{}';
    for v_ex in select value from jsonb_array_elements(v_day -> 'exercises') loop
      if jsonb_typeof(v_ex) <> 'object'
         or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_ex) k)
            is distinct from array['id', 'name', 'reps', 'rest', 'sets', 'step', 'superset'] then
        return 'bad exercise';
      end if;
      if jsonb_typeof(v_ex -> 'id') <> 'string' then return 'bad exercise id'; end if;
      v_id := v_ex ->> 'id';
      if v_id !~ c_id_re or v_id = any (v_ex_ids) then return 'bad exercise id'; end if;
      v_ex_ids := v_ex_ids || v_id;
      if not private.plan_name_ok(v_ex -> 'name') then return 'bad exercise name'; end if;
      if not private.plan_int_ok(v_ex -> 'sets', 1, 10) then return 'sets out of range'; end if;
      if not private.plan_int_ok(v_ex -> 'reps', 1, 100) then return 'reps out of range'; end if;
      if not private.plan_int_ok(v_ex -> 'rest', 0, 600) then return 'rest out of range'; end if;
      if jsonb_typeof(v_ex -> 'step') <> 'number'
         or (v_ex ->> 'step')::numeric <= 0 or (v_ex ->> 'step')::numeric > 50 then
        return 'step out of range';
      end if;
      if jsonb_typeof(v_ex -> 'superset') <> 'boolean' then return 'bad superset'; end if;
    end loop;
  end loop;
  return null;
end;
$$;

-- The plan without its targets: days and exercises (ids, names, order,
-- supersets). Two plans with the same structure differ only in targets.
create function private.plan_structure(p_body jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', d.value -> 'id',
      'name', d.value -> 'name',
      'exercises', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', e.value -> 'id',
            'name', e.value -> 'name',
            'superset', e.value -> 'superset'
          ) order by e.ord
        ), '[]'::jsonb)
        from jsonb_array_elements(d.value -> 'exercises') with ordinality as e (value, ord)
      )
    ) order by d.ord
  ), '[]'::jsonb)
  from jsonb_array_elements(p_body -> 'days') with ordinality as d (value, ord)
$$;

revoke all on function private.plan_name_ok(jsonb), private.plan_int_ok(jsonb, int, int),
  private.plan_problem(jsonb), private.plan_structure(jsonb) from public, anon;
grant execute on function private.plan_name_ok(jsonb), private.plan_int_ok(jsonb, int, int),
  private.plan_problem(jsonb), private.plan_structure(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- save_plan(membership, base_version, body) -> {version, updated_by, updated_at}
--   * a manager of the gym always succeeds (the captain wins) and may
--     ignore base_version; a captain only for trainees, an owner for anyone;
--   * the member themself needs an active membership and the right flag:
--       no plan yet            -> can_build_own_plan (base_version 0)
--       only targets changed   -> can_edit_targets
--       days / exercises added, renamed, removed or reordered -> can_edit_plan
--     and base_version must equal the stored version, else `plan_changed`.
-- Errors: forbidden (42501), invalid_plan: <why> (22023), plan_changed (P0001).
-- Not enforced here: that a day or exercise id is never reused after a
-- removal (the app creates fresh ids; the server keeps no id history).
-- ---------------------------------------------------------------------------
create function public.save_plan(p_membership_id uuid, p_base_version int, p_body jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.memberships;
  v_actor public.memberships;
  v_person uuid := private.current_person_id();
  v_problem text;
  v_plan public.plans;
  v_manager boolean;
  v_new_version int;
begin
  if v_person is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_m from public.memberships where id = p_membership_id for update;
  if not found then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_manager := private.i_manage_role(v_m.gym_id, v_m.role);
  if not v_manager
     and not (v_m.person_id = v_person and v_m.status = 'active' and v_m.role = 'trainee') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  -- A gym that was deleted accepts no more plan changes from anyone.
  if not exists (select 1 from public.gyms where id = v_m.gym_id and deleted_at is null) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_problem := private.plan_problem(p_body);
  if v_problem is not null then
    raise exception 'invalid_plan: %', v_problem using errcode = '22023';
  end if;

  select * into v_plan from public.plans where membership_id = v_m.id for update;

  if not v_manager then
    if not found then
      if not v_m.can_build_own_plan or coalesce(p_base_version, 0) <> 0 then
        raise exception 'forbidden' using errcode = '42501';
      end if;
    else
      if p_base_version is distinct from v_plan.version then
        raise exception 'plan_changed' using errcode = 'P0001';
      end if;
      if v_plan.body = p_body then
        return jsonb_build_object(
          'version', v_plan.version, 'updated_by', v_plan.updated_by, 'updated_at', v_plan.updated_at
        );
      end if;
      if private.plan_structure(v_plan.body) is distinct from private.plan_structure(p_body) then
        if not v_m.can_edit_plan then
          raise exception 'forbidden' using errcode = '42501';
        end if;
      elsif not v_m.can_edit_targets then
        raise exception 'forbidden' using errcode = '42501';
      end if;
    end if;
    v_actor := v_m;
  else
    -- The manager's own membership in this gym stamps updated_by.
    select * into v_actor
      from public.memberships
     where gym_id = v_m.gym_id and person_id = v_person and status = 'active';
  end if;

  if v_plan.id is null then
    insert into public.plans (membership_id, body, version, updated_by)
    values (v_m.id, p_body, 1, v_actor.id)
    on conflict (membership_id) do nothing
    returning * into v_plan;
    if v_plan.id is null then
      raise exception 'plan_changed' using errcode = 'P0001';
    end if;
  else
    v_new_version := v_plan.version + 1;
    update public.plans
       set body = p_body, version = v_new_version,
           updated_by = v_actor.id, updated_at = now()
     where id = v_plan.id
    returning * into v_plan;
  end if;

  return jsonb_build_object(
    'version', v_plan.version, 'updated_by', v_plan.updated_by, 'updated_at', v_plan.updated_at
  );
end;
$$;

revoke all on function public.save_plan(uuid, int, jsonb) from public, anon;
grant execute on function public.save_plan(uuid, int, jsonb) to authenticated;
