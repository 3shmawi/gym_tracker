import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { M, expect, samplePlan, test, type FakePlan } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';
import { memberPath, open, type OpenOptions } from './fixtures/members';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const planPath = (id: string) => `${memberPath(id)}/plan`;
const at = (version: number): FakePlan => ({ body: samplePlan(), version, updated_by: M.captain, updated_at: '2026-11-09T10:00:00Z' });
const plans = { [M.ahmed]: at(3) };

interface Screen {
  name: string;
  options: OpenOptions;
  ready: (page: Page, lang: Lang) => Promise<void>;
}

const exName = (lang: Lang, en: string, ar: string) => (lang === 'ar' ? ar : en);

const screens: Screen[] = [
  {
    name: 'member page with the plan panel',
    options: { path: memberPath(M.ahmed), plans },
    ready: async (page, lang) => {
      await expect(page.getByRole('link', { name: msg(lang, 'member.openPlan') })).toBeVisible();
    },
  },
  {
    name: 'plan editor',
    options: { path: planPath(M.ahmed), plans },
    ready: async (page, lang) => {
      await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'plan.title', { name: 'Ahmed Hassan' }) })).toBeVisible();
      await page.getByLabel(msg(lang, 'plan.setsFor', { name: exName(lang, 'Abs', 'بطن') })).fill('4');
      await page.getByLabel(msg(lang, 'plan.setsFor', { name: exName(lang, 'Abs', 'بطن') })).press('Enter');
      await expect(page.getByText(msg(lang, 'plan.unsaved'))).toBeVisible();
    },
  },
  {
    name: 'no plan yet',
    options: { path: planPath(M.youssef) },
    ready: async (page, lang) => {
      await expect(page.getByRole('heading', { name: msg(lang, 'plan.emptyTitle') })).toBeVisible();
    },
  },
  {
    name: 'add-exercise dialog',
    options: { path: planPath(M.ahmed), plans },
    ready: async (page, lang) => {
      await page.getByRole('button', { name: msg(lang, 'plan.addExercise') }).click();
      await expect(page.getByRole('dialog')).toBeVisible();
    },
  },
  {
    name: 'name dialog',
    options: { path: planPath(M.ahmed), plans },
    ready: async (page, lang) => {
      await page.getByRole('button', { name: msg(lang, 'plan.renameDay') }).click();
      await page.getByRole('dialog').getByLabel(msg(lang, 'name.en')).fill('x'.repeat(41));
      await expect(page.getByRole('dialog').getByText(msg(lang, 'name.tooLong'), { exact: true })).toBeVisible();
    },
  },
  {
    name: 'copy dialog',
    options: { path: planPath(M.ahmed), plans },
    ready: async (page, lang) => {
      await page.getByRole('button', { name: msg(lang, 'plan.copy') }).click();
      await page.getByRole('dialog').getByLabel(msg(lang, 'copy.select', { name: 'Mona Ali' })).check();
    },
  },
  {
    name: 'conflict',
    options: { path: planPath(M.ahmed), plans: { [M.ahmed]: at(3) } },
    ready: async (page, lang) => {
      await page.getByLabel(msg(lang, 'plan.repsFor', { name: exName(lang, 'Abs', 'بطن') })).fill('20');
      await page.getByLabel(msg(lang, 'plan.repsFor', { name: exName(lang, 'Abs', 'بطن') })).press('Enter');
      await page.evaluate(() => undefined);
      await page.route('**/rest/v1/plans?select=version*', (route) =>
        route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([{ version: 9 }]) }),
      );
      await page.getByRole('button', { name: msg(lang, 'plan.save') }).click();
      await expect(page.getByRole('heading', { name: msg(lang, 'conflict.title') })).toBeVisible();
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

test('Arabic is right to left; names show the Arabic first', async ({ page }) => {
  await open(page, { path: planPath(M.ahmed), plans, lang: 'ar', theme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.getByRole('heading', { level: 2, name: 'صدر وضهر' })).toBeVisible();
});

test('the editor works from the keyboard: change a target, add an exercise, save', async ({ page }) => {
  const mock = await open(page, { path: planPath(M.ahmed), plans });
  const sets = page.getByLabel(msg('en', 'plan.setsFor', { name: 'Pec Deck' }));
  await sets.focus();
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.type('5');
  await page.keyboard.press('Enter');
  await page.getByRole('button', { name: msg('en', 'plan.addExercise') }).focus();
  await page.keyboard.press('Enter');
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByLabel(msg('en', 'pick.search'))).toBeFocused();
  await page.keyboard.type('face pull');
  await dialog.getByRole('button', { name: msg('en', 'pick.addName', { name: 'Face Pull' }) }).focus();
  await page.keyboard.press('Enter');
  await expect(dialog).toHaveCount(0);
  await page.getByRole('button', { name: msg('en', 'plan.save') }).focus();
  await page.keyboard.press('Enter');
  await expect(page.getByText(msg('en', 'plan.saved', { name: 'Ahmed Hassan' }))).toBeVisible();
  const body = mock.rpcs.at(-1)?.body.p_body as { days: { exercises: { id: string; sets: number }[] }[] };
  expect(body.days[0]?.exercises.find((e) => e.id === 'pec_deck')?.sets).toBe(5);
  expect(body.days[0]?.exercises.some((e) => e.id === 'face_pull')).toBe(true);
});

test('dialogs trap Tab and close with Escape', async ({ page }) => {
  await open(page, { path: planPath(M.ahmed), plans });
  const rename = page.getByRole('button', { name: msg('en', 'plan.renameDay') });
  await rename.focus();
  await page.keyboard.press('Enter');
  const dialog = page.getByRole('dialog');
  for (let i = 0; i < 8; i++) {
    await page.keyboard.press('Tab');
    await expect(dialog.locator(':focus')).toHaveCount(1);
  }
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(rename).toBeFocused();
});
