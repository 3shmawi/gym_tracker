import { gymWeek, startOfWeek } from '../../src/progress/weeks';
import type { FakeProgress } from './supabase';

// Ahmed's progress for the D5 tests: weeks, workouts and weights relative to
// today, so the "last 12 weeks" always contain them.
const now = new Date();
const thisWeek = gymWeek(now);
const day = (daysAgo: number) => new Date(now.getTime() - daysAgo * 86_400_000).toISOString();

export function ahmedProgress(): FakeProgress {
  return {
    summary: { level: 'intermediate', best_level: 'intermediate', streak_weeks: 5, comeback: false, weeks_to_next: 6, workouts_total: 38, first_workout_at: day(80), last_workout_at: day(1) },
    weeks: [
      { week_start: startOfWeek(thisWeek - 1), workouts: 4, training_days: 4, sets_done: 72, planned_sets: 80, minutes: 230, active_week: true },
      { week_start: startOfWeek(thisWeek - 2), workouts: 2, training_days: 2, sets_done: 30, planned_sets: null, minutes: null, active_week: false },
    ],
    sessions: [
      { session_id: 'c0000000-0000-4000-8000-000000000001', day_id: 'day-1', finished_at: day(1), duration_seconds: 3120, sets_done: 18, sets_logged: 20, planned_sets: 21, skipped_exercise_ids: ['abs'] },
      { session_id: 'c0000000-0000-4000-8000-000000000002', day_id: 'day-gone', finished_at: day(9), duration_seconds: null, sets_done: 12, sets_logged: 12, planned_sets: null, skipped_exercise_ids: null },
    ],
    points: [
      { session_id: 'c0000000-0000-4000-8000-000000000003', exercise_id: 'flat_db_press', finished_at: day(20), top_weight: 20, reps_at_top: 12, is_record: false },
      { session_id: 'c0000000-0000-4000-8000-000000000002', exercise_id: 'flat_db_press', finished_at: day(9), top_weight: 22.5, reps_at_top: 10, is_record: true },
      { session_id: 'c0000000-0000-4000-8000-000000000001', exercise_id: 'flat_db_press', finished_at: day(1), top_weight: 22.5, reps_at_top: 12, is_record: false },
    ],
  };
}
