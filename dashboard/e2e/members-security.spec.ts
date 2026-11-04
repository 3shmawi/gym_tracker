import { expect, test, SUPABASE, GYM_A, M, seedMembers } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { ADD_PATH, MEMBERS_PATH, memberPath, open, rowOf } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
// Built here, not typed, so the source file holds no hidden direction character.
const RLO = String.fromCharCode(0x202e);
const LRI = String.fromCharCode(0x2066);
const PAYLOAD = '<img src=x onerror=alert(1)>';

test.describe('hostile names render as text', () => {
  test('typed names: no element is created, no alert fires, the override is removed', async ({ page }) => {
    const dialogs: string[] = [];
    page.on('dialog', (dialog) => {
      dialogs.push(dialog.message());
      void dialog.dismiss();
    });
    const mock = await open(page, { path: ADD_PATH });
    await page.getByLabel(en('add.names'), { exact: true }).fill([PAYLOAD, `Mo${RLO}na`, `Li${LRI}la`].join('\n'));
    await expect(page.getByText(en('add.cleaned'))).toBeVisible();
    await page.getByRole('button', { name: en('add.make', { count: 3 }) }).click();
    const table = page.getByRole('table');
    await expect(table.getByRole('row')).toHaveCount(4);

    // The payload is text in the cell; there is no image in the page at all.
    await expect(table.getByRole('row').nth(1).locator('b')).toHaveText(PAYLOAD);
    await expect(page.locator('main img')).toHaveCount(0);
    await expect(page.locator('main [onerror]')).toHaveCount(0);
    // The hidden direction characters never reach the table or the server.
    expect(await table.innerText()).not.toMatch(/[\u202A-\u202E\u2066-\u2069]/);
    expect(mock.inserts.map((i) => i.display_name)).toEqual([PAYLOAD, 'Mona', 'Lila']);
    expect(JSON.stringify(mock.inserts)).not.toMatch(/[\u202A-\u202E\u2066-\u2069]/);

    // Print view, too.
    await page.getByRole('button', { name: en('add.check', { count: 3 }) }).click();
    await page.getByRole('button', { name: en('add.print', { count: 3 }) }).click();
    await page.emulateMedia({ media: 'print' });
    await expect(page.locator('.pcard .n').first()).toHaveText(PAYLOAD);
    await expect(page.locator('.print-sheet img')).toHaveCount(0);
    expect(dialogs).toEqual([]);
  });

  test('names stored on the server (members list and member page)', async ({ page }) => {
    const dialogs: string[] = [];
    page.on('dialog', (dialog) => {
      dialogs.push(dialog.message());
      void dialog.dismiss();
    });
    const seed = seedMembers();
    const ahmed = seed.members.find((m) => m.id === M.ahmed);
    const mona = seed.members.find((m) => m.id === M.mona);
    if (!ahmed || !mona) throw new Error('seed changed');
    ahmed.display_name = PAYLOAD;
    mona.display_name = `Mo${RLO}na`;
    await open(page, { members: seed.members, invites: seed.invites });
    await expect(rowOf(page, 'Youssef Khaled')).toBeVisible();
    await expect(page.locator('main img')).toHaveCount(0);
    await expect(rowOf(page, PAYLOAD)).toBeVisible();
    await expect(rowOf(page, 'Mona')).toBeVisible();
    expect(await page.locator('main').innerText()).not.toMatch(/[\u202A-\u202E\u2066-\u2069]/);

    await page.goto(memberPath(M.ahmed));
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(PAYLOAD);
    await expect(page.locator('main img')).toHaveCount(0);
    await page.goto(memberPath(M.mona));
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Mona');
    expect(dialogs).toEqual([]);
  });

  test('a stored name over 40 characters or with control characters is shown cleaned', async ({ page }) => {
    const seed = seedMembers();
    const row = seed.members.find((m) => m.id === M.ahmed);
    if (!row) throw new Error('seed changed');
    row.display_name = `  Ahmed \u0000\u0007 \n  Samir  `;
    await open(page, { members: seed.members, invites: seed.invites, path: memberPath(M.ahmed) });
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Ahmed Samir');
  });

  test('a name typed on the member page is checked: 41 characters cannot be saved', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.youssef) });
    const input = page.getByLabel(en('member.name'));
    await input.fill('x'.repeat(60));
    // The input stops at 40; the saved value never exceeds it.
    await expect(input).toHaveValue('x'.repeat(40));
    await page.getByRole('button', { name: en('member.save'), exact: true }).click();
    expect(String(mock.patches.at(-1)?.body.display_name).length).toBeLessThanOrEqual(40);
  });
});

test.describe('nothing leaves, nothing is kept', () => {
  test('every request goes to this site or the fake project', async ({ page }) => {
    const origins = new Set<string>();
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (url.protocol === 'http:' || url.protocol === 'https:') origins.add(url.origin);
    });
    const mock = await open(page, { gyms: [{ ...GYM_A, role: 'owner', logo: true }], path: MEMBERS_PATH });
    await expect(rowOf(page, 'Ahmed Hassan')).toBeVisible();
    await page.goto(ADD_PATH);
    await page.getByLabel(en('add.names'), { exact: true }).fill('Nour\nSalma');
    await page.getByRole('button', { name: en('add.make', { count: 2 }) }).click();
    await page.getByRole('button', { name: en('add.check', { count: 2 }) }).click();
    await expect(page.getByText(en('add.verified', { ok: 2, total: 2 }))).toBeVisible();
    await page.getByRole('button', { name: en('add.print', { count: 2 }) }).click();
    await page.getByRole('button', { name: en('add.copyLinks') }).count();
    expect([...origins].sort()).toEqual(['http://localhost:4173', SUPABASE].sort());
    expect(mock.storage).toHaveLength(1);
  });

  test('the join link is only text on the page: no request to azmm.pages.dev, no image URL', async ({ page }) => {
    const seen: string[] = [];
    page.on('request', (request) => seen.push(request.url()));
    await open(page, { path: ADD_PATH });
    await page.getByLabel(en('add.names'), { exact: true }).fill('Nour');
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await page.getByRole('button', { name: en('add.checkOne') }).click();
    await page.getByRole('button', { name: en('add.printOne') }).click();
    await page.emulateMedia({ media: 'print' });
    expect(seen.filter((u) => u.startsWith('blob:') || u.startsWith('data:') || u.includes('azmm.pages.dev'))).toEqual([]);
    expect(await page.locator('main img, .print-sheet img, [src^="blob:"], [src^="data:"]').count()).toBe(0);
  });

  test('after making codes, storage and the URL hold no code', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH });
    await page.getByLabel(en('add.names'), { exact: true }).fill('Nour\nSalma\nOmar');
    await page.getByRole('button', { name: en('add.make', { count: 3 }) }).click();
    await expect(page.getByRole('table').getByRole('row')).toHaveCount(4);
    await page.getByRole('button', { name: en('add.check', { count: 3 }) }).click();
    await expect(page.getByText(en('add.verified', { ok: 3, total: 3 }))).toBeVisible();
    expect(mock.codes).toHaveLength(3);

    const stored = await page.evaluate(async () => {
      const dump = (storage: Storage) => JSON.stringify(Object.entries(storage));
      const all: string[] = [dump(localStorage), dump(sessionStorage), location.href, document.cookie];
      for (const db of await indexedDB.databases()) all.push(db.name ?? '');
      return all.join('\n');
    });
    for (const code of mock.codes) {
      expect(stored).not.toContain(code);
      expect(page.url()).not.toContain(code);
    }
    // The session is there (that is the sign-in), nothing else of ours.
    expect((await page.evaluate(() => Object.keys(localStorage))).sort()).toEqual(['azm.dashboard.prefs.v1', 'sb-abcdefghijklmnopqrst-auth-token']);
  });

  test('the member page code is not in storage or the URL either', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.layla) });
    await page.getByRole('button', { name: en('members.makeNewCode') }).click();
    await expect(page.locator('.code')).toBeVisible();
    const stored = await page.evaluate(() => JSON.stringify(Object.entries(localStorage)) + JSON.stringify(Object.entries(sessionStorage)) + location.href);
    expect(stored).not.toContain(mock.codes[0] ?? 'x');
  });

  test('a code made for someone is never in a later list response', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH });
    await page.getByLabel(en('add.names'), { exact: true }).fill('Nour');
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await expect(page.getByRole('table')).toBeVisible();
    await page.goto(MEMBERS_PATH);
    await expect(rowOf(page, 'Nour')).toBeVisible();
    await expect(rowOf(page, 'Nour')).toContainText(en('members.statusCodeSent'));
    expect(await page.content()).not.toContain(mock.codes[0]);
  });
});
