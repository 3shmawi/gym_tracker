import { CLOUDINARY, CLOUD_PATH, GYM_A, GYM_B, SUPABASE, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { open } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const LIST = `/g/${GYM_A.id}/exercises`;
const one = (id: string) => `${LIST}/${id}`;
const PAYLOAD = '<img src=x onerror=alert(1)>';
const RLO = String.fromCharCode(0x202e);

test.describe('crafted URLs', () => {
  for (const id of ['nope', 'LEG_PRESS', 'ex-abc', '..%2f..%2fplans', "abs'%20or%201=1", '%3Cscript%3E', '__proto__', 'abs%00']) {
    test(`exercise id "${id}" is not found and never reaches the server`, async ({ page }) => {
      const mock = await open(page, { path: one(id) });
      await expect(page.getByRole('heading', { name: en('state.notFoundTitle') })).toBeVisible();
      expect(mock.requests.some((r) => r.path.includes('gym_exercise') || r.search.includes(id))).toBe(false);
    });
  }

  test('a gym the person does not manage: forbidden, nothing of it is asked', async ({ page }) => {
    const mock = await open(page, { path: `/g/${GYM_B.id}/exercises` }); // open() manages gym A only
    await expect(page.getByRole('heading', { name: en('state.forbiddenTitle') })).toBeVisible();
    expect(mock.requests.some((r) => r.search.includes(GYM_B.id))).toBe(false);
  });
});

test.describe('hostile data from the server', () => {
  test('bad picture rows and video ids are dropped; titles are text', async ({ page }) => {
    const dialogs: string[] = [];
    page.on('dialog', (d) => {
      dialogs.push(d.message());
      void d.dismiss();
    });
    const mock = await open(page, {
      path: one('abs'),
      pictures: [
        { gym_id: GYM_A.id, exercise_id: 'abs', public_id: 'https://evil.example/x.png', position: 1 },
        { gym_id: GYM_A.id, exercise_id: 'abs', public_id: 'exercises/ek-0099-tension', position: 2 },
      ],
      videos: [{ gym_id: GYM_A.id, exercise_id: 'abs', video_id: 'javascript:a', start_seconds: null, end_seconds: null }],
      catalogExtra: [
        { public_id: 'exercises/ek-0099-tension', exercise_key: 'ek-0099', frame: 'tension', title_en: `${PAYLOAD} Ab${RLO}s`, keywords: ['abs'] },
        { public_id: 'exercises/../../evil', exercise_key: 'ek-0098', frame: 'tension', title_en: 'evil', keywords: ['abs'] },
      ],
    });
    await expect(page.locator('.pic-card')).toHaveCount(1);
    await expect(page.locator('.pic-card .cap')).toContainText(PAYLOAD);
    expect(await page.locator('main').innerText()).not.toMatch(/[‪-‮⁦-⁩]/);
    await expect(page.getByText(en('vid.library'))).toBeVisible();

    await page.getByLabel(en('pic.searchLabel')).fill('abs');
    await page.getByRole('button', { name: en('pic.searchGo') }).click();
    await expect(page.locator('.res-card')).toHaveCount(1);
    await expect(page.locator('main [onerror]')).toHaveCount(0);
    for (const src of await page.locator('main img').evaluateAll((els) => els.map((e) => e.getAttribute('src') ?? ''))) {
      expect(src.startsWith(`${CLOUDINARY}${CLOUD_PATH}`)).toBe(true);
    }
    expect(mock.cdn.some((u) => u.includes('evil'))).toBe(false);
    expect(dialogs).toEqual([]);
  });
});

test.describe('hostile links and words', () => {
  const links = [
    'javascript:alert(document.domain)',
    'https://youtube.com@evil.example/watch?v=dQw4w9WgXcQ',
    'https://www.youtube.com/watch?v=dQw4w9WgX%63Q',
    `https://youtu.be/dQw4w9WgXcQ${RLO}`,
    'https://www.yоutube.com/watch?v=dQw4w9WgXcQ',
    `https://youtu.be/dQw4w9WgXcQ?x=${'a'.repeat(2100)}`,
    PAYLOAD,
  ];
  test('refused links never leave the page; nothing is fetched from YouTube', async ({ page }) => {
    const seen: string[] = [];
    page.on('request', (r) => seen.push(r.url()));
    const mock = await open(page, { path: one('abs') });
    const input = page.getByLabel(en('vid.paste'));
    for (const link of links) {
      await input.fill(link);
      await expect(page.getByText(en('vid.bad'))).toBeVisible();
      await expect(page.getByRole('button', { name: en('vid.save') })).toBeDisabled();
    }
    // A good link: still no request to YouTube (no thumbnail, no oEmbed).
    await input.fill('https://youtu.be/dQw4w9WgXcQ');
    await page.getByRole('button', { name: en('vid.save') }).click();
    await expect(page.getByText(en('vid.saved'))).toBeVisible();
    expect(seen.filter((u) => /youtube|youtu\.be|ytimg|evil\.example/.test(u))).toEqual([]);
    expect(mock.videos.map((v) => v.video_id)).toEqual(['dQw4w9WgXcQ']);
  });

  test('injection-like search words are sent as plain values', async ({ page }) => {
    const mock = await open(page, { path: one('abs') });
    await page.getByLabel(en('pic.searchLabel')).fill("press') or 1=1; drop table exercise_images; --");
    await page.getByRole('button', { name: en('pic.searchGo') }).click();
    await expect(page.locator('.res-card').first()).toBeVisible();
    const search = mock.requests.filter((r) => r.path === '/rest/v1/exercise_images').at(-1);
    const keywords = new URLSearchParams(search?.search).get('keywords');
    expect(keywords).toBe('ov.{press,or,1,drop,table}');
  });
});

test.describe('nothing leaves, nothing is kept', () => {
  test('every request goes to this site, the project or the picture path', async ({ page }) => {
    const origins = new Set<string>();
    page.on('request', (r) => {
      const u = new URL(r.url());
      if (u.protocol === 'http:' || u.protocol === 'https:') origins.add(u.origin);
    });
    const mock = await open(page, { path: LIST, pictures: [{ gym_id: GYM_A.id, exercise_id: 'abs', public_id: 'exercises/ek-0055-tension', position: 1 }] });
    await page.locator('.ex-row').filter({ hasText: 'Flat Dumbbell Press' }).click();
    await page.getByLabel(en('pic.searchLabel')).fill('press');
    await page.getByRole('button', { name: en('pic.searchGo') }).click();
    await page.getByRole('button', { name: en('pic.addBothLabel', { name: 'Dumbbell Bench Press' }) }).click();
    await page.getByRole('button', { name: en('pic.save') }).click();
    await expect(page.getByText(en('pic.saved'))).toBeVisible();
    expect([...origins].sort()).toEqual(['http://localhost:4173', CLOUDINARY, SUPABASE].sort());
    for (const u of mock.cdn) expect(u.startsWith(CLOUD_PATH)).toBe(true);
  });

  test('the CSP allows pictures from the one cloud path only', async ({ request }) => {
    const res = await request.get('/_headers');
    const csp = /Content-Security-Policy: (.+)/.exec(await res.text())?.[1] ?? '';
    expect(/img-src ([^;]+)/.exec(csp)?.[1]).toBe(`'self' ${CLOUDINARY}${CLOUD_PATH}`);
    expect(/connect-src ([^;]+)/.exec(csp)?.[1]).not.toContain('cloudinary');
  });

  test('no link, video id or picture choice is stored in the browser', async ({ page }) => {
    await open(page, { path: one('abs') });
    await page.getByLabel(en('vid.paste')).fill('https://youtu.be/dQw4w9WgXcQ?si=secretshare');
    await page.getByRole('button', { name: en('vid.save') }).click();
    await expect(page.getByText(en('vid.saved'))).toBeVisible();
    const stored = await page.evaluate(() => JSON.stringify(Object.entries(localStorage)) + JSON.stringify(Object.entries(sessionStorage)) + document.cookie + location.href);
    expect(stored).not.toContain('dQw4w9WgXcQ');
    expect(stored).not.toContain('secretshare');
    expect((await page.evaluate(() => Object.keys(localStorage))).sort()).toEqual(['azm.dashboard.prefs.v1', 'sb-abcdefghijklmnopqrst-auth-token']);
  });
});
