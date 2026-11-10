-- The 5-day template's days 4 and 5 (migration 0018), pgTAP.
-- Run: supabase test db   (docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

create temp table t (old4 jsonb, old5 jsonb, new4 jsonb, new5 jsonb, legs jsonb);
insert into t values (
  '[{"id":"flat_db_press","name":{"ar":"دفع دمبل مستوي","en":"Flat Dumbbell Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"wide_lat_pulldown","name":{"ar":"سحب عالي واسع","en":"Wide Lat Pulldown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"incline_machine_press","name":{"ar":"دفع جهاز عالي","en":"Incline Machine Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"close_grip_row","name":{"ar":"سحب أرضي ضيق","en":"Close-Grip Seated Row"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"pec_deck","name":{"ar":"فراشة","en":"Pec Deck"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"straight_arm_pulldown","name":{"ar":"مسطرة من فوق كابل","en":"Straight-Arm Cable Pulldown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"abs","name":{"ar":"بطن","en":"Abs"},"sets":3,"reps":15,"rest":90,"step":5.0,"superset":false}]', '[{"id":"db_shoulder_press","name":{"ar":"دفع دمبل جانبي كتف","en":"Dumbbell Shoulder Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"db_front_raise","name":{"ar":"رفرفة دمبل أمامي كتف","en":"Dumbbell Front Raise"},"sets":3,"reps":12,"rest":90,"step":1.0,"superset":false},{"id":"reverse_pec_deck","name":{"ar":"فراشة خلفي","en":"Reverse Pec Deck"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"db_shrug","name":{"ar":"ترباس دمبل","en":"Dumbbell Shrug"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"alternating_db_curl","name":{"ar":"تبادل دمبل باي","en":"Alternating Dumbbell Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"cable_kickback","name":{"ar":"رفس كابل تراي","en":"Cable Kickback"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"hammer_curl","name":{"ar":"شاكوش دمبل باي","en":"Hammer Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"rope_pushdown","name":{"ar":"حبل خلفي تراي","en":"Rope Pushdown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false}]', '[{"id":"incline_barbell_press","name":{"ar":"بار عالي","en":"Incline Barbell Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"lat_pulldown_machine","name":{"ar":"ظرافة","en":"Lat Pulldown Machine"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"flat_machine_press","name":{"ar":"دفع جهاز مستوي","en":"Flat Machine Chest Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"wide_t_bar_row","name":{"ar":"طرمبة واسع","en":"Wide-Grip T-Bar Row"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"high_cable_crossover","name":{"ar":"كابل تجميع من فوق","en":"High Cable Crossover"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"hammer_close_grip_row","name":{"ar":"جهاز همر ضيق","en":"Close-Grip Hammer Row"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"abs","name":{"ar":"بطن","en":"Abs"},"sets":3,"reps":15,"rest":90,"step":5.0,"superset":false}]', '[{"id":"machine_shoulder_press","name":{"ar":"دفع جهاز أمامي كتف","en":"Machine Shoulder Press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"db_lateral_raise","name":{"ar":"رفرفة دمبل جانبي كتف","en":"Dumbbell Lateral Raise"},"sets":3,"reps":12,"rest":90,"step":1.0,"superset":false},{"id":"face_pull","name":{"ar":"حبل على الوش","en":"Face Pull"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"smith_shrug","name":{"ar":"ترباس بار سميث","en":"Smith Machine Shrug"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"cable_bar_curl","name":{"ar":"مسطرة كابل من تحت باي","en":"Straight-Bar Cable Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"rope_pushdown","name":{"ar":"حبل خلفي تراي","en":"Rope Pushdown"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false},{"id":"preacher_curl","name":{"ar":"تكوير على جهاز الحصان","en":"Preacher Curl"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":true},{"id":"db_overhead_extension","name":{"ar":"دمبل زوجي تراي","en":"Two-Hand DB Overhead Extension"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false}]',
  '[{"id": "barbell_squat", "name": {"ar": "بار اسكوات حر", "en": "Barbell Back Squat"}, "sets": 3, "reps": 12, "rest": 120, "step": 5, "superset": false}]');

create function pg_temp.plan(p4 jsonb, p5 jsonb) returns jsonb language sql as $$
  select jsonb_build_object('days', jsonb_build_array(
    jsonb_build_object('id', 'day-1', 'name', '{"ar": "بنش وضهر", "en": "Chest & Back"}'::jsonb, 'exercises', (select old4 from t)),
    jsonb_build_object('id', 'day-2', 'name', '{"ar": "كتف ودراع", "en": "Shoulders & Arms"}'::jsonb, 'exercises', (select old5 from t)),
    jsonb_build_object('id', 'day-3', 'name', '{"ar": "رجل", "en": "Legs"}'::jsonb, 'exercises', (select legs from t)),
    jsonb_build_object('id', 'day-4', 'name', '{"ar": "بنش وضهر", "en": "Chest & Back"}'::jsonb, 'exercises', p4),
    jsonb_build_object('id', 'day-5', 'name', '{"ar": "كتف ودراع", "en": "Shoulders & Arms"}'::jsonb, 'exercises', p5)));
$$;

-- An untouched old plan gets the real days 4 and 5, and stays valid.
select is(
  private.template_days_upgrade(pg_temp.plan((select old4 from t), (select old5 from t))),
  pg_temp.plan((select new4 from t), (select new5 from t)),
  'old copies of days 1 and 2 become the real days 4 and 5');
select is(
  private.plan_problem(pg_temp.plan((select new4 from t), (select new5 from t))), null,
  'the upgraded plan passes the plan rules');
select is(
  private.template_days_upgrade(pg_temp.plan((select old4 from t), (select old5 from t))) -> 'days' -> 0,
  pg_temp.plan((select old4 from t), (select old5 from t)) -> 'days' -> 0,
  'day 1 is not touched');

-- Anything edited, or already right, is left alone.
select is(
  private.template_days_upgrade(pg_temp.plan((select old4 - 0 from t), (select old5 from t))),
  pg_temp.plan((select old4 - 0 from t), (select old5 from t)),
  'an edited day 4 is left alone');
select is(
  private.template_days_upgrade(pg_temp.plan((select old4 from t), (select jsonb_set(old5, '{0,sets}', '4') from t))),
  pg_temp.plan((select old4 from t), (select jsonb_set(old5, '{0,sets}', '4') from t)),
  'a changed target on day 5 is left alone');
select is(
  private.template_days_upgrade(pg_temp.plan((select new4 from t), (select new5 from t))),
  pg_temp.plan((select new4 from t), (select new5 from t)),
  'a plan already right is left alone');
select is(
  private.template_days_upgrade('{"days": [{"id": "d1", "name": {"ar": "ا", "en": "A"}, "exercises": []}]}'::jsonb),
  '{"days": [{"id": "d1", "name": {"ar": "ا", "en": "A"}, "exercises": []}]}'::jsonb,
  'a plan of its own (no day-4/day-5) is left alone');
select is(private.template_days_upgrade(null), null, 'null in, null out');

-- Clients cannot call it.
select ok(
  not has_function_privilege('authenticated', 'private.template_days_upgrade(jsonb)', 'execute'),
  'authenticated cannot run the helper');

select * from finish();
rollback;
