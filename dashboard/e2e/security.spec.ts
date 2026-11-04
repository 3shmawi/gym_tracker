import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { EMAIL, GOOD_CODE, GYM_A, SUPABASE, mockSupabase, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);

test('no request leaves localhost or the mocked project', async ({ page }) => {
  const urls: string[] = [];
  page.on('request', (request) => urls.push(request.url()));
  await mockSupabase(page);
  await page.goto('/');
  await page.getByLabel(en('signIn.email'), { exact: true }).fill(EMAIL);
  await page.getByRole('button', { name: en('signIn.send') }).click();
  await page.getByLabel(en('signIn.code'), { exact: true }).fill(GOOD_CODE);
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: en('gyms.title') })).toBeVisible();
  await page.getByRole('link', { name: new RegExp(GYM_A.name) }).click();
  await expect(page.getByRole('heading', { level: 1, name: en('members.title') })).toBeVisible();

  expect(urls.length).toBeGreaterThan(5);
  for (const raw of urls) {
    const url = new URL(raw);
    if (url.protocol === 'data:' || url.protocol === 'blob:') continue;
    const allowed = url.hostname === 'localhost' || url.origin === SUPABASE;
    expect(allowed, raw).toBe(true);
  }
});

test('after sign-in only the session and the prefs are stored', async ({ page }) => {
  await mockSupabase(page);
  await page.goto('/');
  await page.getByLabel(en('signIn.email'), { exact: true }).fill(EMAIL);
  await page.getByRole('button', { name: en('signIn.send') }).click();
  await page.getByLabel(en('signIn.code'), { exact: true }).fill(GOOD_CODE);
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: en('gyms.title') })).toBeVisible();

  const stored = await page.evaluate(() => Object.fromEntries(Object.entries(window.localStorage)));
  expect(Object.keys(stored).sort()).toEqual(['azm.dashboard.prefs.v1', 'sb-abcdefghijklmnopqrst-auth-token']);
  const prefs = JSON.parse(stored['azm.dashboard.prefs.v1'] ?? '{}') as Record<string, unknown>;
  expect(Object.keys(prefs).sort()).toEqual(['lang', 'theme']);
  expect(await page.evaluate(() => window.sessionStorage.length)).toBe(0);
});

test('a hostile gym name is shown as plain text', async ({ page }) => {
  const override = String.fromCharCode(0x202e);
  const markup = '<img src=x onerror=alert(1)>';
  const hostile = `Evil${override}Gym ${markup}`;
  const dialogs: string[] = [];
  page.on('dialog', (dialog) => {
    dialogs.push(dialog.message());
    void dialog.dismiss();
  });
  await mockSupabase(page, { gyms: [{ ...GYM_A, name: hostile, role: 'owner' }, { id: '44444444-4444-4444-8444-444444444444', name: 'Other', role: 'captain' }] });
  await page.goto('/');
  await page.getByLabel(en('signIn.email'), { exact: true }).fill(EMAIL);
  await page.getByRole('button', { name: en('signIn.send') }).click();
  await page.getByLabel(en('signIn.code'), { exact: true }).fill(GOOD_CODE);
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: en('gyms.title') })).toBeVisible();

  const card = page.locator('a.gym-card').first();
  await expect(card).toContainText(markup);
  const text = await card.innerText();
  expect(text.includes(override)).toBe(false);
  await expect(page.locator('main img')).toHaveCount(0);
  expect(await page.locator('img[src="x"]').count()).toBe(0);
  expect(dialogs).toEqual([]);
});

test('the Cloudflare headers file has a CSP and forbids framing', () => {
  const file = fileURLToPath(new URL('../dist/_headers', import.meta.url));
  const headers = readFileSync(file, 'utf8');
  expect(headers).toMatch(/Content-Security-Policy: .*default-src 'self'/);
  expect(headers).toContain("frame-ancestors 'none'");
  expect(headers).toContain("object-src 'none'");
  expect(headers).toContain('X-Frame-Options: DENY');
});

test('tokens in the URL do not sign anyone in', async ({ page }) => {
  const mock = await mockSupabase(page);
  await page.goto('/?access_token=a.b.c&refresh_token=r#access_token=a.b.c&refresh_token=r&token_type=bearer&type=magiclink');
  await expect(page.getByRole('heading', { level: 1, name: en('signIn.title') })).toBeVisible();
  expect(await page.evaluate(() => window.localStorage.getItem('sb-abcdefghijklmnopqrst-auth-token'))).toBeNull();
  await expect(page.getByRole('heading', { name: en('gyms.title') })).toHaveCount(0);
  expect(mock.verifyRequests).toHaveLength(0);
});
