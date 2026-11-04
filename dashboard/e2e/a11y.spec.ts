import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { EMAIL, GYM_A, mockSupabase, prefs, signedInBefore, expect, test, type MockOptions } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];

interface Screen {
  name: string;
  options?: MockOptions;
  signedIn: boolean;
  open: (page: Page, lang: Lang) => Promise<void>;
}

const screens: Screen[] = [
  {
    name: 'sign-in email step',
    signedIn: false,
    open: async (page, lang) => {
      await page.goto('/');
      await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'signIn.title') })).toBeVisible();
    },
  },
  {
    name: 'sign-in code step',
    signedIn: false,
    open: async (page, lang) => {
      await page.goto('/');
      await page.getByLabel(msg(lang, 'signIn.email'), { exact: true }).fill(EMAIL);
      await page.getByRole('button', { name: msg(lang, 'signIn.send') }).click();
      await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'signIn.checkTitle') })).toBeVisible();
    },
  },
  {
    name: 'gym picker',
    signedIn: true,
    open: async (page, lang) => {
      await page.goto('/');
      await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'gyms.title') })).toBeVisible();
    },
  },
  {
    name: 'members page',
    signedIn: true,
    open: async (page, lang) => {
      await page.goto(`/g/${GYM_A.id}/members`);
      await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'members.title') })).toBeVisible();
    },
  },
  {
    name: 'not found',
    signedIn: true,
    open: async (page, lang) => {
      await page.goto('/nope');
      await expect(page.getByRole('heading', { name: msg(lang, 'state.notFoundTitle') })).toBeVisible();
    },
  },
  {
    name: 'no gym',
    signedIn: true,
    options: { hasPerson: false, gyms: [] },
    open: async (page, lang) => {
      await page.goto('/');
      await expect(page.getByRole('heading', { name: msg(lang, 'noGym.title') })).toBeVisible();
    },
  },
];

const looks: { lang: Lang; theme: Theme }[] = [
  { lang: 'en', theme: 'light' },
  { lang: 'en', theme: 'dark' },
  { lang: 'ar', theme: 'light' },
  { lang: 'ar', theme: 'dark' },
];

for (const screen of screens) {
  for (const { lang, theme } of looks) {
    test(`axe: ${screen.name} (${lang} ${theme})`, async ({ page }) => {
      await prefs(page, lang, theme);
      if (screen.signedIn) await signedInBefore(page);
      await mockSupabase(page, screen.options);
      await screen.open(page, lang);
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme);
      const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
      expect(results.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
    });
  }
}

test('keyboard: skip link first, then the email field; Enter sends the code', async ({ page }) => {
  const mock = await mockSupabase(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'signIn.title') })).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: msg('en', 'app.skipToContent') })).toBeFocused();

  const email = page.getByLabel(msg('en', 'signIn.email'), { exact: true });
  for (let i = 0; i < 10 && !(await email.evaluate((el) => el === document.activeElement)); i++) await page.keyboard.press('Tab');
  await expect(email).toBeFocused();

  // A visible focus ring on the keyboard-focused field.
  const outline = await email.evaluate((el) => getComputedStyle(el).outlineStyle);
  expect(outline).not.toBe('none');

  await page.keyboard.type(EMAIL);
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'signIn.checkTitle') })).toBeVisible();
  expect(mock.otpRequests).toHaveLength(1);
});

test('keyboard: every tab stop shows a focus outline', async ({ page }) => {
  await mockSupabase(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'signIn.title') })).toBeVisible();
  const seen: string[] = [];
  for (let i = 0; i < 12; i++) {
    await page.keyboard.press('Tab');
    const info = await page.evaluate(() => {
      const el = document.activeElement;
      if (!el || el === document.body) return null;
      const style = getComputedStyle(el);
      return { tag: `${el.tagName.toLowerCase()}.${el.className}`, outline: style.outlineStyle, matches: el.matches(':focus-visible') };
    });
    if (!info) break;
    seen.push(info.tag);
    expect(info.matches, info.tag).toBe(true);
    expect(info.outline, info.tag).not.toBe('none');
  }
  expect(seen.length).toBeGreaterThan(3);
});

// Touch targets (>= 44x44). Skipped on purpose:
// - the skip link: visually hidden until focused;
// - links inside a sentence (the contact email in "Still stuck? ..."): inline
//   text links are exempt from the WCAG 2.2 target-size rule (inline exception).
// Footer links: only the height is checked (they are separate short words, 44px high; a
//   width of 44 would not make them easier to hit and WCAG 2.2 allows 24px targets).
async function smallTargets(page: Page): Promise<string[]> {
  const targets = page.locator('header.hdr, #menu-panel, main, footer').locator('button, a:not(.skip)');
  const small: string[] = [];
  for (const target of await targets.all()) {
    if (!(await target.isVisible())) continue;
    const inline = await target.evaluate((el) => el.closest('p, span.cap') !== null);
    if (inline) continue;
    const box = await target.boundingBox();
    if (!box) continue;
    if (box.width < 44 || box.height < 44) {
      small.push(`${(await target.innerText()).trim() || (await target.getAttribute('aria-label')) || '?'} ${Math.round(box.width)}x${Math.round(box.height)}`);
    }
  }
  return small;
}

test('touch targets: sign-in page', async ({ page }) => {
  await mockSupabase(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'signIn.title') })).toBeVisible();
  expect(await smallTargets(page)).toEqual([]);
});

test('touch targets: code step', async ({ page }) => {
  await mockSupabase(page);
  await page.goto('/');
  await page.getByLabel(msg('en', 'signIn.email'), { exact: true }).fill(EMAIL);
  await page.getByRole('button', { name: msg('en', 'signIn.send') }).click();
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'signIn.checkTitle') })).toBeVisible();
  expect(await smallTargets(page)).toEqual([]);
});

test('touch targets: gym picker and members page (header, menu, nav)', async ({ page }) => {
  await signedInBefore(page);
  await mockSupabase(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'gyms.title') })).toBeVisible();
  expect(await smallTargets(page)).toEqual([]);
  await page.goto(`/g/${GYM_A.id}/members`);
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'members.title') })).toBeVisible();
  expect(await smallTargets(page)).toEqual([]);
  if ((page.viewportSize()?.width ?? 1280) <= 720) {
    await page.getByRole('button', { name: msg('en', 'app.openMenu') }).click();
    await expect(page.locator('#menu-panel')).toBeVisible();
    expect(await smallTargets(page)).toEqual([]);
  }
});
