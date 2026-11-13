import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-return */
import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import { parsePath } from '../src/app/router';
import { byExercise, fillWeeks, MOVE_DAY_ID, perWeek, ProgressRepository, toPoint, toSummary, toWeek, toWorkout, type Summary } from '../src/progress/progress';
import { dateLabel, gymWeek, num, startOfWeek, weekLabel, weekOfStart } from '../src/progress/weeks';

const M = 'a0000000-0000-4000-8000-000000000001';
const GYM = 'b0000000-0000-4000-8000-000000000001';
const S1 = 'c0000000-0000-4000-8000-000000000001';

describe('the gym week (like the app and private.gym_week)', () => {
  it('Saturday 1 Jan 2000 is week 0; weeks run Saturday to Friday in Cairo', () => {
    expect(gymWeek(new Date('2000-01-01T00:00:00+02:00'))).toBe(0);
    expect(gymWeek(new Date('2000-01-07T23:59:00+02:00'))).toBe(0);
    expect(gymWeek(new Date('2000-01-08T00:00:00+02:00'))).toBe(1);
    // Friday 23:30 UTC is already Saturday in Cairo: the next week.
    const fri = gymWeek(new Date('2026-11-06T21:30:00Z'));
    expect(gymWeek(new Date('2026-11-06T23:30:00Z'))).toBe(fri + 1);
    expect(startOfWeek(fri + 1)).toBe('2026-11-07');
    expect(new Date(`${startOfWeek(fri + 1)}T00:00:00Z`).getUTCDay()).toBe(6);
  });

  it('reads week_start back; anything that is not a Saturday is refused', () => {
    expect(weekOfStart('2026-11-07')).toBe(gymWeek(new Date('2026-11-07T12:00:00+02:00')));
    for (const bad of ['2026-11-08', 'x', '2026-13-01', "2026-11-07' or 1=1", '']) expect(weekOfStart(bad), bad).toBeNull();
  });

  it('labels use Western digits in both languages', () => {
    const w = weekOfStart('2026-11-07') ?? 0;
    expect(weekLabel('en', w)).toBe('Sat 7 Nov – Fri 13 Nov');
    const ar = weekLabel('ar', w);
    expect(ar).toMatch(/7/);
    expect(ar).toMatch(/13/);
    expect(ar).not.toMatch(/[٠-٩]/);
    expect(num('ar', 1234.56, 1)).toBe('1,234.6');
    expect(dateLabel('ar', new Date('2026-11-07T10:00:00Z'))).not.toMatch(/[٠-٩]/);
  });
});

describe('view rows (nulls included)', () => {
  it('member_progress_summary', () => {
    const row = { level: 'intermediate', best_level: 'pro', streak_weeks: 2, comeback: true, weeks_to_next: 3, workouts_total: 38, first_workout_at: '2026-09-01T10:00:00Z', last_workout_at: '2026-11-10T10:00:00Z' };
    expect(toSummary(row)).toMatchObject({ level: 'intermediate', bestLevel: 'pro', comeback: true, weeksToNext: 3, workoutsTotal: 38 });
    expect(toSummary({ ...row, weeks_to_next: null })?.weeksToNext).toBeNull();
    expect(toSummary({ ...row, first_workout_at: null, last_workout_at: null, workouts_total: 0 })).toMatchObject({ firstWorkoutAt: null, lastWorkoutAt: null, workoutsTotal: 0 });
    expect(toSummary({ ...row, level: 'god' })).toBeNull();
    expect(toSummary({ ...row, streak_weeks: -1 })).toBeNull();
    expect(toSummary({ ...row, comeback: 'yes' })).toBeNull();
    expect(toSummary(null)).toBeNull();
  });

  it('member_weekly_attendance: planned sets and minutes may be null', () => {
    const row = { week_start: '2026-11-07', workouts: 3, training_days: 3, sets_done: 54, planned_sets: 60, minutes: 150, active_week: true };
    expect(toWeek(row)).toMatchObject({ workouts: 3, plannedSets: 60, minutes: 150, activeWeek: true });
    expect(toWeek({ ...row, planned_sets: null, minutes: null })).toMatchObject({ plannedSets: null, minutes: null });
    expect(toWeek({ ...row, week_start: '2026-11-08' })).toBeNull();
    expect(toWeek({ ...row, workouts: 2.5 })).toBeNull();
  });

  it('member_session_stats: old workouts have no duration; a removed day has no plan', () => {
    const row = { session_id: S1, day_id: 'day-1', finished_at: '2026-11-10T10:00:00Z', duration_seconds: 3120, sets_done: 18, sets_logged: 20, planned_sets: 21, skipped_exercise_ids: ['abs', '<script>', 'x y'] };
    expect(toWorkout(row)).toMatchObject({ durationSeconds: 3120, setsDone: 18, plannedSets: 21, skippedExerciseIds: ['abs'] });
    expect(toWorkout({ ...row, duration_seconds: null, planned_sets: null, skipped_exercise_ids: null, day_id: '../x' })).toMatchObject({ durationSeconds: null, plannedSets: null, skippedExerciseIds: null, dayId: null });
    expect(toWorkout({ ...row, duration_seconds: 999_999 })?.durationSeconds).toBeNull();
    expect(toWorkout({ ...row, finished_at: 'nope' })).toBeNull();
  });

  it('member_exercise_progress: numeric weight as number or string', () => {
    const row = { session_id: S1, exercise_id: 'flat_db_press', finished_at: '2026-11-10T10:00:00Z', top_weight: 22.5, reps_at_top: 10, is_record: true };
    expect(toPoint(row)).toMatchObject({ topWeight: 22.5, isRecord: true });
    expect(toPoint({ ...row, top_weight: '22.50' })?.topWeight).toBe(22.5);
    expect(toPoint({ ...row, top_weight: 'NaN' })).toBeNull();
    expect(toPoint({ ...row, top_weight: -1 })).toBeNull();
    expect(toPoint({ ...row, exercise_id: '<img>' })).toBeNull();
    expect(toPoint({ ...row, is_record: 'true' })?.isRecord).toBe(false);
  });
});

describe('chart data', () => {
  const now = new Date('2026-11-11T10:00:00Z');
  it('fills the last 12 weeks, zero where no workout, oldest first', () => {
    const thisWeek = gymWeek(now);
    const weeks = fillWeeks([{ week: thisWeek - 1, workouts: 4, trainingDays: 4, setsDone: 60, plannedSets: null, minutes: null, activeWeek: true }], now);
    expect(weeks).toHaveLength(12);
    expect(weeks[0]?.week).toBe(thisWeek - 11);
    expect(weeks.at(-1)).toMatchObject({ week: thisWeek, workouts: 0 });
    expect(weeks.at(-2)?.workouts).toBe(4);
  });

  it('a week average since the first workout', () => {
    const s: Summary = { level: 'beginner', bestLevel: 'beginner', streakWeeks: 0, comeback: false, weeksToNext: 4, workoutsTotal: 10, firstWorkoutAt: new Date(now.getTime() - 27 * 86_400_000), lastWorkoutAt: now };
    expect(perWeek(s, now)).toBeCloseTo(10 / (gymWeek(now) - gymWeek(s.firstWorkoutAt ?? now) + 1), 1);
    expect(perWeek({ ...s, workoutsTotal: 0 }, now)).toBeNull();
  });

  it('groups exercise points oldest first, most recent exercise first', () => {
    const p = (ex: string, day: number, w: number) => ({ sessionId: `s${day}`, exerciseId: ex, finishedAt: new Date(Date.UTC(2026, 10, day)), topWeight: w, repsAtTop: 10, isRecord: false });
    const map = byExercise([p('a', 3, 20), p('b', 5, 40), p('a', 1, 18)]);
    expect([...map.keys()]).toEqual(['b', 'a']);
    expect(map.get('a')?.map((x) => x.topWeight)).toEqual([18, 20]);
  });
});

interface Call { table: string; columns?: string; filters: [string, string, unknown][] }
function fake(answer: (c: Call) => unknown) {
  const calls: Call[] = [];
  const builder = (call: Call): any => {
    const b: any = {
      select: (c: string) => ((call.columns = c), b),
      eq: (c: string, v: unknown) => (call.filters.push(['eq', c, v]), b),
      gte: (c: string, v: unknown) => (call.filters.push(['gte', c, v]), b),
      order: () => b,
      limit: () => b,
      maybeSingle: () => b,
      then: (resolve: (v: unknown) => void) => {
        calls.push(call);
        resolve({ data: answer(call), error: null });
      },
    };
    return b;
  };
  return { client: { from: (table: string) => builder({ table, filters: [] }) } as unknown as SupabaseClient, calls };
}

describe('ProgressRepository', () => {
  it('reads the four views for one membership with explicit columns', async () => {
    const { client, calls } = fake((c) => (c.table === 'member_progress_summary' ? null : []));
    const r = await new ProgressRepository(client).load(M, new Date('2026-11-11T10:00:00Z'));
    expect(r).toEqual({ ok: true, value: { summary: null, weeks: [], workouts: [], points: [] } });
    expect(calls.map((c) => c.table).sort()).toEqual(['member_exercise_progress', 'member_progress_summary', 'member_session_stats', 'member_weekly_attendance']);
    for (const c of calls) {
      expect(c.filters).toContainEqual(['eq', 'membership_id', M]);
      expect(c.columns).not.toContain('*');
    }
    expect(calls.find((c) => c.table === 'member_weekly_attendance')?.filters).toContainEqual(['gte', 'week_start', startOfWeek(gymWeek(new Date('2026-11-11T10:00:00Z')) - 11)]);
  });

  it('a crafted id never reaches the server', async () => {
    const { client, calls } = fake(() => []);
    expect((await new ProgressRepository(client).load("x' or 1=1")).ok).toBe(false);
    expect((await new ProgressRepository(client).lastWorkouts('../gyms')).ok).toBe(false);
    expect(calls).toHaveLength(0);
  });

  it('last workouts for the members list: valid rows only', async () => {
    const { client } = fake(() => [{ membership_id: M, workouts_total: 3, last_workout_at: '2026-11-10T10:00:00Z' }, { membership_id: 'x', workouts_total: 1 }]);
    const r = await new ProgressRepository(client).lastWorkouts(GYM);
    expect(r.ok && [...r.value.keys()]).toEqual([M]);
  });

  it('routes: the settings page needs a UUID gym id', () => {
    expect(parsePath(`/g/${GYM}/settings`)).toEqual({ name: 'settings', gymId: GYM });
    expect(parsePath('/g/x/settings').name).toBe('not_found');
  });
});

describe('Move games rounds', () => {
  it('use the same day id as the app', () => {
    const dart = readFileSync(resolve(process.cwd(), '../lib/features/workout/domain/entities/workout_session.dart'), 'utf8');
    expect(dart).toContain(`static const moveDayId = '${MOVE_DAY_ID}';`);
  });
});
