import { diffPlans, type Change, type TargetField } from './diff';
import { setSuperset, setTargets, type EditResult } from './edit';
import type { Plan, PlanExercise } from './model';

// How a member's plan differs from the template it was made from (board
// "Dashboard 6"), matched by day and exercise id, and the two edits built on
// that: Reset one exercise to the template, and carry one exercise's targets
// to another member's plan ("apply a change to everyone on this template").

const TARGETS: readonly TargetField[] = ['sets', 'reps', 'rest', 'step', 'unit', 'superset'];

export const exerciseKey = (dayId: string, exerciseId: string) => `${dayId}/${exerciseId}`;

export interface ExerciseDiff {
  readonly dayId: string;
  readonly exerciseId: string;
  readonly template: PlanExercise;
  readonly mine: PlanExercise;
  readonly fields: readonly TargetField[];
}

/** Exercises in both, with different targets; keyed by exerciseKey(day, exercise). */
export function targetDiffs(plan: Plan, template: Plan): Map<string, ExerciseDiff> {
  const out = new Map<string, ExerciseDiff>();
  const templateDays = new Map(template.days.map((d) => [d.id, d]));
  for (const day of plan.days) {
    const tDay = templateDays.get(day.id);
    if (!tDay) continue;
    const tEx = new Map(tDay.exercises.map((e) => [e.id, e]));
    for (const e of day.exercises) {
      const t = tEx.get(e.id);
      if (!t) continue;
      const fields = TARGETS.filter((f) => e[f] !== t[f]);
      if (fields.length > 0) out.set(exerciseKey(day.id, e.id), { dayId: day.id, exerciseId: e.id, template: t, mine: e, fields });
    }
  }
  return out;
}

/** Every difference (structure and targets), as the summary line counts them. */
export function templateChanges(plan: Plan, template: Plan): Change[] {
  return diffPlans(template, plan);
}

/** Sets one exercise's targets to `source`'s (Reset uses the template's). */
export function copyTargets(plan: Plan, dayId: string, exerciseId: string, source: PlanExercise): EditResult {
  const r = setTargets(plan, dayId, exerciseId, { sets: source.sets, reps: source.reps, rest: source.rest, step: source.step, unit: source.unit });
  return r.ok ? setSuperset(r.plan, dayId, exerciseId, source.superset) : r;
}

/** Reset one exercise to the template. */
export function resetToTemplate(plan: Plan, diff: ExerciseDiff): EditResult {
  return copyTargets(plan, diff.dayId, diff.exerciseId, diff.template);
}
