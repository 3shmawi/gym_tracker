import { GYM_A, mockSupabase, prefs, signedInBefore, expect, test } from './fixtures/supabase';
import { msg, tools } from './fixtures/helpers';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const UNKNOWN = '99999999-9999-4999-8999-999999999999';

test('one gym goes straight to its members page', async ({ page }) => {
  await signedInBefore(page);
  await mockSupabase(page, { gyms: [{ ...GYM_A, role: 'owner' }] });
  await page.goto('/');
  await expect(page).toHaveURL(new RegExp(`/g/${GYM_A.id}/members$`));
  await expect(page.getByRole('heading', { level: 1, name: en('members.title') })).toBeVisible();
});

test('no person shows "No gym to manage yet" with Sign out', async ({ page }) => {
  await signedInBefore(page);
  await mockSupabase(page, { hasPerson: false, gyms: [] });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: en('noGym.title') })).toBeVisible();
  await expect(page.getByRole('main').getByRole('button', { name: en('app.signOut') })).toBeVisible();
});

test('a failing REST call shows the error view, Retry then loads the picker', async ({ page }) => {
  await signedInBefore(page);
  const mock = await mockSupabase(page, { restFails: true });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: en('state.errorTitle') })).toBeVisible();
  mock.recover();
  await page.getByRole('button', { name: en('state.retry') }).click();
  await expect(page.getByRole('heading', { level: 1, name: en('gyms.title') })).toBeVisible();
});

test('an unknown gym id shows the forbidden view', async ({ page }) => {
  await signedInBefore(page);
  await mockSupabase(page);
  await page.goto(`/g/${UNKNOWN}/members`);
  await expect(page.getByRole('heading', { name: en('state.forbiddenTitle') })).toBeVisible();
});

test('an unknown path shows not found', async ({ page }) => {
  await signedInBefore(page);
  await mockSupabase(page);
  await page.goto('/nope');
  await expect(page.getByRole('heading', { name: en('state.notFoundTitle') })).toBeVisible();
});

test('an anonymous stored session is shown the sign-in page', async ({ page }) => {
  await signedInBefore(page, true);
  await mockSupabase(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: en('signIn.title') })).toBeVisible();
  await expect(page.getByRole('heading', { name: en('gyms.title') })).toHaveCount(0);
});

test('the language toggle switches to Arabic and back', async ({ page }) => {
  await prefs(page, 'en', 'light');
  await mockSupabase(page);
  await page.goto('/');
  let header = await tools(page);
  await header.getByRole('button', { name: msg('en', 'app.switchLanguageLabel') }).click();
  const root = page.locator('html');
  await expect(root).toHaveAttribute('lang', 'ar');
  await expect(root).toHaveAttribute('dir', 'rtl');
  await expect(page.getByRole('heading', { level: 1, name: msg('ar', 'signIn.title') })).toBeVisible();
  header = await tools(page, 'ar');
  await header.getByRole('button', { name: msg('ar', 'app.switchLanguageLabel') }).click();
  await expect(root).toHaveAttribute('lang', 'en');
  await expect(root).toHaveAttribute('dir', 'ltr');
  await expect(page.getByRole('heading', { level: 1, name: en('signIn.title') })).toBeVisible();
});

test('the theme toggle sets data-theme', async ({ page }) => {
  await prefs(page, 'en', 'light');
  await mockSupabase(page);
  await page.goto('/');
  const header = await tools(page);
  await header.getByRole('button', { name: en('app.themeDark') }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.getByRole('button', { name: en('app.themeLight') })).toBeVisible();
});

test('phone: the menu opens, Escape closes it and focus returns to the button', async ({ page }, info) => {
  test.skip(info.project.name !== 'phone', 'the menu button only exists on the phone layout');
  await mockSupabase(page);
  await page.goto('/');
  const open = page.getByRole('button', { name: en('app.openMenu') });
  await open.click();
  const button = page.getByRole('button', { name: en('app.closeMenu') });
  await expect(button).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator('#menu-panel')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#menu-panel')).toHaveCount(0);
  const closed = page.getByRole('button', { name: en('app.openMenu') });
  await expect(closed).toHaveAttribute('aria-expanded', 'false');
  await expect(closed).toBeFocused();
});

test('desktop: there is no menu button', async ({ page }, info) => {
  test.skip(info.project.name !== 'desktop', 'desktop layout only');
  await mockSupabase(page);
  await page.goto('/');
  await expect(page.getByRole('button', { name: en('app.openMenu') })).toBeHidden();
});
