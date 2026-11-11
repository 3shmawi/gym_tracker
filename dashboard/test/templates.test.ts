/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-return */
import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import { parsePath } from '../src/app/router';
import { toBody, type Plan, type PlanExercise } from '../src/plans/model';
import { copyTargets, exerciseKey, resetToTemplate, targetDiffs, templateChanges } from '../src/plans/templateDiff';
import { TemplatesRepository, toTemplate } from '../src/plans/templates';

const GYM = 'b0000000-0000-4000-8000-000000000001';
const T = 'f0000000-0000-4000-8000-00000000000a';
const M = 'a0000000-0000-4000-8000-000000000001';
const ex = (id: string, over: Partial<PlanExercise> = {}): PlanExercise => ({ id, name: { ar: `ت ${id}`, en: `Ex ${id}` }, sets: 3, reps: 12, rest: 90, step: 2.5, superset: false, unit: 'kg', ...over });
const template: Plan = { days: [{ id: 'day-1', name: { ar: 'صدر', en: 'Chest' }, exercises: [ex('flat_db_press'), ex('incline_machine_press'), ex('pec_deck')] }] };
const ok = (r: { ok: true; plan: Plan } | { ok: false; error: string }): Plan => {
  if (!r.ok) throw new Error(r.error);
  return r.plan;
};

interface Call { table?: string; rpc?: string; op: string; payload?: unknown; args?: unknown; columns?: string; filters: [string, string, unknown][] }
function fake(answer: (call: Call) => { data: unknown; error: unknown }) {
  const calls: Call[] = [];
  const builder = (call: Call): any => {
    const b: any = {
      select: (c: string) => ((call.columns = c), b),
      insert: (p: unknown) => ((call.op = 'insert'), (call.payload = p), b),
      update: (p: unknown) => ((call.op = 'update'), (call.payload = p), b),
      delete: () => ((call.op = 'delete'), b),
      eq: (c: string, v: unknown) => (call.filters.push(['eq', c, v]), b),
      order: () => b,
      limit: () => b,
      overrideTypes: () => b,
      single: () => b,
      maybeSingle: () => b,
      then: (resolve: (v: unknown) => void) => {
        calls.push(call);
        resolve(answer(call));
      },
    };
    return b;
  };
  const client = { from: (table: string) => builder({ table, op: 'select', filters: [] }), rpc: (rpc: string, args: unknown) => builder({ rpc, args, op: 'rpc', filters: [] }) } as unknown as SupabaseClient;
  return { client, calls };
}

describe('template rows', () => {
  it('reads valid rows; drops bad names and ids; a body it can\'t read is kept but not usable', () => {
    const row = { id: T, name: { ar: 'دفع', en: 'Push' }, body: toBody(template), version: 2, updated_at: '2026-11-10T10:00:00Z' };
    expect(toTemplate(row)?.plan).toEqual(template);
    expect(toTemplate({ ...row, body: { days: [], evil: 1 } })?.plan).toBeNull();
    expect(toTemplate({ ...row, id: '../x' })).toBeNull();
    expect(toTemplate({ ...row, name: { ar: '', en: 'x' } })).toBeNull();
    expect(toTemplate({ ...row, name: 'Push' })).toBeNull();
    expect(toTemplate({ ...row, version: 0 })).toBeNull();
  });
});

describe('TemplatesRepository', () => {
  it('lists the gym\'s templates with explicit columns', async () => {
    const { client, calls } = fake(() => ({ data: [], error: null }));
    await new TemplatesRepository(client).list(GYM);
    expect(calls[0]).toMatchObject({ table: 'plan_templates', columns: 'id, name, body, version, updated_at', filters: [['eq', 'gym_id', GYM]] });
  });

  it('before migration 0019 is deployed: no templates, no link, no error', async () => {
    const missing = fake(() => ({ data: null, error: { code: 'PGRST205', message: 'Could not find the table' } }));
    expect(await new TemplatesRepository(missing.client).list(GYM)).toEqual({ ok: true, value: [] });
    const noColumn = fake(() => ({ data: null, error: { code: '42703', message: 'column plans.template_id does not exist' } }));
    expect(await new TemplatesRepository(noColumn.client).link(M)).toEqual({ ok: true, value: { templateId: null, templateVersion: null } });
  });

  it('creates with only gym_id, name and body; refuses a bad plan or name before sending', async () => {
    const { client, calls } = fake(() => ({ data: { id: T, name: { ar: 'دفع', en: 'Push' }, body: toBody(template), version: 1, updated_at: null }, error: null }));
    const repo = new TemplatesRepository(client);
    const r = await repo.create(GYM, { ar: 'دفع', en: 'Push' }, template);
    expect(r.ok && r.value.id).toBe(T);
    expect(Object.keys(calls[0]?.payload as object).sort()).toEqual(['body', 'gym_id', 'name']);
    expect((await repo.create(GYM, { ar: '', en: '' }, template)).ok).toBe(false);
    expect((await repo.create(GYM, { ar: 'x', en: 'x' }, { days: [] })).ok).toBe(false);
    expect((await repo.create("'; drop", { ar: 'x', en: 'x' }, template)).ok).toBe(false);
    expect(calls).toHaveLength(1);
  });

  it('the 51st template: a fixed reason', async () => {
    const { client } = fake(() => ({ data: null, error: { code: '23514', message: 'too_many_templates_in_gym' } }));
    const r = await new TemplatesRepository(client).create(GYM, { ar: 'x', en: 'x' }, template);
    expect(!r.ok && r.failure).toEqual({ kind: 'conflict', reason: 'too_many_templates_in_gym' });
  });

  it('rename / delete: a row RLS hid means forbidden', async () => {
    const { client } = fake(() => ({ data: [], error: null }));
    const repo = new TemplatesRepository(client);
    expect(await repo.rename(T, { ar: 'x', en: 'x' })).toMatchObject({ ok: false, failure: { kind: 'forbidden' } });
    expect(await repo.remove(T)).toMatchObject({ ok: false, failure: { kind: 'forbidden' } });
  });

  it('apply goes through the RPC with the base version', async () => {
    const { client, calls } = fake(() => ({ data: { version: 4, template_id: T, template_version: 2 }, error: null }));
    const r = await new TemplatesRepository(client).apply(M, T, 3);
    expect(r).toEqual({ ok: true, value: { version: 4 } });
    expect(calls[0]).toMatchObject({ rpc: 'apply_plan_template', args: { p_membership_id: M, p_template_id: T, p_base_version: 3 } });
    const bad = fake(() => ({ data: null, error: null }));
    expect((await new TemplatesRepository(bad.client).apply(M, 'not-a-uuid', 3)).ok).toBe(false);
    expect((await new TemplatesRepository(bad.client).apply(M, T, -1)).ok).toBe(false);
    expect(bad.calls).toHaveLength(0);
  });

  it('linked plans: only readable rows with valid ids', async () => {
    const { client, calls } = fake(() => ({ data: [{ membership_id: M, version: 2, body: toBody(template) }, { membership_id: 'x', version: 1, body: {} }], error: null }));
    const r = await new TemplatesRepository(client).linkedPlans(T);
    expect(r.ok && r.value.map((p) => p.membershipId)).toEqual([M]);
    expect(calls[0]?.filters).toEqual([['eq', 'template_id', T]]);
  });
});

describe('differences from the template', () => {
  it('finds target changes by day and exercise id', () => {
    let plan = ok(copyTargets(template, 'day-1', 'incline_machine_press', ex('incline_machine_press', { sets: 4 })));
    plan = ok(copyTargets(plan, 'day-1', 'flat_db_press', ex('flat_db_press', { reps: 10, superset: true })));
    const diffs = targetDiffs(plan, template);
    expect([...diffs.keys()]).toEqual([exerciseKey('day-1', 'flat_db_press'), exerciseKey('day-1', 'incline_machine_press')]);
    expect(diffs.get(exerciseKey('day-1', 'flat_db_press'))?.fields).toEqual(['reps', 'superset']);
    expect(templateChanges(plan, template)).toHaveLength(2);
  });

  it('Reset puts one exercise back; the others stay', () => {
    let plan = ok(copyTargets(template, 'day-1', 'incline_machine_press', ex('incline_machine_press', { sets: 4, unit: 'plate' })));
    plan = ok(copyTargets(plan, 'day-1', 'pec_deck', ex('pec_deck', { reps: 15 })));
    const d = targetDiffs(plan, template).get(exerciseKey('day-1', 'incline_machine_press'));
    if (!d) throw new Error('no diff');
    const reset = ok(resetToTemplate(plan, d));
    expect(reset.days[0]?.exercises[1]).toEqual(template.days[0]?.exercises[1]);
    expect(reset.days[0]?.exercises[2]?.reps).toBe(15);
  });

  it('copying a change to a plan without that exercise is refused (skipped)', () => {
    const other: Plan = { days: [{ id: 'day-1', name: { ar: 'a', en: 'a' }, exercises: [ex('abs')] }] };
    expect(copyTargets(other, 'day-1', 'pec_deck', ex('pec_deck', { reps: 15 })).ok).toBe(false);
    expect(copyTargets(other, 'day-9', 'abs', ex('abs')).ok).toBe(false);
  });

  it('the templates route needs a UUID gym id', () => {
    expect(parsePath(`/g/${GYM}/templates`)).toEqual({ name: 'templates', gymId: GYM });
    expect(parsePath('/g/x/templates').name).toBe('not_found');
    expect(parsePath(`/g/${GYM}/templates/extra`).name).toBe('not_found');
  });
});
