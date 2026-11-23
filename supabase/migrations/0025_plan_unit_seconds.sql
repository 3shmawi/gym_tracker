-- 0025: an exercise may be logged in seconds, a hold such as a plank
-- (spec: docs/designs/plank_hold.md).
--
-- Plan JSON gains one value for the optional "unit" key (0016):
--   "unit": "kg" | "plate" | "reps" | "seconds"   (missing = "kg")
-- A seconds set is stored like a reps-only set: weight 0, "reps" = seconds.
-- Sessions need nothing: a set's reps are already 0-1000 (0009).
--
-- Backward compatible: every plan valid before stays valid. Only
-- private.plan_problem changes (same signature, same callers: save_plan,
-- import_solo_data, personal backups 0022, the plan_templates CHECK 0019).
-- No table, grant or policy changes. Tests: plan_unit_seconds.test.sql.

create or replace function private.plan_problem(p_body jsonb)
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
      -- 'unit' (0016) and 'top' (0024) are optional; every other key is
      -- required, nothing else.
      if jsonb_typeof(v_ex) <> 'object'
         or (select array_agg(k order by k collate "C") from jsonb_object_keys(v_ex) k
             where k not in ('unit', 'top'))
            is distinct from array['id', 'name', 'reps', 'rest', 'sets', 'step', 'superset'] then
        return 'bad exercise';
      end if;
      if v_ex ? 'unit'
         and (jsonb_typeof(v_ex -> 'unit') <> 'string'
              or v_ex ->> 'unit' not in ('kg', 'plate', 'reps', 'seconds')) then
        return 'bad unit';
      end if;
      if jsonb_typeof(v_ex -> 'id') <> 'string' then return 'bad exercise id'; end if;
      v_id := v_ex ->> 'id';
      if v_id !~ c_id_re or v_id = any (v_ex_ids) then return 'bad exercise id'; end if;
      v_ex_ids := v_ex_ids || v_id;
      if not private.plan_name_ok(v_ex -> 'name') then return 'bad exercise name'; end if;
      if not private.plan_int_ok(v_ex -> 'sets', 1, 10) then return 'sets out of range'; end if;
      if not private.plan_int_ok(v_ex -> 'reps', 1, 100) then return 'reps out of range'; end if;
      -- A rep range (0024): 'reps' is its bottom, 'top' its top (reps..100).
      -- Checked after 'reps', so 'reps' is a valid integer here.
      if v_ex ? 'top'
         and not private.plan_int_ok(v_ex -> 'top', (v_ex ->> 'reps')::numeric::int, 100) then
        return 'top out of range';
      end if;
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
