import { CLOUDINARY, GYM_A, M, SUPABASE, expect, samplePlan, test, type FakePlan } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { memberPath, open } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const planPath = (id: string) => `${memberPath(id)}/plan`;
const at = (version: number, body: unknown = samplePlan()): FakePlan => ({ body, version, updated_by: M.captain, updated_at: '2026-11-09T10:00:00Z' });
const PAYLOAD = '<img src=x onerror=alert(1)>';
// Built so no raw control or direction character sits in the source.
const RLO = String.fromCharCode(0x202e);
const NUL = String.fromCharCode(0);
type Body = { days: { name: { ar: string; en: string }; exercises: { id: string; name: { ar: string; en: string } }[] }[] };

test.describe('crafted URLs', () => {
  for (const id of ['not-a-uuid', '..%2F..%2Fplans', "x'%20or%201=1", '%3Cscript%3E', M.ahmed.toUpperCase()]) {
    test(`member id "${id}" in the plan URL is not found, nothing asked`, async ({ page }) => {
      const mock = await open(page, { path: `/g/${GYM_A.id}/members/${id}/plan` });
      await expect(page.getByRole('heading', { name: en('state.notFoundTitle') })).toBeVisible();
      expect(mock.requests.some((r) => r.path.includes('plans') || r.path.includes('save_plan'))).toBe(false);
    });
  }

  test('a member id of no one in this gym: not found, and nothing is saved', async ({ page }) => {
    const mock = await open(page, { path: planPath('aaaaaaaa-0000-4000-8000-000000009999') });
    await expect(page.getByRole('heading', { name: en('member.notFoundTitle') })).toBeVisible();
    expect(mock.rpcs).toEqual([]);
  });
});

test.describe('hostile names', () => {
  test('typed names: cleaned, 40 characters at most, stored as text', async ({ page }) => {
    const dialogs: string[] = [];
    page.on('dialog', (d) => {
      dialogs.push(d.message());
      void d.dismiss();
    });
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(1) } });
    await page.getByRole('button', { name: en('plan.addExercise') }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: en('pick.own') }).click();
    // 41 characters cannot be added.
    await dialog.getByLabel(en('name.en')).fill('x'.repeat(41));
    await expect(dialog.getByText(en('name.tooLong'), { exact: true })).toBeVisible();
    await expect(dialog.getByRole('button', { name: en('pick.addOwn') })).toBeDisabled();
    // Injection-like text and hidden characters.
    await dialog.getByLabel(en('name.en')).fill(`  ${PAYLOAD}${RLO}\n${NUL}  `);
    await dialog.getByLabel(en('name.ar')).fill("'; DROP TABLE plans; --");
    await dialog.getByRole('button', { name: en('pick.addOwn') }).click();
    await expect(page.getByRole('row').filter({ hasText: PAYLOAD })).toBeVisible();
    await expect(page.locator('main img')).toHaveCount(0);
    await expect(page.locator('main [onerror]')).toHaveCount(0);

    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByText(en('plan.saved', { name: 'Ahmed Hassan' }))).toBeVisible();
    const body = mock.rpcs.at(-1)?.body.p_body as Body;
    const own = body.days[0]?.exercises.at(-1);
    expect(own?.name).toEqual({ ar: "'; DROP TABLE plans; --", en: PAYLOAD });
    // No control or direction-override character reaches the server.
    expect(Array.from(JSON.stringify(body)).some((c) => { const n = c.charCodeAt(0); return n < 0x20 || (n >= 0x202a && n <= 0x202e) || (n >= 0x2066 && n <= 0x2069); })).toBe(false);
    expect(dialogs).toEqual([]);
  });

  test('a stored plan with hostile names renders as text; a malformed one is not editable', async ({ page }) => {
    const hostile = samplePlan() as Body;
    if (hostile.days[0]) hostile.days[0].name = { ar: PAYLOAD, en: PAYLOAD };
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(2, hostile), [M.mona]: at(1, { days: [{ id: 'd', name: { ar: 'a', en: 'a' }, exercises: [], evil: true }] }) } });
    await expect(page.getByRole('heading', { level: 2, name: PAYLOAD })).toBeVisible();
    await expect(page.locator('main img')).toHaveCount(0);
    await page.goto(planPath(M.mona));
    await expect(page.getByRole('heading', { name: en('plan.unreadableTitle') })).toBeVisible();
    await expect(page.getByRole('button', { name: en('plan.save') })).toHaveCount(0);
    expect(mock.rpcs).toEqual([]);
  });

  test('numbers outside the limits are clamped before they are saved', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(1) } });
    for (const [key, value] of [['plan.setsFor', '999'], ['plan.repsFor', '-5']] as const) {
      const input = page.getByLabel(en(key, { name: 'Abs' }));
      await input.fill(value);
      await input.press('Enter');
    }
    await page.getByRole('button', { name: en('plan.save') }).click();
    await expect(page.getByText(en('plan.saved', { name: 'Ahmed Hassan' }))).toBeVisible();
    const abs = (mock.rpcs.at(-1)?.body.p_body as { days: { exercises: { id: string; sets: number; reps: number }[] }[] }).days[0]?.exercises.find((e) => e.id === 'abs');
    expect(abs).toMatchObject({ sets: 10, reps: 1 });
  });
});

test.describe('nothing leaves, nothing is kept', () => {
  test('every request goes to this site, the project or the picture path', async ({ page }) => {
    const origins = new Set<string>();
    page.on('request', (r) => {
      const u = new URL(r.url());
      if (u.protocol === 'http:' || u.protocol === 'https:') origins.add(u.origin);
    });
    await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(1) }, pictures: [{ gym_id: GYM_A.id, exercise_id: 'abs', public_id: 'exercises/ek-0055-tension', position: 1 }] });
    await page.getByRole('button', { name: en('plan.copy') }).click();
    await page.getByRole('dialog').getByLabel(en('copy.select', { name: 'Mona Ali' })).check();
    await page.getByRole('dialog').getByRole('button', { name: en('copy.goOne') }).click();
    await expect(page.getByRole('dialog').getByText(en('copy.done', { ok: 1, total: 1 }))).toBeVisible();
    for (const o of origins) expect(['http://localhost:4173', SUPABASE, CLOUDINARY]).toContain(o);
  });

  test('no plan, name or draft is kept in the browser', async ({ page }) => {
    await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: at(1) } });
    await page.getByLabel(en('plan.setsFor', { name: 'Abs' })).fill('7');
    await page.getByLabel(en('plan.setsFor', { name: 'Abs' })).press('Enter');
    const stored = await page.evaluate(() => JSON.stringify(Object.entries(localStorage)) + JSON.stringify(Object.entries(sessionStorage)) + document.cookie + location.href);
    expect(stored).not.toContain('Flat Dumbbell');
    expect(stored).not.toContain('day-1');
    expect((await page.evaluate(() => Object.keys(localStorage))).sort()).toEqual(['azm.dashboard.prefs.v1', 'sb-abcdefghijklmnopqrst-auth-token']);
  });
});
