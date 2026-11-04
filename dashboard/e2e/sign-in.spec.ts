import { EMAIL, GYM_A, mockSupabase, prefs, expect, test } from './fixtures/supabase';
import { msg, signInWithCode, tools, type Lang, type Theme } from './fixtures/helpers';

// The main flow, as a demo: real typing, natural order, pauses between steps.
const pause = (ms = 250) => new Promise((resolve) => setTimeout(resolve, ms));

const variants: { lang: Lang; theme: Theme }[] = [
  { lang: 'en', theme: 'light' },
  { lang: 'ar', theme: 'dark' },
];

for (const { lang, theme } of variants) {
  test(`sign in, pick a gym, sign out (${lang} ${theme})`, async ({ page }) => {
    await prefs(page, lang, theme);
    const mock = await mockSupabase(page);
    const m = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg(lang, key, values);

    await page.goto('/');
    const root = page.locator('html');
    await expect(root).toHaveAttribute('lang', lang);
    await expect(root).toHaveAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
    await expect(root).toHaveAttribute('data-theme', theme);
    await expect(page.getByRole('heading', { level: 1, name: m('signIn.title') })).toBeVisible();
    await pause();

    // Step 1: the email.
    await page.getByLabel(m('signIn.email'), { exact: true }).pressSequentially(EMAIL, { delay: 25 });
    await pause();
    await page.getByRole('button', { name: m('signIn.send') }).click();

    // Step 2: "Check your email", with the masked address only.
    await expect(page.getByRole('heading', { level: 1, name: m('signIn.checkTitle') })).toBeVisible();
    await expect(page.getByText('c•••@example.com')).toBeVisible();
    await expect(page.getByText(EMAIL)).toHaveCount(0);
    expect(mock.otpRequests).toHaveLength(1);
    const otp = mock.otpRequests[0] ?? {};
    expect(otp.email).toBe(EMAIL);
    // supabase-js sends shouldCreateUser: false as create_user: false.
    expect(otp.create_user).toBe(false);
    await pause();

    await page.getByLabel(m('signIn.code'), { exact: true }).pressSequentially('481270', { delay: 40 });
    await pause();
    await page.getByRole('button', { name: m('signIn.verify'), exact: true }).click();

    // Two gyms: the picker.
    await expect(page.getByRole('heading', { level: 1, name: m('gyms.title') })).toBeVisible();
    await expect(page.getByText(m('gyms.subtitle', { count: 2 }))).toBeVisible();
    expect(mock.verifyRequests).toHaveLength(1);
    expect(mock.verifyRequests[0]).toMatchObject({ type: 'email', email: EMAIL, token: '481270' });
    const cards = page.locator('a.gym-card');
    await expect(cards).toHaveCount(2);
    await pause();

    await page.getByRole('link', { name: new RegExp(GYM_A.name) }).click();

    // Members page with the gym switcher in the header (in the menu on a phone).
    await expect(page).toHaveURL(new RegExp(`/g/${GYM_A.id}/members$`));
    await expect(page.getByRole('heading', { level: 1, name: m('members.title') })).toBeVisible();
    const header = await tools(page, lang);
    await expect(header.getByRole('link', { name: m('gyms.change', { gym: GYM_A.name }) })).toBeVisible();
    await pause();

    // Sign out: back to sign-in; only this browser is signed out.
    await header.getByRole('button', { name: m('app.signOut') }).click();
    await expect(page.getByRole('heading', { level: 1, name: m('signIn.title') })).toBeVisible();
    await expect(page).toHaveURL(/\/sign-in$/);
    expect(mock.logoutRequests).toHaveLength(1);
    expect(mock.logoutRequests[0]).toContain('scope=local');
    expect(await page.evaluate(() => window.localStorage.getItem('sb-abcdefghijklmnopqrst-auth-token'))).toBeNull();
  });
}

test('the helper signs in with the same steps', async ({ page }) => {
  await mockSupabase(page);
  await page.goto('/');
  await signInWithCode(page);
  await expect(page.getByRole('heading', { level: 1, name: msg('en', 'gyms.title') })).toBeVisible();
});
