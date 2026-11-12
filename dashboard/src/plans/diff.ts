import type { Plan, PlanExercise, PlanName } from './model';

// What changed between two versions of a plan, matched by id (ids never
// change, so a rename is a rename and not a delete + add). Used when someone
// else saved while the captain was editing: the page lists these lines.

export type Change =
  | { readonly kind: 'day_added' | 'day_removed'; readonly day: PlanName }
  | { readonly kind: 'day_renamed'; readonly from: PlanName; readonly to: PlanName }
  | { readonly kind: 'days_reordered' }
  | { readonly kind: 'exercise_added' | 'exercise_removed'; readonly day: PlanName; readonly exercise: PlanName }
  | { readonly kind: 'exercise_renamed'; readonly day: PlanName; readonly from: PlanName; readonly to: PlanName }
  | { readonly kind: 'exercises_reordered'; readonly day: PlanName }
  | { readonly kind: 'targets_changed'; readonly day: PlanName; readonly exercise: PlanName; readonly fields: readonly TargetField[] };

export type TargetField = 'sets' | 'reps' | 'rest' | 'step' | 'unit' | 'superset';

const sameName = (a: PlanName, b: PlanName) => a.ar === b.ar && a.en === b.en;

const FIELDS: readonly TargetField[] = ['sets', 'reps', 'rest', 'step', 'unit', 'superset'];
function changedFields(a: PlanExercise, b: PlanExercise): TargetField[] {
  return FIELDS.filter((f) => a[f] !== b[f]);
}

function sameOrder(a: readonly { id: string }[], b: readonly { id: string }[]): boolean {
  const shared = new Set(b.map((x) => x.id));
  const left = a.filter((x) => shared.has(x.id)).map((x) => x.id);
  const kept = new Set(left);
  const right = b.filter((x) => kept.has(x.id)).map((x) => x.id);
  return left.every((id, i) => id === right[i]);
}

export function diffPlans(before: Plan | null, after: Plan | null): Change[] {
  const out: Change[] = [];
  const oldDays = before?.days ?? [];
  const newDays = after?.days ?? [];
  const oldById = new Map(oldDays.map((d) => [d.id, d]));
  const newById = new Map(newDays.map((d) => [d.id, d]));

  for (const d of oldDays) if (!newById.has(d.id)) out.push({ kind: 'day_removed', day: d.name });
  for (const d of newDays) {
    const old = oldById.get(d.id);
    if (!old) {
      out.push({ kind: 'day_added', day: d.name });
      continue;
    }
    if (!sameName(old.name, d.name)) out.push({ kind: 'day_renamed', from: old.name, to: d.name });
    const oldEx = new Map(old.exercises.map((e) => [e.id, e]));
    const newEx = new Map(d.exercises.map((e) => [e.id, e]));
    for (const e of old.exercises) if (!newEx.has(e.id)) out.push({ kind: 'exercise_removed', day: d.name, exercise: e.name });
    for (const e of d.exercises) {
      const o = oldEx.get(e.id);
      if (!o) {
        out.push({ kind: 'exercise_added', day: d.name, exercise: e.name });
        continue;
      }
      if (!sameName(o.name, e.name)) out.push({ kind: 'exercise_renamed', day: d.name, from: o.name, to: e.name });
      const fields = changedFields(o, e);
      if (fields.length > 0) out.push({ kind: 'targets_changed', day: d.name, exercise: e.name, fields });
    }
    if (!sameOrder(old.exercises, d.exercises)) out.push({ kind: 'exercises_reordered', day: d.name });
  }
  if (!sameOrder(oldDays, newDays)) out.push({ kind: 'days_reordered' });
  return out;
}
