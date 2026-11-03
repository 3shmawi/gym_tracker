-- Gym accounts, part 6: what the captain's dashboard will read, per trainee
-- (docs/decisions/gym_accounts.md §8; docs/features/trainee_dashboard_data.md).
--
-- No new tables: everything is a view over `workout_sessions` (+ the plan in
-- `plans`), so there is one copy of the data and one set of Row Level Security
-- rules. The views are `security_invoker`: they run as the person asking, so
-- the policies of `workout_sessions`, `plans` and `memberships` decide what a
-- row is visible to whom:
--   * the trainee reads their own gym rows;
--   * the gym's owner reads everyone's, a captain only trainees', and only
--     while that membership is active;
--   * never solo sessions (`gym_id is null` is filtered out here and by the
--     policies), never another gym, never an ended member, never `anon`.
--
-- Only one thing is new on the phone: `started_at` (the workout's start, which
-- the app already knows) so duration can be computed. Rest overruns are NOT
-- stored: the app does not time a rest against the next set yet.

-- ---------------------------------------------------------------------------
-- started_at
-- ---------------------------------------------------------------------------
alter table public.workout_sessions add column started_at timestamptz;
alter table public.workout_sessions
  add constraint workout_sessions_started_sane
  check (started_at is null
         or (started_at <= finished_at and finished_at - started_at <= interval '24 hours'));
-- Set when the workout is logged, like the other content of the session.
grant insert (started_at) on table public.workout_sessions to authenticated;
grant update (started_at) on table public.workout_sessions to authenticated;

-- ---------------------------------------------------------------------------
-- The gym week: Saturday to Friday in Egypt, numbered from Saturday 2000-01-01
-- exactly like the app (`GetLevel._week`).
-- ---------------------------------------------------------------------------
create function private.gym_week(p_at timestamptz)
returns int
language sql
stable
set search_path = ''
as $$
  select (((p_at at time zone 'Africa/Cairo')::date - date '2000-01-01') / 7)::int
$$;

create function private.gym_week_start(p_at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select date '2000-01-01' + 7 * private.gym_week(p_at)
$$;

-- ---------------------------------------------------------------------------
-- Level and streak: a copy of the app's `GetLevel` (lib/features/workout/
-- domain/usecases/get_level.dart), over this membership's gym workouts.
--   active week = at least 3 workouts; 4 active weeks in a row make a
--   beginner intermediate, 8 more make a pro; the first week of a break
--   (a finished week that is not active) drops one level; climbing back to a
--   level reached before takes half the weeks, rounded up; the week in
--   progress never counts as a break. Keep the two in step: the pgTAP file
--   checks the same cases as `get_level_test.dart`.
-- Runs as the caller, so it only counts sessions the caller may read.
-- ---------------------------------------------------------------------------
create function private.level_weeks(p_level int, p_comeback boolean)
returns int
language sql
immutable
set search_path = ''
as $$
  select case when p_comeback then ceil(f / 2.0)::int else f end
  from (select case p_level when 1 then 4 when 2 then 8 else 0 end as f) t
$$;

create function private.member_level(p_membership_id uuid, p_now timestamptz default now())
returns table (level text, best_level text, streak_weeks int, comeback boolean, weeks_to_next int)
language plpgsql
stable
set search_path = ''
as $$
declare
  c_names constant text[] := array['beginner', 'intermediate', 'pro'];
  v_this int := private.gym_week(p_now);
  v_per jsonb;
  v_first int;
  w int;
  v_level int := 0;
  v_best int := 0;
  v_climb int := 0;
  v_streak int := 0;
  v_break boolean := false;
  v_next int;
begin
  select coalesce(jsonb_object_agg(wk::text, n), '{}'::jsonb), min(wk)
    into v_per, v_first
  from (
    select private.gym_week(s.finished_at) as wk, count(*)::int as n
    from public.workout_sessions s
    where s.membership_id = p_membership_id and s.gym_id is not null
    group by 1
  ) t;

  if v_first is not null then
    for w in v_first..v_this loop
      if coalesce((v_per ->> w::text)::int, 0) >= 3 then
        v_break := false;
        v_streak := v_streak + 1;
        v_climb := v_climb + 1;
        v_next := v_level + 1;
        if v_next <= 2 and v_climb >= private.level_weeks(v_next, v_next <= v_best) then
          v_level := v_next;
          v_climb := 0;
          if v_level > v_best then v_best := v_level; end if;
        end if;
      elsif w < v_this then
        if not v_break then v_level := greatest(0, v_level - 1); end if;
        v_break := true;
        v_streak := 0;
        v_climb := 0;
      end if;
    end loop;
  end if;

  v_next := v_level + 1;
  level := c_names[v_level + 1];
  best_level := c_names[v_best + 1];
  streak_weeks := v_streak;
  comeback := v_next <= 2 and v_next <= v_best;
  weeks_to_next := case when v_next > 2 then null
    else greatest(1, private.level_weeks(v_next, comeback) - v_climb) end;
  return next;
end;
$$;

revoke all on function private.gym_week(timestamptz), private.gym_week_start(timestamptz),
  private.level_weeks(int, boolean), private.member_level(uuid, timestamptz) from public, anon;
grant execute on function private.gym_week(timestamptz), private.gym_week_start(timestamptz),
  private.level_weeks(int, boolean), private.member_level(uuid, timestamptz)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- member_session_stats: one row per gym workout.
--   sets_done      sets with at least one rep (reps 0 = skipped set)
--   planned_*      from the member's plan AS IT IS NOW for that day (the plan
--                  keeps no history, so an older workout is compared with the
--                  current day); null when the day is no longer in the plan
--   skipped_exercise_ids  planned exercises with no set done
--   duration_seconds      null for workouts without a start time
-- ---------------------------------------------------------------------------
create view public.member_session_stats
with (security_invoker = true) as
select
  s.id as session_id,
  s.gym_id,
  s.membership_id,
  s.day_id,
  s.finished_at,
  private.gym_week_start(s.finished_at) as week_start,
  s.started_at,
  case when s.started_at is null then null
       else extract(epoch from s.finished_at - s.started_at)::int end as duration_seconds,
  a.sets_done,
  a.sets_logged,
  coalesce(cardinality(a.done_ids), 0) as exercises_done,
  pl.planned_sets,
  pl.planned_exercises,
  case when pl.planned_exercises is null then null
       else cardinality(pl.skipped_ids) end as skipped_exercises,
  pl.skipped_ids as skipped_exercise_ids
from public.workout_sessions s
cross join lateral (
  select
    (count(*) filter (where (e.value ->> 'reps')::int > 0))::int as sets_done,
    count(*)::int as sets_logged,
    coalesce(array_agg(distinct e.value ->> 'exercise')
             filter (where (e.value ->> 'reps')::int > 0), '{}'::text[]) as done_ids
  from jsonb_array_elements(s.sets) e
) a
left join lateral (
  select
    sum((x.value ->> 'sets')::int)::int as planned_sets,
    count(*)::int as planned_exercises,
    coalesce(array_agg(x.value ->> 'id')
             filter (where not ((x.value ->> 'id') = any (a.done_ids))), '{}'::text[]) as skipped_ids
  from public.plans p
  cross join lateral jsonb_array_elements(p.body -> 'days') d
  cross join lateral jsonb_array_elements(d.value -> 'exercises') x
  where p.membership_id = s.membership_id and d.value ->> 'id' = s.day_id
  having count(*) > 0
) pl on true
where s.gym_id is not null and s.membership_id is not null;

-- ---------------------------------------------------------------------------
-- member_weekly_attendance: per member and gym week.
-- ---------------------------------------------------------------------------
create view public.member_weekly_attendance
with (security_invoker = true) as
select
  membership_id,
  gym_id,
  week_start,
  count(*)::int as workouts,
  count(distinct (finished_at at time zone 'Africa/Cairo')::date)::int as training_days,
  sum(sets_done)::int as sets_done,
  sum(planned_sets)::int as planned_sets,
  (sum(duration_seconds) / 60)::int as minutes,
  count(*) >= 3 as active_week
from public.member_session_stats
group by membership_id, gym_id, week_start;

-- ---------------------------------------------------------------------------
-- member_exercise_progress: per workout and exercise, the heaviest set, and
-- whether it beat everything before (first times are not records, like the
-- app). Ordered by finished_at it is the weight progress of an exercise.
-- ---------------------------------------------------------------------------
create view public.member_exercise_progress
with (security_invoker = true) as
with per as (
  select
    s.id as session_id,
    s.gym_id,
    s.membership_id,
    s.finished_at,
    e.value ->> 'exercise' as exercise_id,
    max((e.value ->> 'weight')::numeric) as top_weight,
    (array_agg((e.value ->> 'reps')::int
               order by (e.value ->> 'weight')::numeric desc, (e.value ->> 'reps')::int desc))[1]
      as reps_at_top,
    count(*)::int as sets_done
  from public.workout_sessions s
  cross join lateral jsonb_array_elements(s.sets) e
  where s.gym_id is not null and s.membership_id is not null
    and (e.value ->> 'reps')::int > 0
  group by s.id, s.gym_id, s.membership_id, s.finished_at, e.value ->> 'exercise'
)
select
  per.*,
  coalesce(
    top_weight > max(top_weight) over (
      partition by membership_id, exercise_id
      order by finished_at, session_id
      rows between unbounded preceding and 1 preceding),
    false) as is_record
from per;

-- ---------------------------------------------------------------------------
-- member_progress_summary: one row per visible active membership.
-- ---------------------------------------------------------------------------
create view public.member_progress_summary
with (security_invoker = true) as
select
  m.id as membership_id,
  m.gym_id,
  m.display_name,
  lv.level,
  lv.best_level,
  lv.streak_weeks,
  lv.comeback,
  lv.weeks_to_next,
  t.workouts_total,
  t.first_workout_at,
  t.last_workout_at
from public.memberships m
cross join lateral private.member_level(m.id) lv
cross join lateral (
  select count(*)::int as workouts_total,
         min(s.finished_at) as first_workout_at,
         max(s.finished_at) as last_workout_at
  from public.workout_sessions s
  where s.membership_id = m.id and s.gym_id is not null
) t
where m.status = 'active';

-- Signed-in people only; the policies underneath do the rest.
revoke all on table public.member_session_stats, public.member_weekly_attendance,
  public.member_exercise_progress, public.member_progress_summary from public, anon, authenticated;
grant select on table public.member_session_stats, public.member_weekly_attendance,
  public.member_exercise_progress, public.member_progress_summary to authenticated;
