import type { Page } from '@playwright/test';
import { CLOUD_PATH, GYM_A, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { isPhone, open } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
export const EXERCISES_PATH = `/g/${GYM_A.id}/exercises`;
const exercisePath = (id: string) => `${EXERCISES_PATH}/${id}`;
const pid = (key: string, frame: 'tension' | 'relaxation') => `exercises/${key}-${frame}`;
const rows = (page: Page) => page.locator('.ex-row');

test.describe('exercises list', () => {
  test('lists the 36 library exercises, searches and filters', async ({ page }) => {
    await open(page, {
      path: EXERCISES_PATH,
      pictures: [{ gym_id: GYM_A.id, exercise_id: 'flat_db_press', public_id: pid('ek-0055', 'tension'), position: 1 }],
      videos: [{ gym_id: GYM_A.id, exercise_id: 'leg_press', video_id: 'dQw4w9WgXcQ', start_seconds: null, end_seconds: null }],
    });
    await expect(page.getByRole('heading', { level: 1, name: en('ex.title') })).toBeVisible();
    await expect(rows(page)).toHaveCount(36);
    await expect(page.getByText(en('ex.summary', { shown: 36, total: 36, pictures: 1, videos: 1 }))).toBeVisible();
    // The 13 exercises added for days 4 and 5 are there too.
    for (const name of ['Smith Machine Shrug', 'Preacher Curl', 'Two-Hand DB Overhead Extension']) await expect(rows(page).filter({ hasText: name })).toHaveCount(1);
    await expect(rows(page).filter({ hasText: 'Flat Dumbbell Press' })).toContainText(en('ex.picsOne'));
    await expect(rows(page).filter({ hasText: 'Leg Press' }).first()).toContainText(en('ex.videoYours'));

    const search = page.getByRole('searchbox', { name: en('ex.search') });
    await search.fill('دمبل');
    await expect(rows(page).first()).toBeVisible();
    for (const text of await rows(page).allTextContents()) expect(text).toMatch(/دمبل|Dumbbell|DB/i);
    await search.fill('');
    await page.getByRole('group', { name: en('ex.show') }).getByRole('button', { name: `${en('ex.tabNoVideo')} 13` }).click();
    await expect(rows(page)).toHaveCount(13);
  });
});

test.describe('one exercise: the main flow', () => {
  test('choose pictures (both frames, order, cover), set a video, see it all after a reload', async ({ page }) => {
    const mock = await open(page, { path: EXERCISES_PATH });
    await rows(page).filter({ hasText: 'Flat Dumbbell Press' }).click();
    await expect(page).toHaveURL(exercisePath('flat_db_press'));
    await expect(page.getByRole('heading', { level: 1, name: 'Flat Dumbbell Press' })).toBeVisible();
    await expect(page.getByText(en('pic.emptyTitle'))).toBeVisible();

    // Search the library; the box starts with the exercise's name.
    const box = page.getByLabel(en('pic.searchLabel'));
    await box.fill('dumbbell press');
    await page.getByRole('button', { name: en('pic.searchGo') }).click();
    await page.getByRole('button', { name: en('pic.addBothLabel', { name: 'Dumbbell Bench Press' }) }).click();
    await page.getByRole('button', { name: en('pic.frame', { frame: en('pic.start'), name: 'Incline Dumbbell Press' }) }).click();
    await expect(page.locator('.pic-card')).toHaveCount(3);
    await expect(page.getByText(en('pic.unsaved'))).toBeVisible();

    // The incline picture becomes the cover.
    const incline = `Incline Dumbbell Press · ${en('pic.start')}`;
    await page.getByRole('button', { name: en('pic.earlier', { name: incline }) }).click();
    await page.getByRole('button', { name: en('pic.earlier', { name: incline }) }).click();
    await expect(page.locator('.pic-card').first().locator('.pic-badge')).toHaveText(en('pic.cover'));
    await expect(page.locator('.pic-card').first().locator('img')).toHaveAttribute('alt', en('pic.position', { n: 1, count: 3, name: incline }));

    await page.getByRole('button', { name: en('pic.save') }).click();
    await expect(page.getByText(en('pic.saved'))).toBeVisible();
    expect(mock.rpcs.at(-1)).toEqual({
      name: 'set_gym_exercise_images',
      body: { p_gym_id: GYM_A.id, p_exercise_id: 'flat_db_press', p_public_ids: [pid('ek-0056', 'tension'), pid('ek-0055', 'tension'), pid('ek-0055', 'relaxation')] },
    });

    // The video: paste a link, only the id (and start) goes to the server.
    await page.getByLabel(en('vid.paste')).fill('https://youtu.be/dQw4w9WgXcQ?si=share123&t=15');
    await expect(page.getByText(en('vid.ok', { id: 'dQw4w9WgXcQ' }))).toBeVisible();
    await page.getByRole('button', { name: en('vid.save') }).click();
    await expect(page.getByText(en('vid.saved'))).toBeVisible();
    const insert = mock.requests.filter((r) => r.path === '/rest/v1/gym_exercise_videos' && r.method === 'POST').at(-1);
    expect(insert?.body).toEqual({ gym_id: GYM_A.id, exercise_id: 'flat_db_press', video_id: 'dQw4w9WgXcQ', start_seconds: 15, end_seconds: null });
    expect(JSON.stringify(mock.requests)).not.toContain('youtu.be');
    expect(JSON.stringify(mock.requests)).not.toContain('share123');

    // Change it: an update of the allowed columns, not an upsert.
    await page.getByLabel(en('vid.paste')).fill('https://www.youtube.com/shorts/aaaaaaaaaaa');
    await page.getByRole('button', { name: en('vid.save') }).click();
    await expect(page.getByText(en('vid.saved'))).toBeVisible();
    const patch = mock.requests.filter((r) => r.path === '/rest/v1/gym_exercise_videos' && r.method === 'PATCH').at(-1);
    expect(patch?.body).toEqual({ video_id: 'aaaaaaaaaaa', start_seconds: null, end_seconds: null });
    expect(mock.requests.some((r) => r.search.includes('on_conflict'))).toBe(false);

    // After a reload everything comes back from the server.
    await page.reload();
    await expect(page.locator('.pic-card')).toHaveCount(3);
    await expect(page.locator('.pic-card').first().locator('.pic-badge')).toHaveText(en('pic.cover'));
    await expect(page.getByText(en('vid.yours'))).toBeVisible();
    await expect(page.getByRole('link', { name: new RegExp(en('vid.open')) })).toHaveAttribute('href', 'https://www.youtube.com/watch?v=aaaaaaaaaaa');

    // Pictures come from the one cloud path with the fixed sizes only.
    expect(mock.cdn.length).toBeGreaterThan(0);
    for (const u of mock.cdn) expect(u).toMatch(new RegExp(`^${CLOUD_PATH}c_limit,w_(160|640),f_webp,q_auto/exercises/ek-[0-9]{4}-(tension|relaxation)\\.png$`));

    // Remove the video: members see the library video again.
    await page.getByRole('button', { name: en('vid.remove') }).click();
    await expect(page.getByText(en('vid.removed'))).toBeVisible();
    expect(mock.videos).toEqual([]);

    // Back to the list: it shows what was chosen.
    await page.getByRole('link', { name: en('ex.back') }).click();
    await expect(rows(page).filter({ hasText: 'Flat Dumbbell Press' })).toContainText(en('ex.picsMany', { count: 3 }));
  });

  test('remove all pictures, with a warning before leaving unsaved changes', async ({ page }) => {
    const mock = await open(page, {
      path: exercisePath('leg_press'),
      pictures: [1, 2].map((n) => ({ gym_id: GYM_A.id, exercise_id: 'leg_press', public_id: pid('ek-0102', n === 1 ? 'tension' : 'relaxation'), position: n })),
    });
    await expect(page.locator('.pic-card')).toHaveCount(2);
    await page.getByRole('button', { name: en('pic.removeAll') }).click();
    await expect(page.getByText(en('pic.emptyTitle'))).toBeVisible();

    // Leaving now asks first; "cancel" stays.
    page.once('dialog', (dialog) => {
      expect(dialog.message()).toBe(en('ex.leave'));
      void dialog.dismiss();
    });
    if (isPhone(page)) await page.getByRole('link', { name: en('ex.back') }).click();
    else await page.getByRole('navigation', { name: en('app.mainNav') }).getByRole('link', { name: en('nav.members') }).click();
    await expect(page).toHaveURL(exercisePath('leg_press'));

    await page.getByRole('button', { name: en('pic.save') }).click();
    await expect(page.getByText(en('pic.saved'))).toBeVisible();
    expect(mock.rpcs.at(-1)?.body.p_public_ids).toEqual([]);
    expect(mock.pictures).toEqual([]);
  });
});

test.describe('exercise media states', () => {
  test('loading error with retry', async ({ page }) => {
    const mock = await open(page, { path: EXERCISES_PATH, mediaFails: true });
    await expect(page.getByRole('heading', { name: en('state.errorTitle') })).toBeVisible();
    mock.set({ mediaFails: false });
    await page.getByRole('button', { name: en('state.retry') }).click();
    await expect(rows(page)).toHaveCount(36);
  });

  test('offline: what is loaded stays, saving and searching wait', async ({ page, context }) => {
    await open(page, { path: exercisePath('abs') });
    await expect(page.getByRole('heading', { level: 1, name: 'Abs' })).toBeVisible();
    await context.setOffline(true);
    await expect(page.getByRole('status').getByText(en('state.offline'))).toBeVisible();
    await expect(page.getByText(en('pic.searchOffline'))).toBeVisible();
    await page.getByLabel(en('vid.paste')).fill('https://youtu.be/dQw4w9WgXcQ');
    await expect(page.getByRole('button', { name: en('vid.save') })).toBeDisabled();
    await expect(page.getByRole('button', { name: en('pic.searchGo') })).toBeDisabled();
    await context.setOffline(false);
    await expect(page.getByRole('button', { name: en('vid.save') })).toBeEnabled();
  });

  test('server refusals show fixed messages and keep the draft', async ({ page }) => {
    const mock = await open(page, { path: exercisePath('abs'), savePictures: 'too_many_pictures_in_gym', saveVideo: 'forbidden' });
    await page.getByLabel(en('pic.searchLabel')).fill('squat');
    await page.getByRole('button', { name: en('pic.searchGo') }).click();
    await page.getByRole('button', { name: en('pic.frame', { frame: en('pic.start'), name: 'Barbell Squat' }) }).click();
    await page.getByRole('button', { name: en('pic.save') }).click();
    await expect(page.getByRole('alert').filter({ hasText: en('media.errGymPictures') })).toBeVisible();
    await expect(page.locator('.pic-card')).toHaveCount(1);
    mock.set({ savePictures: 'ok' });
    await page.getByRole('button', { name: en('pic.save') }).click();
    await expect(page.getByText(en('pic.saved'))).toBeVisible();

    await page.getByLabel(en('vid.paste')).fill('https://youtu.be/dQw4w9WgXcQ');
    await page.getByRole('button', { name: en('vid.save') }).click();
    await expect(page.getByRole('alert').filter({ hasText: en('media.errForbidden') })).toBeVisible();
  });

  test('the 6-picture limit', async ({ page }) => {
    const ids = ['ek-0055', 'ek-0056', 'ek-0101'].flatMap((k) => [pid(k, 'tension'), pid(k, 'relaxation')]);
    await open(page, { path: exercisePath('abs'), pictures: ids.map((id, i) => ({ gym_id: GYM_A.id, exercise_id: 'abs', public_id: id, position: i + 1 })) });
    await expect(page.locator('.pic-card')).toHaveCount(6);
    await expect(page.getByText(en('pic.full', { max: 6 }))).toBeVisible();
    await page.getByLabel(en('pic.searchLabel')).fill('leg');
    await page.getByRole('button', { name: en('pic.searchGo') }).click();
    await expect(page.getByRole('button', { name: en('pic.frame', { frame: en('pic.start'), name: 'Leg Press' }) })).toBeDisabled();
  });
});
