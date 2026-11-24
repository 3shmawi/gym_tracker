-- The "seconds" unit (a hold such as a plank) in plan JSON (migration 0025), pgTAP.
-- Spec: docs/designs/plank_hold.md. Run: supabase test db   (docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

create temp table ex (label text, ex jsonb);
insert into ex values
  ('base', '{"id": "plank", "name": {"ar": "بلانك", "en": "Plank"}, "sets": 3, "reps": 30, "rest": 60, "step": 2.5, "superset": false}');

create function pg_temp.plan_with(p_ex jsonb) returns jsonb language sql as $$
  select jsonb_build_object('days', jsonb_build_array(jsonb_build_object(
    'id', 'd1', 'name', '{"ar": "Core", "en": "Core"}'::jsonb,
    'exercises', jsonb_build_array(p_ex))));
$$;

select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "seconds"}' from ex))), null, 'unit seconds');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "seconds", "top": 60}' from ex))), null,
  'seconds with a range');

-- The units from before still work; no unit is still kg.
select is(private.plan_problem(pg_temp.plan_with((select ex from ex))), null, 'no unit');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "reps"}' from ex))), null, 'unit reps');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "plate"}' from ex))), null, 'unit plate');

-- Anything else is refused.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "SECONDS"}' from ex))), 'bad unit', 'case matters');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "sec"}' from ex))), 'bad unit', 'abbreviation');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": 1}' from ex))), 'bad unit', 'a number');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "seconds; drop table plans; --"}' from ex))),
  'bad unit', 'injection-like text');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "seconds", "reps": 101}' from ex))),
  'reps out of range', 'the seconds target keeps the reps limit');

select * from finish();
rollback;
