import { isValidName, LIMITS, type Plan, type PlanDay, type PlanExercise, type PlanName, type Unit } from './model';

// Every change the plan editor makes, as pure functions (the app's EditPlan,
// lib/features/workout/domain/usecases/edit_plan.dart): plan in, new plan out,
// or the reason it can't be done. Days and exercises are found by id; targets
// are clamped to LIMITS; the last exercise of a day never stays "superset with
// next" (there is no next). Ids never change, so history stays matched.

export type EditError = 'last_day' | 'not_found' | 'invalid_name' | 'too_many' | 'duplicate';
export type EditResult = { readonly ok: true; readonly plan: Plan } | { readonly ok: false; readonly error: EditError };

const done = (plan: Plan): EditResult => ({ ok: true, plan });
const refuse = (error: EditError): EditResult => ({ ok: false, error });

const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, Math.round(v)));

/** The last exercise has no "next" to superset with. */
function endSupersets(day: PlanDay): PlanDay {
  const last = day.exercises.at(-1);
  if (!last?.superset) return day;
  return { ...day, exercises: [...day.exercises.slice(0, -1), { ...last, superset: false }] };
}

function move<T>(items: readonly T[], from: number, to: number): T[] | null {
  if (from < 0 || from >= items.length || to < 0 || to >= items.length) return null;
  const list = [...items];
  const [item] = list.splice(from, 1);
  if (item === undefined) return null;
  list.splice(to, 0, item);
  return list;
}

function updateDay(plan: Plan, dayId: string, change: (day: PlanDay) => PlanDay | EditError): EditResult {
  const i = plan.days.findIndex((d) => d.id === dayId);
  const day = plan.days[i];
  if (!day) return refuse('not_found');
  const next = change(day);
  if (typeof next === 'string') return refuse(next);
  const days = [...plan.days];
  days[i] = endSupersets(next);
  return done({ days });
}

function updateExercise(plan: Plan, dayId: string, exerciseId: string, change: (e: PlanExercise) => PlanExercise | EditError): EditResult {
  return updateDay(plan, dayId, (day) => {
    const i = day.exercises.findIndex((e) => e.id === exerciseId);
    const ex = day.exercises[i];
    if (!ex) return 'not_found';
    const next = change(ex);
    if (typeof next === 'string') return next;
    const exercises = [...day.exercises];
    exercises[i] = next;
    return { ...day, exercises };
  });
}

// ----------------------------------------------------------------- days ----

export function addDay(plan: Plan, name: PlanName, id: string): EditResult {
  if (plan.days.length >= LIMITS.maxDays) return refuse('too_many');
  if (!isValidName(name)) return refuse('invalid_name');
  if (plan.days.some((d) => d.id === id)) return refuse('duplicate');
  return done({ days: [...plan.days, { id, name, exercises: [] }] });
}

export function renameDay(plan: Plan, dayId: string, name: PlanName): EditResult {
  if (!isValidName(name)) return refuse('invalid_name');
  return updateDay(plan, dayId, (day) => ({ ...day, name }));
}

export function deleteDay(plan: Plan, dayId: string): EditResult {
  if (!plan.days.some((d) => d.id === dayId)) return refuse('not_found');
  if (plan.days.length <= LIMITS.minDays) return refuse('last_day');
  return done({ days: plan.days.filter((d) => d.id !== dayId) });
}

export function moveDay(plan: Plan, dayId: string, by: -1 | 1): EditResult {
  const from = plan.days.findIndex((d) => d.id === dayId);
  if (from < 0) return refuse('not_found');
  const days = move(plan.days, from, from + by);
  return days ? done({ days }) : done(plan);
}

// ------------------------------------------------------------ exercises ----

export interface NewExercise {
  readonly id: string;
  readonly name: PlanName;
  readonly sets?: number;
  readonly reps?: number;
  readonly rest?: number;
  readonly step?: number;
}

export function addExercise(plan: Plan, dayId: string, ex: NewExercise): EditResult {
  if (!isValidName(ex.name)) return refuse('invalid_name');
  return updateDay(plan, dayId, (day) => {
    if (day.exercises.length >= LIMITS.maxExercisesPerDay) return 'too_many';
    if (day.exercises.some((e) => e.id === ex.id)) return 'duplicate';
    const exercise: PlanExercise = {
      id: ex.id,
      name: ex.name,
      sets: clamp(ex.sets ?? LIMITS.newSets, LIMITS.minSets, LIMITS.maxSets),
      reps: clamp(ex.reps ?? LIMITS.newReps, LIMITS.minReps, LIMITS.maxReps),
      rest: clamp(ex.rest ?? LIMITS.newRest, LIMITS.minRest, LIMITS.maxRest),
      step: ex.step !== undefined && Number.isFinite(ex.step) && ex.step > 0 && ex.step <= LIMITS.maxWeightStep ? ex.step : LIMITS.newWeightStep,
      superset: false,
      unit: 'kg',
    };
    return { ...day, exercises: [...day.exercises, exercise] };
  });
}

export function renameExercise(plan: Plan, dayId: string, exerciseId: string, name: PlanName): EditResult {
  if (!isValidName(name)) return refuse('invalid_name');
  return updateExercise(plan, dayId, exerciseId, (e) => ({ ...e, name }));
}

export function deleteExercise(plan: Plan, dayId: string, exerciseId: string): EditResult {
  return updateDay(plan, dayId, (day) => {
    if (!day.exercises.some((e) => e.id === exerciseId)) return 'not_found';
    return { ...day, exercises: day.exercises.filter((e) => e.id !== exerciseId) };
  });
}

export function moveExercise(plan: Plan, dayId: string, exerciseId: string, by: -1 | 1): EditResult {
  return updateDay(plan, dayId, (day) => {
    const from = day.exercises.findIndex((e) => e.id === exerciseId);
    if (from < 0) return 'not_found';
    const exercises = move(day.exercises, from, from + by);
    return exercises ? { ...day, exercises } : day;
  });
}

export function setSuperset(plan: Plan, dayId: string, exerciseId: string, withNext: boolean): EditResult {
  return updateExercise(plan, dayId, exerciseId, (e) => ({ ...e, superset: withNext }));
}

export interface Targets {
  readonly sets?: number;
  readonly reps?: number;
  readonly rest?: number;
  readonly step?: number;
  readonly unit?: Unit;
}

/** Changes the targets given; numbers are clamped, a weight step outside (0, 50] is refused. */
export function setTargets(plan: Plan, dayId: string, exerciseId: string, t: Targets): EditResult {
  if (t.step !== undefined && (!Number.isFinite(t.step) || t.step <= 0 || t.step > LIMITS.maxWeightStep)) return refuse('not_found');
  for (const v of [t.sets, t.reps, t.rest]) if (v !== undefined && !Number.isFinite(v)) return refuse('not_found');
  return updateExercise(plan, dayId, exerciseId, (e) => ({
    ...e,
    sets: t.sets === undefined ? e.sets : clamp(t.sets, LIMITS.minSets, LIMITS.maxSets),
    reps: t.reps === undefined ? e.reps : clamp(t.reps, LIMITS.minReps, LIMITS.maxReps),
    rest: t.rest === undefined ? e.rest : clamp(t.rest, LIMITS.minRest, LIMITS.maxRest),
    step: t.step ?? e.step,
    unit: t.unit ?? e.unit,
  }));
}

/** A plan with one empty day, for a member who has none yet. */
export function firstPlan(name: PlanName, dayId: string): Plan {
  return { days: [{ id: dayId, name, exercises: [] }] };
}
