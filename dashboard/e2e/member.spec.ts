import { GYM_A, M, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { memberPath, open } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);
const CODE = /^[A-HJKMNP-Z2-9]{6}$/;
const owner = [{ ...GYM_A, role: 'owner' as const }];
const captain = [{ ...GYM_A, role: 'captain' as const }];

const saveButton = (page: import('@playwright/test').Page) => page.getByRole('button', { name: en('member.save'), exact: true });
const endButton = (page: import('@playwright/test').Page) => page.getByRole('main').getByRole('button', { name: en('member.end'), exact: true });

test.describe('member page: permissions', () => {
  test('whole plan checks and locks "weights and reps"; Save sends the flags', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.ahmed) });
    await expect(page.getByRole('heading', { level: 1, name: 'Ahmed Hassan' })).toBeVisible();
    const targets = page.getByRole('checkbox', { name: new RegExp(en('member.permTargets')) });
    const plan = page.getByRole('checkbox', { name: new RegExp(en('member.permPlan')) });
    await expect(targets).toBeChecked();
    await expect(targets).toBeEnabled();
    await expect(saveButton(page)).toBeDisabled();

    await plan.check();
    await expect(targets).toBeChecked();
    await expect(targets).toBeDisabled();
    await expect(page.getByText(en('member.permTargetsAuto'))).toBeVisible();
    await saveButton(page).click();

    await expect(page.getByRole('status').filter({ hasText: en('member.saved') })).toBeVisible();
    expect(mock.patches).toEqual([{ id: M.ahmed, body: { can_edit_targets: true, can_edit_plan: true, can_build_own_plan: false } }]);
    await expect(saveButton(page)).toBeDisabled();
  });

  test('a trainee with nothing can be given "build their own plan"', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.youssef) });
    await page.getByRole('checkbox', { name: new RegExp(en('member.permOwn')) }).check();
    await saveButton(page).click();
    await expect(page.getByText(en('member.saved'))).toBeVisible();
    expect(mock.patches.at(-1)?.body).toEqual({ can_edit_targets: false, can_edit_plan: false, can_build_own_plan: true });
  });

  test('renaming sends only the name', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.youssef) });
    await page.getByLabel(en('member.name')).fill('Youssef K.');
    await saveButton(page).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Youssef K.' })).toBeVisible();
    expect(mock.patches.at(-1)?.body).toEqual({ display_name: 'Youssef K.' });
  });

  test('an empty name cannot be saved', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.youssef) });
    await page.getByLabel(en('member.name')).fill('   ');
    await expect(page.getByText(en('member.nameInvalid'))).toBeVisible();
    await expect(saveButton(page)).toBeDisabled();
    expect(mock.patches).toHaveLength(0);
  });

  test('an unknown member says it cannot find them', async ({ page }) => {
    await open(page, { path: memberPath('bbbbbbbb-0000-4000-8000-000000000999') });
    await expect(page.getByRole('heading', { name: en('member.notFoundTitle') })).toBeVisible();
  });
});

test.describe('member page: who can change whom', () => {
  test('a captain opening a captain sees a read-only page', async ({ page }) => {
    const mock = await open(page, { gyms: captain, path: memberPath(M.captain) });
    await expect(page.getByText(en('member.readOnlyCaptain'))).toBeVisible();
    await expect(saveButton(page)).toHaveCount(0);
    await expect(page.getByLabel(en('member.name'))).toBeDisabled();
    await expect(endButton(page)).toBeDisabled();
    expect(mock.patches).toHaveLength(0);
  });

  test('a captain opening the owner sees the owner message', async ({ page }) => {
    await open(page, { gyms: captain, path: memberPath(M.owner) });
    await expect(page.getByText(en('member.readOnlyOwner'))).toBeVisible();
    await expect(saveButton(page)).toHaveCount(0);
  });

  test('a captain can change a trainee but the role is the owner\'s to change', async ({ page }) => {
    await open(page, { gyms: captain, path: memberPath(M.ahmed) });
    await expect(page.getByLabel(en('member.role'), { exact: true })).toBeDisabled();
    await expect(page.getByText(en('member.roleOwnerOnly'))).toBeVisible();
    await expect(endButton(page)).toBeEnabled();
  });

  test('an owner changes a captain into a trainee', async ({ page }) => {
    const mock = await open(page, { gyms: owner, path: memberPath(M.captain) });
    await page.getByLabel(en('member.role'), { exact: true }).selectOption('trainee');
    // The plan options appear for a trainee.
    await expect(page.getByRole('checkbox', { name: new RegExp(en('member.permPlan')) })).toBeVisible();
    await saveButton(page).click();
    await expect(page.getByText(en('member.saved'))).toBeVisible();
    expect(mock.patches).toEqual([{ id: M.captain, body: { role: 'trainee', can_edit_targets: false, can_edit_plan: false, can_build_own_plan: false } }]);
    await expect(page.getByRole('main').getByText(en('members.roleTrainee'), { exact: true }).first()).toBeVisible();
  });

  test('the last owner cannot step down: the message says nothing changed', async ({ page }) => {
    const mock = await open(page, { gyms: owner, path: memberPath(M.owner), patch: 'last_owner' });
    await page.getByLabel(en('member.role'), { exact: true }).selectOption('captain');
    await saveButton(page).click();
    const alert = page.getByRole('alert').filter({ hasText: en('fail.lastOwner') });
    await expect(alert).toBeVisible();
    await expect(alert).toContainText(en('fail.nothingChanged'));
    expect(mock.patches).toHaveLength(1);
    await alert.getByRole('button', { name: en('fail.ok') }).click();
    await expect(alert).toHaveCount(0);
  });

  test('when RLS filters the row out (no row back) the message is "you can\'t make this change"', async ({ page }) => {
    await open(page, { gyms: captain, path: memberPath(M.ahmed), patch: 'rls_empty' });
    await page.getByRole('checkbox', { name: new RegExp(en('member.permOwn')) }).check();
    await saveButton(page).click();
    await expect(page.getByRole('alert').filter({ hasText: en('fail.forbidden') })).toBeVisible();
    await expect(page.getByText(en('member.saved'))).toHaveCount(0);
  });
});

test.describe('member page: end membership', () => {
  test('a dialog asks first; Escape cancels and focus returns; Confirm ends it', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.ahmed) });
    await endButton(page).click();
    const dialog = page.getByRole('dialog', { name: en('member.endTitle', { name: 'Ahmed Hassan' }) });
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(en('member.endConfirmBody'));
    await expect(dialog.getByRole('button', { name: en('member.cancel') })).toBeFocused();

    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
    await expect(endButton(page)).toBeFocused();
    expect(mock.patches).toHaveLength(0);

    await endButton(page).click();
    await page.getByRole('dialog').getByRole('button', { name: en('member.end'), exact: true }).click();
    await expect(page.getByText(en('member.ended'), { exact: true })).toBeVisible();
    expect(mock.patches).toEqual([{ id: M.ahmed, body: { status: 'ended' } }]);
    await expect(page.getByText(en('member.endedNote'))).toBeVisible();
    await expect(saveButton(page)).toHaveCount(0);
    await expect(endButton(page)).toHaveCount(0);
  });

  test('Cancel keeps the membership', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.mona) });
    await endButton(page).click();
    await page.getByRole('dialog').getByRole('button', { name: en('member.cancel') }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    expect(mock.patches).toHaveLength(0);
  });

  test('a gym that locks history after the end says so in the page and in the dialog', async ({ page }) => {
    await open(page, { gyms: [{ ...GYM_A, role: 'owner', historyAfterEnd: 'locked' }], path: memberPath(M.ahmed) });
    await expect(page.getByText(en('member.endBodyLocked'))).toBeVisible();
    await expect(page.getByText(en('member.endBody'), { exact: true })).toHaveCount(0);
    await endButton(page).click();
    await expect(page.getByRole('dialog')).toContainText(en('member.endConfirmBodyLocked'));
  });

  test('a gym that keeps history readable uses the readable wording', async ({ page }) => {
    await open(page, { path: memberPath(M.ahmed) });
    await expect(page.getByText(en('member.endBody'), { exact: true })).toBeVisible();
  });

  test('an ended member shows the note and no actions', async ({ page }) => {
    await open(page, { path: memberPath(M.hana) });
    await expect(page.getByText(en('member.endedNote'))).toBeVisible();
    await expect(saveButton(page)).toHaveCount(0);
    await expect(endButton(page)).toHaveCount(0);
  });
});

test.describe('member page: codes', () => {
  test('a new join code for someone waiting is shown once, with a print card', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.layla) });
    await expect(page.getByRole('heading', { name: en('member.sectionPending') })).toBeVisible();
    await page.getByRole('button', { name: en('members.makeNewCode') }).click();

    const section = page.getByRole('region', { name: en('member.codeTitle', { name: 'Layla Ibrahim' }) });
    await expect(section).toBeVisible();
    await expect(section.getByText(en('member.codeOnce'))).toBeVisible();
    const code = (await section.locator('.code').textContent()) ?? '';
    expect(code).toMatch(CODE);
    expect(mock.rpcs).toEqual([{ name: 'create_invite', body: { p_membership_id: M.layla, p_kind: 'join' } }]);
    expect(mock.codes).toEqual([code]);

    // Printing needs a QR that read back; the card holds name, QR and code.
    await section.getByRole('button', { name: en('member.printCard') }).click();
    await expect.poll(() => page.evaluate(() => (window as unknown as { __printCalls?: number }).__printCalls ?? 0)).toBe(1);
    await page.emulateMedia({ media: 'print' });
    await expect(page.locator('.print-page')).toHaveCount(1);
    await expect(page.locator('.pcard')).toHaveCount(1);
    await expect(page.locator('.pcard canvas')).toHaveCount(1);
    await expect(page.locator('.pcard')).toContainText(code);
    await expect(page.locator('.pcard')).toContainText('Layla Ibrahim');
    await expect(page.locator('.screen-only')).toBeHidden();
    await page.emulateMedia({ media: 'screen' });

    // Done hides the code for good: it is not on the page again after a reload.
    await section.getByRole('button', { name: en('member.codeDone') }).click();
    await expect(section).toHaveCount(0);
  });

  test('the code is not in the page again after leaving and coming back', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.layla) });
    await page.getByRole('button', { name: en('members.makeNewCode') }).click();
    await expect(page.locator('.code')).toBeVisible();
    page.once('dialog', (dialog) => void dialog.accept());
    await page.reload();
    await expect(page.getByRole('heading', { level: 1, name: 'Layla Ibrahim' })).toBeVisible();
    await expect(page.locator('.code')).toHaveCount(0);
    expect(await page.content()).not.toContain(mock.codes[0]);
  });

  test('revoking the sent code', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.layla) });
    await page.getByRole('button', { name: en('member.revoke') }).click();
    await expect(page.getByText(en('member.revoked'))).toBeVisible();
    expect(mock.rpcs).toEqual([{ name: 'revoke_invite', body: { p_invite_id: mock.invites[0]?.id } }]);
    // No usable code is left, so there is nothing to revoke any more.
    await expect(page.getByRole('button', { name: en('member.revoke') })).toHaveCount(0);
  });

  test('someone with an expired code gets a new one', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.karim) });
    await expect(page.getByRole('main').getByText(en('members.statusCodeExpired'))).toBeVisible();
    await page.getByRole('button', { name: en('members.makeNewCode') }).click();
    await expect(page.locator('.code')).toHaveText(CODE);
    expect(mock.rpcs[0]?.body).toEqual({ p_membership_id: M.karim, p_kind: 'join' });
  });

  test('a recovery code for an active member', async ({ page }) => {
    const mock = await open(page, { path: memberPath(M.ahmed) });
    await expect(page.getByRole('heading', { name: en('member.sectionPhone') })).toBeVisible();
    await page.getByRole('button', { name: en('member.makeRecovery') }).click();
    await expect(page.locator('.code')).toHaveText(CODE);
    expect(mock.rpcs).toEqual([{ name: 'create_invite', body: { p_membership_id: M.ahmed, p_kind: 'recover' } }]);
  });

  test('a recovery code for someone in another gym explains why (board 1.5 F)', async ({ page }) => {
    await open(page, { path: memberPath(M.ahmed), createInvite: 'person_in_other_gym' });
    await page.getByRole('button', { name: en('member.makeRecovery') }).click();
    const alert = page.getByRole('alert');
    await expect(alert).toContainText(en('fail.otherGymTitle'));
    await expect(alert).toContainText(en('fail.otherGym', { name: 'Ahmed Hassan' }));
    await expect(page.locator('.code')).toHaveCount(0);
  });

  test('a refused code ("forbidden") shows the forbidden message', async ({ page }) => {
    await open(page, { path: memberPath(M.layla), createInvite: 'forbidden' });
    await page.getByRole('button', { name: en('members.makeNewCode') }).click();
    await expect(page.getByRole('alert')).toContainText(en('fail.forbidden'));
    await expect(page.locator('.code')).toHaveCount(0);
  });

  test('leaving while a code is shown asks first: Cancel stays, OK leaves', async ({ page }) => {
    await open(page, { path: memberPath(M.layla) });
    await page.getByRole('button', { name: en('members.makeNewCode') }).click();
    await expect(page.locator('.code')).toBeVisible();

    const messages: string[] = [];
    page.once('dialog', (dialog) => {
      messages.push(dialog.message());
      void dialog.dismiss();
    });
    await page.getByRole('link', { name: en('member.back') }).click();
    await expect.poll(() => messages.length).toBe(1);
    expect(messages[0]).toContain(en('member.codeOnce'));
    await expect(page).toHaveURL(new RegExp(`${M.layla}$`));
    await expect(page.locator('.code')).toBeVisible();

    page.once('dialog', (dialog) => void dialog.accept());
    await page.getByRole('link', { name: en('member.back') }).click();
    await expect(page).toHaveURL(/\/members$/);
  });
});

test.describe('member page: what a captain opens it for comes first', () => {
  test('the plan card and progress sit above the name and permissions', async ({ page }) => {
    await open(page, { path: memberPath(M.ahmed) });
    const plan = page.getByRole('heading', { name: en('member.sectionPlan') });
    const details = page.getByRole('heading', { name: en('member.sectionName') });
    await expect(plan).toBeVisible();
    const a = await plan.boundingBox();
    const b = await details.boundingBox();
    expect(a && b && a.y < b.y).toBe(true);
  });
});
