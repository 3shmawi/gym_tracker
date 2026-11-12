import type { SupabaseClient } from '@supabase/supabase-js';
import { failed, guard, unwrap, type Result } from '../core/result';
import { isGymId } from '../gyms/gyms';
import { gymWeek, startOfWeek, weekOfStart } from './weeks';

// A member's progress (D5), read from the four security_invoker views of
// migration 0012 (docs/features/trainee_dashboard_data.md). They run as the
// reader, so RLS decides: an owner sees everyone, a captain trainees only,
// only while the membership is active; never solo workouts, never another gym.
// Nothing is written. Rows outside the rules are dropped, never shown.

export type Level = 'beginner' | 'intermediate' | 'pro';

export interface Summary {
  readonly level: Level;
  readonly bestLevel: Level;
  readonly streakWeeks: number;
  readonly comeback: boolean;
  /** null at the top level. */
  readonly weeksToNext: number | null;
  readonly workoutsTotal: number;
  readonly firstWorkoutAt: Date | null;
  readonly lastWorkoutAt: Date | null;
}

export interface Week {
  readonly week: number;
  readonly workouts: number;
  readonly trainingDays: number;
  readonly setsDone: number;
  /** null when no workout of that week matched a day of the current plan. */
  readonly plannedSets: number | null;
  /** null when no workout of the week has a start time (older app versions). */
  readonly minutes: number | null;
  readonly activeWeek: boolean;
}

export interface Workout {
  readonly id: string;
  readonly dayId: string | null;
  readonly finishedAt: Date;
  /** null for workouts saved before the app sent a start time. */
  readonly durationSeconds: number | null;
  readonly setsDone: number;
  readonly setsLogged: number;
  readonly plannedSets: number | null;
  readonly skippedExerciseIds: readonly string[] | null;
}

export interface ExercisePoint {
  readonly sessionId: string;
  readonly exerciseId: string;
  readonly finishedAt: Date;
  readonly topWeight: number;
  readonly repsAtTop: number;
  readonly isRecord: boolean;
}

export interface Progress {
  /** null: no row (not active, or not visible to this person). */
  readonly summary: Summary | null;
  readonly weeks: readonly Week[];
  readonly workouts: readonly Workout[];
  readonly points: readonly ExercisePoint[];
}

export interface LastWorkout {
  readonly lastWorkoutAt: Date | null;
  readonly workoutsTotal: number;
}

export const WEEKS_SHOWN = 12;
export const WORKOUTS_SHOWN = 10;
const MAX_POINTS = 2000;
const LEVELS: readonly Level[] = ['beginner', 'intermediate', 'pro'];
const PLAN_ID = /^[A-Za-z0-9_-]{1,64}$/;

const int = (v: unknown): number | null => (typeof v === 'number' && Number.isInteger(v) ? v : null);
const nonNeg = (v: unknown): number | null => {
  const n = int(v);
  return n !== null && n >= 0 ? n : null;
};
const date = (v: unknown): Date | null => {
  if (typeof v !== 'string') return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
};
// numeric arrives as a JSON number, or as a string for very large values.
const decimal = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : typeof v === 'string' && /^\d{1,6}(\.\d{1,3})?$/.test(v) ? Number(v) : NaN;
  return Number.isFinite(n) && n >= 0 && n <= 10_000 ? n : null;
};
const level = (v: unknown): Level | null => (typeof v === 'string' && (LEVELS as readonly string[]).includes(v) ? (v as Level) : null);

export function toSummary(r: Record<string, unknown> | null): Summary | null {
  if (!r) return null;
  const lv = level(r.level);
  const best = level(r.best_level);
  const streak = nonNeg(r.streak_weeks);
  const total = nonNeg(r.workouts_total);
  if (!lv || !best || streak === null || total === null || typeof r.comeback !== 'boolean') return null;
  const next = r.weeks_to_next === null ? null : nonNeg(r.weeks_to_next);
  return { level: lv, bestLevel: best, streakWeeks: streak, comeback: r.comeback, weeksToNext: next, workoutsTotal: total, firstWorkoutAt: date(r.first_workout_at), lastWorkoutAt: date(r.last_workout_at) };
}

export function toWeek(r: Record<string, unknown>): Week | null {
  const week = typeof r.week_start === 'string' ? weekOfStart(r.week_start) : null;
  const workouts = nonNeg(r.workouts);
  const days = nonNeg(r.training_days);
  const done = nonNeg(r.sets_done);
  if (week === null || workouts === null || days === null || done === null || typeof r.active_week !== 'boolean') return null;
  return { week, workouts, trainingDays: days, setsDone: done, plannedSets: r.planned_sets === null ? null : nonNeg(r.planned_sets), minutes: r.minutes === null ? null : nonNeg(r.minutes), activeWeek: r.active_week };
}

export function toWorkout(r: Record<string, unknown>): Workout | null {
  const finishedAt = date(r.finished_at);
  const done = nonNeg(r.sets_done);
  const logged = nonNeg(r.sets_logged);
  if (typeof r.session_id !== 'string' || !finishedAt || done === null || logged === null) return null;
  const skipped = Array.isArray(r.skipped_exercise_ids) ? (r.skipped_exercise_ids as unknown[]).filter((x): x is string => typeof x === 'string' && PLAN_ID.test(x)) : null;
  const duration = r.duration_seconds === null ? null : nonNeg(r.duration_seconds);
  return {
    id: r.session_id,
    dayId: typeof r.day_id === 'string' && PLAN_ID.test(r.day_id) ? r.day_id : null,
    finishedAt,
    durationSeconds: duration !== null && duration <= 86_400 ? duration : null,
    setsDone: done,
    setsLogged: logged,
    plannedSets: r.planned_sets === null ? null : nonNeg(r.planned_sets),
    skippedExerciseIds: skipped,
  };
}

export function toPoint(r: Record<string, unknown>): ExercisePoint | null {
  const finishedAt = date(r.finished_at);
  const weight = decimal(r.top_weight);
  const reps = nonNeg(r.reps_at_top);
  if (typeof r.session_id !== 'string' || typeof r.exercise_id !== 'string' || !PLAN_ID.test(r.exercise_id) || !finishedAt || weight === null || reps === null) return null;
  return { sessionId: r.session_id, exerciseId: r.exercise_id, finishedAt, topWeight: weight, repsAtTop: reps, isRecord: r.is_record === true };
}

const rows = <T>(list: unknown, map: (r: Record<string, unknown>) => T | null): T[] =>
  (Array.isArray(list) ? list : []).flatMap((r) => {
    const v = typeof r === 'object' && r !== null ? map(r as Record<string, unknown>) : null;
    return v === null ? [] : [v];
  });

/**
 * The last `count` weeks ending with this week, oldest first; weeks without
 * a workout are there with zeros (the view only has weeks with workouts).
 */
export function fillWeeks(weeks: readonly Week[], now: Date, count = WEEKS_SHOWN): Week[] {
  const last = gymWeek(now);
  const byWeek = new Map(weeks.map((w) => [w.week, w]));
  return Array.from({ length: count }, (_, i) => {
    const week = last - count + 1 + i;
    return byWeek.get(week) ?? { week, workouts: 0, trainingDays: 0, setsDone: 0, plannedSets: null, minutes: null, activeWeek: false };
  });
}

/** Workouts per week since the first one (this week included), for "x a week". */
export function perWeek(summary: Summary, now: Date): number | null {
  if (!summary.firstWorkoutAt || summary.workoutsTotal === 0) return null;
  const weeks = Math.max(1, gymWeek(now) - gymWeek(summary.firstWorkoutAt) + 1);
  return Math.round((summary.workoutsTotal / weeks) * 10) / 10;
}

/** Each exercise's points, oldest first, keyed by exercise id; most recent exercise first. */
export function byExercise(points: readonly ExercisePoint[]): Map<string, ExercisePoint[]> {
  const out = new Map<string, ExercisePoint[]>();
  for (const p of [...points].sort((a, b) => a.finishedAt.getTime() - b.finishedAt.getTime())) {
    const list = out.get(p.exerciseId) ?? [];
    list.push(p);
    out.set(p.exerciseId, list);
  }
  return new Map([...out.entries()].sort((a, b) => (b[1].at(-1)?.finishedAt.getTime() ?? 0) - (a[1].at(-1)?.finishedAt.getTime() ?? 0)));
}

export { startOfWeek };

export class ProgressRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async load(membershipId: string, now: Date = new Date()): Promise<Result<Progress>> {
    if (!isGymId(membershipId)) return failed({ kind: 'not_found' });
    const since = startOfWeek(gymWeek(now) - WEEKS_SHOWN + 1);
    return guard(async () => {
      const [summary, weeks, workouts, points] = await Promise.all([
        this.supabase
          .from('member_progress_summary')
          .select('level, best_level, streak_weeks, comeback, weeks_to_next, workouts_total, first_workout_at, last_workout_at')
          .eq('membership_id', membershipId)
          .maybeSingle<Record<string, unknown>>(),
        this.supabase
          .from('member_weekly_attendance')
          .select('week_start, workouts, training_days, sets_done, planned_sets, minutes, active_week')
          .eq('membership_id', membershipId)
          .gte('week_start', since)
          .order('week_start')
          .limit(WEEKS_SHOWN + 2),
        this.supabase
          .from('member_session_stats')
          .select('session_id, day_id, finished_at, duration_seconds, sets_done, sets_logged, planned_sets, skipped_exercise_ids')
          .eq('membership_id', membershipId)
          .order('finished_at', { ascending: false })
          .limit(WORKOUTS_SHOWN),
        this.supabase
          .from('member_exercise_progress')
          .select('session_id, exercise_id, finished_at, top_weight, reps_at_top, is_record')
          .eq('membership_id', membershipId)
          .order('finished_at')
          .limit(MAX_POINTS),
      ]);
      return {
        summary: toSummary(unwrap(summary)),
        weeks: rows(unwrap(weeks), toWeek),
        workouts: rows(unwrap(workouts), toWorkout),
        points: rows(unwrap(points), toPoint),
      };
    });
  }

  /** Last workout of every member this person may see (the members list). */
  async lastWorkouts(gymId: string): Promise<Result<ReadonlyMap<string, LastWorkout>>> {
    if (!isGymId(gymId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const list = unwrap(await this.supabase.from('member_progress_summary').select('membership_id, workouts_total, last_workout_at').eq('gym_id', gymId).limit(2000));
      const out = new Map<string, LastWorkout>();
      for (const r of (list ?? []) as Record<string, unknown>[]) {
        const total = nonNeg(r.workouts_total);
        if (typeof r.membership_id === 'string' && isGymId(r.membership_id) && total !== null) out.set(r.membership_id, { lastWorkoutAt: date(r.last_workout_at), workoutsTotal: total });
      }
      return out;
    });
  }
}
