-- The optional exercise "unit" in plan JSON (migration 0016), pgTAP.
-- Run: supabase test db   (docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

create temp table ex (label text, ex jsonb);
insert into ex values
  ('base', '{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 3, "reps": 12, "rest": 90, "step": 2.5, "superset": false}');

create function pg_temp.plan_with(p_ex jsonb) returns jsonb language sql as $$
  select jsonb_build_object('days', jsonb_build_array(jsonb_build_object(
    'id', 'd1', 'name', '{"ar": "Push", "en": "Push"}'::jsonb,
    'exercises', jsonb_build_array(p_ex))));
$$;

-- Still valid: plans written by the published app (no unit).
select is(private.plan_problem(pg_temp.plan_with((select ex from ex))), null,
  'a plan without unit is still valid (backward compatible)');

-- The three units.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "kg"}' from ex))), null, 'unit kg');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "plate"}' from ex))), null, 'unit plate');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "reps"}' from ex))), null, 'unit reps');

-- Anything else is refused.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "lb"}' from ex))), 'bad unit', 'unknown unit');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "KG"}' from ex))), 'bad unit', 'case matters');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": ""}' from ex))), 'bad unit', 'empty unit');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": 1}' from ex))), 'bad unit', 'a number');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": null}' from ex))), 'bad unit', 'null');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "kg''; drop table plans; --"}' from ex))), 'bad unit', 'injection-like text');

-- Other unknown keys are still refused; required keys still required.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"color": "red"}' from ex))), 'bad exercise', 'another new key is refused');
select is(private.plan_problem(pg_temp.plan_with((select (ex - 'step') || '{"unit": "plate"}' from ex))), 'bad exercise', 'unit does not replace a required key');

select * from finish();
rollback;
