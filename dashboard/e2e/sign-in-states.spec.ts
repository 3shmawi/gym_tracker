import { EMAIL, GOOD_CODE, mockSupabase, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);

async function askForCode(page: import('@playwright/test').Page) {
  await page.goto('/');
  await page.getByLabel(en('signIn.email'), { exact: true }).fill(EMAIL);
  await page.getByRole('button', { name: en('signIn.send') }).click();
}

test('an invalid email shows the error and sends nothing', async ({ page }) => {
  const mock = await mockSupabase(page);
  await page.goto('/');
  await page.getByLabel(en('signIn.email'), { exact: true }).fill('not-an-email');
  await page.getByRole('button', { name: en('signIn.send') }).click();
  await expect(page.getByRole('alert').filter({ hasText: en('signIn.emailInvalid') })).toBeVisible();
  await expect(page.getByLabel(en('signIn.email'), { exact: true })).toHaveAttribute('aria-invalid', 'true');
  expect(mock.otpRequests).toHaveLength(0);
});

test('an unknown user sees the same "Check your email" screen', async ({ page }) => {
  const mock = await mockSupabase(page, { otp: 'unknown_user' });
  await askForCode(page);
  await expect(page.getByRole('heading', { level: 1, name: en('signIn.checkTitle') })).toBeVisible();
  expect(mock.otpRequests).toHaveLength(1);
});

test('rate limited shows the wait message', async ({ page }) => {
  await mockSupabase(page, { otp: 'rate_limited' });
  await askForCode(page);
  await expect(page.getByRole('alert').filter({ hasText: en('signIn.rateLimited') })).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: en('signIn.title') })).toBeVisible();
});

test('a wrong code shows the wrong-code message and keeps the form', async ({ page }) => {
  const mock = await mockSupabase(page, { wrongCode: 'invalid' });
  await askForCode(page);
  await page.getByLabel(en('signIn.code'), { exact: true }).fill('000000');
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: en('signIn.codeWrong') })).toBeVisible();
  expect(mock.verifyRequests).toHaveLength(1);
  await expect(page.getByLabel(en('signIn.code'), { exact: true })).toBeVisible();
});

test('a code that is not 6 digits is refused before any request', async ({ page }) => {
  const mock = await mockSupabase(page);
  await askForCode(page);
  await page.getByLabel(en('signIn.code'), { exact: true }).fill('12ab');
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: en('signIn.codeInvalid', { length: 6 }) })).toBeVisible();
  expect(mock.verifyRequests).toHaveLength(0);
});

test('an expired code offers a new one', async ({ page }) => {
  const mock = await mockSupabase(page, { wrongCode: 'otp_expired' });
  await askForCode(page);
  await page.getByLabel(en('signIn.code'), { exact: true }).fill('000000');
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByText(en('signIn.codeExpired'))).toBeVisible();
  const again = page.getByRole('button', { name: en('signIn.sendNew') });
  await expect(again).toBeVisible();
  await again.click();
  await expect.poll(() => mock.otpRequests.length).toBe(2);
  expect(GOOD_CODE).toHaveLength(6);
});

test('offline disables Send and shows the offline banner', async ({ page, context }) => {
  await mockSupabase(page);
  await page.goto('/');
  await context.setOffline(true);
  await expect(page.getByRole('button', { name: en('signIn.send') })).toBeDisabled();
  await expect(page.getByRole('status').getByText(en('state.offline'))).toBeVisible();
  await expect(page.getByText(en('signIn.offlineHint'))).toBeVisible();
  await context.setOffline(false);
  await expect(page.getByRole('button', { name: en('signIn.send') })).toBeEnabled();
});

test('"Use another email" returns to step 1', async ({ page }) => {
  await mockSupabase(page);
  await askForCode(page);
  await page.getByRole('button', { name: en('signIn.otherEmail') }).click();
  await expect(page.getByRole('heading', { level: 1, name: en('signIn.title') })).toBeVisible();
  await expect(page.getByLabel(en('signIn.email'), { exact: true })).toBeVisible();
});

test('the resend countdown is visible after a code is sent', async ({ page }) => {
  await mockSupabase(page);
  await askForCode(page);
  await expect(page.getByText(/Send again in\s+(0:5\d|1:00)/)).toBeVisible();
  await expect(page.getByRole('button', { name: en('signIn.resend') })).toHaveCount(0);
});

test('a wrong code (server default answer) shows "wrong or has expired" with a new-code button', async ({ page }) => {
  await mockSupabase(page);
  await askForCode(page);
  await page.getByLabel(en('signIn.code'), { exact: true }).fill('000000');
  await page.getByRole('button', { name: en('signIn.verify'), exact: true }).click();
  await expect(page.getByText(en('signIn.codeExpired'))).toBeVisible();
  await expect(page.getByRole('button', { name: en('signIn.sendNew') })).toBeVisible();
});
