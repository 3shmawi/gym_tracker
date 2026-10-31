-- ensure_trial_plan(): new users get the default plan once (pgTAP).
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (id, email) values
  ('44444444-4444-4444-4444-444444444444', null);

select is(
  (select count(*)::int from public.plan_days
   where plan_id = (select id from public.plans where is_default)),
  5,
  'the default plan has 5 days'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","is_anonymous":true}', true);

select is(
  public.ensure_trial_plan(),
  '00000000-0000-0000-0000-0000000000a1'::uuid,
  'a new (anonymous) user gets the default plan'
);

select is(
  public.ensure_trial_plan(),
  '00000000-0000-0000-0000-0000000000a1'::uuid,
  'calling it again keeps the same plan'
);

select is(
  (select count(*)::int from public.plan_assignments),
  1,
  'only one assignment is created'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$ select public.ensure_trial_plan() $$,
  '42501', null,
  'anon cannot get a plan'
);

select * from finish();
rollback;
