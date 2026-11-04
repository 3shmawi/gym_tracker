import { GYM_A, expect, test } from './fixtures/supabase';
import { msg } from './fixtures/helpers';
import { ADD_CAPTAIN_PATH, MEMBERS_PATH, open, rowOf } from './fixtures/members';

const en = (key: Parameters<typeof msg>[1], values?: Record<string, string | number>) => msg('en', key, values);

test.describe('members list', () => {
  test('shows the counts, the tabs and every person with role and status', async ({ page }) => {
    await open(page);
    await expect(page.getByRole('heading', { level: 1, name: en('members.title') })).toBeVisible();
    // 7 people are not ended; one of the two waiting people has a code that still works.
    await expect(page.getByText(en('members.peopleMany', { count: 7 }))).toBeVisible();
    await expect(page.getByText(en('members.codesOne'))).toBeVisible();

    const tabs = page.getByRole('group', { name: en('members.show') });
    await expect(tabs.getByRole('button', { name: `${en('members.tabAll')} 8` })).toHaveAttribute('aria-pressed', 'true');
    await expect(tabs.getByRole('button', { name: `${en('members.tabActive')} 5` })).toBeVisible();
    await expect(tabs.getByRole('button', { name: `${en('members.tabWaiting')} 2` })).toBeVisible();
    await expect(tabs.getByRole('button', { name: `${en('members.tabEnded')} 1` })).toBeVisible();

    await expect(rowOf(page, 'Sara Owner')).toContainText(en('members.roleOwner'));
    await expect(rowOf(page, 'Sara Owner')).toContainText(en('members.statusActive'));
    await expect(rowOf(page, 'Omar Captain')).toContainText(en('members.roleCaptain'));
    await expect(rowOf(page, 'Ahmed Hassan')).toContainText(en('members.roleTrainee'));
    await expect(rowOf(page, 'Ahmed Hassan')).toContainText(en('members.permTargets'));
    await expect(rowOf(page, 'Mona Ali')).toContainText(`${en('members.permTargets')} · ${en('members.permPlan')}`);
    await expect(rowOf(page, 'Youssef Khaled')).toContainText(en('members.permNone'));
    await expect(rowOf(page, 'Layla Ibrahim')).toContainText(en('members.statusCodeSent'));
    await expect(rowOf(page, 'Layla Ibrahim')).toContainText(en('members.expiresMany', { count: 5 }));
    await expect(rowOf(page, 'Karim Nabil')).toContainText(en('members.statusCodeExpired'));
    await expect(rowOf(page, 'Hana Adel')).toContainText(en('members.statusEnded'));
  });

  test('the tabs filter the list', async ({ page }) => {
    await open(page);
    const tabs = page.getByRole('group', { name: en('members.show') });
    await tabs.getByRole('button', { name: `${en('members.tabWaiting')} 2` }).click();
    await expect(rowOf(page, 'Layla Ibrahim')).toBeVisible();
    await expect(rowOf(page, 'Karim Nabil')).toBeVisible();
    await expect(rowOf(page, 'Ahmed Hassan')).toHaveCount(0);

    await tabs.getByRole('button', { name: `${en('members.tabEnded')} 1` }).click();
    await expect(rowOf(page, 'Hana Adel')).toBeVisible();
    await expect(rowOf(page, 'Layla Ibrahim')).toHaveCount(0);

    await tabs.getByRole('button', { name: `${en('members.tabActive')} 5` }).click();
    await expect(rowOf(page, 'Mona Ali')).toBeVisible();
    await expect(rowOf(page, 'Hana Adel')).toHaveCount(0);
  });

  test('search finds a name, and says so when nobody matches', async ({ page }) => {
    await open(page);
    const search = page.getByRole('searchbox', { name: en('members.search') });
    await search.fill('mon');
    await expect(rowOf(page, 'Mona Ali')).toBeVisible();
    await expect(rowOf(page, 'Ahmed Hassan')).toHaveCount(0);

    await search.fill('zzz');
    await expect(page.getByRole('heading', { name: en('members.noMatchTitle', { query: 'zzz' }) })).toBeVisible();
    await page.getByRole('button', { name: en('members.clearSearch') }).click();
    await expect(search).toHaveValue('');
    await expect(rowOf(page, 'Ahmed Hassan')).toBeVisible();
  });

  test('an empty tab offers to show everyone', async ({ page }) => {
    const mock = await open(page, { path: MEMBERS_PATH });
    // Only active people left: the Ended tab is empty.
    mock.members.splice(0, mock.members.length, ...mock.members.filter((m) => m.status === 'active'));
    await page.reload();
    await page.getByRole('group', { name: en('members.show') }).getByRole('button', { name: `${en('members.tabEnded')} 0` }).click();
    await expect(page.getByRole('heading', { name: en('members.noneHereTitle') })).toBeVisible();
    await page.getByRole('button', { name: en('members.showEveryone') }).click();
    await expect(rowOf(page, 'Ahmed Hassan')).toBeVisible();
  });

  test('a gym with only its owner shows the empty state with Add trainees', async ({ page }) => {
    const mock = await open(page);
    mock.members.splice(1);
    await page.reload();
    await expect(page.getByRole('heading', { name: en('members.emptyTitle') })).toBeVisible();
    await page.getByRole('main').getByRole('link', { name: en('members.addTrainees') }).last().click();
    await expect(page).toHaveURL(/\/members\/add$/);
  });

  test('the members request never asks for the secret half of a code', async ({ page }) => {
    const mock = await open(page);
    await expect(rowOf(page, 'Ahmed Hassan')).toBeVisible();
    const invites = mock.requests.filter((r) => r.path === '/rest/v1/invites');
    expect(invites.length).toBeGreaterThan(0);
    for (const request of invites) expect(decodeURIComponent(request.search)).not.toContain('code');
    expect(JSON.stringify(mock.requests)).not.toContain('code_hmac');
  });

  test('an owner sees "Add a captain"; Add trainees opens the add page', async ({ page }) => {
    await open(page);
    await expect(page.getByRole('link', { name: en('members.addCaptain') })).toBeVisible();
    await page.getByRole('link', { name: en('members.addTrainees') }).first().click();
    await expect(page).toHaveURL(new RegExp(`/g/${GYM_A.id}/members/add$`));
    await expect(page.getByRole('heading', { level: 1, name: en('add.titleTrainees') })).toBeVisible();
  });

  test('a captain does not see "Add a captain"', async ({ page }) => {
    await open(page, { gyms: [{ ...GYM_A, role: 'captain' }] });
    await expect(page.getByRole('link', { name: en('members.addTrainees') }).first()).toBeVisible();
    await expect(page.getByRole('link', { name: en('members.addCaptain') })).toHaveCount(0);
  });

  test('a captain opening /add-captain gets the "only the owner" message', async ({ page }) => {
    await open(page, { gyms: [{ ...GYM_A, role: 'captain' }], path: ADD_CAPTAIN_PATH });
    await expect(page.getByRole('heading', { name: en('add.onlyOwnerTitle') })).toBeVisible();
    await expect(page.getByText(en('add.onlyOwnerBody'))).toBeVisible();
    await expect(page.getByLabel(en('add.names'))).toHaveCount(0);
  });

  test('Arabic: the list is right to left with Arabic labels', async ({ page }) => {
    await open(page, { lang: 'ar' });
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
    await expect(page.getByRole('heading', { level: 1, name: msg('ar', 'members.title') })).toBeVisible();
    await expect(rowOf(page, 'Ahmed Hassan')).toBeVisible();
  });
});
