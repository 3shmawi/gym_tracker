import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { CLOUDINARY, GYM_A, GYM_B, M, SUPABASE, expect, samplePlan, test } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';
import { memberPath, MEMBERS_PATH, open, type OpenOptions } from './fixtures/members';
import { ahmedProgress } from './fixtures/progress';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const SETTINGS = `/g/${GYM_A.id}/settings`;
const plans = { [M.ahmed]: { body: samplePlan(), version: 2, updated_by: null, updated_at: '2026-11-09T10:00:00Z' } };

interface Screen {
  name: string;
  options: OpenOptions;
  ready: (page: Page, lang: Lang) => Promise<void>;
}

const screens: Screen[] = [
  {
    name: 'member progress with tables open',
    options: { path: memberPath(M.ahmed), progress: { [M.ahmed]: ahmedProgress() }, plans },
    ready: async (page, lang) => {
      const panel = page.getByRole('region', { name: msg(lang, 'prog.title', { gym: GYM_A.name }) });
      await expect(panel.getByLabel(msg(lang, 'prog.exPick'))).toBeVisible();
      for (const s of await panel.getByText(msg(lang, 'prog.showTable')).all()) await s.click();
    },
  },
  { name: 'member with no workouts', options: { path: memberPath(M.youssef) }, ready: async (page, lang) => { await expect(page.getByRole('heading', { name: msg(lang, 'prog.noneTitle') })).toBeVisible(); } },
  { name: 'ended member', options: { path: memberPath(M.hana) }, ready: async (page, lang) => { await expect(page.getByRole('heading', { name: msg(lang, 'prog.endedTitle') })).toBeVisible(); } },
  { name: 'members list with last workout', options: { path: MEMBERS_PATH, progress: { [M.ahmed]: ahmedProgress() } }, ready: async (page) => { await expect(page.getByText('Ahmed Hassan').filter({ visible: true }).first()).toBeVisible(); } },
  { name: 'settings', options: { path: SETTINGS }, ready: async (page, lang) => { await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'set.title') })).toBeVisible(); } },
  { name: 'settings for a captain (read-only)', options: { path: SETTINGS, gyms: [{ ...GYM_A, role: 'captain' }] }, ready: async (page, lang) => { await expect(page.getByRole('note')).toContainText(msg(lang, 'set.readOnly')); } },
  {
    name: 'settings with errors',
    options: { path: SETTINGS },
    ready: async (page, lang) => {
      await page.getByLabel(msg(lang, 'set.name')).fill('x'.repeat(61));
      await page.locator('#logo-file').setInputFiles({ name: 'x.png', mimeType: 'image/png', buffer: Buffer.from('nope') });
      await expect(page.getByRole('alert')).toBeVisible();
    },
  },
];

const looks: { lang: Lang; theme: Theme }[] = [
  { lang: 'en', theme: 'light' },
  { lang: 'ar', theme: 'dark' },
];

for (const screen of screens) {
  for (const { lang, theme } of looks) {
    test(`axe: ${screen.name} (${lang} ${theme})`, async ({ page }) => {
      await open(page, { ...screen.options, lang, theme });
      await screen.ready(page, lang);
      const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
      expect(results.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
    });
  }
}

test('Arabic: right to left, Western digits in progress', async ({ page }) => {
  await open(page, { path: memberPath(M.ahmed), progress: { [M.ahmed]: ahmedProgress() }, plans, lang: 'ar', theme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  const panel = page.getByRole('region', { name: msg('ar', 'prog.title', { gym: GYM_A.name }) });
  await expect(panel.getByText('38', { exact: true })).toBeVisible();
  expect(await panel.innerText()).not.toMatch(/[٠-٩]/);
});

test('settings from the keyboard only: rename and the history choice', async ({ page }) => {
  const mock = await open(page, { path: SETTINGS });
  const name = page.getByLabel(msg('en', 'set.name'));
  await name.focus();
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.type('Keyboard Gym');
  await page.keyboard.press('Enter');
  await expect(page.getByText(msg('en', 'set.nameSaved'))).toBeVisible();
  const readable = page.getByRole('radio', { name: new RegExp(msg('en', 'set.readable')) });
  await readable.focus();
  await page.keyboard.press('ArrowDown');
  await expect(page.getByText(msg('en', 'set.historySaved'), { exact: true })).toBeVisible();
  expect(mock.gymRows[GYM_A.id]).toMatchObject({ name: 'Keyboard Gym', history_after_end: 'locked' });
  // The logo button is reachable and opens the file picker from the keyboard.
  const chooser = page.waitForEvent('filechooser');
  await page.locator('#logo-file').focus();
  await page.keyboard.press('Space');
  expect(await chooser).toBeTruthy();
});

test.describe('security', () => {
  test('crafted ids in the URL: not found or forbidden, and nothing is asked', async ({ page }) => {
    const mock = await open(page, { path: `/g/${GYM_A.id}/members/not-a-uuid` });
    await expect(page.getByRole('heading', { name: msg('en', 'state.notFoundTitle') })).toBeVisible();
    await page.goto('/g/%27%20or%201=1/settings');
    await expect(page.getByRole('heading', { name: msg('en', 'state.notFoundTitle') })).toBeVisible();
    await page.goto(`/g/${GYM_B.id}/settings`); // a gym this person doesn't manage
    await expect(page.getByRole('heading', { name: msg('en', 'state.forbiddenTitle') })).toBeVisible();
    await page.goto(memberPath('aaaaaaaa-0000-4000-8000-000000009999'));
    await expect(page.getByRole('heading', { name: msg('en', 'member.notFoundTitle') })).toBeVisible();
    expect(mock.requests.some((r) => r.path.startsWith('/rest/v1/member_') || (r.path === '/rest/v1/gyms' && r.method === 'PATCH'))).toBe(false);
  });

  test('a captain sees trainees\' progress only (owner/captain rows never asked)', async ({ page }) => {
    const mock = await open(page, { gyms: [{ ...GYM_A, role: 'captain' }], path: memberPath(M.owner), progress: { [M.owner]: ahmedProgress() } });
    await expect(page.getByRole('heading', { level: 1, name: 'Sara Owner' })).toBeVisible();
    await expect(page.getByRole('region', { name: msg('en', 'prog.title', { gym: GYM_A.name }) })).toHaveCount(0);
    expect(mock.requests.some((r) => r.path.startsWith('/rest/v1/member_') && r.search.includes(M.owner))).toBe(false);
  });

  test('every request goes to this site, the project or the picture path; no token or code in storage or the URL', async ({ page }) => {
    const origins = new Set<string>();
    page.on('request', (r) => {
      const u = new URL(r.url());
      if (u.protocol === 'http:' || u.protocol === 'https:') origins.add(u.origin);
    });
    await open(page, { path: memberPath(M.ahmed), progress: { [M.ahmed]: ahmedProgress() }, plans });
    await expect(page.getByRole('region', { name: msg('en', 'prog.title', { gym: GYM_A.name }) })).toBeVisible();
    await page.goto(SETTINGS);
    await page.locator('#logo-file').setInputFiles({ name: 'logo.png', mimeType: 'image/png', buffer: (await import('node:fs')).readFileSync(new URL('../public/logo-96.png', import.meta.url)) });
    await expect(page.getByText(msg('en', 'set.logoSaved'))).toBeVisible();
    for (const o of origins) expect(['http://localhost:4173', SUPABASE, CLOUDINARY]).toContain(o);
    expect(page.url()).not.toMatch(/token|code|logo/i);
    const stored = await page.evaluate(() => Object.keys(localStorage).sort().join(',') + JSON.stringify(Object.entries(sessionStorage)) + document.cookie);
    expect(stored).toBe('azm.dashboard.prefs.v1,sb-abcdefghijklmnopqrst-auth-token[]');
  });
});
