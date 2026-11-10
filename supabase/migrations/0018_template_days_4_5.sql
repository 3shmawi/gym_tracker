-- 0018: the 5-day template's real days 4 and 5 (owner's plan, 2026-11-10).
--
-- Until now the app's ready-made 5-day plan repeated day 1's exercises on
-- day 4 and day 2's on day 5. The server never had its own copy of the
-- template: it stored what the app sent (a gym plan in `plans`, the solo plan
-- moved into the account in `personal_plans`), so those rows carry the same
-- copies.
--
-- This rewrites day 4 and day 5 of a stored plan ONLY when both are still
-- exactly the old copies (same day ids, same exercises, never edited): the
-- same rule as the app (`PlanTemplates.upgrade`). Any plan a member or a
-- captain changed is left alone. Names, day ids and the other days stay, so
-- history and the waiting workout keep pointing at the same days.
--
-- The version goes up so phones fetch the new plan (the server's plan wins,
-- docs/decisions/gym_accounts.md §11). `updated_by` becomes null: nobody in
-- the gym made the change, so the member gets no "your captain updated your
-- plan" toast.
--
-- No table, grant or policy changes; the helper is private and not callable
-- by clients.

create function private.template_days_upgrade(p_body jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  c_old_day4 constant jsonb := '[{"id":"flat_db_press","name":{"ar":"دفع دمبل مستوي","en":"Flat Dumbbell Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"wide_lat_pulldown","name":{"ar":"سحب عالي واسع","en":"Wide Lat Pulldown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"incline_machine_press","name":{"ar":"دفع جهاز عالي","en":"Incline Machine Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"close_grip_row","name":{"ar":"سحب أرضي ضيق","en":"Close-Grip Seated Row"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"pec_deck","name":{"ar":"فراشة","en":"Pec Deck"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"straight_arm_pulldown","name":{"ar":"مسطرة من فوق كابل","en":"Straight-Arm Cable Pulldown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"abs","name":{"ar":"بطن","en":"Abs"},"sets":3,"reps":15,"rest":90,"step":5.0,"superset":false}]'::jsonb;
  c_old_day5 constant jsonb := '[{"id":"db_shoulder_press","name":{"ar":"دفع دمبل جانبي كتف","en":"Dumbbell Shoulder Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"db_front_raise","name":{"ar":"رفرفة دمبل أمامي كتف","en":"Dumbbell Front Raise"},"sets":3,"reps":12,"rest":90,"step":1.0,"superset":false},{"id":"reverse_pec_deck","name":{"ar":"فراشة خلفي","en":"Reverse Pec Deck"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"db_shrug","name":{"ar":"ترباس دمبل","en":"Dumbbell Shrug"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"alternating_db_curl","name":{"ar":"تبادل دمبل باي","en":"Alternating Dumbbell Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"cable_kickback","name":{"ar":"رفس كابل تراي","en":"Cable Kickback"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"hammer_curl","name":{"ar":"شاكوش دمبل باي","en":"Hammer Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"rope_pushdown","name":{"ar":"حبل خلفي تراي","en":"Rope Pushdown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false}]'::jsonb;
  c_new_day4 constant jsonb := '[{"id":"incline_barbell_press","name":{"ar":"بار عالي","en":"Incline Barbell Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"lat_pulldown_machine","name":{"ar":"ظرافة","en":"Lat Pulldown Machine"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"flat_machine_press","name":{"ar":"دفع جهاز مستوي","en":"Flat Machine Chest Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"wide_t_bar_row","name":{"ar":"طرمبة واسع","en":"Wide-Grip T-Bar Row"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"high_cable_crossover","name":{"ar":"كابل تجميع من فوق","en":"High Cable Crossover"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"hammer_close_grip_row","name":{"ar":"جهاز همر ضيق","en":"Close-Grip Hammer Row"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"abs","name":{"ar":"بطن","en":"Abs"},"sets":3,"reps":15,"rest":90,"step":5.0,"superset":false}]'::jsonb;
  c_new_day5 constant jsonb := '[{"id":"machine_shoulder_press","name":{"ar":"دفع جهاز أمامي كتف","en":"Machine Shoulder Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"db_lateral_raise","name":{"ar":"رفرفة دمبل جانبي كتف","en":"Dumbbell Lateral Raise"},"sets":3,"reps":12,"rest":90,"step":1.0,"superset":false},{"id":"face_pull","name":{"ar":"حبل على الوش","en":"Face Pull"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"smith_shrug","name":{"ar":"ترباس بار سميث","en":"Smith Machine Shrug"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"cable_bar_curl","name":{"ar":"مسطرة كابل من تحت باي","en":"Straight-Bar Cable Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"rope_pushdown","name":{"ar":"حبل خلفي تراي","en":"Rope Pushdown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"preacher_curl","name":{"ar":"تكوير على جهاز الحصان","en":"Preacher Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"db_overhead_extension","name":{"ar":"دمبل زوجي تراي","en":"Two-Hand DB Overhead Extension"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false}]'::jsonb;
  v_i4 int;
  v_i5 int;
begin
  if p_body is null or jsonb_typeof(p_body -> 'days') <> 'array' then
    return p_body;
  end if;
  select ord - 1 into v_i4
    from jsonb_array_elements(p_body -> 'days') with ordinality as t(day, ord)
    where day ->> 'id' = 'day-4' limit 1;
  select ord - 1 into v_i5
    from jsonb_array_elements(p_body -> 'days') with ordinality as t(day, ord)
    where day ->> 'id' = 'day-5' limit 1;
  if v_i4 is null or v_i5 is null then return p_body; end if;
  if p_body -> 'days' -> v_i4 -> 'exercises' is distinct from c_old_day4
     or p_body -> 'days' -> v_i5 -> 'exercises' is distinct from c_old_day5 then
    return p_body;
  end if;
  return jsonb_set(
    jsonb_set(p_body, array['days', v_i4::text, 'exercises'], c_new_day4),
    array['days', v_i5::text, 'exercises'], c_new_day5);
end;
$$;

revoke all on function private.template_days_upgrade(jsonb) from public, anon, authenticated;

update public.plans
   set body = private.template_days_upgrade(body),
       version = version + 1,
       updated_by = null,
       updated_at = now()
 where private.template_days_upgrade(body) is distinct from body;

update public.personal_plans
   set body = private.template_days_upgrade(body),
       version = version + 1,
       updated_at = now()
 where private.template_days_upgrade(body) is distinct from body;
