import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { GYM_A, M, expect, test } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';
import { open, type OpenOptions } from './fixtures/members';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const LIST = `/g/${GYM_A.id}/exercises`;
const one = (id: string) => `${LIST}/${id}`;
const pid = (key: string, frame: 'tension' | 'relaxation') => `exercises/${key}-${frame}`;
const six = ['ek-0055', 'ek-0056', 'ek-0101'].flatMap((k) => [pid(k, 'tension'), pid(k, 'relaxation')]).map((id, i) => ({ gym_id: GYM_A.id, exercise_id: 'abs', public_id: id, position: i + 1 }));

interface Screen {
  name: string;
  options: OpenOptions;
  ready: (page: Page, lang: Lang) => Promise<void>;
}

async function searchPictures(page: Page, lang: Lang, words: string) {
  await page.getByLabel(msg(lang, 'pic.searchLabel')).fill(words);
  await page.getByRole('button', { name: msg(lang, 'pic.searchGo') }).click();
  await expect(page.locator('.res-card').first()).toBeVisible();
}

const screens: Screen[] = [
  {
    name: 'exercises list',
    options: { path: LIST, pictures: [six[0] ?? { gym_id: GYM_A.id, exercise_id: 'abs', public_id: pid('ek-0055', 'tension'), position: 1 }] },
    ready: async (page) => {
      await expect(page.locator('.ex-row')).toHaveCount(36);
    },
  },
  {
    name: 'exercises list, no match',
    options: { path: LIST },
    ready: async (page, lang) => {
      await page.getByRole('searchbox').fill('zzz');
      await expect(page.getByRole('heading', { name: msg(lang, 'ex.noMatchTitle', { query: 'zzz' }) })).toBeVisible();
    },
  },
  {
    name: 'exercise, empty, with search results',
    options: { path: one('flat_db_press') },
    ready: async (page, lang) => {
      await searchPictures(page, lang, 'press');
      await page.getByRole('button', { name: msg(lang, 'pic.addBothLabel', { name: 'Dumbbell Bench Press' }) }).click();
    },
  },
  {
    name: 'exercise, 6 pictures and a gym video',
    options: { path: one('abs'), pictures: six, videos: [{ gym_id: GYM_A.id, exercise_id: 'abs', video_id: 'dQw4w9WgXcQ', start_seconds: 15, end_seconds: 80 }] },
    ready: async (page, lang) => {
      await expect(page.getByText(msg(lang, 'pic.full', { max: 6 }))).toBeVisible();
    },
  },
  {
    name: 'exercise, refused link',
    options: { path: one('abs') },
    ready: async (page, lang) => {
      await page.getByLabel(msg(lang, 'vid.paste')).fill('https://www.youtube.com/live/dQw4w9WgXcQ');
      await expect(page.getByText(msg(lang, 'vid.bad'))).toBeVisible();
    },
  },
  {
    name: 'exercise, save refused',
    options: { path: one('abs'), saveVideo: 'forbidden' },
    ready: async (page, lang) => {
      await page.getByLabel(msg(lang, 'vid.paste')).fill('https://youtu.be/dQw4w9WgXcQ');
      await page.getByRole('button', { name: msg(lang, 'vid.save') }).click();
      await expect(page.getByRole('alert')).toBeVisible();
    },
  },
  {
    name: 'exercises list with a plan exercise',
    options: {
      path: LIST,
      plans: {
        [M.ahmed]: {
          body: { days: [{ id: 'day-1', name: { ar: 'يوم', en: 'Day' }, exercises: [{ id: 'ex-lq3k9a', name: { ar: 'تيست', en: 'Testt' }, sets: 3, reps: 12, rest: 90, step: 2.5, superset: false, unit: 'kg' }] }] },
          version: 1,
          updated_by: M.captain,
          updated_at: '2026-11-09T10:00:00Z',
        },
      },
    },
    ready: async (page) => {
      await expect(page.locator('.ex-row')).toHaveCount(37);
    },
  },
  {
    name: 'exercises, load error',
    options: { path: LIST, mediaFails: true },
    ready: async (page, lang) => {
      await expect(page.getByRole('button', { name: msg(lang, 'state.retry') })).toBeVisible();
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

test('Arabic is right to left and the link box stays left to right', async ({ page }) => {
  await open(page, { path: one('abs'), lang: 'ar', theme: 'dark' });
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.getByRole('heading', { level: 1, name: 'بطن' })).toBeVisible();
  await expect(page.getByLabel(msg('ar', 'vid.paste'))).toHaveAttribute('dir', 'ltr');
});

test('pictures can be chosen, ordered and saved from the keyboard only', async ({ page }) => {
  const mock = await open(page, { path: one('flat_db_press') });
  const box = page.getByLabel(msg('en', 'pic.searchLabel'));
  await box.focus();
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.type('press');
  await page.keyboard.press('Enter');
  const add = page.getByRole('button', { name: msg('en', 'pic.addBothLabel', { name: 'Dumbbell Bench Press' }) });
  await add.focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('.pic-card')).toHaveCount(2);

  // Move the second picture earlier: focus stays on a move button of that picture.
  const end = `Dumbbell Bench Press · ${msg('en', 'pic.end')}`;
  await page.getByRole('button', { name: msg('en', 'pic.earlier', { name: end }) }).focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('.pic-card').first()).toHaveAttribute('data-pic', pid('ek-0055', 'relaxation'));
  await expect(page.getByRole('button', { name: msg('en', 'pic.later', { name: end }) })).toBeFocused();

  await page.getByRole('button', { name: msg('en', 'pic.save') }).focus();
  await page.keyboard.press('Enter');
  await expect(page.getByText(msg('en', 'pic.saved'))).toBeVisible();
  expect(mock.rpcs.at(-1)?.body.p_public_ids).toEqual([pid('ek-0055', 'relaxation'), pid('ek-0055', 'tension')]);
});
