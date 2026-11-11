/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-return, @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access -- hostile bodies are built as untyped JSON on purpose */
import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import { diffPlans } from '../src/plans/diff';
import * as edit from '../src/plans/edit';
import { bodyBytes, cleanPlanName, LIMITS, nameFrom, nameProblem, newPlanId, parsePlan, planIds, planProblem, toBody, type Plan, type PlanExercise } from '../src/plans/model';
import { PlansRepository, toStoredPlan } from '../src/plans/plans';
import { changeLine, planFailureKey } from '../src/plans/text';
import { makeI18n } from '../src/i18n';

const M = 'a0000000-0000-4000-8000-000000000001';
const ex = (id: string, over: Partial<PlanExercise> = {}): PlanExercise => ({ id, name: { ar: `ت ${id}`, en: `Ex ${id}` }, sets: 3, reps: 12, rest: 90, step: 2.5, superset: false, unit: 'kg', ...over });
const plan = (): Plan => ({
  days: [
    { id: 'day-1', name: { ar: 'صدر', en: 'Chest' }, exercises: [ex('flat_db_press'), ex('pec_deck', { superset: true }), ex('abs', { step: 5, reps: 15 })] },
    { id: 'day-2', name: { ar: 'رجل', en: 'Legs' }, exercises: [ex('leg_press', { unit: 'plate' })] },
  ],
});
const ok = (r: edit.EditResult): Plan => {
  if (!r.ok) throw new Error(r.error);
  return r.plan;
};
const day0 = (p: Plan) => {
  const d = p.days[0];
  if (!d) throw new Error('no day');
  return d;
};
// Built so no raw direction character sits in the source.
const RLO = String.fromCharCode(0x202e);

describe('names (PlanNames in the app, plan_name_ok on the server)', () => {
  it('cleans to one line and removes direction overrides', () => {
    expect(cleanPlanName(`  Bench\n\tPress${RLO}  `)).toBe('Bench Press');
    expect(cleanPlanName(`a${String.fromCharCode(0)}b`)).toBe('a b');
    expect(cleanPlanName(42)).toBe('');
  });
  it('checks length in characters (an emoji counts once)', () => {
    expect(nameProblem('x'.repeat(40))).toBeNull();
    expect(nameProblem('x'.repeat(41))).toBe('too_long');
    expect(nameProblem('💪'.repeat(40))).toBeNull();
    expect(nameProblem('   ')).toBe('empty');
    expect(nameProblem('   ', false)).toBeNull();
  });
  it('one language fills the other; hostile text stays text', () => {
    expect(nameFrom('', 'Leg Day')).toEqual({ ar: 'Leg Day', en: 'Leg Day' });
    expect(nameFrom("'; DROP TABLE plans; --", '<script>x</script>')).toEqual({ ar: "'; DROP TABLE plans; --", en: '<script>x</script>' });
    expect(nameFrom('', '')).toBeNull();
    expect(nameFrom('x'.repeat(41), 'ok')).toBeNull();
  });
});

describe('the plan body', () => {
  it('round-trips the app JSON exactly; unit only when not kg', () => {
    const body = toBody(plan());
    expect(JSON.stringify(body.days[1])).toBe('{"id":"day-2","name":{"ar":"رجل","en":"Legs"},"exercises":[{"id":"leg_press","name":{"ar":"ت leg_press","en":"Ex leg_press"},"sets":3,"reps":12,"rest":90,"step":2.5,"superset":false,"unit":"plate"}]}');
    expect(JSON.stringify(body)).not.toContain('"unit":"kg"');
    expect(parsePlan(body)).toEqual(plan());
  });

  it('reads only what plan_problem accepts', () => {
    const good = toBody(plan()) as any;
    const bad = (change: (b: any) => void) => {
      const b = structuredClone(good);
      change(b);
      return parsePlan(b);
    };
    expect(bad((b) => { b.extra = 1; })).toBeNull();
    expect(bad((b) => { b.days[0].color = 'red'; })).toBeNull();
    expect(bad((b) => { b.days[0].exercises[0].note = 'x'; })).toBeNull();
    expect(bad((b) => { b.days[0].exercises[0].unit = 'lb'; })).toBeNull();
    expect(bad((b) => { b.days[0].exercises[0].sets = 2.5; })).toBeNull();
    expect(bad((b) => { b.days[0].exercises[0].step = '2.5'; })).toBeNull();
    expect(bad((b) => { b.days[0].id = '../x'; })).toBeNull();
    expect(bad((b) => { b.days[1].id = 'day-1'; })).toBeNull();
    expect(bad((b) => { b.days = []; })).toBeNull();
    expect(parsePlan(null)).toBeNull();
    expect(parsePlan('{"days":[]}')).toBeNull();
  });

  it('reports problems in the server\'s words', () => {
    const p = plan();
    expect(planProblem(p)).toBeNull();
    expect(planProblem({ days: [] })).toBe('bad day count');
    expect(planProblem({ days: Array.from({ length: 15 }, (_, i) => ({ id: `d${i}`, name: { ar: 'a', en: 'a' }, exercises: [] })) })).toBe('bad day count');
    expect(planProblem({ days: [{ ...day0(p), name: { ar: 'a  b', en: 'x' } }] })).toBe('bad day name');
    expect(planProblem({ days: [{ ...day0(p), exercises: Array.from({ length: 31 }, (_, i) => ex(`e${i}`)) }] })).toBe('too many exercises');
    expect(planProblem({ days: [{ ...day0(p), exercises: [ex('a', { sets: 11 })] }] })).toBe('sets out of range');
    expect(planProblem({ days: [{ ...day0(p), exercises: [ex('a', { reps: 0 })] }] })).toBe('reps out of range');
    expect(planProblem({ days: [{ ...day0(p), exercises: [ex('a', { rest: 601 })] }] })).toBe('rest out of range');
    expect(planProblem({ days: [{ ...day0(p), exercises: [ex('a', { step: 0 })] }] })).toBe('step out of range');
    expect(planProblem({ days: [{ ...day0(p), exercises: [ex('a', { step: Number.NaN })] }] })).toBe('step out of range');
    expect(planProblem({ days: [{ ...day0(p), exercises: [ex('a b')] }] })).toBe('bad exercise id');
  });

  it('counts the size like the server (jsonb text) and refuses over 64 KB', () => {
    expect(bodyBytes({ days: [{ id: 'd', name: { ar: 'a', en: 'b' }, exercises: [] }] })).toBe('{"days": [{"id": "d", "name": {"ar": "a", "en": "b"}, "exercises": []}]}'.length);
    const big: Plan = { days: Array.from({ length: 14 }, (_, d) => ({ id: `day-${d}`, name: { ar: 'ي'.repeat(40), en: 'D'.repeat(40) }, exercises: Array.from({ length: 30 }, (_, i) => ex(`ex-${d}-${i}`, { name: { ar: 'ت'.repeat(40), en: 'E'.repeat(40) } })) })) };
    expect(bodyBytes(big)).toBeGreaterThan(LIMITS.maxBodyBytes);
    expect(planProblem(big)).toBe('too large');
    const typical: Plan = { days: Array.from({ length: 6 }, (_, d) => ({ id: `day-${d}`, name: { ar: 'يوم', en: 'Day' }, exercises: Array.from({ length: 10 }, (_, i) => ex(`ex-${d}-${i}`)) })) };
    expect(planProblem(typical)).toBeNull();
  });

  it('new ids are time-based, never reused, and accepted by the tables', () => {
    const taken = planIds(plan());
    const a = newPlanId('ex', taken, 1_762_800_000_000);
    expect(a).toMatch(/^ex-[a-z0-9]{1,20}$/);
    expect(newPlanId('ex', new Set([a]), 1_762_800_000_000)).toBe(`${a}-2`);
    expect(newPlanId('day', taken, 1_762_800_000_001)).not.toBe(newPlanId('day', taken, 1_762_800_000_000));
  });
});

describe('editing (EditPlan in the app)', () => {
  it('days: add, rename, move, delete; never the last one; at most 14', () => {
    let p = ok(edit.addDay(plan(), { ar: 'كتف', en: 'Shoulders' }, 'day-3'));
    expect(p.days.map((d) => d.id)).toEqual(['day-1', 'day-2', 'day-3']);
    p = ok(edit.moveDay(p, 'day-3', -1));
    expect(p.days.map((d) => d.id)).toEqual(['day-1', 'day-3', 'day-2']);
    expect(ok(edit.moveDay(p, 'day-1', -1))).toBe(p);
    p = ok(edit.renameDay(p, 'day-3', { ar: 'كتف ٢', en: 'Shoulders 2' }));
    expect(p.days[1]?.name.en).toBe('Shoulders 2');
    expect(edit.renameDay(p, 'day-3', { ar: '', en: '' })).toEqual({ ok: false, error: 'invalid_name' });
    p = ok(edit.deleteDay(p, 'day-3'));
    expect(edit.deleteDay({ days: [day0(p)] }, 'day-1')).toEqual({ ok: false, error: 'last_day' });
    expect(edit.addDay(p, { ar: 'x', en: 'x' }, 'day-1')).toEqual({ ok: false, error: 'duplicate' });
    const full: Plan = { days: Array.from({ length: 14 }, (_, i) => ({ id: `d${i}`, name: { ar: 'a', en: 'a' }, exercises: [] })) };
    expect(edit.addDay(full, { ar: 'x', en: 'x' }, 'new')).toEqual({ ok: false, error: 'too_many' });
  });

  it('exercises: library defaults, clamps, no duplicate id in a day, at most 30', () => {
    let p = ok(edit.addExercise(plan(), 'day-2', { id: 'barbell_squat', name: { ar: 'بار', en: 'Squat' }, sets: 3, reps: 12, rest: 120, step: 5 }));
    expect(p.days[1]?.exercises.at(-1)).toMatchObject({ id: 'barbell_squat', rest: 120, step: 5, unit: 'kg', superset: false });
    expect(edit.addExercise(p, 'day-2', { id: 'barbell_squat', name: { ar: 'x', en: 'x' } })).toEqual({ ok: false, error: 'duplicate' });
    p = ok(edit.addExercise(p, 'day-2', { id: 'ex-abc', name: { ar: 'x', en: 'x' }, sets: 99, rest: -5, step: 999 }));
    expect(p.days[1]?.exercises.at(-1)).toMatchObject({ sets: 10, rest: 0, step: 2.5 });
    const full: Plan = { days: [{ id: 'd', name: { ar: 'a', en: 'a' }, exercises: Array.from({ length: 30 }, (_, i) => ex(`e${i}`)) }] };
    expect(edit.addExercise(full, 'd', { id: 'x', name: { ar: 'x', en: 'x' } })).toEqual({ ok: false, error: 'too_many' });
  });

  it('targets are clamped; a bad weight step is refused', () => {
    const p = ok(edit.setTargets(plan(), 'day-1', 'abs', { sets: 0, reps: 500, rest: 601.4, unit: 'reps' }));
    expect(p.days[0]?.exercises[2]).toMatchObject({ sets: 1, reps: 100, rest: 600, unit: 'reps' });
    expect(edit.setTargets(plan(), 'day-1', 'abs', { step: 0 }).ok).toBe(false);
    expect(edit.setTargets(plan(), 'day-1', 'abs', { step: 51 }).ok).toBe(false);
    expect(edit.setTargets(plan(), 'day-1', 'abs', { sets: Number.NaN }).ok).toBe(false);
    expect(edit.setTargets(plan(), 'day-1', 'nope', { sets: 3 })).toEqual({ ok: false, error: 'not_found' });
  });

  it('the last exercise never keeps "superset with next"', () => {
    let p = ok(edit.setSuperset(plan(), 'day-1', 'abs', true));
    expect(p.days[0]?.exercises[2]?.superset).toBe(false);
    // pec_deck (paired with abs) moves to the end: its pairing ends.
    p = ok(edit.moveExercise(plan(), 'day-1', 'pec_deck', 1));
    expect(p.days[0]?.exercises.map((e) => [e.id, e.superset])).toEqual([['flat_db_press', false], ['abs', false], ['pec_deck', false]]);
    // Deleting the partner ends it too.
    p = ok(edit.deleteExercise(plan(), 'day-1', 'abs'));
    expect(p.days[0]?.exercises.at(-1)).toMatchObject({ id: 'pec_deck', superset: false });
  });

  it('ids never change: rename keeps the id, a first plan is valid', () => {
    const p = ok(edit.renameExercise(plan(), 'day-1', 'flat_db_press', { ar: 'جديد', en: 'New' }));
    expect(p.days[0]?.exercises[0]?.id).toBe('flat_db_press');
    expect(planProblem(edit.firstPlan({ ar: 'اليوم ١', en: 'Day 1' }, 'day-x'))).toBeNull();
  });
});

describe('what changed (conflict view)', () => {
  it('matches by id: renames, adds, removes, moves, targets', () => {
    const before = plan();
    let after = ok(edit.renameDay(before, 'day-2', { ar: 'رجلين', en: 'Leg day' }));
    after = ok(edit.setTargets(after, 'day-1', 'abs', { reps: 20 }));
    after = ok(edit.deleteExercise(after, 'day-1', 'flat_db_press'));
    after = ok(edit.addDay(after, { ar: 'كتف', en: 'Shoulders' }, 'day-3'));
    after = ok(edit.moveDay(after, 'day-2', -1));
    const kinds = diffPlans(before, after).map((c) => c.kind);
    expect(kinds).toEqual(expect.arrayContaining(['day_renamed', 'targets_changed', 'exercise_removed', 'day_added', 'days_reordered']));
    expect(diffPlans(before, before)).toEqual([]);
    expect(diffPlans(null, before).filter((c) => c.kind === 'day_added')).toHaveLength(2);
  });
  it('reads in both languages', () => {
    const changes = diffPlans(plan(), ok(edit.setTargets(plan(), 'day-1', 'abs', { reps: 20, sets: 4 })));
    expect(changeLine(makeI18n('en'), (changes[0] ?? { kind: 'days_reordered' }))).toBe('Chest: Ex abs: sets, reps');
    expect(changeLine(makeI18n('ar'), (changes[0] ?? { kind: 'days_reordered' }))).toBe('صدر: ت abs: المجموعات، العدّات');
  });
});

// ------------------------------------------------------------ repository ----

interface Call { table?: string; rpc?: string; args?: unknown; columns?: string; filters: [string, string, unknown][] }
function fake(answer: (call: Call, n: number) => { data: unknown; error: unknown }) {
  const calls: Call[] = [];
  const builder = (call: Call): any => {
    const b: any = {
      select: (c: string) => ((call.columns = c), b),
      eq: (c: string, v: unknown) => (call.filters.push(['eq', c, v]), b),
      in: (c: string, v: unknown) => (call.filters.push(['in', c, v]), b),
      limit: () => b,
      overrideTypes: () => b,
      maybeSingle: () => b,
      then: (resolve: (v: unknown) => void) => {
        calls.push(call);
        resolve(answer(call, calls.length));
      },
    };
    return b;
  };
  const client = {
    from: (table: string) => builder({ table, filters: [] }),
    rpc: (rpc: string, args: unknown) => builder({ rpc, args, filters: [] }),
  } as unknown as SupabaseClient;
  return { client, calls };
}

describe('PlansRepository', () => {
  it('reads one member\'s plan with explicit columns; a crafted id never leaves', async () => {
    const { client, calls } = fake(() => ({ data: { body: toBody(plan()), version: 4, updated_by: M, updated_at: '2026-11-10T10:00:00Z' }, error: null }));
    const r = await new PlansRepository(client).get(M);
    expect(r.ok && r.value.version).toBe(4);
    expect(r.ok && r.value.plan).toEqual(plan());
    expect(calls[0]).toMatchObject({ table: 'plans', columns: 'body, version, updated_by, updated_at', filters: [['eq', 'membership_id', M]] });
    const bad = fake(() => ({ data: null, error: null }));
    expect((await new PlansRepository(bad.client).get("x' or 1=1")).ok).toBe(false);
    expect(bad.calls).toHaveLength(0);
  });

  it('no row = no plan (version 0); a body it can\'t read is not editable', () => {
    expect(toStoredPlan(null)).toMatchObject({ plan: null, version: 0, unreadable: false });
    expect(toStoredPlan({ body: { days: [{ id: 'x' }] }, version: 2, updated_by: 'not-a-uuid', updated_at: 'nope' })).toMatchObject({ plan: null, version: 2, unreadable: true, updatedBy: null, updatedAt: null });
  });

  it('saves through save_plan with the base version and the app\'s JSON', async () => {
    const { client, calls } = fake((call) => (call.rpc ? { data: { version: 5 }, error: null } : { data: { version: 4 }, error: null }));
    const r = await new PlansRepository(client).save(M, 4, plan());
    expect(r).toEqual({ ok: true, value: { version: 5 } });
    expect(calls.at(-1)).toMatchObject({ rpc: 'save_plan', args: { p_membership_id: M, p_base_version: 4, p_body: toBody(plan()) } });
  });

  it('someone saved meanwhile: plan_changed, and nothing is sent', async () => {
    const { client, calls } = fake(() => ({ data: { version: 6 }, error: null }));
    const r = await new PlansRepository(client).save(M, 4, plan());
    expect(!r.ok && r.failure).toEqual({ kind: 'conflict', reason: 'plan_changed' });
    expect(calls.some((c) => c.rpc)).toBe(false);
  });

  it('a first plan uses base version 0; the server\'s own plan_changed is a conflict too', async () => {
    const { client } = fake((call) => (call.rpc ? { data: null, error: { code: 'P0001', message: 'plan_changed' } } : { data: null, error: null }));
    const r = await new PlansRepository(client).save(M, 0, plan());
    expect(!r.ok && r.failure).toEqual({ kind: 'conflict', reason: 'plan_changed' });
  });

  it('refuses a plan the server would refuse, before any request', async () => {
    const { client, calls } = fake(() => ({ data: null, error: null }));
    const r = await new PlansRepository(client).save(M, 1, { days: [] });
    expect(!r.ok && r.failure).toEqual({ kind: 'invalid', reason: 'invalid_plan' });
    expect(calls).toHaveLength(0);
  });

  it('maps forbidden / invalid_plan / offline to fixed messages', async () => {
    const cases: [unknown, string][] = [
      [{ code: '42501', message: 'forbidden' }, 'plan.errForbidden'],
      [{ code: '22023', message: 'invalid_plan: bad day name' }, 'plan.errInvalid'],
      [{ code: 'XX000', message: '<b>boom</b>' }, 'plan.errServer'],
    ];
    for (const [error, key] of cases) {
      const { client } = fake((call) => (call.rpc ? { data: null, error } : { data: { version: 1 }, error: null }));
      const r = await new PlansRepository(client).save(M, 1, plan());
      expect(r.ok ? null : planFailureKey(r.failure)).toBe(key);
    }
  });

  it('copy: replace reads the target\'s current version; versions in one query', async () => {
    const { client, calls } = fake((call) => (call.rpc ? { data: { version: 3 }, error: null } : call.filters.some((f) => f[0] === 'in') ? { data: [{ membership_id: M, version: 2 }, { membership_id: 'x', version: 9 }], error: null } : { data: { version: 2 }, error: null }));
    const repo = new PlansRepository(client);
    expect(await repo.replace(M, plan())).toEqual({ ok: true, value: { version: 3 } });
    expect(calls.find((c) => c.rpc)?.args).toMatchObject({ p_base_version: 2 });
    const v = await repo.versions([M, 'not-a-uuid', M]);
    expect(v.ok && [...v.value.entries()]).toEqual([[M, 2]]);
    expect(calls.at(-1)?.filters).toContainEqual(['in', 'membership_id', [M]]);
  });
});
