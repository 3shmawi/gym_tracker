import type { Page } from '@playwright/test';
import { GYM_A, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { ADD_PATH, MEMBERS_PATH, ROSTER, chooseFile, open, xlsx } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const CODE = /^[A-HJKMNP-Z2-9]{6}$/;
const namesBox = (page: Page) => page.getByLabel(en('add.names'), { exact: true });

/** Types names the way a person does: one line at a time, Enter between them. */
async function typeNames(page: Page, names: readonly string[]): Promise<void> {
  await namesBox(page).click();
  for (const [i, name] of names.entries()) {
    if (i > 0) await page.keyboard.press('Enter');
    await page.keyboard.type(name, { delay: 15 });
  }
}

test.describe('add trainees (the demo)', () => {
  test('type names, pick permissions, make codes, copy links, check and print', async ({ page }, info) => {
    await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
    const mock = await open(page, { delayMs: 250 });
    await page.getByRole('link', { name: en('members.addTrainees') }).first().click();
    await expect(page.getByRole('heading', { level: 1, name: en('add.titleTrainees') })).toBeVisible();
    await expect(page.getByRole('button', { name: en('add.makeNone') })).toBeDisabled();

    // 1. Names: two English, one Arabic.
    await typeNames(page, ['Nour Hassan', 'محمد علي', 'Salma Adel']);
    await expect(page.getByText(en('add.ready', { count: 3 }))).toBeVisible();

    // Permissions: the whole plan turns "weights and reps" on and locks it.
    const targets = page.getByRole('checkbox', { name: new RegExp(en('member.permTargets')) });
    const plan = page.getByRole('checkbox', { name: new RegExp(en('member.permPlan')) });
    const own = page.getByRole('checkbox', { name: new RegExp(en('member.permOwn')) });
    await expect(targets).toBeChecked();
    await plan.check();
    await expect(targets).toBeDisabled();
    await own.check();

    // 2. Make codes, with the progress shown.
    await page.getByRole('button', { name: en('add.make', { count: 3 }) }).click();
    await expect(page.getByRole('status').filter({ hasText: /Making codes \d of 3/ })).toBeVisible();
    const table = page.getByRole('table');
    await expect(table.getByRole('row')).toHaveCount(4);
    await expect(page.getByText(en('add.codesBanner'))).toBeVisible();
    await expect(page.getByRole('status').filter({ hasText: /Making codes/ })).toHaveCount(0);

    expect(mock.codes).toHaveLength(3);
    for (const code of mock.codes) expect(code).toMatch(CODE);
    for (const [i, name] of ['Nour Hassan', 'محمد علي', 'Salma Adel'].entries()) {
      const row = table.getByRole('row').nth(i + 1);
      await expect(row).toContainText(name);
      await expect(row.locator('.code')).toHaveText(mock.codes[i] ?? '');
    }
    // What was sent: pending trainees with the picked flags, created_by = my person row; one code each.
    expect(mock.inserts).toHaveLength(3);
    expect(mock.inserts[0]).toEqual({
      gym_id: GYM_A.id,
      display_name: 'Nour Hassan',
      role: 'trainee',
      can_edit_targets: true,
      can_edit_plan: true,
      can_build_own_plan: true,
      created_by: '22222222-2222-4222-8222-222222222222',
    });
    expect(mock.inserts.map((i) => i.display_name)).toEqual(['Nour Hassan', 'محمد علي', 'Salma Adel']);
    expect(mock.rpcs.map((r) => r.body.p_kind)).toEqual(['join', 'join', 'join']);

    // Copy links: "name<TAB>link" per line.
    await page.getByRole('button', { name: en('add.copyLinks') }).click();
    await expect(page.getByText(en('add.copied'))).toBeVisible();
    const clip = await page.evaluate(() => navigator.clipboard.readText());
    expect(clip).toBe(['Nour Hassan', 'محمد علي', 'Salma Adel'].map((n, i) => `${n}\thttps://azmm.pages.dev/join/${mock.codes[i]}`).join('\n'));

    // 3. Check and print: every QR is read back.
    await page.getByRole('button', { name: en('add.check', { count: 3 }) }).click();
    await expect(page.getByText(en('add.verified', { ok: 3, total: 3 }))).toBeVisible();
    await expect(page.getByText(en('add.cardsSummary', { cards: 3, pages: 1 }))).toBeVisible();
    await page.getByRole('button', { name: en('add.print', { count: 3 }) }).click();
    await expect.poll(() => page.evaluate(() => (window as unknown as { __printCalls?: number }).__printCalls ?? 0)).toBe(1);

    // The print view: one A4 page, three cards, each with a canvas QR, the code, and the EN + AR lines.
    await page.emulateMedia({ media: 'print' });
    await expect(page.locator('.print-page')).toHaveCount(1);
    await expect(page.locator('.pcard')).toHaveCount(3);
    await expect(page.locator('.pcard canvas')).toHaveCount(3);
    await expect(page.locator('.screen-only')).toBeHidden();
    await expect(page.locator('.hdr')).toBeHidden();
    const scanEn = en('print.scan');
    const scanAr = msg('ar', 'print.scan');
    for (const [i, card] of (await page.locator('.pcard').all()).entries()) {
      await expect(card).toContainText(GYM_A.name);
      await expect(card.locator('.c')).toHaveText(mock.codes[i] ?? '');
      await expect(card.locator('.u')).toHaveText(`https://azmm.pages.dev/join/${mock.codes[i]}`);
      await expect(card.locator('[lang="en"]').first()).toHaveText(scanEn);
      await expect(card.locator('[lang="ar"]').first()).toHaveText(scanAr);
      await expect(card.locator('[lang="ar"]').first()).toHaveAttribute('dir', 'rtl');
      await expect(card.locator('.qr')).toHaveAttribute('role', 'img');
    }
    // The canvas has the QR drawn (dark pixels exist) and is not empty.
    const dark = await page.locator('.pcard canvas').first().evaluate((canvas: HTMLCanvasElement) => {
      const data = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data ?? new Uint8ClampedArray();
      let n = 0;
      for (let i = 0; i < data.length; i += 4) if ((data[i] ?? 255) < 80) n++;
      return n;
    });
    expect(dark).toBeGreaterThan(500);

    // A PDF through Chromium's own print path (desktop only; the phone project shares the same engine).
    if (info.project.name === 'desktop') {
      const pdf = await page.pdf({ format: 'A4', printBackground: true, preferCSSPageSize: true });
      expect(pdf.byteLength).toBeGreaterThan(5_000);
      expect(pdf.subarray(0, 5).toString()).toBe('%PDF-');
      const pages = pdf.toString('latin1').match(/\/Type\s*\/Page[^s]/g)?.length ?? 0;
      expect(pages).toBe(1);
    }
    await page.emulateMedia({ media: 'screen' });
    await expect(page.locator('.screen-only')).toBeVisible();
  });

  test('five cards make two A4 pages', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH });
    await typeNames(page, ['One', 'Two', 'Three', 'Four', 'Five']);
    await page.getByRole('button', { name: en('add.make', { count: 5 }) }).click();
    await expect(page.getByRole('table').getByRole('row')).toHaveCount(6);
    await page.getByRole('button', { name: en('add.check', { count: 5 }) }).click();
    await page.getByRole('button', { name: en('add.print', { count: 5 }) }).click();
    await page.emulateMedia({ media: 'print' });
    await expect(page.locator('.print-page')).toHaveCount(2);
    await expect(page.locator('.print-page').first().locator('.pcard')).toHaveCount(4);
    await expect(page.locator('.print-page').last().locator('.pcard')).toHaveCount(1);
    expect(mock.codes).toHaveLength(5);
  });

  test('"Done" and "Back to the codes" work from the print step', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await typeNames(page, ['Nour']);
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await page.getByRole('button', { name: en('add.checkOne') }).click();
    await expect(page.getByText(en('add.verified', { ok: 1, total: 1 }))).toBeVisible();
    await page.getByRole('button', { name: en('add.backToCodes') }).click();
    await expect(page.getByRole('table')).toBeVisible();
  });

  test('the gym logo is fetched from the private bucket and the cards still read back', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH, gyms: [{ ...GYM_A, role: 'owner', logo: true }] });
    await typeNames(page, ['Nour']);
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await page.getByRole('button', { name: en('add.checkOne') }).click();
    await expect(page.getByText(en('add.verified', { ok: 1, total: 1 }))).toBeVisible();
    expect(mock.storage).toEqual([`gym-logos/${GYM_A.id}/logo.png`]);
  });

  test('a missing gym logo falls back to the app icon, never to a failed page', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH, gyms: [{ ...GYM_A, role: 'owner', logo: true }], logoFile: 'missing' });
    await typeNames(page, ['Nour']);
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await page.getByRole('button', { name: en('add.checkOne') }).click();
    await expect(page.getByText(en('add.verified', { ok: 1, total: 1 }))).toBeVisible();
    expect(mock.storage).toHaveLength(1);
  });

  test('adding a captain (owner): the flags stay off and the page says captain', async ({ page }) => {
    const mock = await open(page, { path: `${MEMBERS_PATH}/add-captain` });
    await expect(page.getByRole('heading', { level: 1, name: en('add.titleCaptain') })).toBeVisible();
    await expect(page.getByRole('checkbox')).toHaveCount(0);
    await typeNames(page, ['Captain Mariam']);
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await expect(page.getByRole('table').getByRole('row')).toHaveCount(2);
    expect(mock.inserts[0]).toMatchObject({ role: 'captain', can_edit_targets: false, can_edit_plan: false, can_build_own_plan: false });
  });
});

test.describe('add trainees: when something fails', () => {
  test('the 2nd insert fails (board 1.5 G): 2 of 3 made, "Try again for 1" makes the last', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH, failInsertAt: [2] });
    await typeNames(page, ['Nour Hassan', 'Salma Adel', 'Omar Khaled']);
    await page.getByRole('button', { name: en('add.make', { count: 3 }) }).click();

    const alert = page.getByRole('alert').filter({ hasText: en('add.partial', { done: 2, total: 3 }) });
    await expect(alert).toBeVisible();
    await expect(alert).toContainText(en('add.partialWho'));
    await expect(alert).toContainText('Salma Adel');
    await expect(alert).toContainText(en('fail.server'));
    await expect(page.getByRole('table').getByRole('row')).toHaveCount(3);
    expect(mock.codes).toHaveLength(2);

    await alert.getByRole('button', { name: en('add.retry', { count: 1 }) }).click();
    await expect(page.getByRole('table').getByRole('row')).toHaveCount(4);
    await expect(page.getByRole('alert')).toHaveCount(0);
    expect(mock.codes).toHaveLength(3);
    expect(mock.inserts.map((i) => i.display_name)).toEqual(['Nour Hassan', 'Omar Khaled', 'Salma Adel']);
    // The three codes are all in the table.
    for (const code of mock.codes) await expect(page.getByRole('table').getByText(code, { exact: true })).toBeVisible();
  });

  test('no code could be made at all: "No codes were made" and nothing to print', async ({ page }) => {
    await open(page, { path: ADD_PATH, failInsertAt: [1, 2] });
    await typeNames(page, ['Nour', 'Salma']);
    await page.getByRole('button', { name: en('add.make', { count: 2 }) }).click();
    await expect(page.getByText(en('add.partialNone'))).toBeVisible();
    await expect(page.getByRole('button', { name: /Check and print/ })).toHaveCount(0);
  });

  test('the member is saved but the code is refused: "waiting", and retry only asks for a code', async ({ page }) => {
    const mock = await open(page, { path: ADD_PATH, createInvite: 'forbidden' });
    await typeNames(page, ['Nour', 'Salma']);
    await page.getByRole('button', { name: en('add.make', { count: 2 }) }).click();
    const alert = page.getByRole('alert').filter({ hasText: en('add.partialNone') });
    await expect(alert).toBeVisible();
    await expect(alert.getByText(en('add.waitingNote'))).toHaveCount(2);
    mock.set({ createInvite: 'ok' });
    await alert.getByRole('button', { name: en('add.retry', { count: 2 }) }).click();
    await expect(page.getByRole('table').getByRole('row')).toHaveCount(3);
    // No second membership was inserted: only codes were asked for.
    expect(mock.inserts).toHaveLength(2);
  });

  test('too many names: the page offers to keep the first 50', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await namesBox(page).fill(Array.from({ length: 52 }, (_, i) => `Name ${i + 1}`).join('\n'));
    await expect(page.getByText(en('add.errTooMany', { max: 50, count: 52 }))).toBeVisible();
    await expect(page.getByRole('button', { name: /Make \d+ codes/ })).toBeDisabled();
    await page.getByRole('button', { name: en('add.keepFirst', { max: 50 }) }).click();
    await expect(page.getByText(en('add.ready', { count: 50 }))).toBeVisible();
    await expect(page.getByRole('button', { name: en('add.make', { count: 50 }) })).toBeEnabled();
  });

  test('a name over 40 characters is marked by its line', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await namesBox(page).fill(`Short\n${'x'.repeat(41)}`);
    await expect(page.getByText(en('add.errTooLong', { line: 2, max: 40 }))).toBeVisible();
    await expect(page.getByRole('button', { name: en('add.make', { count: 2 }) })).toBeDisabled();
  });

  test('repeated and empty lines are reported, not dropped silently', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await namesBox(page).fill('Nour\n\nNour\nSalma');
    await expect(page.getByText(en('add.skippedEmpty', { count: 1 }))).toBeVisible();
    await expect(page.getByText(en('add.repeated', { names: 'Nour' }))).toBeVisible();
    await expect(page.getByText(en('add.ready', { count: 3 }))).toBeVisible();
  });
});

test.describe('add trainees: leaving while codes are shown', () => {
  async function withCodes(page: Page) {
    await page.goto('/');
    await page.getByRole('link', { name: en('members.addTrainees') }).first().click();
    await typeNames(page, ['Nour']);
    await page.getByRole('button', { name: en('add.makeOne') }).click();
    await expect(page.getByRole('table')).toBeVisible();
  }

  test('clicking the header brand asks: dismiss stays, accept leaves', async ({ page }) => {
    await open(page, { path: MEMBERS_PATH });
    await withCodes(page);
    const messages: string[] = [];
    page.once('dialog', (dialog) => {
      messages.push(dialog.type() + ':' + dialog.message());
      void dialog.dismiss();
    });
    await page.locator('.hdr .brand').click();
    await expect.poll(() => messages.length).toBe(1);
    expect(messages[0]).toMatch(/^confirm:/);
    expect(messages[0]).toContain(en('add.leaveTitle'));
    await expect(page).toHaveURL(/\/members\/add$/);
    await expect(page.getByRole('table')).toBeVisible();

    page.once('dialog', (dialog) => void dialog.accept());
    await page.locator('.hdr .brand').click();
    await expect(page).not.toHaveURL(/\/members\/add$/);
  });

  test('browser Back asks too', async ({ page }) => {
    await open(page, { path: MEMBERS_PATH });
    await withCodes(page);
    page.once('dialog', (dialog) => void dialog.dismiss());
    await page.goBack();
    await expect(page).toHaveURL(/\/members\/add$/);
    await expect(page.getByRole('table')).toBeVisible();

    page.once('dialog', (dialog) => void dialog.accept());
    await page.goBack();
    await expect(page).toHaveURL(/\/members$/);
  });

  test('the "All members" link opens a Stay / Leave dialog', async ({ page }) => {
    await open(page, { path: MEMBERS_PATH });
    await withCodes(page);
    await page.getByRole('main').getByRole('link', { name: en('nav.members') }).click();
    const dialog = page.getByRole('dialog', { name: en('add.leaveTitle') });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: en('add.stay') })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
    await expect(page.getByRole('table')).toBeVisible();

    await page.getByRole('main').getByRole('link', { name: en('nav.members') }).click();
    await page.getByRole('dialog').getByRole('button', { name: en('add.leave') }).click();
    await expect(page).toHaveURL(/\/members$/);
    await expect(page.getByRole('heading', { level: 1, name: en('members.title') })).toBeVisible();
  });

  test('on the names step nothing asks', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await typeNames(page, ['Nour']);
    let asked = false;
    page.on('dialog', (dialog) => {
      asked = true;
      void dialog.dismiss();
    });
    await page.getByRole('main').getByRole('link', { name: en('nav.members') }).click();
    await expect(page).toHaveURL(/\/members$/);
    expect(asked).toBe(false);
  });
});

test.describe('names from Excel, CSV and paste', () => {
  const sheet = (page: Page) => page.getByText(en('imp.column'));

  test('a real .xlsx: pick the column, the title row, and use the names', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await page.getByText(en('imp.upload'), { exact: true }).waitFor();
    await chooseFile(page, { name: 'roster.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', buffer: ROSTER });
    await expect(page.getByText(en('imp.firstSheet', { file: 'roster.xlsx' }))).toBeVisible();

    const column = page.getByLabel(en('imp.column'));
    await expect(column.locator('option')).toHaveText(['A · Joined', 'B · Name']);
    // Column A holds dates (numbers) — pick B.
    await column.selectOption({ label: 'B · Name' });
    const title = page.getByRole('checkbox', { name: new RegExp(en('imp.titleRow')) });
    await expect(title).toBeChecked();
    await expect(page.getByText(en('imp.titleRowHint', { first: 'Name' }))).toBeVisible();
    // 4 names after the title row; the empty cell and the repeated name are reported.
    await expect(page.getByRole('button', { name: en('imp.use', { count: 4 }) })).toBeVisible();
    await expect(page.getByText(en('imp.skippedEmpty', { count: 1 }))).toBeVisible();
    await expect(page.getByText(en('imp.repeated', { name: 'Nour Hassan' }))).toBeVisible();
    await expect(page.getByText(en('imp.andMore', { count: 1 }))).toBeVisible();

    // If row 1 isn't a title, the header counts as a name.
    await title.uncheck();
    await expect(page.getByRole('button', { name: en('imp.use', { count: 5 }) })).toBeVisible();
    await title.check();

    await page.getByRole('button', { name: en('imp.use', { count: 4 }) }).click();
    await expect(namesBox(page)).toHaveValue('Nour Hassan\nSalma Adel\nOmar Khaled\nNour Hassan');
    await expect(page.getByText(en('add.ready', { count: 4 }))).toBeVisible();
    await expect(page.getByText(en('add.repeated', { names: 'Nour Hassan' }))).toBeVisible();
    await expect(sheet(page)).toHaveCount(0);
  });

  test('Cancel leaves the list alone', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await namesBox(page).fill('Keep Me');
    await chooseFile(page, { name: 'roster.xlsx', mimeType: 'application/octet-stream', buffer: ROSTER });
    await page.getByRole('button', { name: en('imp.cancel') }).click();
    await expect(namesBox(page)).toHaveValue('Keep Me');
    await expect(page.getByText(en('imp.upload'), { exact: true })).toBeVisible();
  });

  test('an old .xls says how to save it as .xlsx', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'old.xls', mimeType: 'application/vnd.ms-excel', buffer: Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0]) });
    await expect(page.getByRole('alert')).toBeVisible();
    await expect(page.getByText(en('imp.oldExcel'))).toBeVisible();
    await expect(page.getByText(en('imp.pasteWorks'))).toBeVisible();
    await expect(page.getByText(en('imp.chooseOther'))).toBeVisible();
  });

  test('a password-protected workbook says it has a password', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'locked.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0]) });
    await expect(page.getByRole('alert')).toContainText(en('imp.locked'));
  });

  test('a PDF is the wrong type', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'names.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4\n') });
    await expect(page.getByRole('alert')).toContainText(en('imp.wrongType'));
    await expect(namesBox(page)).toHaveValue('');
  });

  test('a file over 1 MB is too big, and is not read', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'huge.csv', mimeType: 'text/csv', buffer: Buffer.alloc(1024 * 1024 + 16, 'a') });
    await expect(page.getByRole('alert')).toContainText(en('imp.tooBig'));
  });

  test('a file named .xlsx that is not a workbook is unreadable', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'fake.xlsx', mimeType: 'application/octet-stream', buffer: Buffer.from('this is not a zip file at all') });
    await expect(page.getByRole('alert')).toContainText(en('imp.unreadable'));
  });

  test('a workbook with no names says so', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'blank.xlsx', mimeType: 'application/octet-stream', buffer: xlsx([['Name'], [null]]) });
    await expect(page.getByText(en('imp.noNames'))).toBeVisible();
    await expect(page.getByRole('button', { name: /Use these/ })).toBeDisabled();
  });

  test('a .csv with ";" as the delimiter', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await chooseFile(page, { name: 'names.csv', mimeType: 'text/csv', buffer: Buffer.from('Name;Phone\nAhmed;010\nمنى;011\n', 'utf8') });
    await expect(page.getByLabel(en('imp.column')).locator('option')).toHaveText(['A · Name', 'B · Phone']);
    await page.getByRole('button', { name: en('imp.use', { count: 2 }) }).click();
    await expect(namesBox(page)).toHaveValue('Ahmed\nمنى');
  });

  test('more than 50 names: the first 50 go in and the next row is named', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    const rows: (string | null)[][] = [['Name'], ...Array.from({ length: 60 }, (_, i) => [`Person ${i + 1}`])];
    await chooseFile(page, { name: 'big.xlsx', mimeType: 'application/octet-stream', buffer: xlsx(rows) });
    await expect(page.getByText(en('imp.found', { count: 60, max: 50 }))).toBeVisible();
    await expect(page.getByText(en('imp.firstGo', { max: 50, row: 52 }))).toBeVisible();
    await page.getByRole('button', { name: en('imp.useFirst', { max: 50 }) }).click();
    await expect(page.getByText(en('add.ready', { count: 50 }))).toBeVisible();
  });

  test('a column pasted from Excel (tab between cells) keeps the first column', async ({ page }) => {
    await open(page, { path: ADD_PATH });
    await namesBox(page).fill('Ahmed\t010\nMona\t011');
    await expect(page.getByText(en('add.ready', { count: 2 }))).toBeVisible();
    await page.getByRole('button', { name: en('add.make', { count: 2 }) }).click();
    const table = page.getByRole('table');
    await expect(table.getByRole('row')).toHaveCount(3);
    await expect(table).toContainText('Ahmed');
    await expect(table).not.toContainText('010');
  });
});
