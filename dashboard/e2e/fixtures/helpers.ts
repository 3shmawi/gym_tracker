import { type Page } from '@playwright/test';
import { ar } from '../../src/i18n/ar';
import { en } from '../../src/i18n/en';
import { EMAIL, GOOD_CODE } from './supabase';

export type Lang = 'en' | 'ar';
export type Theme = 'light' | 'dark';

export const strings = { en, ar } as const;

/** The dashboard's own message for a key, with {placeholders} filled. */
export function msg(lang: Lang, key: keyof typeof en, values: Record<string, string | number> = {}): string {
  let text: string = strings[lang][key];
  for (const [name, value] of Object.entries(values)) text = text.replaceAll(`{${name}}`, typeof value === 'number' ? new Intl.NumberFormat(lang === 'ar' ? 'ar-EG' : 'en').format(value) : value);
  return text;
}

/** Types the email, asks for a code, types the code and signs in (stops at the gym picker or members page). */
export async function signInWithCode(page: Page, lang: Lang = 'en'): Promise<void> {
  await page.getByLabel(msg(lang, 'signIn.email'), { exact: true }).fill(EMAIL);
  await page.getByRole('button', { name: msg(lang, 'signIn.send') }).click();
  await page.getByLabel(msg(lang, 'signIn.code'), { exact: true }).fill(GOOD_CODE);
  await page.getByRole('button', { name: msg(lang, 'signIn.verify'), exact: true }).click();
}


/**
 * Where the header tools (gym switcher, language, theme, sign out) are: the
 * header on desktop; on the phone they live in the menu panel, which this opens.
 */
export async function tools(page: Page, lang: Lang = 'en') {
  const phone = (page.viewportSize()?.width ?? 1280) <= 720;
  if (!phone) return page.locator('header.hdr');
  const button = page.getByRole('button', { name: msg(lang, 'app.openMenu') });
  if ((await button.getAttribute('aria-expanded')) !== 'true') await button.click();
  return page.locator('#menu-panel');
}
