import AxeBuilder from '@axe-core/playwright';
import type { Locator, Page } from '@playwright/test';
import { GYM_A, GYM_B, expect, test } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';
import { open, type OpenOptions } from './fixtures/members';

// D6 gym brand colour (docs/designs/gym_brand_colours.md): the owner picks a
// colour, sees what the app makes of it and a phone preview, saves or resets.

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const SETTINGS = `/g/${GYM_A.id}/settings`;
const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];

const panel = (page: Page, lang: Lang = 'en') => page.getByRole('region', { name: msg(lang, 'brand.title') });
const cssVar = (el: Locator, name: string) => el.evaluate((node, n) => getComputedStyle(node).getPropertyValue(n).trim(), name);
const brandWrites = (mock: { requests: { path: string; method: string }[] }) => mock.requests.filter((r) => r.path === '/rest/v1/gyms' && r.method === 'PATCH').length;

test.describe('brand colour', () => {
  test('pick a colour: the samples, the numbers and the preview follow; save and reset', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    const p = panel(page);
    await expect(p).toBeVisible();
    // No colour yet: Azm's, and nothing to save or reset.
    await expect(p.getByText(en('brand.azmNote'))).toBeVisible();
    expect(await cssVar(p.getByTestId('preview-dark'), '--b-brand')).toBe('#22c55e');
    await expect(p.getByRole('button', { name: en('brand.save') })).toBeDisabled();
    await expect(p.getByRole('button', { name: en('brand.reset') })).toBeDisabled();

    // Yellow: as picked in dark, darker in light so it shows.
    await p.getByRole('button', { name: `${en('brand.yellow')} #FACC15` }).click();
    await expect(p.getByLabel(en('brand.code'))).toHaveValue('#FACC15');
    expect(await cssVar(p.getByTestId('preview-dark'), '--b-brand')).toBe('#facc15');
    expect(await cssVar(p.getByTestId('preview-light'), '--b-brand')).toBe('#a8890e');
    expect(await cssVar(p.getByTestId('preview-light'), '--b-on')).toBe('#000000');
    await expect(p.getByTestId('sample-light')).toContainText(en('brand.darker', { percent: 33 }));
    await expect(p.getByTestId('sample-dark')).toContainText(en('brand.asPicked'));
    await expect(p.getByRole('row').filter({ hasText: en('brand.checkFill') })).toContainText('3.0:1');
    await expect(p.getByRole('row').filter({ hasText: en('brand.checkOn') })).toContainText('6.2:1');

    // The preview has three screens.
    await p.getByRole('button', { name: en('brand.pvWorkout') }).click();
    await expect(p.getByRole('button', { name: en('brand.pvWorkout') })).toHaveAttribute('aria-pressed', 'true');
    await p.getByRole('button', { name: en('brand.pvSheet') }).click();
    await expect(p.getByRole('img', { name: en('brand.pvAlt', { mode: en('brand.light') }) })).toBeVisible();

    await p.getByRole('button', { name: en('brand.save') }).click();
    await expect(p.getByRole('status')).toContainText(en('brand.saved'));
    expect(mock.gymRows[GYM_A.id]?.brand_color).toBe('#facc15');
    await expect(p.getByRole('button', { name: en('brand.save') })).toBeDisabled();

    await p.getByRole('button', { name: en('brand.reset') }).click();
    await expect(p.getByRole('status')).toContainText(en('brand.resetDone'));
    expect(mock.gymRows[GYM_A.id]?.brand_color).toBeNull();
    await expect(p.getByLabel(en('brand.code'))).toHaveValue('');
    expect(await cssVar(p.getByTestId('preview-light'), '--b-brand')).toBe('#22c55e');
  });

  test('a saved colour is shown when the page opens; typing in any case works', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'owner', brandColor: '#1e3a8a' }] });
    const p = panel(page);
    await expect(p.getByLabel(en('brand.code'))).toHaveValue('#1E3A8A');
    expect(await cssVar(p.getByTestId('preview-light'), '--b-brand')).toBe('#1e3a8a');
    expect(await cssVar(p.getByTestId('preview-dark'), '--b-brand')).toBe('#5065a4');
    await p.getByLabel(en('brand.code')).fill('  #dc2626 ');
    await expect(p.getByRole('note')).toContainText(en('brand.nearRed'));
    await p.getByRole('button', { name: en('brand.save') }).click();
    await expect(p.getByRole('status')).toContainText(en('brand.saved'));
    expect(mock.gymRows[GYM_A.id]?.brand_color).toBe('#dc2626');
  });

  test('from the keyboard only: type a code and save', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    const code = panel(page).getByLabel(en('brand.code'));
    await code.focus();
    await page.keyboard.type('#6D28D9');
    await panel(page).getByRole('button', { name: en('brand.save') }).focus();
    await page.keyboard.press('Enter');
    await expect(panel(page).getByRole('status')).toContainText(en('brand.saved'));
    expect(mock.gymRows[GYM_A.id]?.brand_color).toBe('#6d28d9');
  });

  test('a captain sees the colour and the preview read-only: no field, no button, no request that writes', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'captain', brandColor: '#facc15' }] });
    const p = panel(page);
    await expect(p.getByText('#FACC15', { exact: true }).first()).toBeVisible();
    await expect(p.getByText(en('brand.bodyCaptain'))).toBeVisible();
    expect(await cssVar(p.getByTestId('preview-dark'), '--b-brand')).toBe('#facc15');
    await expect(p.getByRole('textbox')).toHaveCount(0);
    await expect(p.locator('input[type="color"]')).toHaveCount(0);
    await expect(p.getByRole('button', { name: en('brand.save') })).toHaveCount(0);
    await expect(p.getByRole('button', { name: en('brand.reset') })).toHaveCount(0);
    expect(brandWrites(mock)).toBe(0);
  });

  test('offline: nothing can be picked or saved', async ({ page, context }) => {
    await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'owner', brandColor: '#facc15' }] });
    const p = panel(page);
    await expect(p.getByLabel(en('brand.code'))).toBeEnabled();
    await context.setOffline(true);
    await expect(p.getByLabel(en('brand.code'))).toBeDisabled();
    await expect(p.getByRole('button', { name: en('brand.reset') })).toBeDisabled();
    await context.setOffline(false);
    await expect(p.getByLabel(en('brand.code'))).toBeEnabled();
  });
});

test.describe('brand colour: security', () => {
  test('hostile codes: never saved, never asked, shown as text only', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    const p = panel(page);
    const code = p.getByLabel(en('brand.code'));
    const save = p.getByRole('button', { name: en('brand.save') });
    for (const bad of ['red', '#FFF', '#GGGGGG', '#FACC155', 'rgb(1,2,3)', "#facc15'; drop table gyms;--", '<img src=x onerror=alert(1)>', '{"brand_color":"#facc15","is_demo":true}', '#٢٢c55e']) {
      await code.fill(bad);
      await expect(p.getByText(en('brand.errFormat'), { exact: true })).toBeVisible();
      await expect(save).toBeDisabled();
      // The preview falls back to Azm's colours, like the app does.
      expect(await cssVar(p.getByTestId('preview-light'), '--b-brand')).toBe('#22c55e');
    }
    for (const grey of ['#000000', '#FFFFFF', '#808080']) {
      await code.fill(grey);
      await expect(p.getByText(en('brand.errNoColour'))).toBeVisible();
      await expect(save).toBeDisabled();
    }
    // A very long paste is cut by the field and still refused.
    await code.fill('#facc15'.repeat(5000));
    expect((await code.inputValue()).length).toBeLessThanOrEqual(32);
    await expect(save).toBeDisabled();
    await expect(page.locator('img[src="x"]')).toHaveCount(0);
    expect(brandWrites(mock)).toBe(0);
    expect(mock.gymRows[GYM_A.id]?.brand_color).toBeNull();
  });

  test('the request carries only the colour, to this gym only', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    const p = panel(page);
    const sent: { url: string; body: string }[] = [];
    page.on('request', (r) => { if (r.method() === 'PATCH' && r.url().includes('/rest/v1/gyms')) sent.push({ url: r.url(), body: r.postData() ?? '' }); });
    await p.getByLabel(en('brand.code')).fill('#06B6D4');
    await p.getByRole('button', { name: en('brand.save') }).click();
    await expect(p.getByRole('status')).toContainText(en('brand.saved'));
    expect(sent).toHaveLength(1);
    expect(JSON.parse(sent[0]?.body ?? '{}')).toEqual({ brand_color: '#06b6d4' });
    expect(sent[0]?.url).toContain(`id=eq.${GYM_A.id}`);
    expect(mock.gymRows[GYM_B.id]?.brand_color ?? null).toBeNull();
  });

  test("another gym's id in the URL: forbidden, and nothing is written", async ({ page }) => {
    const mock = await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'owner' }] });
    await expect(panel(page)).toBeVisible();
    await page.goto(`/g/${GYM_B.id}/settings`);
    await expect(page.getByRole('heading', { name: en('state.forbiddenTitle') })).toBeVisible();
    await expect(panel(page)).toHaveCount(0);
    expect(brandWrites(mock)).toBe(0);
  });

  test('the server refusing (not the owner any more): says so, and keeps the saved colour', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'owner', brandColor: '#facc15' }] });
    const p = panel(page);
    await expect(p.getByLabel(en('brand.code'))).toHaveValue('#FACC15');
    // Someone removed the gym on the server: RLS answers with no row.
    Reflect.deleteProperty(mock.gymRows, GYM_A.id);
    await p.getByLabel(en('brand.code')).fill('#1E3A8A');
    await p.getByRole('button', { name: en('brand.save') }).click();
    await expect(p.getByRole('alert')).toContainText(en('set.errForbidden'));
  });

  test('colours reach the page without a style attribute (the CSP is unchanged)', async ({ page }) => {
    await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'owner', brandColor: '#facc15' }] });
    await expect(panel(page)).toBeVisible();
    const violations: string[] = [];
    page.on('console', (m) => { if (/Content Security Policy/i.test(m.text())) violations.push(m.text()); });
    await panel(page).getByRole('button', { name: `${en('brand.navy')} #1E3A8A` }).click();
    expect(await cssVar(panel(page).getByTestId('preview-dark'), '--b-brand')).toBe('#5065a4');
    expect(violations).toEqual([]);
  });
});

const looks: { lang: Lang; theme: Theme }[] = [
  { lang: 'en', theme: 'light' },
  { lang: 'ar', theme: 'dark' },
];
const states: { name: string; gyms: NonNullable<OpenOptions['gyms']>; ready: (page: Page, lang: Lang) => Promise<void> }[] = [
  { name: 'no colour', gyms: [{ ...GYM_A, role: 'owner' }], ready: async () => {} },
  { name: 'a light colour', gyms: [{ ...GYM_A, role: 'owner', brandColor: '#facc15' }], ready: async () => {} },
  { name: 'a dark colour near red, sheet preview', gyms: [{ ...GYM_A, role: 'owner', brandColor: '#7f1d1d' }], ready: async (page, lang) => { await panel(page, lang).getByRole('button', { name: msg(lang, 'brand.pvSheet') }).click(); } },
  { name: 'an invalid code', gyms: [{ ...GYM_A, role: 'owner' }], ready: async (page, lang) => { await panel(page, lang).getByLabel(msg(lang, 'brand.code')).fill('#12'); await expect(panel(page, lang).getByText(msg(lang, 'brand.errFormat'), { exact: true })).toBeVisible(); } },
  { name: 'a captain (read-only)', gyms: [{ ...GYM_A, role: 'captain', brandColor: '#1e3a8a' }], ready: async () => {} },
];
for (const state of states) {
  for (const { lang, theme } of looks) {
    test(`axe: brand colour, ${state.name} (${lang} ${theme})`, async ({ page }) => {
      await open(page, { path: SETTINGS, gyms: state.gyms, lang, theme });
      await expect(panel(page, lang)).toBeVisible();
      await state.ready(page, lang);
      const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
      expect(results.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
    });
  }
}

test('Arabic: right to left, the code stays left to right, no page overflow on a phone', async ({ page }) => {
  await open(page, { path: SETTINGS, gyms: [{ ...GYM_A, role: 'owner', brandColor: '#facc15' }], lang: 'ar', theme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  const p = panel(page, 'ar');
  await expect(p.getByLabel(msg('ar', 'brand.code'))).toHaveAttribute('dir', 'ltr');
  await expect(p.getByTestId('sample-light')).toContainText(msg('ar', 'brand.darker', { percent: 33 }));
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
});
