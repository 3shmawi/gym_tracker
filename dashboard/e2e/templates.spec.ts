import { GYM_A, M, expect, samplePlan, test, type FakePlan, type FakeTemplate } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { isPhone, memberPath, open } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const planPath = (id: string) => `${memberPath(id)}/plan`;
const TEMPLATES = `/g/${GYM_A.id}/templates`;
const TPL = 'f0000000-0000-4000-8000-00000000000a';
const tpl = (over: Partial<FakeTemplate> = {}): FakeTemplate => ({ id: TPL, gym_id: GYM_A.id, name: { ar: 'دفع وسحب', en: 'Push / Pull' }, body: samplePlan(), version: 1, updated_at: '2026-11-09T10:00:00Z', ...over });
const linked = (version: number, over: Partial<FakePlan> = {}): FakePlan => ({ body: samplePlan(), version, updated_by: M.owner, updated_at: '2026-11-09T10:00:00Z', template_id: TPL, template_version: 1, ...over });
type Body = { days: { exercises: { id: string; sets: number }[] }[] };
const setsOf = (body: unknown, id: string) => (body as Body).days[0]?.exercises.find((e) => e.id === id)?.sets;

test.describe('gym templates', () => {
  test('save a plan as a template, then rename and delete it on the templates page', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: { body: samplePlan(), version: 3, updated_by: null, updated_at: '2026-11-09T10:00:00Z' } } });
    await page.getByRole('button', { name: en('tpl.saveAs') }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel(en('name.en')).fill('Push / Pull');
    await dialog.getByLabel(en('name.ar')).fill('دفع وسحب');
    await dialog.getByRole('button', { name: en('name.save') }).click();
    await expect(page.getByText(en('tpl.saved', { name: 'Push / Pull' }))).toBeVisible();
    expect(mock.templates).toHaveLength(1);
    expect(mock.templates[0]?.body).toEqual(samplePlan());
    const insert = mock.requests.find((r) => r.path === '/rest/v1/plan_templates' && r.method === 'POST');
    expect(Object.keys(insert?.body as object).sort()).toEqual(['body', 'gym_id', 'name']);

    if (isPhone(page)) await page.goto(TEMPLATES);
    else await page.getByRole('navigation', { name: en('app.mainNav') }).getByRole('link', { name: en('nav.templates') }).click();
    await expect(page.getByRole('heading', { level: 1, name: en('tpl.title') })).toBeVisible();
    await expect(page.getByText(en('tpl.summary', { days: 2, exercises: 4 }))).toBeVisible();
    await page.getByRole('button', { name: en('tpl.renameName', { name: 'Push / Pull' }) }).click();
    await dialog.getByLabel(en('name.en')).fill('Upper body');
    await dialog.getByRole('button', { name: en('name.save') }).click();
    await expect(page.getByText(en('tpl.renamed'))).toBeVisible();
    await expect(page.getByText('Upper body', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: en('tpl.deleteName', { name: 'Upper body' }) }).click();
    await dialog.getByRole('button', { name: en('tpl.delete') }).click();
    await expect(page.getByText(en('tpl.deleted'))).toBeVisible();
    await expect(page.getByRole('heading', { name: en('tpl.emptyTitle') })).toBeVisible();
    expect(mock.templates).toHaveLength(0);
  });

  test('replace a member\'s plan with a template; see changes; Reset one', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.youssef), templates: [tpl()] });
    await expect(page.getByRole('heading', { name: en('plan.emptyTitle') })).toBeVisible();
    await page.getByRole('button', { name: en('tpl.replace') }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText(en('tpl.replaceBody', { name: 'Youssef Khaled' }))).toBeVisible();
    await dialog.getByRole('button', { name: en('tpl.replaceGo') }).click();
    await expect(page.getByText(en('tpl.replaced', { name: 'Youssef Khaled', template: 'Push / Pull' }))).toBeVisible();
    expect(mock.rpcs.find((r) => r.name === 'apply_plan_template')?.body).toEqual({ p_membership_id: M.youssef, p_template_id: TPL, p_base_version: 0 });
    await expect(page.getByText(en('tpl.changesNone', { name: 'Youssef Khaled' }))).toBeVisible();

    // A change for this member shows against the template, and Reset undoes it.
    const sets = page.getByLabel(en('plan.setsFor', { name: 'Abs' }));
    await sets.fill('5');
    await sets.press('Enter');
    await expect(page.getByText(en('tpl.changesOne', { name: 'Youssef Khaled' }))).toBeVisible();
    await expect(page.getByRole('row').filter({ hasText: 'Abs' })).toContainText(en('tpl.templateValue', { value: en('tpl.values', { sets: 3, reps: 15, rest: 90 }) }));
    await page.getByRole('button', { name: en('tpl.resetName', { name: 'Abs' }) }).click();
    await expect(page.getByText(en('tpl.changesNone', { name: 'Youssef Khaled' }))).toBeVisible();
    await expect(page.getByLabel(en('plan.setsFor', { name: 'Abs' }))).toHaveValue('3');
    await expect(page.getByRole('button', { name: en('plan.save') })).toBeDisabled();
  });

  test('apply a change to everyone on the template: one save_plan each, and the template', async ({ page }) => {
    const mock = await open(page, {
      path: planPath(M.ahmed),
      templates: [tpl()],
      plans: { [M.ahmed]: linked(2), [M.mona]: linked(4), [M.youssef]: linked(1, { body: { days: [{ id: 'day-9', name: { ar: 'ا', en: 'A' }, exercises: [] }] } }) },
    });
    const sets = page.getByLabel(en('plan.setsFor', { name: 'Abs' }));
    await sets.fill('5');
    await sets.press('Enter');
    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByText(en('plan.saved', { name: 'Ahmed Hassan' }))).toBeVisible();

    await page.getByRole('button', { name: en('tpl.applyAll') }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText('Mona Ali')).toBeVisible();
    await expect(dialog.getByText('Youssef Khaled')).toBeVisible();
    await expect(dialog.getByText('Ahmed Hassan')).toHaveCount(0);
    await dialog.getByRole('button', { name: en('tpl.applyGo', { count: 2 }) }).click();
    await expect(dialog.getByText(en('tpl.applyDone', { ok: 1, total: 2 }))).toBeVisible();
    await expect(dialog.getByText(en('tpl.applyMissing'))).toBeVisible();
    expect(setsOf(mock.plans[M.mona]?.body, 'abs')).toBe(5);
    expect(mock.plans[M.mona]?.version).toBe(5);
    expect(mock.plans[M.youssef]?.version).toBe(1);
    // The template itself was changed too (its version grew).
    expect(setsOf(mock.templates[0]?.body, 'abs')).toBe(5);
    expect(mock.templates[0]?.version).toBe(2);
  });

  test('a plan whose template was deleted says so; before migration 0019 everything still works', async ({ page }) => {
    await open(page, { path: planPath(M.ahmed), templates: [tpl({ id: 'f0000000-0000-4000-8000-00000000000b' })], plans: { [M.ahmed]: linked(2) } });
    await expect(page.getByText(en('tpl.gone'))).toBeVisible();

    const old = await open(page, { path: planPath(M.ahmed), noTemplates: true, plans: { [M.ahmed]: { body: samplePlan(), version: 2, updated_by: null, updated_at: '2026-11-09T10:00:00Z' } } });
    await expect(page.getByRole('heading', { level: 1, name: en('plan.title', { name: 'Ahmed Hassan' }) })).toBeVisible();
    await expect(page.getByRole('alert')).toHaveCount(0);
    await page.goto(TEMPLATES);
    await expect(page.getByRole('heading', { name: en('tpl.emptyTitle') })).toBeVisible();
    expect(old.rpcs).toEqual([]);
  });

  test('a stale base version: plan_changed, nothing replaced', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.ahmed), templates: [tpl()], plans: { [M.ahmed]: { body: samplePlan(), version: 2, updated_by: null, updated_at: '2026-11-09T10:00:00Z' } } });
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    mock.plans[M.ahmed] = { body: samplePlan(), version: 3, updated_by: M.captain, updated_at: '2026-11-10T10:00:00Z' };
    await page.getByRole('button', { name: en('tpl.replace') }).click();
    await page.getByRole('dialog').getByRole('button', { name: en('tpl.replaceGo') }).click();
    await expect(page.getByRole('alert').filter({ hasText: en('conflict.title') })).toBeVisible();
    expect(mock.plans[M.ahmed]?.template_id).toBeUndefined();
  });
});
