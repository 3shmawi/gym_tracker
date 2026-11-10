// A member's plan, as the app stores it (lib/features/workout/domain/entities/
// workout_plan.dart) and the server checks it (private.plan_problem, migrations
// 0007 + 0016). The dashboard must only ever send a body the app accepts.

export type Unit = 'kg' | 'plate' | 'reps';

export interface PlanName {
  readonly ar: string;
  readonly en: string;
}

export interface PlanExercise {
  readonly id: string;
  readonly name: PlanName;
  readonly sets: number;
  readonly reps: number;
  /** Seconds after a set (or a superset round). */
  readonly rest: number;
  /** Weight step, kg. */
  readonly step: number;
  /** Done together with the next exercise (the last one of a day never is). */
  readonly superset: boolean;
  readonly unit: Unit;
}

export interface PlanDay {
  readonly id: string;
  readonly name: PlanName;
  readonly exercises: readonly PlanExercise[];
}

export interface Plan {
  readonly days: readonly PlanDay[];
}

/** PlanLimits in the app; the same numbers as private.plan_problem. */
export const LIMITS = {
  minDays: 1,
  maxDays: 14,
  maxExercisesPerDay: 30,
  maxNameLength: 40,
  minSets: 1,
  maxSets: 10,
  minReps: 1,
  maxReps: 100,
  minRest: 0,
  maxRest: 600,
  restStep: 15,
  weightSteps: [0.5, 1, 1.25, 2, 2.5, 5] as readonly number[],
  maxWeightStep: 50,
  newSets: 3,
  newReps: 12,
  newRest: 90,
  newWeightStep: 2.5,
  /** octet_length(body::text) in the plans table and plan_problem. */
  maxBodyBytes: 65_536,
} as const;

/** Day and exercise ids the server accepts (plan_problem's c_id_re). */
export const PLAN_ID = /^[A-Za-z0-9_-]{1,64}$/;

// ------------------------------------------------------------------ names ----

// PlanNames in the app: control characters and the bidi marks that can flip a
// name become a space, then runs of spaces collapse. The server refuses the
// same characters (plan_name_ok), so a cleaned name always passes.
const INVISIBLE_CLASS = '[\\u0000-\\u001F\\u007F-\\u009F\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]';
const INVISIBLE = new RegExp(INVISIBLE_CLASS, 'g');

export function cleanPlanName(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  return raw.replace(INVISIBLE, ' ').replace(/\s+/g, ' ').trim();
}

/** Characters as a person sees them (an emoji counts once, like Dart's runes). */
export const nameLength = (name: string): number => Array.from(name).length;

export type NameProblem = 'empty' | 'too_long';

export function nameProblem(raw: string, required = true): NameProblem | null {
  const name = cleanPlanName(raw);
  if (name === '') return required ? 'empty' : null;
  if (nameLength(name) > LIMITS.maxNameLength) return 'too_long';
  return null;
}

/** Both fields as a name, or null. One empty language takes the other's text. */
export function nameFrom(ar: string, en: string): PlanName | null {
  const a = cleanPlanName(ar);
  const e = cleanPlanName(en);
  if (a === '' && e === '') return null;
  if (nameProblem(a, false) !== null || nameProblem(e, false) !== null) return null;
  return { ar: a === '' ? e : a, en: e === '' ? a : e };
}

export function isValidName(name: PlanName): boolean {
  return (
    name.ar !== '' &&
    name.en !== '' &&
    cleanPlanName(name.ar) === name.ar &&
    cleanPlanName(name.en) === name.en &&
    nameLength(name.ar) <= LIMITS.maxNameLength &&
    nameLength(name.en) <= LIMITS.maxNameLength
  );
}

// ------------------------------------------------------------ JSON body ----

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const sameKeys = (o: Record<string, unknown>, keys: readonly string[]) => {
  const got = Object.keys(o).sort();
  return got.length === keys.length && [...keys].sort().every((k, i) => got[i] === k);
};

function readName(v: unknown): PlanName | null {
  if (!isObject(v) || !sameKeys(v, ['ar', 'en']) || typeof v.ar !== 'string' || typeof v.en !== 'string') return null;
  return { ar: v.ar, en: v.en };
}

/**
 * Reads a stored plan body. Strict: anything plan_problem would refuse gives
 * null, so the dashboard never edits (and re-sends) a plan it misread.
 */
export function parsePlan(body: unknown): Plan | null {
  if (!isObject(body) || !sameKeys(body, ['days']) || !Array.isArray(body.days)) return null;
  const days: PlanDay[] = [];
  for (const d of body.days as unknown[]) {
    if (!isObject(d) || !sameKeys(d, ['exercises', 'id', 'name']) || typeof d.id !== 'string' || !Array.isArray(d.exercises)) return null;
    const name = readName(d.name);
    if (!name) return null;
    const exercises: PlanExercise[] = [];
    for (const e of d.exercises as unknown[]) {
      if (!isObject(e)) return null;
      const keys = Object.keys(e).filter((k) => k !== 'unit');
      if (!sameKeys(Object.fromEntries(keys.map((k) => [k, 1])), ['id', 'name', 'reps', 'rest', 'sets', 'step', 'superset'])) return null;
      const exName = readName(e.name);
      if (!exName || typeof e.id !== 'string' || !isInt(e.sets) || !isInt(e.reps) || !isInt(e.rest)) return null;
      if (typeof e.step !== 'number' || !Number.isFinite(e.step) || typeof e.superset !== 'boolean') return null;
      if ('unit' in e && e.unit !== 'kg' && e.unit !== 'plate' && e.unit !== 'reps') return null;
      const unit: Unit = e.unit === 'plate' || e.unit === 'reps' ? e.unit : 'kg';
      exercises.push({ id: e.id, name: exName, sets: e.sets, reps: e.reps, rest: e.rest, step: e.step, superset: e.superset, unit });
    }
    days.push({ id: d.id, name, exercises });
  }
  const plan = { days };
  return planProblem(plan) === null ? plan : null;
}

/** The JSON body exactly as the app writes it (`unit` only when not kg). */
export function toBody(plan: Plan): { days: unknown[] } {
  return {
    days: plan.days.map((d) => ({
      id: d.id,
      name: { ar: d.name.ar, en: d.name.en },
      exercises: d.exercises.map((e) => ({
        id: e.id,
        name: { ar: e.name.ar, en: e.name.en },
        sets: e.sets,
        reps: e.reps,
        rest: e.rest,
        step: e.step,
        superset: e.superset,
        ...(e.unit === 'kg' ? {} : { unit: e.unit }),
      })),
    })),
  };
}

/**
 * The size the server checks: octet_length(body::text). Postgres prints jsonb
 * with a space after every ":" and ",", so this counts those too (a plain
 * JSON.stringify would undercount by about a quarter and let a too-large plan
 * reach the server).
 */
export function bodyBytes(plan: Plan): number {
  return new TextEncoder().encode(jsonbText(toBody(plan))).length;
}

function jsonbText(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(jsonbText).join(', ')}]`;
  if (typeof v === 'object' && v !== null) return `{${Object.entries(v).map(([k, x]) => `${JSON.stringify(k)}: ${jsonbText(x)}`).join(', ')}}`;
  return JSON.stringify(v);
}

/**
 * What is wrong with a plan, in private.plan_problem's own words (so a
 * refusal reads the same on both sides), or null when the server will take it.
 */
export function planProblem(plan: Plan): string | null {
  if (plan.days.length < LIMITS.minDays || plan.days.length > LIMITS.maxDays) return 'bad day count';
  const dayIds = new Set<string>();
  for (const day of plan.days) {
    if (!PLAN_ID.test(day.id) || dayIds.has(day.id)) return 'bad day id';
    dayIds.add(day.id);
    if (!isValidName(day.name)) return 'bad day name';
    if (day.exercises.length > LIMITS.maxExercisesPerDay) return 'too many exercises';
    const exIds = new Set<string>();
    for (const e of day.exercises) {
      if (!PLAN_ID.test(e.id) || exIds.has(e.id)) return 'bad exercise id';
      exIds.add(e.id);
      if (!isValidName(e.name)) return 'bad exercise name';
      if (!isInt(e.sets) || e.sets < LIMITS.minSets || e.sets > LIMITS.maxSets) return 'sets out of range';
      if (!isInt(e.reps) || e.reps < LIMITS.minReps || e.reps > LIMITS.maxReps) return 'reps out of range';
      if (!isInt(e.rest) || e.rest < LIMITS.minRest || e.rest > LIMITS.maxRest) return 'rest out of range';
      if (!Number.isFinite(e.step) || e.step <= 0 || e.step > LIMITS.maxWeightStep) return 'step out of range';
    }
  }
  if (bodyBytes(plan) > LIMITS.maxBodyBytes) return 'too large';
  return null;
}

/** Every id the plan uses (days and exercises). */
export function planIds(plan: Plan): Set<string> {
  const ids = new Set<string>();
  for (const d of plan.days) {
    ids.add(d.id);
    for (const e of d.exercises) ids.add(e.id);
  }
  return ids;
}

/**
 * A new id that is not in `taken`: the prefix, then the time in microseconds
 * in base 36, like the app's newPlanId ("ex-m3k9w2a1b"). Time only grows, so a
 * deleted id is never handed out again and a new exercise never inherits old
 * history. `taken` holds every id in the plan and every id issued this session.
 */
export function newPlanId(prefix: 'day' | 'ex', taken: ReadonlySet<string>, nowMs: number): string {
  const base = `${prefix}-${(Math.floor(nowMs) * 1000).toString(36)}`;
  let id = base;
  for (let n = 2; taken.has(id); n++) id = `${base}-${n}`;
  return id;
}
