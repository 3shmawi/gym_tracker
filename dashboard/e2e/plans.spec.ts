import type { Page } from '@playwright/test';
import { M, expect, samplePlan, test, type FakePlan } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { memberPath, open } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
export const planPath = (id: string) => `${memberPath(id)}/plan`;
const at = (version: number, body: unknown = samplePlan()): FakePlan => ({ body, version, updated_by: M.captain, updated_at: '2026-11-09T10:00:00Z' });

type Body = { days: { id: string; name: { ar: string; en: string }; exercises: { id: string; name: { en: string }; sets: number; superset: boolean; unit?: string }[] }[] };
const lastSave = (mock: { rpcs: { name: string; body: Record<string, unknown> }[] }) => mock.rpcs.filter((r) => r.name === 'save_plan').at(-1)?.body;
const row = (page: Page, name: string) => page.getByRole('row').filter({ hasText: name });

test.describe('a member\'s plan', () => {
  test('open from the member page, edit, save (only through save_plan)', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.ahmed), plans: { [M.ahmed]: at(3) } });
    await page.getByRole('link', { name: en('member.openPlan') }).click();
    await expect(page.getByRole('heading', { level: 1, name: en('plan.title', { name: 'Ahmed Hassan' }) })).toBeVisible();
    await expect(page.getByText(en('plan.summary', { days: 2, exercises: 4 }))).toBeVisible();
    await expect(page.getByText(new RegExp(en('plan.changedBy', { name: 'Omar Captain', date: 'X' }).split('X')[0] ?? 'x'))).toBeVisible();

    // Targets in place: 3 → 4 sets.
    const sets = page.getByLabel(en('plan.setsFor', { name: 'Flat Dumbbell Press' }));
    await sets.fill('4');
    await sets.press('Enter');
    await expect(page.getByText(en('plan.unsaved'))).toBeVisible();

    // A library exercise keeps the library id and its starting targets.
    await page.getByRole('button', { name: en('plan.addExercise') }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel(en('pick.search')).fill('squat');
    await dialog.getByRole('button', { name: en('pick.addName', { name: 'Barbell Back Squat' }) }).click();
    await expect(row(page, 'Barbell Back Squat')).toBeVisible();

    // One written by hand gets a new ex-… id.
    await page.getByRole('button', { name: en('plan.addExercise') }).click();
    await dialog.getByRole('button', { name: en('pick.own') }).click();
    await dialog.getByLabel(en('name.en')).fill('Cable Fly');
    await dialog.getByRole('button', { name: en('pick.addOwn') }).click();
    await expect(row(page, 'Cable Fly')).toContainText(en('plan.ownExercise'));

    // Move it up, pair it with the next, rename the day.
    await page.getByRole('button', { name: en('plan.exEarlier', { name: 'Cable Fly' }) }).click();
    await page.getByLabel(en('plan.supersetFor', { name: 'Cable Fly' })).check();
    await page.getByRole('button', { name: en('plan.renameDay') }).click();
    await dialog.getByLabel(en('name.en')).fill('Push day');
    await dialog.getByLabel(en('name.ar')).fill('يوم دفع');
    await dialog.getByRole('button', { name: en('name.save') }).click();

    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByText(en('plan.saved', { name: 'Ahmed Hassan' }))).toBeVisible();

    const sent = lastSave(mock);
    expect(sent?.p_membership_id).toBe(M.ahmed);
    expect(sent?.p_base_version).toBe(3);
    const body = sent?.p_body as Body;
    const day = body.days[0];
    expect(day?.name).toEqual({ ar: 'يوم دفع', en: 'Push day' });
    expect(day?.exercises.map((e) => e.id).slice(0, 3)).toEqual(['flat_db_press', 'pec_deck', 'abs']);
    expect(day?.exercises[0]?.sets).toBe(4);
    const squat = day?.exercises.find((e) => e.id === 'barbell_squat');
    expect(squat).toMatchObject({ sets: 3, reps: 12, rest: 120, step: 5, superset: false });
    const own = day?.exercises.find((e) => e.name.en === 'Cable Fly');
    expect(own?.id).toMatch(/^ex-[a-z0-9]{1,20}$/);
    expect(own?.superset).toBe(true);
    // The plate exercise keeps its unit; kg exercises carry no unit key.
    expect(body.days[1]?.exercises[0]?.unit).toBe('plate');
    expect(JSON.stringify(body)).not.toContain('"unit":"kg"');
    // Nothing was written to the plans table directly.
    expect(mock.requests.some((r) => r.path === '/rest/v1/plans' && r.method !== 'GET')).toBe(false);
    expect(mock.plans[M.ahmed]?.version).toBe(4);
  });

  test('someone saved meanwhile: show what changed, load the newest, redo', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(3) } });
    const reps = page.getByLabel(en('plan.repsFor', { name: 'Abs' }));
    await reps.fill('20');
    await reps.press('Enter');

    // Another captain (or the member) saves first.
    const theirs = samplePlan() as Body;
    if (theirs.days[1]) theirs.days[1].name = { ar: 'رجلين', en: 'Leg day' };
    mock.plans[M.ahmed] = at(4, theirs);

    await page.getByRole('button', { name: en('plan.save') }).click();
    const panel = page.getByRole('alert').filter({ hasText: en('conflict.title') });
    await expect(panel).toBeVisible();
    await expect(panel).toContainText(en('diff.dayRenamed', { from: 'Legs', to: 'Leg day' }));
    await expect(panel).toContainText(en('diff.targets', { day: 'Chest & Back', exercise: 'Abs', fields: en('diff.f.reps') }));
    expect(mock.rpcs.filter((r) => r.name === 'save_plan')).toHaveLength(0);

    await panel.getByRole('button', { name: en('conflict.load') }).click();
    await expect(page.getByRole('button', { name: /Leg day/ })).toBeVisible();
    await expect(page.getByLabel(en('plan.repsFor', { name: 'Abs' }))).toHaveValue('15');
    // Redo the change on the newest version.
    await page.getByLabel(en('plan.repsFor', { name: 'Abs' })).fill('20');
    await page.getByLabel(en('plan.repsFor', { name: 'Abs' })).press('Enter');
    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByText(en('plan.saved', { name: 'Ahmed Hassan' }))).toBeVisible();
    expect(lastSave(mock)?.p_base_version).toBe(4);
  });

  test('copy a plan to two members: warning, one save_plan each, retry the failed', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(3), [M.mona]: at(1, { days: [{ id: 'day-x', name: { ar: 'ا', en: 'A' }, exercises: [] }] }) } });
    await page.getByRole('button', { name: en('plan.copy') }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: en('copy.title', { name: 'Ahmed Hassan' }) })).toBeVisible();
    // Ended members are not offered.
    await expect(dialog.getByText('Hana Adel')).toHaveCount(0);
    await expect(dialog.locator('label').filter({ hasText: 'Mona Ali' })).toContainText(en('copy.hasPlan'));
    await expect(dialog.locator('label').filter({ hasText: 'Youssef Khaled' })).toContainText(en('copy.noPlan'));
    await dialog.getByLabel(en('copy.select', { name: 'Mona Ali' })).check();
    await dialog.getByLabel(en('copy.select', { name: 'Youssef Khaled' })).check();
    await expect(dialog.getByText(en('copy.replaceOne'))).toBeVisible();

    mock.set({ savePlan: 'server_error' });
    await dialog.getByRole('button', { name: en('copy.goMany', { count: 2 }) }).click();
    await expect(dialog.getByText(en('copy.done', { ok: 0, total: 2 }))).toBeVisible();
    await expect(dialog.getByText(en('copy.failed', { why: en('plan.errServer') }))).toHaveCount(2);

    mock.set({ savePlan: 'ok' });
    await dialog.getByRole('button', { name: en('copy.retry', { count: 2 }) }).click();
    await expect(dialog.getByText(en('copy.done', { ok: 2, total: 2 }))).toBeVisible();
    // Each got an independent copy of the same body, ids unchanged.
    expect(mock.plans[M.mona]?.body).toEqual(samplePlan());
    expect(mock.plans[M.youssef]?.body).toEqual(samplePlan());
    expect(mock.plans[M.mona]?.version).toBe(2);
    expect(mock.plans[M.youssef]?.version).toBe(1);
    const saves = mock.rpcs.filter((r) => r.name === 'save_plan' && r.body.p_membership_id === M.youssef);
    expect(saves.at(-1)?.body.p_base_version).toBe(0);
    await dialog.getByRole('button', { name: en('copy.close') }).click();
    await expect(dialog).toHaveCount(0);
  });

  test('no plan yet: start one, add an exercise, save as the first version', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.youssef) });
    await expect(page.getByRole('heading', { name: en('plan.emptyTitle') })).toBeVisible();
    await page.getByRole('button', { name: en('plan.start') }).click();
    await page.getByRole('button', { name: en('plan.addExercise') }).click();
    await page.getByRole('dialog').getByLabel(en('pick.search')).fill('abs');
    await page.getByRole('dialog').getByRole('button', { name: en('pick.addName', { name: 'Abs' }) }).click();
    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByText(en('plan.saved', { name: 'Youssef Khaled' }))).toBeVisible();
    expect(lastSave(mock)?.p_base_version).toBe(0);
    expect((lastSave(mock)?.p_body as Body).days[0]?.name).toEqual({ ar: 'اليوم ١', en: 'Day 1' });
  });

  test('states: error with retry, refused save, offline, leave warning', async ({ page, context }) => {
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(3) }, plansFail: true });
    await expect(page.getByRole('heading', { name: en('state.errorTitle') })).toBeVisible();
    mock.set({ plansFail: false });
    await page.getByRole('button', { name: en('state.retry') }).click();
    await expect(page.getByRole('heading', { level: 1, name: en('plan.title', { name: 'Ahmed Hassan' }) })).toBeVisible();

    mock.set({ savePlan: 'forbidden' });
    await page.getByLabel(en('plan.setsFor', { name: 'Abs' })).fill('5');
    await page.getByLabel(en('plan.setsFor', { name: 'Abs' })).press('Enter');
    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByRole('alert').filter({ hasText: en('plan.errForbidden') })).toBeVisible();
    await expect(page.getByLabel(en('plan.setsFor', { name: 'Abs' }))).toHaveValue('5');

    await context.setOffline(true);
    await expect(page.getByRole('button', { name: en('plan.save') })).toBeDisabled();
    await expect(page.getByText(en('plan.offlineHint'))).toBeVisible();
    await context.setOffline(false);

    page.once('dialog', (d) => {
      expect(d.message()).toBe(en('plan.leave'));
      void d.dismiss();
    });
    await page.getByRole('link', { name: en('plan.back', { name: 'Ahmed Hassan' }) }).click();
    await expect(page).toHaveURL(planPath(M.ahmed));
  });

  test('a captain can open trainees\' plans, not another captain\'s or the owner\'s', async ({ page }) => {
    await open(page, { gyms: [{ id: '33333333-3333-4333-8333-333333333333', name: 'Power Gym', role: 'captain' }], path: memberPath(M.owner) });
    await expect(page.getByRole('heading', { level: 1, name: 'Sara Owner' })).toBeVisible();
    await expect(page.getByRole('link', { name: en('member.openPlan') })).toHaveCount(0);
    await page.goto(memberPath(M.ahmed));
    await expect(page.getByRole('link', { name: en('member.openPlan') })).toBeVisible();
  });
});
