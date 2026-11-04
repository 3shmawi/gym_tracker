import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { expect, test } from './fixtures/supabase';
import { M } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';
import { ADD_PATH, MEMBERS_PATH, ROSTER, chooseFile, memberPath, open, rowOf, type OpenOptions } from './fixtures/members';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];

interface Screen {
  name: string;
  options?: OpenOptions;
  ready: (page: Page, lang: Lang) => Promise<void>;
}

const names = (lang: Lang) => (lang === 'ar' ? ['نور حسن', 'محمد علي', 'سلمى عادل'] : ['Nour Hassan', 'Mohamed Ali', 'Salma Adel']);

async function toCodes(page: Page, lang: Lang): Promise<void> {
  await page.getByLabel(msg(lang, 'add.names'), { exact: true }).fill(names(lang).join('\n'));
  await page.getByRole('button', { name: msg(lang, 'add.make', { count: 3 }) }).click();
  await expect(page.getByRole('table')).toBeVisible();
}

const screens: Screen[] = [
  {
    name: 'members list',
    ready: async (page, lang) => {
      await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'members.title') })).toBeVisible();
      await expect(rowOf(page, 'Ahmed Hassan')).toBeVisible();
    },
  },
  {
    name: 'members list, no match',
    ready: async (page, lang) => {
      await page.getByRole('searchbox').fill('zzz');
      await expect(page.getByRole('heading', { name: msg(lang, 'members.noMatchTitle', { query: 'zzz' }) })).toBeVisible();
    },
  },
  {
    name: 'member page (trainee)',
    options: { path: memberPath(M.ahmed) },
    ready: async (page) => {
      await expect(page.getByRole('heading', { level: 1, name: 'Ahmed Hassan' })).toBeVisible();
    },
  },
  {
    name: 'member page (read only)',
    options: { path: memberPath(M.captain), gyms: [{ id: '33333333-3333-4333-8333-333333333333', name: 'Power Gym', role: 'captain' }] },
    ready: async (page, lang) => {
      await expect(page.getByText(msg(lang, 'member.readOnlyCaptain'))).toBeVisible();
    },
  },
  {
    name: 'member page (code shown)',
    options: { path: memberPath(M.layla) },
    ready: async (page, lang) => {
      await page.getByRole('button', { name: msg(lang, 'members.makeNewCode') }).click();
      await expect(page.locator('.code')).toBeVisible();
    },
  },
  {
    name: 'add page, names step',
    options: { path: ADD_PATH },
    ready: async (page, lang) => {
      await page.getByLabel(msg(lang, 'add.names'), { exact: true }).fill(names(lang).join('\n'));
      await expect(page.getByText(msg(lang, 'add.ready', { count: 3 }))).toBeVisible();
    },
  },
  {
    name: 'add page, codes step',
    options: { path: ADD_PATH },
    ready: async (page, lang) => {
      await toCodes(page, lang);
    },
  },
  {
    name: 'add page, codes step with a failure',
    options: { path: ADD_PATH, failInsertAt: [2] },
    ready: async (page, lang) => {
      await toCodes(page, lang);
      await expect(page.getByRole('alert')).toBeVisible();
    },
  },
  {
    name: 'add page, import preview',
    options: { path: ADD_PATH },
    ready: async (page, lang) => {
      await chooseFile(page, { name: 'roster.xlsx', mimeType: 'application/octet-stream', buffer: ROSTER });
      await expect(page.getByLabel(msg(lang, 'imp.column'))).toBeVisible();
    },
  },
  {
    name: 'add page, import problem',
    options: { path: ADD_PATH },
    ready: async (page) => {
      await chooseFile(page, { name: 'names.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4') });
      await expect(page.getByRole('alert')).toBeVisible();
    },
  },
  {
    name: 'add page, verified and ready to print',
    options: { path: ADD_PATH },
    ready: async (page, lang) => {
      await toCodes(page, lang);
      await page.getByRole('button', { name: msg(lang, 'add.check', { count: 3 }) }).click();
      await expect(page.getByText(msg(lang, 'add.verified', { ok: 3, total: 3 }))).toBeVisible();
    },
  },
  {
    name: 'print view',
    options: { path: ADD_PATH },
    ready: async (page, lang) => {
      await toCodes(page, lang);
      await page.getByRole('button', { name: msg(lang, 'add.check', { count: 3 }) }).click();
      await page.getByRole('button', { name: msg(lang, 'add.print', { count: 3 }) }).click();
      await page.emulateMedia({ media: 'print' });
      await expect(page.locator('.pcard')).toHaveCount(3);
    },
  },
  {
    name: 'end-membership dialog',
    options: { path: memberPath(M.ahmed) },
    ready: async (page, lang) => {
      await page.getByRole('main').getByRole('button', { name: msg(lang, 'member.end'), exact: true }).click();
      await expect(page.getByRole('dialog')).toBeVisible();
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
      await open(page, { path: MEMBERS_PATH, ...screen.options, lang, theme });
      await screen.ready(page, lang);
      const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
      expect(results.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
    });
  }
}

test('the end-membership dialog traps Tab and Escape closes it', async ({ page }) => {
  await open(page, { path: memberPath(M.ahmed) });
  const endButton = page.getByRole('main').getByRole('button', { name: msg('en', 'member.end'), exact: true });
  await endButton.focus();
  await page.keyboard.press('Enter');
  const dialog = page.getByRole('dialog');
  const cancel = dialog.getByRole('button', { name: msg('en', 'member.cancel') });
  const confirm = dialog.getByRole('button', { name: msg('en', 'member.end'), exact: true });
  await expect(cancel).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(confirm).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(cancel).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(confirm).toBeFocused();
  for (let i = 0; i < 6; i++) {
    await page.keyboard.press('Tab');
    await expect(dialog.locator(':focus')).toHaveCount(1);
  }
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(endButton).toBeFocused();
});

test('the whole add flow works from the keyboard', async ({ page }) => {
  await open(page, { path: ADD_PATH });
  await page.getByLabel(msg('en', 'add.names'), { exact: true }).focus();
  await page.keyboard.type('Nour');
  const make = page.getByRole('button', { name: msg('en', 'add.makeOne') });
  await make.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('table')).toBeVisible();
  const check = page.getByRole('button', { name: msg('en', 'add.checkOne') });
  await check.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByText(msg('en', 'add.verified', { ok: 1, total: 1 }))).toBeVisible();
});
