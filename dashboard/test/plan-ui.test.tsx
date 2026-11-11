import { render } from 'preact';
import { act } from 'preact/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { failed, ok } from '../src/core/result';
import type { MediaRepository } from '../src/exercises/media';
import type { ManagedGym } from '../src/gyms/gyms';
import { I18nContext, makeI18n, translate, type MessageKey } from '../src/i18n';
import type { Member, MembersRepository } from '../src/members/members';
import { PlanPage } from '../src/pages/PlanPage';
import type { Plan } from '../src/plans/model';
import type { PlansRepository, StoredPlan } from '../src/plans/plans';
import type { TemplatesRepository } from '../src/plans/templates';

const GYM = 'b0000000-0000-4000-8000-000000000001';
const id = (n: number) => `a0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const gym: ManagedGym = { id: GYM, name: 'Power Gym', role: 'owner', logoPath: null, historyAfterEnd: 'readable', memberCount: 3 };
const en = (key: MessageKey, p?: Record<string, string | number>) => translate('en', key, p);
const member = (n: number, name: string, over: Partial<Member> = {}): Member => ({ id: id(n), name, role: 'trainee', status: 'active', permissions: { editTargets: false, editPlan: false, buildOwnPlan: false }, joinedAt: null, endedAt: null, createdAt: new Date(), invite: { state: 'none' }, ...over });
const people = [member(1, 'Ahmed'), member(2, 'Mona'), member(3, 'Hana', { status: 'ended' })];
const plan: Plan = { days: [{ id: 'day-1', name: { ar: 'صدر', en: 'Chest' }, exercises: [{ id: 'abs', name: { ar: 'بطن', en: 'Abs' }, sets: 3, reps: 15, rest: 90, step: 5, superset: false, unit: 'kg' }] }] };
const stored = (p: Plan | null, version: number): StoredPlan => ({ plan: p, version, unreadable: false, updatedBy: null, updatedAt: null });

function setup(over: Partial<Record<keyof PlansRepository, unknown>> = {}) {
  const plans = { get: vi.fn(() => Promise.resolve(ok(stored(plan, 2)))), save: vi.fn(() => Promise.resolve(ok({ version: 3 }))), version: vi.fn(), versions: vi.fn(() => Promise.resolve(ok(new Map([[id(2), 1]])))), replace: vi.fn(() => Promise.resolve(ok({ version: 2 }))), ...over };
  const members = { list: vi.fn(() => Promise.resolve(ok(people))) } as unknown as MembersRepository;
  const media = { load: vi.fn(() => Promise.resolve(failed({ kind: 'server' }))) } as unknown as MediaRepository;
  const templates = { list: vi.fn(() => Promise.resolve(ok([]))), link: vi.fn(() => Promise.resolve(ok({ templateId: null, templateVersion: null }))) } as unknown as TemplatesRepository;
  return { plans, members, media, templates };
}

let host: HTMLElement;
beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
});
afterEach(async () => {
  await act(() => { render(null, host); });
  host.remove();
});
const flush = () => act(async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); });
async function mount(s: ReturnType<typeof setup>, memberId = id(1)) {
  await act(() => {
    render(<I18nContext.Provider value={makeI18n('en')}><PlanPage gym={gym} memberId={memberId} members={s.members} plans={s.plans as unknown as PlansRepository} templates={s.templates} media={s.media} cloudName={null} online /></I18nContext.Provider>, host);
  });
  await flush();
}
const button = (label: string) => {
  const b = [...host.querySelectorAll('button')].find((x) => x.textContent.trim() === label || x.getAttribute('aria-label') === label);
  if (!b) throw new Error(`no button ${label}`);
  return b;
};
async function setNumber(label: string, value: string) {
  const input = host.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
  if (!input) throw new Error(label);
  await act(() => {
    input.value = value;
    input.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

describe('PlanPage state', () => {
  it('edit → dirty → save with the version it loaded → saved', async () => {
    const s = setup();
    await mount(s);
    expect(button(en('plan.save')).disabled).toBe(true);
    await setNumber(en('plan.setsFor', { name: 'Abs' }), '6');
    expect(host.textContent).toContain(en('plan.unsaved'));
    await act(() => { button(en('plan.save')).click(); });
    await flush();
    expect(s.plans.save).toHaveBeenCalledWith(id(1), 2, expect.objectContaining({ days: [expect.objectContaining({ exercises: [expect.objectContaining({ sets: 6 })] })] }));
    expect(host.textContent).toContain(en('plan.saved', { name: 'Ahmed' }));
  });

  it('a conflict shows both sides and loads the newest; nothing is saved', async () => {
    const theirs: Plan = { days: [{ ...plan.days[0], id: 'day-1', name: { ar: 'صدر', en: 'Push' }, exercises: plan.days[0]?.exercises ?? [] }] };
    const get = vi.fn().mockResolvedValueOnce(ok(stored(plan, 2))).mockResolvedValue(ok(stored(theirs, 3)));
    const save = vi.fn(() => Promise.resolve(failed({ kind: 'conflict', reason: 'plan_changed' })));
    const s = setup({ get, save });
    await mount(s);
    await setNumber(en('plan.repsFor', { name: 'Abs' }), '20');
    await act(() => { button(en('plan.save')).click(); });
    await flush();
    expect(host.textContent).toContain(en('conflict.title'));
    expect(host.textContent).toContain(en('diff.dayRenamed', { from: 'Chest', to: 'Push' }));
    expect(host.textContent).toContain(en('diff.targets', { day: 'Chest', exercise: 'Abs', fields: en('diff.f.reps') }));
    await act(() => { button(en('conflict.load')).click(); });
    await flush();
    expect(host.querySelector('h2')?.textContent).toBe('Push');
    expect(save).toHaveBeenCalledTimes(1);
  });

  it('empty, then a first plan saved at version 0', async () => {
    const s = setup({ get: vi.fn(() => Promise.resolve(ok(stored(null, 0)))) });
    await mount(s);
    expect(host.textContent).toContain(en('plan.emptyTitle'));
    await act(() => { button(en('plan.start')).click(); });
    await act(() => { button(en('plan.save')).click(); });
    await flush();
    expect(s.plans.save).toHaveBeenCalledWith(id(1), 0, { days: [expect.objectContaining({ name: { ar: 'اليوم ١', en: 'Day 1' }, exercises: [] })] });
  });

  it('copy offers active members only, then reports each one', async () => {
    const s = setup();
    await mount(s);
    await act(() => { button(en('plan.copy')).click(); });
    await flush();
    const dialog = host.querySelector('[role="dialog"]');
    expect(dialog?.textContent).toContain('Mona');
    expect(dialog?.textContent).not.toContain('Hana');
    expect(dialog?.textContent).toContain(en('copy.hasPlan'));
    const box = dialog?.querySelector<HTMLInputElement>('input[type="checkbox"]');
    await act(() => { box?.click(); });
    expect(dialog?.textContent).toContain(en('copy.replaceOne'));
    await act(() => { button(en('copy.goOne')).click(); });
    await flush();
    expect(s.plans.replace).toHaveBeenCalledWith(id(2), plan);
    expect(dialog?.textContent).toContain(en('copy.done', { ok: 1, total: 1 }));
  });

  it('error with retry', async () => {
    const get = vi.fn().mockResolvedValueOnce(failed({ kind: 'server' })).mockResolvedValue(ok(stored(plan, 1)));
    const s = setup({ get });
    await mount(s);
    expect(host.textContent).toContain(en('state.errorTitle'));
    await act(() => { button(en('state.retry')).click(); });
    await flush();
    expect(host.textContent).toContain(en('plan.title', { name: 'Ahmed' }));
  });
});
