import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { CLOUDINARY, GYM_A, GYM_B, M, SUPABASE, expect, samplePlan, test, type FakePlan, type FakeTemplate } from './fixtures/supabase';
import { msg, type Lang, type Theme } from './fixtures/helpers';
import { memberPath, open, type OpenOptions } from './fixtures/members';

const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'];
const planPath = (id: string) => `${memberPath(id)}/plan`;
const TEMPLATES = `/g/${GYM_A.id}/templates`;
const TPL = 'f0000000-0000-4000-8000-00000000000a';
const PAYLOAD = '<img src=x onerror=alert(1)>';
const tpl = (over: Partial<FakeTemplate> = {}): FakeTemplate => ({ id: TPL, gym_id: GYM_A.id, name: { ar: 'دفع وسحب', en: 'Push / Pull' }, body: samplePlan(), version: 1, updated_at: '2026-11-09T10:00:00Z', ...over });
const linked = (version: number): FakePlan => ({ body: samplePlan(), version, updated_by: M.owner, updated_at: '2026-11-09T10:00:00Z', template_id: TPL, template_version: 1 });
const abs = (lang: Lang) => (lang === 'ar' ? 'بطن' : 'Abs');

interface Screen {
  name: string;
  options: OpenOptions;
  ready: (page: Page, lang: Lang) => Promise<void>;
}

const screens: Screen[] = [
  { name: 'templates list', options: { path: TEMPLATES, templates: [tpl()] }, ready: async (page, lang) => { await expect(page.getByRole('heading', { level: 1, name: msg(lang, 'tpl.title') })).toBeVisible(); } },
  { name: 'templates, none yet', options: { path: TEMPLATES }, ready: async (page, lang) => { await expect(page.getByRole('heading', { name: msg(lang, 'tpl.emptyTitle') })).toBeVisible(); } },
  {
    name: 'plan with a template change',
    options: { path: planPath(M.ahmed), templates: [tpl()], plans: { [M.ahmed]: linked(2) } },
    ready: async (page, lang) => {
      await page.getByLabel(msg(lang, 'plan.setsFor', { name: abs(lang) })).fill('5');
      await page.getByLabel(msg(lang, 'plan.setsFor', { name: abs(lang) })).press('Enter');
      await expect(page.getByRole('button', { name: msg(lang, 'tpl.resetName', { name: abs(lang) }) })).toBeVisible();
    },
  },
  {
    name: 'replace dialog',
    options: { path: planPath(M.youssef), templates: [tpl()] },
    ready: async (page, lang) => {
      await page.getByRole('button', { name: msg(lang, 'tpl.replace') }).click();
      await expect(page.getByRole('dialog')).toBeVisible();
    },
  },
  {
    name: 'apply-to-everyone dialog',
    options: { path: planPath(M.ahmed), templates: [tpl()], plans: { [M.ahmed]: { ...linked(2), body: (() => { const b = samplePlan() as { days: { exercises: { id: string; sets: number }[] }[] }; const e = b.days[0]?.exercises.find((x) => x.id === 'abs'); if (e) e.sets = 5; return b; })() }, [M.mona]: linked(1) } },
    ready: async (page, lang) => {
      await page.getByRole('button', { name: msg(lang, 'tpl.applyAll') }).click();
      await expect(page.getByRole('dialog').getByText('Mona Ali')).toBeVisible();
    },
  },
];

const looks: { lang: Lang; theme: Theme }[] = [
  { lang: 'en', theme: 'light' },
  { lang: 'ar', theme: 'dark' },
];

for (const screen of screens) {
  for (const { lang, theme } of looks) {
    test(`axe: ${screen.name} (${lang} ${theme})`, async ({ page }) => {
      await open(page, { ...screen.options, lang, theme });
      await screen.ready(page, lang);
      const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
      expect(results.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
    });
  }
}

test.describe('templates: security', () => {
  test('crafted gym id in the templates URL: not found; another gym: forbidden; nothing asked', async ({ page }) => {
    const mock = await open(page, { path: '/g/not-a-uuid/templates', templates: [tpl()] });
    await expect(page.getByRole('heading', { name: msg('en', 'state.notFoundTitle') })).toBeVisible();
    await page.goto(`/g/${GYM_B.id}/templates`);
    await expect(page.getByRole('heading', { name: msg('en', 'state.forbiddenTitle') })).toBeVisible();
    expect(mock.requests.some((r) => r.path === '/rest/v1/plan_templates')).toBe(false);
  });

  test('a hostile template name renders as text; a malformed body is not offered', async ({ page }) => {
    const dialogs: string[] = [];
    page.on('dialog', (d) => {
      dialogs.push(d.message());
      void d.dismiss();
    });
    await open(page, { path: TEMPLATES, templates: [tpl({ name: { ar: PAYLOAD, en: PAYLOAD } }), tpl({ id: 'f0000000-0000-4000-8000-00000000000c', name: { ar: 'خطأ', en: 'Broken' }, body: { days: [], evil: true } })] });
    await expect(page.getByText(PAYLOAD).first()).toBeVisible();
    await expect(page.getByText(msg('en', 'tpl.unreadable'))).toBeVisible();
    await expect(page.locator('main img')).toHaveCount(0);
    await page.goto(planPath(M.youssef));
    await page.getByRole('button', { name: msg('en', 'tpl.replace') }).click();
    await expect(page.getByRole('dialog').getByText('Broken')).toHaveCount(0);
    expect(dialogs).toEqual([]);
  });

  test('a 41-character or hidden-character template name is cleaned or refused before saving', async ({ page }) => {
    const mock = await open(page, { path: planPath(M.ahmed), plans: { [M.ahmed]: { body: samplePlan(), version: 1, updated_by: null, updated_at: '2026-11-09T10:00:00Z' } } });
    await page.getByRole('button', { name: msg('en', 'tpl.saveAs') }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel(msg('en', 'name.en')).fill('x'.repeat(41));
    await expect(dialog.getByRole('button', { name: msg('en', 'name.save') })).toBeDisabled();
    await dialog.getByLabel(msg('en', 'name.en')).fill(`Push${String.fromCharCode(0x202e)}\n Day`);
    await dialog.getByLabel(msg('en', 'name.ar')).fill("'; DROP TABLE plan_templates; --");
    await dialog.getByRole('button', { name: msg('en', 'name.save') }).click();
    await expect(page.getByText(msg('en', 'tpl.saved', { name: 'Push Day' }))).toBeVisible();
    expect(mock.templates[0]?.name).toEqual({ ar: "'; DROP TABLE plan_templates; --", en: 'Push Day' });
  });

  test('every request goes to the site, the project or the picture path; nothing kept', async ({ page }) => {
    const origins = new Set<string>();
    page.on('request', (r) => {
      const u = new URL(r.url());
      if (u.protocol === 'http:' || u.protocol === 'https:') origins.add(u.origin);
    });
    await open(page, { path: planPath(M.youssef), templates: [tpl()] });
    await page.getByRole('button', { name: msg('en', 'tpl.replace') }).click();
    await page.getByRole('dialog').getByRole('button', { name: msg('en', 'tpl.replaceGo') }).click();
    await expect(page.getByText(msg('en', 'tpl.replaced', { name: 'Youssef Khaled', template: 'Push / Pull' }))).toBeVisible();
    for (const o of origins) expect(['http://localhost:4173', SUPABASE, CLOUDINARY]).toContain(o);
    expect((await page.evaluate(() => Object.keys(localStorage))).sort()).toEqual(['azm.dashboard.prefs.v1', 'sb-abcdefghijklmnopqrst-auth-token']);
    expect(await page.evaluate(() => JSON.stringify(Object.entries(sessionStorage)) + location.href)).not.toContain('Push');
  });
});
