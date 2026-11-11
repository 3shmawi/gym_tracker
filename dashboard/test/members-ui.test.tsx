/* eslint-disable @typescript-eslint/no-unnecessary-type-parameters, @typescript-eslint/no-explicit-any */
import type { ComponentChildren } from 'preact';
import { render } from 'preact';
import { act } from 'preact/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { failed, ok } from '../src/core/result';
import type { Lang } from '../src/core/prefs';
import type { ManagedGym } from '../src/gyms/gyms';
import { I18nContext, makeI18n } from '../src/i18n';
import type { Member, MembersRepository, NewCode } from '../src/members/members';
import { AddMembersPage } from '../src/pages/AddMembersPage';
import { MemberPage } from '../src/pages/MemberPage';
import { MembersPage } from '../src/pages/MembersPage';

// jsdom has no canvas: the QR drawing is replaced. A code that starts with
// "Z" plays a QR that does not read back.
vi.mock('../src/invites/qr', async () => {
  const actual = await vi.importActual<typeof import('../src/invites/qr')>('../src/invites/qr');
  return {
    ...actual,
    drawQr: vi.fn((code: string) => ({ canvas: document.createElement('canvas'), verified: !code.startsWith('Z') })),
  };
});

const NOW = new Date();
const DAY = 86_400_000;
const GYM_ID = 'b0000000-0000-4000-8000-000000000001';
const ME = 'c0000000-0000-4000-8000-000000000001';
const id = (n: number) => `a0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const gym = (role: 'owner' | 'captain'): ManagedGym => ({ id: GYM_ID, name: 'Power Gym', role, logoPath: null, historyAfterEnd: 'readable', brandColor: null, memberCount: 5 });
const noFlags = { editTargets: false, editPlan: false, buildOwnPlan: false };

function member(n: number, over: Partial<Member> = {}): Member {
  return {
    id: id(n),
    name: `Person ${n}`,
    role: 'trainee',
    status: 'active',
    permissions: noFlags,
    joinedAt: new Date('2026-10-12T10:00:00Z'),
    endedAt: null,
    createdAt: new Date('2026-10-01T10:00:00Z'),
    invite: { state: 'none' },
    ...over,
  };
}

const sample: Member[] = [
  member(1, { name: 'Mohamed Hassan', role: 'owner' }),
  member(2, { name: 'Karim Adel', role: 'captain' }),
  member(3, { name: 'Ahmed Samir', permissions: { editTargets: true, editPlan: true, buildOwnPlan: false } }),
  member(4, { name: 'Mona Youssef', status: 'pending', joinedAt: null, invite: { state: 'sent', inviteId: id(104), expiresAt: new Date(NOW.getTime() + 5 * DAY - 3600_000), kind: 'join' } }),
  member(5, { name: 'Omar Tarek', status: 'pending', joinedAt: null, invite: { state: 'expired', expiresAt: new Date(NOW.getTime() - DAY) } }),
  member(6, { name: 'Sara Ramzy', status: 'ended', endedAt: new Date('2026-11-02T10:00:00Z') }),
];

type Async = Mock<(...args: any[]) => Promise<any>>;
interface Fake {
  repo: MembersRepository;
  list: Async;
  add: Async;
  newCode: Async;
  revokeInvite: Async;
  update: Async;
  end: Async;
  myPersonId: Async;
}

const newCode = (membershipId: string, name: string, code: string): NewCode => ({ membershipId, name, code, expiresAt: new Date('2026-11-11T10:00:00Z') });
let counter = 0;
const CODES = ['K7QM3D', 'PX4WNA', 'H2RT9V', 'B8ZEJC', 'ZZ4WNA'];

function fake(members: Member[] = sample, over: Partial<Record<keyof Omit<Fake, 'repo'>, unknown>> = {}): Fake {
  counter = 0;
  const f = {
    list: vi.fn(() => Promise.resolve(ok(members))),
    add: vi.fn((_g: string, _p: string, names: string[]) =>
      Promise.resolve(ok(names.map((name) => ({ ok: true as const, code: newCode(id(200 + counter), name, CODES[counter++] ?? 'AAAAAA') })))),
    ),
    newCode: vi.fn((membershipId: string, name: string) => Promise.resolve(ok(newCode(membershipId, name, 'K7QM3D')))),
    revokeInvite: vi.fn(() => Promise.resolve(ok(undefined))),
    update: vi.fn(() => Promise.resolve(ok(undefined))),
    end: vi.fn(() => Promise.resolve(ok(undefined))),
    myPersonId: vi.fn(() => Promise.resolve(ok(ME))),
    ...over,
  } as Omit<Fake, 'repo'>;
  return { ...f, repo: f as unknown as MembersRepository };
}

let host: HTMLElement;
const printSpy = vi.fn();
beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
  printSpy.mockClear();
  window.print = printSpy;
});
afterEach(async () => {
  await act(() => {
    render(null, host);
  });
  host.remove();
  vi.restoreAllMocks();
});

async function mount(node: ComponentChildren, lang: Lang = 'en') {
  await act(() => {
    render(null, host);
    render(<I18nContext.Provider value={makeI18n(lang)}>{node}</I18nContext.Provider>, host);
  });
  await flush();
}
const flush = () => act(async () => { await Promise.resolve(); });
const q = <T extends Element>(selector: string) => host.querySelector<T>(selector);
function m<T extends Element>(selector: string): T {
  const el = host.querySelector<T>(selector);
  if (!el) throw new Error(`missing ${selector}`);
  return el;
}
const all = (selector: string) => [...host.querySelectorAll<HTMLElement>(selector)];
const text = () => host.textContent;
function button(label: string | RegExp): HTMLButtonElement {
  const found = [...document.querySelectorAll('button')].find((b) => (typeof label === 'string' ? b.textContent.trim() === label : label.test(b.textContent)));
  if (!found) throw new Error(`no button ${String(label)}`);
  return found;
}
async function click(el: Element) {
  await act(() => { (el as HTMLElement).click(); });
  await flush();
}
async function type(el: HTMLInputElement | HTMLTextAreaElement, value: string) {
  await act(() => {
    el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
async function check(el: HTMLInputElement) {
  await act(() => { el.click(); });
}
const rows = () => all('table.t tbody tr');

describe('MembersPage', () => {
  it('shows a skeleton, then the list with counts, status text and permissions', async () => {
    const f = fake();
    await act(() => {
      render(<I18nContext.Provider value={makeI18n('en')}><MembersPage gym={gym('owner')} members={f.repo} /></I18nContext.Provider>, host);
    });
    expect(q('[aria-busy=true]')).not.toBeNull();
    expect(q('h1')?.textContent).toBe('Members');
    await flush();
    expect(q('[aria-busy=true]')).toBeNull();
    expect(f.list).toHaveBeenCalledWith(GYM_ID);
    expect(text()).toContain('5 people');
    expect(text()).toContain('1 code waiting to be used');
    expect(rows()).toHaveLength(6);
    const mona = rows().find((r) => r.textContent.includes('Mona'));
    expect(mona?.textContent).toContain('Code sent');
    expect(mona?.textContent).toContain('Expires in 5 days');
    expect(rows().find((r) => r.textContent.includes('Omar'))?.textContent).toContain('Code expired');
    expect(rows().find((r) => r.textContent.includes('Sara'))?.textContent).toContain('Ended');
    expect(rows().find((r) => r.textContent.includes('Ahmed'))?.textContent).toContain('Targets · Whole plan');
    expect(rows().find((r) => r.textContent.includes('Mohamed'))?.textContent).toContain('Everything');
    // a name is a link target with a plain-text name
    const manage = m<HTMLAnchorElement>('a[aria-label="Manage Ahmed Samir"]');
    expect(manage.getAttribute('href')).toBe(`/g/${GYM_ID}/members/${id(3)}`);
  });

  it('filters by segment and shows counts', async () => {
    const f = fake();
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />);
    const counts = all('.seg button').map((b) => b.textContent.replace(/\s+/g, ' ').trim());
    expect(counts).toEqual(['All 6', 'Active 3', 'Waiting to join 2', 'Ended 1']);
    await click(button(/^Waiting to join/));
    expect(rows().map((r) => r.querySelector('b')?.textContent)).toEqual(['Mona Youssef', 'Omar Tarek']);
    expect(button(/^Waiting to join/).getAttribute('aria-pressed')).toBe('true');
    await click(button(/^Ended/));
    expect(rows()).toHaveLength(1);
    await click(button(/^Active/));
    expect(rows()).toHaveLength(3);
  });

  it('searches by name, case-insensitively, in memory', async () => {
    const f = fake();
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />);
    const search = m<HTMLInputElement>('#member-search');
    expect(search.maxLength).toBe(40);
    await type(search, 'mO');
    expect(rows().map((r) => r.querySelector('b')?.textContent)).toEqual(['Mohamed Hassan', 'Mona Youssef']);
    await type(search, 'zz');
    expect(rows()).toHaveLength(0);
    expect(text()).toContain('No one called “zz”');
    await click(button('Clear search'));
    expect(rows()).toHaveLength(6);
    expect(f.list).toHaveBeenCalledTimes(1);
  });

  it('shows the empty state when there are no trainees', async () => {
    const f = fake([member(1, { name: 'Mohamed Hassan', role: 'owner' })]);
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />);
    expect(text()).toContain('No trainees yet');
    expect(all('a').some((a) => a.getAttribute('href') === `/g/${GYM_ID}/members/add` && a.className.includes('pri') && a.closest('.state'))).toBe(true);
  });

  it('shows "Add a captain" to owners only', async () => {
    const f = fake();
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />);
    expect(all('a').some((a) => a.textContent === 'Add a captain')).toBe(true);
    await mount(<MembersPage gym={gym('captain')} members={f.repo} />);
    expect(all('a').some((a) => a.textContent === 'Add a captain')).toBe(false);
    expect(all('a').some((a) => a.textContent.includes('Add trainees'))).toBe(true);
  });

  it('shows an error with retry', async () => {
    const f = fake();
    f.list.mockResolvedValueOnce(failed({ kind: 'server' }));
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />);
    expect(text()).toContain("Couldn't load this page");
    await click(button('Try again'));
    await flush();
    expect(f.list).toHaveBeenCalledTimes(2);
    expect(rows()).toHaveLength(6);
  });

  it('renders in Arabic with an Arabic date', async () => {
    const f = fake();
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />, 'ar');
    expect(q('h1')?.textContent).toBe('الأعضاء');
    expect(text()).toContain('انضم');
  });

  it('shows names as text only', async () => {
    const f = fake([member(1, { name: 'Mohamed Hassan', role: 'owner' }), member(2, { name: '<img src=x onerror=alert(1)>' })]);
    await mount(<MembersPage gym={gym('owner')} members={f.repo} />);
    expect(q('table img')).toBeNull();
    expect(text()).toContain('<img src=x onerror=alert(1)>');
  });
});

const memberPage = (f: Fake, memberId: string, role: 'owner' | 'captain' = 'owner') => (
  <MemberPage gym={gym(role)} memberId={memberId} members={f.repo} loadLogo={() => Promise.resolve(null)} />
);

describe('MemberPage', () => {
  it('says so when the member is not in the gym list', async () => {
    const f = fake();
    await mount(memberPage(f, id(99)));
    expect(text()).toContain("We can't find this member");
    expect(q('form')).toBeNull();
  });

  it('is read only for a captain opening a captain, with the banner', async () => {
    const f = fake();
    await mount(memberPage(f, id(2), 'captain'));
    expect(text()).toContain("Only the gym's owner can change captains.");
    expect(m<HTMLInputElement>('#member-name').disabled).toBe(true);
    expect(m<HTMLSelectElement>('#member-role').disabled).toBe(true);
    expect(button('End membership').disabled).toBe(true);
    expect(q('button[type=submit]')).toBeNull();
  });

  it('lets a captain edit a trainee, but not the role', async () => {
    const f = fake();
    await mount(memberPage(f, id(3), 'captain'));
    expect(m<HTMLInputElement>('#member-name').disabled).toBe(false);
    const role = m<HTMLSelectElement>('#member-role');
    expect(role.disabled).toBe(true);
    expect(text()).toContain("Only the gym's owner can change roles.");
    await type(m<HTMLInputElement>('#member-name'), 'Ahmed S.');
    await act(() => { m<HTMLFormElement>('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
    expect(f.update).toHaveBeenCalledWith(id(3), { name: 'Ahmed S.' });
  });

  it('checks and locks "Weights and reps" when "The whole plan" is on, and saves the implication', async () => {
    const f = fake([member(3, { name: 'Ahmed Samir' })]);
    await mount(memberPage(f, id(3)));
    const boxes = all('fieldset.perms input[type=checkbox]') as HTMLInputElement[];
    const [targets, plan] = boxes as [HTMLInputElement, HTMLInputElement];
    expect(targets.checked).toBe(false);
    await check(plan);
    expect(targets.checked).toBe(true);
    expect(targets.disabled).toBe(true);
    await act(() => { m<HTMLFormElement>('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
    expect(f.update).toHaveBeenCalledWith(id(3), { permissions: { editTargets: true, editPlan: true, buildOwnPlan: false } });
    await flush();
    expect(text()).toContain('Saved.');
    expect(f.list).toHaveBeenCalledTimes(2);
  });

  it('refuses an invalid name before saving', async () => {
    const f = fake();
    await mount(memberPage(f, id(3)));
    await type(m<HTMLInputElement>('#member-name'), '   ');
    expect(text()).toContain('Type a name of 1 to 40 characters.');
    expect(m<HTMLButtonElement>('button[type=submit]').disabled).toBe(true);
  });

  it('an owner changing a trainee to captain sends only the role', async () => {
    const f = fake();
    await mount(memberPage(f, id(3)));
    const select = m<HTMLSelectElement>('#member-role');
    await act(() => {
      select.value = 'captain';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(q('fieldset.perms')).toBeNull();
    await act(() => { m<HTMLFormElement>('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
    expect(f.update).toHaveBeenCalledWith(id(3), { role: 'captain' });
  });

  it('asks before ending a membership; Escape and Cancel do nothing, the confirm calls end', async () => {
    const f = fake();
    await mount(memberPage(f, id(6 - 3)));
    const opener = button('End membership');
    opener.focus();
    await click(opener);
    const dialog = m<HTMLElement>('[role=dialog]');
    expect(dialog.getAttribute('aria-modal')).toBe('true');
    expect(dialog.textContent).toContain("End Ahmed Samir's membership?");
    expect(document.activeElement?.textContent).toBe('Cancel');
    await act(() => { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); });
    expect(q('[role=dialog]')).toBeNull();
    expect(document.activeElement).toBe(opener);
    expect(f.end).not.toHaveBeenCalled();
    await click(opener);
    await click(button('Cancel'));
    expect(f.end).not.toHaveBeenCalled();
    await click(opener);
    await click(m<HTMLElement>('[role=dialog] .btn.danger'));
    await flush();
    expect(f.end).toHaveBeenCalledWith(id(3));
    expect(q('[role=dialog]')).toBeNull();
    expect(text()).toContain('Membership ended.');
  });

  it('shows the last-owner message when ending is refused with a conflict', async () => {
    const f = fake([member(1, { name: 'Mohamed Hassan', role: 'owner' })], { end: vi.fn(() => Promise.resolve(failed({ kind: 'conflict', reason: 'last_owner' }))) });
    await mount(memberPage(f, id(1)));
    await click(button('End membership'));
    await click(m<HTMLElement>('[role=dialog] .btn.danger'));
    await flush();
    expect(m('[role=alert]').textContent).toContain('A gym needs at least one active owner. Make someone else owner first.');
    expect(text()).toContain('Nothing was changed.');
  });

  it('shows a refused write as a message', async () => {
    const f = fake(sample, { update: vi.fn(() => Promise.resolve(failed({ kind: 'forbidden', reason: 'forbidden' }))) });
    await mount(memberPage(f, id(3)));
    await type(m<HTMLInputElement>('#member-name'), 'New name');
    await act(() => { m<HTMLFormElement>('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
    await flush();
    expect(m('[role=alert]').textContent).toContain("You can't make this change");
  });

  it('makes a recovery code, shows it once and prints the verified card', async () => {
    const f = fake();
    await mount(memberPage(f, id(3)));
    await click(button('Make a recovery code'));
    await flush();
    expect(f.newCode).toHaveBeenCalledWith(id(3), 'Ahmed Samir', 'recover');
    expect(m('.code').textContent).toBe('K7QM3D');
    expect(q('.print-sheet')).toBeNull();
    await click(button('Print card'));
    expect(printSpy).toHaveBeenCalledTimes(1);
    expect(all('.print-sheet .pcard')).toHaveLength(1);
    expect(m('.print-sheet .pcard').textContent).toContain('https://azmm.pages.dev/join/K7QM3D');
    await act(() => { window.dispatchEvent(new Event('afterprint')); });
    expect(q('.print-sheet')).toBeNull();
    await click(button('Done'));
    expect(q('.code')).toBeNull();
  });

  it('never prints a recovery card whose QR did not read back', async () => {
    const f = fake(sample, { newCode: vi.fn((mid: string, name: string) => Promise.resolve(ok(newCode(mid, name, 'ZZ4WNA')))) });
    await mount(memberPage(f, id(3)));
    await click(button('Make a recovery code'));
    await flush();
    expect(q('[role=alert]')?.textContent).toContain('didn’t read back');
    expect(() => button('Print card')).toThrow();
  });

  it('explains a recovery code refused because the person is in another gym', async () => {
    const f = fake(sample, { newCode: vi.fn(() => Promise.resolve(failed({ kind: 'conflict', reason: 'person_in_other_gym' }))) });
    await mount(memberPage(f, id(3)));
    await click(button('Make a recovery code'));
    await flush();
    const alert = m('[role=alert]').textContent;
    expect(alert).toContain("Can't make a recovery code.");
    expect(alert).toContain('Ahmed Samir is also a member of another gym');
    await click(button('OK'));
    expect(q('[role=alert]')).toBeNull();
  });

  it('waiting members: new join code and revoke', async () => {
    const f = fake();
    await mount(memberPage(f, id(4)));
    expect(q('fieldset.perms')).not.toBeNull();
    await click(button('Revoke code'));
    await flush();
    expect(f.revokeInvite).toHaveBeenCalledWith(id(104));
    expect(text()).toContain('The code was revoked.');
    await click(button('Make a new code'));
    await flush();
    expect(f.newCode).toHaveBeenCalledWith(id(4), 'Mona Youssef', 'join');
    // no code sent yet: no "Revoke code"
    await mount(memberPage(fake(), id(5)));
    expect(() => button('Revoke code')).toThrow();
  });

  it('an ended member is read only and cannot be ended again', async () => {
    const f = fake();
    await mount(memberPage(f, id(6)));
    expect(m<HTMLInputElement>('#member-name').disabled).toBe(true);
    expect(text()).toContain('This membership has ended.');
    expect(() => button('End membership')).toThrow();
  });

  it('disables writes while offline', async () => {
    const f = fake();
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    await mount(memberPage(f, id(3)));
    expect(button('End membership').disabled).toBe(true);
    expect(button('Make a recovery code').disabled).toBe(true);
  });
});

const addPage = (f: Fake, role: 'trainee' | 'captain' = 'trainee', g: ManagedGym = gym('owner')) => (
  <AddMembersPage gym={g} role={role} userId="u1" members={f.repo} loadLogo={() => Promise.resolve(null)} />
);
const namesBox = () => m<HTMLTextAreaElement>('#names');
const submitNames = () => act(() => { m<HTMLFormElement>('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
const makeButton = () => m<HTMLButtonElement>('form button[type=submit]');

async function toCodes(f: Fake, names = 'Ahmed Samir\nMona Youssef') {
  await mount(addPage(f));
  await type(namesBox(), names);
  await submitNames();
  await flush();
  await flush();
}

describe('AddMembersPage: names', () => {
  it('shows "Only the gym\'s owner can add captains" to a captain', async () => {
    await mount(addPage(fake(), 'captain', gym('captain')));
    expect(text()).toContain("Only the gym's owner can add captains");
    expect(q('textarea')).toBeNull();
  });

  it('gives owners a captain form without permissions', async () => {
    await mount(addPage(fake(), 'captain'));
    expect(q('h1')?.textContent).toBe('Add a captain');
    expect(q('fieldset.perms')).toBeNull();
  });

  it('counts names and labels the button', async () => {
    await mount(addPage(fake()));
    expect(makeButton().disabled).toBe(true);
    await type(namesBox(), 'Ahmed\n\nMona\n');
    expect(makeButton().textContent).toBe('Make 2 codes');
    expect(text()).toContain('Names ready: 2');
    expect(text()).toContain('We skipped 1 empty lines.');
    await type(namesBox(), 'Ahmed');
    expect(makeButton().textContent).toBe('Make 1 code');
  });

  it('refuses a name of 41 characters and accepts 40', async () => {
    await mount(addPage(fake()));
    await type(namesBox(), `${'x'.repeat(41)}\nMona`);
    expect(text()).toContain('Line 1: the name is longer than 40 characters.');
    expect(namesBox().getAttribute('aria-invalid')).toBe('true');
    expect(makeButton().disabled).toBe(true);
    await type(namesBox(), `${'x'.repeat(40)}\nMona`);
    expect(makeButton().disabled).toBe(false);
  });

  it('removes hidden characters and says so, and sends the cleaned name', async () => {
    const f = fake();
    await mount(addPage(f));
    const hidden = String.fromCharCode(0x202e, 0x200b);
    await type(namesBox(), `ad${hidden}min`);
    expect(text()).toContain('We removed hidden characters that flip the direction of the text.');
    await submitNames();
    await flush();
    expect(f.add.mock.calls[0]?.[2]).toEqual(['admin']);
  });

  it('refuses more than 50 names and can keep the first 50', async () => {
    await mount(addPage(fake()));
    await type(namesBox(), Array.from({ length: 52 }, (_, i) => `Name ${i + 1}`).join('\n'));
    expect(text()).toContain('Up to 50 names at a time. You have 52.');
    expect(makeButton().disabled).toBe(true);
    await click(button('Keep the first 50'));
    expect(text()).toContain('Names ready: 50');
    expect(makeButton().disabled).toBe(false);
  });

  it('notes repeated names', async () => {
    await mount(addPage(fake()));
    await type(namesBox(), 'Ahmed Samir\nahmed samir');
    expect(text()).toContain('appear more than once');
    expect(makeButton().disabled).toBe(false);
  });

  it('keeps the button off while offline', async () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false);
    await mount(addPage(fake()));
    await type(namesBox(), 'Ahmed');
    expect(makeButton().disabled).toBe(true);
    expect(text()).toContain("The button comes back when you're online.");
  });

  it('reads a CSV file and uses the picked column', async () => {
    await mount(addPage(fake()));
    const input = m<HTMLInputElement>('#names-file');
    const file = new File(['Name,Phone\nAhmed Samir,1\nMona Youssef,2\n'], 'members.csv', { type: 'text/csv' });
    await act(async () => {
      Object.defineProperty(input, 'files', { value: [file], configurable: true });
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 20));
    });
    expect(text()).toContain('members.csv · first sheet');
    expect(text()).toContain('“Name” is skipped.');
    await click(button('Use these 2 names'));
    expect(namesBox().value).toBe('Ahmed Samir\nMona Youssef');
  });

  it('says what is wrong with a file that cannot be used', async () => {
    await mount(addPage(fake()));
    const input = m<HTMLInputElement>('#names-file');
    const file = new File(['x'], 'old.xls');
    await act(async () => {
      Object.defineProperty(input, 'files', { value: [file], configurable: true });
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 20));
    });
    expect(m('[role=alert]').textContent).toContain('We can only read .xlsx and .csv files.');
    expect(text()).toContain('Old Excel file (.xls)?');
  });

  it('offers the first 50 of a long file and the row to start at next', async () => {
    await mount(addPage(fake()));
    const input = m<HTMLInputElement>('#names-file');
    const body = ['Name', ...Array.from({ length: 68 }, (_, i) => `Person ${i + 1}`)].join('\n');
    await act(async () => {
      Object.defineProperty(input, 'files', { value: [new File([body], 'big.csv')], configurable: true });
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 20));
    });
    expect(text()).toContain('68 names found. We make 50 at a time.');
    expect(text()).toContain('pick “Start at row 52”');
    await click(button('Use the first 50'));
    expect(text()).toContain('Names ready: 50');
  });
});

describe('AddMembersPage: codes', () => {
  it('makes the codes one name at a time with progress, then shows the table once', async () => {
    const f = fake();
    let release: (() => void) | undefined;
    const gate = new Promise<void>((r) => { release = r; });
    f.add.mockImplementationOnce(async (_g: string, _p: string, names: string[]) => {
      await gate;
      counter++;
      return ok([{ ok: true as const, code: newCode(id(200), names[0] ?? '', 'K7QM3D') }]);
    });
    await mount(addPage(f));
    await type(namesBox(), 'Ahmed Samir\nMona Youssef');
    await submitNames();
    await flush();
    expect(m('[role=status][aria-live=polite]').textContent).toContain('Making codes 0 of 2');
    await act(async () => {
      release?.();
      await gate;
    });
    await flush();
    await flush();
    expect(f.myPersonId).toHaveBeenCalledWith('u1');
    expect(f.add).toHaveBeenCalledTimes(2);
    expect(f.add.mock.calls[0]).toEqual([GYM_ID, ME, ['Ahmed Samir'], 'trainee', { editTargets: true, editPlan: false, buildOwnPlan: false }]);
    expect(f.add.mock.calls[1]?.[2]).toEqual(['Mona Youssef']);
    const body = all('table.t tbody tr').map((r) => r.textContent);
    expect(body[0]).toContain('Ahmed Samir');
    expect(body[0]).toContain('K7QM3D');
    expect(body[1]).toContain('PX4WNA');
    expect(text()).toContain('These codes are shown only now.');
    expect(q('.print-sheet')).toBeNull();
  });

  it('sends the permissions with the implication, and none for a captain', async () => {
    const f = fake();
    await mount(addPage(f));
    await type(namesBox(), 'Ahmed');
    const plan = all('fieldset.perms input[type=checkbox]')[1] as HTMLInputElement;
    await check(plan);
    await submitNames();
    await flush();
    expect(f.add.mock.calls[0]?.[4]).toEqual({ editTargets: true, editPlan: true, buildOwnPlan: false });
    const g = fake();
    await mount(addPage(g, 'captain'));
    await type(namesBox(), 'Karim');
    await submitNames();
    await flush();
    expect(g.add.mock.calls[0]?.slice(3)).toEqual(['captain', { editTargets: false, editPlan: false, buildOwnPlan: false }]);
  });

  it('copies one "name<TAB>link" line per code', async () => {
    const write = vi.fn(() => Promise.resolve());
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: write }, configurable: true });
    await toCodes(fake());
    await click(button('Copy links'));
    expect(write).toHaveBeenCalledWith('Ahmed Samir\thttps://azmm.pages.dev/join/K7QM3D\nMona Youssef\thttps://azmm.pages.dev/join/PX4WNA');
    expect(text()).toContain('Links copied.');
  });

  it('says when it cannot copy', async () => {
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: () => Promise.reject(new Error('denied')) }, configurable: true });
    await toCodes(fake());
    await click(button('Copy links'));
    expect(text()).toContain("Couldn't copy.");
  });

  it('reports the names that got no code and retries only those', async () => {
    const f = fake();
    f.add.mockImplementation((_g: string, _p: string, names: string[]) => {
      const name = names[0] ?? '';
      if (name === 'Mona Youssef' && f.add.mock.calls.length === 2) return Promise.resolve(ok([{ ok: false as const, name, failure: { kind: 'offline' as const }, membershipId: id(300) }]));
      if (name === 'Omar Tarek' && f.add.mock.calls.length === 3) return Promise.resolve(ok([{ ok: false as const, name, failure: { kind: 'server' as const } }]));
      counter++;
      return Promise.resolve(ok([{ ok: true as const, code: newCode(id(200 + counter), name, CODES[counter - 1] ?? 'AAAAAA') }]));
    });
    await toCodes(f, 'Ahmed Samir\nMona Youssef\nOmar Tarek');
    expect(text()).toContain('2 of 3 codes made.'.replace('2', '1'));
    expect(m('[role=alert]').textContent).toContain('Mona Youssef');
    expect(m('[role=alert]').textContent).toContain('Omar Tarek');
    expect(all('table.t tbody tr')).toHaveLength(1);
    const retry = button('Try again for 2');
    f.add.mockClear();
    await click(retry);
    await flush();
    await flush();
    // the one with a membership gets a new join code; the one without is added again; the one that worked is left alone
    expect(f.newCode).toHaveBeenCalledWith(id(300), 'Mona Youssef', 'join');
    expect(f.add).toHaveBeenCalledTimes(1);
    expect(f.add.mock.calls[0]?.[2]).toEqual(['Omar Tarek']);
    expect(q('[role=alert]')).toBeNull();
    expect(all('table.t tbody tr').map((r) => r.querySelector('b')?.textContent)).toEqual(['Ahmed Samir', 'Mona Youssef', 'Omar Tarek']);
  });

  it('checks every QR and prints only the verified cards', async () => {
    const f = fake();
    await toCodes(f, 'Ahmed\nMona\nOmar\nNour\nZed');
    expect(all('table.t tbody tr')).toHaveLength(5);
    await click(button('Check and print 5 cards'));
    expect(m('[role=alert]').textContent).toContain('4 of 5 QR codes checked. 1 didn’t read back.');
    expect(text()).toContain('The card for Zed is left out of the print.');
    expect(button('Print 4 cards')).toBeTruthy();
    expect(text()).toContain('Cards: 4 · A4 pages: 1');
    expect(q('.print-sheet')).toBeNull();
    await click(button('Print 4 cards'));
    expect(printSpy).toHaveBeenCalledTimes(1);
    const cards = all('.print-sheet .pcard');
    expect(cards).toHaveLength(4);
    expect(cards.map((c) => c.querySelector('.c')?.textContent)).toEqual(['K7QM3D', 'PX4WNA', 'H2RT9V', 'B8ZEJC']);
    expect(m('.print-sheet').textContent).not.toContain('ZZ4WNA');
    expect(cards.every((c) => c.querySelector('canvas'))).toBe(true);
    // both languages, both dates, the link
    expect(cards[0]?.textContent).toContain('Scan with your phone camera');
    expect(cards[0]?.textContent).toContain('امسح الكود بكاميرا الموبايل');
    expect(cards[0]?.textContent).toContain('Single use · expires 11 Nov 2026');
    expect(cards[0]?.textContent).toContain('https://azmm.pages.dev/join/K7QM3D');
    await act(() => { window.dispatchEvent(new Event('afterprint')); });
    expect(q('.print-sheet')).toBeNull();
  });

  it('says every QR was read back when they all were, and puts 4 cards on a page', async () => {
    await toCodes(fake(), 'A\nB\nC');
    await click(button('Check and print 3 cards'));
    expect(m('[role=status] .num, .banner.ok').textContent).toContain('Every QR was read back and matches its code: 3 of 3.');
    await click(button('Print 3 cards'));
    expect(all('.print-page')).toHaveLength(1);
  });

  it('warns before leaving while codes are on screen', async () => {
    const add = vi.spyOn(window, 'addEventListener');
    await toCodes(fake());
    expect(add.mock.calls.some(([type]) => type === 'beforeunload')).toBe(true);
    const link = all('a').find((a) => a.textContent.includes('Members') && a.className.includes('back')) as HTMLAnchorElement;
    await click(link);
    expect(m('[role=dialog]').textContent).toContain('Leave this page?');
    expect(window.location.pathname).not.toBe(`/g/${GYM_ID}/members`);
    await act(() => { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); });
    expect(q('[role=dialog]')).toBeNull();
    expect(q('table.t')).not.toBeNull();
    await click(link);
    await click(button('Leave'));
    expect(window.location.pathname).toBe(`/g/${GYM_ID}/members`);
  });

  it('leaves at once when no codes were made', async () => {
    await mount(addPage(fake()));
    const link = all('a').find((a) => a.className.includes('back')) as HTMLAnchorElement;
    await click(link);
    expect(q('[role=dialog]')).toBeNull();
    expect(window.location.pathname).toBe(`/g/${GYM_ID}/members`);
  });

  it('keeps the codes out of the URL and storage', async () => {
    await toCodes(fake());
    expect(window.location.href).not.toContain('K7QM3D');
    expect(JSON.stringify(Object.entries(window.localStorage))).not.toContain('K7QM3D');
    expect(JSON.stringify(Object.entries(window.sessionStorage))).not.toContain('K7QM3D');
  });
});
