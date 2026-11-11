import { readFileSync } from 'node:fs';
import type { Page } from '@playwright/test';
import { GYM_A, M, expect, samplePlan, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { isPhone, memberPath, MEMBERS_PATH, open } from './fixtures/members';
import { ahmedProgress } from './fixtures/progress';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const SETTINGS = `/g/${GYM_A.id}/settings`;
const LOGO_PNG = readFileSync(new URL('../public/logo-96.png', import.meta.url));
const plans = { [M.ahmed]: { body: samplePlan(), version: 2, updated_by: null, updated_at: '2026-11-09T10:00:00Z' } };

async function chooseLogo(page: Page, file: { name: string; mimeType: string; buffer: Buffer }) {
  await page.locator('#logo-file').setInputFiles(file);
}

test.describe('member progress', () => {
  test('a trainee with workouts: stats, weeks, recent workouts, weight progress', async ({ page }) => {
    await open(page, { path: memberPath(M.ahmed), progress: { [M.ahmed]: ahmedProgress() }, plans });
    const panel = page.getByRole('region', { name: en('prog.title', { gym: GYM_A.name }) });
    await expect(panel).toBeVisible();
    await expect(panel.getByText('38', { exact: true })).toBeVisible();
    await expect(panel.getByText(en('prog.level.intermediate'), { exact: true })).toBeVisible();
    await expect(panel.getByText(en('prog.levelNote'))).toBeVisible();
    await expect(panel.getByRole('img', { name: /Workouts per week, last 12 weeks/ })).toBeVisible();
    await panel.getByText(en('prog.showTable')).first().click();
    await expect(panel.getByRole('row').filter({ hasText: '72 / 80' })).toBeVisible();
    await expect(panel.getByRole('row').filter({ hasText: '30 / —' })).toBeVisible();
    // Recent workouts: names from the plan, "—" for old ones, skipped by name.
    const recent = panel.getByRole('table').filter({ hasText: en('prog.colSetsFull') });
    await expect(recent.getByRole('row').nth(1)).toContainText('Chest & Back');
    await expect(recent.getByRole('row').nth(1)).toContainText(en('prog.minutes', { count: 52 }));
    await expect(recent.getByRole('row').nth(1)).toContainText('Abs');
    await expect(recent.getByRole('row').nth(2)).toContainText(en('prog.dayGone'));
    await expect(recent.getByRole('row').nth(2)).toContainText(en('prog.records', { count: 1 }));
    await expect(recent.getByRole('row').nth(2).getByRole('cell').nth(1)).toHaveText('—');
    // Weight progress with the record marked.
    await expect(panel.getByLabel(en('prog.exPick'))).toHaveValue('flat_db_press');
    await expect(panel.getByRole('img', { name: /Flat Dumbbell Press: top weight per workout\. From 20 kg to 22\.5 kg\. Records: 1\./ })).toBeVisible();
  });

  test('no workouts yet, waiting to join, ended, error with retry', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.youssef) });
    await expect(page.getByRole('heading', { name: en('prog.noneTitle') })).toBeVisible();
    await page.goto(memberPath(M.layla));
    await expect(page.getByRole('heading', { name: en('prog.pendingTitle') })).toBeVisible();
    await page.goto(memberPath(M.hana));
    await expect(page.getByRole('heading', { name: en('prog.endedTitle') })).toBeVisible();
    expect(mock.requests.some((r) => r.path.startsWith('/rest/v1/member_') && r.search.includes(M.hana))).toBe(false);
    mock.set({ progressFails: true });
    await page.goto(memberPath(M.ahmed));
    await expect(page.getByRole('region', { name: en('prog.title', { gym: GYM_A.name }) }).getByRole('button', { name: en('state.retry') })).toBeVisible();
    mock.set({ progressFails: false });
    await page.getByRole('button', { name: en('state.retry') }).click();
    await expect(page.getByRole('heading', { name: en('prog.noneTitle') })).toBeVisible();
  });

  test('the members list shows the last workout', async ({ page }) => {
    await open(page, { path: MEMBERS_PATH, progress: { [M.ahmed]: ahmedProgress() } });
    if (isPhone(page)) await expect(page.getByRole('listitem').filter({ hasText: 'Ahmed Hassan' })).toContainText(en('members.colLast'));
    else {
      await expect(page.getByRole('columnheader', { name: en('members.colLast') })).toBeVisible();
      await expect(page.getByRole('row').filter({ hasText: 'Youssef Khaled' })).toContainText(en('members.lastNever'));
    }
  });
});

test.describe('gym settings', () => {
  test('rename, upload, replace and remove the logo, change the history setting', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    await expect(page.getByRole('heading', { level: 1, name: en('set.title') })).toBeVisible();
    const name = page.getByLabel(en('set.name'));
    await name.fill('  Power   Gym Nasr City ');
    await page.getByRole('button', { name: en('set.saveName') }).click();
    await expect(page.getByText(en('set.nameSaved'))).toBeVisible();
    expect(mock.gymRows[GYM_A.id]?.name).toBe('Power Gym Nasr City');

    await chooseLogo(page, { name: 'logo.png', mimeType: 'image/png', buffer: LOGO_PNG });
    await expect(page.getByText(en('set.logoSaved'))).toBeVisible();
    expect(mock.uploads.at(-1)).toMatchObject({ path: `${GYM_A.id}/logo.png`, contentType: 'image/png' });
    expect(mock.uploads.at(-1)?.head.slice(0, 4)).toEqual([0x89, 0x50, 0x4e, 0x47]);
    expect(mock.gymRows[GYM_A.id]?.logo_path).toBe(`${GYM_A.id}/logo.png`);
    await expect(page.getByRole('img', { name: en('set.logoAlt', { gym: 'Power Gym Nasr City' }) })).toBeVisible();

    await page.getByRole('button', { name: en('set.logoRemove') }).click();
    await expect(page.getByText(en('set.logoRemoved'))).toBeVisible();
    expect(mock.gymRows[GYM_A.id]?.logo_path).toBeNull();
    expect(mock.removed).toContain(`${GYM_A.id}/logo.png`);

    await page.getByRole('radio', { name: new RegExp(en('set.locked')) }).check();
    await expect(page.getByText(en('set.historySaved'))).toBeVisible();
    expect(mock.gymRows[GYM_A.id]?.history_after_end).toBe('locked');
  });

  test('a wrong file is refused before any request', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    await chooseLogo(page, { name: 'logo.png', mimeType: 'image/png', buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>') });
    await expect(page.getByRole('alert').filter({ hasText: en('set.logoType') })).toBeVisible();
    await chooseLogo(page, { name: 'big.png', mimeType: 'image/png', buffer: Buffer.concat([LOGO_PNG, Buffer.alloc(600 * 1024)]) });
    await expect(page.getByRole('alert').filter({ hasText: en('set.logoBig') })).toBeVisible();
    await chooseLogo(page, { name: '../../etc/passwd.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('not a picture') });
    await expect(page.getByRole('alert').filter({ hasText: en('set.logoType') })).toBeVisible();
    await chooseLogo(page, { name: 'empty.png', mimeType: 'image/png', buffer: Buffer.alloc(0) });
    await expect(page.getByRole('alert').filter({ hasText: en('set.logoEmpty') })).toBeVisible();
    expect(mock.uploads).toEqual([]);
    expect(mock.requests.some((r) => r.path.startsWith('/storage/v1/object/gym-logos') && r.method !== 'GET')).toBe(false);
  });

  test('hostile names: 61+ characters and empty can\'t be saved; control and direction characters are removed', async ({ page }) => {
    const mock = await open(page, { path: SETTINGS });
    const name = page.getByLabel(en('set.name'));
    await name.fill('x'.repeat(61));
    await expect(page.getByText(en('set.nameLong'))).toBeVisible();
    await expect(page.getByRole('button', { name: en('set.saveName') })).toBeDisabled();
    await name.fill('   ');
    await expect(page.getByText(en('set.nameEmpty'))).toBeVisible();
    await name.fill(`<img src=x onerror=alert(1)>${String.fromCharCode(0x202e)}${String.fromCharCode(7)}'; DROP TABLE gyms; --`);
    await page.getByRole('button', { name: en('set.saveName') }).click();
    await expect(page.getByText(en('set.nameSaved'))).toBeVisible();
    expect(mock.gymRows[GYM_A.id]?.name).toBe("<img src=x onerror=alert(1)>'; DROP TABLE gyms; --");
    await expect(page.locator('img[src="x"]')).toHaveCount(0);
  });

  test('offline: nothing can be saved', async ({ page, context }) => {
    await open(page, { path: SETTINGS });
    await expect(page.getByRole('heading', { level: 1, name: en('set.title') })).toBeVisible();
    await context.setOffline(true);
    await expect(page.getByRole('radio', { name: new RegExp(en('set.locked')) })).toBeDisabled();
    await expect(page.getByText(en('plan.offlineHint'))).toBeVisible();
    await context.setOffline(false);
    await expect(page.getByRole('radio', { name: new RegExp(en('set.locked')) })).toBeEnabled();
  });
});
