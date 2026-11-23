-- The optional exercise "top" (rep range) in plan JSON (migration 0024), pgTAP.
-- Spec: docs/designs/rep_ranges.md. Run: supabase test db   (docs/security.md)
begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

create temp table ex (label text, ex jsonb);
insert into ex values
  ('base', '{"id": "e1", "name": {"ar": "Bench", "en": "Bench"}, "sets": 2, "reps": 6, "rest": 90, "step": 2.5, "superset": false}');

create function pg_temp.plan_with(p_ex jsonb) returns jsonb language sql as $$
  select jsonb_build_object('days', jsonb_build_array(jsonb_build_object(
    'id', 'd1', 'name', '{"ar": "Push", "en": "Push"}'::jsonb,
    'exercises', jsonb_build_array(p_ex))));
$$;

-- Still valid: plans written before 0024 (no top).
select is(private.plan_problem(pg_temp.plan_with((select ex from ex))), null,
  'a plan without top is still valid (backward compatible)');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"unit": "plate"}' from ex))), null,
  'unit alone still valid');

-- Valid ranges.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 10}' from ex))), null, 'range 6-10');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 6}' from ex))), null, 'top equal to reps');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 100}' from ex))), null, 'top 100');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 12, "unit": "reps"}' from ex))), null,
  'a range with a unit');

-- Out of range or the wrong type.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 5}' from ex))), 'top out of range', 'top below reps');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 101}' from ex))), 'top out of range', 'top above 100');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": 8.5}' from ex))), 'top out of range', 'a fraction');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": "8"}' from ex))), 'top out of range', 'a string');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": true}' from ex))), 'top out of range', 'a boolean');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": null}' from ex))), 'top out of range', 'null');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"top": "10; drop table plans; --"}' from ex))),
  'top out of range', 'injection-like text');

-- Reps is still checked first; other keys still refused.
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"reps": 0, "top": 10}' from ex))),
  'reps out of range', 'a bad bottom is reported as reps');
select is(private.plan_problem(pg_temp.plan_with((select ex || '{"failure": true, "top": 10}' from ex))),
  'bad exercise', 'another new key is refused');
select is(private.plan_problem(pg_temp.plan_with((select (ex - 'reps') || '{"top": 10}' from ex))),
  'bad exercise', 'top does not replace reps');

select * from finish();
rollback;
