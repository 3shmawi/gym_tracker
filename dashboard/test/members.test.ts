import { describe, expect, it } from 'vitest';
import { canManage, MembersRepository, normalizePermissions, validName, type AddResult } from '../src/members/members';
import { fakeMembersClient, type MembersFakeOptions } from './fakes';

const NOW = new Date('2026-11-04T12:00:00Z');
const GYM = 'b0000000-0000-4000-8000-000000000001';
const ME = 'c0000000-0000-4000-8000-000000000001';
const id = (n: number) => `a0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const NO_FLAGS = { editTargets: false, editPlan: false, buildOwnPlan: false };

const row = (n: number, over: Record<string, unknown> = {}) => ({
  id: id(n),
  display_name: `Member ${n}`,
  role: 'trainee',
  status: 'active',
  can_edit_targets: false,
  can_edit_plan: false,
  can_build_own_plan: false,
  joined_at: '2026-10-12T10:00:00Z',
  ended_at: null,
  created_at: `2026-10-0${n}T10:00:00Z`,
  ...over,
});
const invite = (n: number, member: number, over: Record<string, unknown> = {}) => ({
  id: id(100 + n),
  membership_id: id(member),
  kind: 'join',
  created_at: '2026-11-01T10:00:00Z',
  expires_at: '2026-11-09T10:00:00Z',
  used_at: null,
  revoked_at: null,
  ...over,
});

const make = (options: MembersFakeOptions = {}) => {
  const fake = fakeMembersClient(options);
  return { repo: new MembersRepository(fake.client, () => NOW), calls: fake.calls };
};

describe('MembersRepository.list', () => {
  it('maps rows and invite states', async () => {
    const bidi = String.fromCharCode(0x202e);
    const { repo, calls } = make({
      memberships: [
        row(1, { display_name: `Ahmed${bidi}  Samir`, can_edit_targets: true }),
        row(2, { status: 'pending', joined_at: null }), // sent
        row(3, { status: 'pending', joined_at: null }), // expired
        row(4, { status: 'pending', joined_at: null }), // no invite at all
        row(5, { status: 'ended', ended_at: '2026-11-02T10:00:00Z' }), // ended: invite is none
        row(6, { status: 'pending', joined_at: null }), // newest invite revoked wins over an older sent one
        row(7, { status: 'pending', joined_at: null }), // used
        row(8, { status: 'pending', joined_at: null }), // newest recover invite
        row(9, { role: 'boss' }),
        row(10, { status: 'zombie' }),
        { ...row(11), id: 'not-a-uuid' },
      ],
      invites: [
        invite(1, 2),
        invite(2, 3, { expires_at: '2026-11-03T10:00:00Z' }),
        invite(3, 5),
        invite(4, 6, { created_at: '2026-10-30T10:00:00Z' }),
        invite(5, 6, { created_at: '2026-11-02T10:00:00Z', revoked_at: '2026-11-02T11:00:00Z' }),
        invite(6, 7, { used_at: '2026-11-02T11:00:00Z' }),
        invite(7, 8, { kind: 'recover', created_at: '2026-11-03T10:00:00Z' }),
      ],
    });
    const result = await repo.list(GYM);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const byId = new Map(result.value.map((m) => [m.id, m]));
    expect(result.value).toHaveLength(8);
    expect(byId.has(id(9))).toBe(false);
    expect(byId.has(id(10))).toBe(false);
    expect(byId.get(id(1))?.name).toBe('Ahmed Samir');
    expect(byId.get(id(1))?.permissions).toEqual({ editTargets: true, editPlan: false, buildOwnPlan: false });
    expect(byId.get(id(2))?.invite).toMatchObject({ state: 'sent', inviteId: id(101), kind: 'join' });
    expect(byId.get(id(3))?.invite.state).toBe('expired');
    expect(byId.get(id(4))?.invite).toEqual({ state: 'none' });
    expect(byId.get(id(5))?.invite).toEqual({ state: 'none' });
    expect(byId.get(id(5))?.endedAt).toEqual(new Date('2026-11-02T10:00:00Z'));
    expect(byId.get(id(6))?.invite).toEqual({ state: 'none' });
    expect(byId.get(id(7))?.invite).toEqual({ state: 'none' });
    expect(byId.get(id(8))?.invite).toMatchObject({ state: 'sent', kind: 'recover', inviteId: id(107) });
    // active first, then waiting, then ended
    expect(result.value.map((m) => m.status)).toEqual(['active', 'pending', 'pending', 'pending', 'pending', 'pending', 'pending', 'ended']);
    // never asks for the code's hash
    const columns = calls.flatMap((c) => (c.kind === 'select' ? [c.columns ?? ''] : []));
    expect(columns).toHaveLength(2);
    expect(columns.join(' ')).not.toContain('code_hmac');
    expect(calls.every((c) => c.filters?.some(([col, val]) => col === 'gym_id' && val === GYM))).toBe(true);
  });

  it('refuses a gym id that is not a UUID without a call', async () => {
    const { repo, calls } = make();
    expect(await repo.list('nope')).toEqual({ ok: false, failure: { kind: 'not_found' } });
    expect(calls).toHaveLength(0);
  });
});

describe('MembersRepository.add', () => {
  const perms = { editTargets: false, editPlan: true, buildOwnPlan: true };
  const goodRpc: MembersFakeOptions['onRpc'] = (_name, args, n) => ({
    data: { code: ['K7QM3D', 'PX4WNA', 'H2RT9V'][n - 1] ?? 'B8ZEJC', expires_at: '2026-11-11T10:00:00Z', membership_id: args.p_membership_id },
    error: null,
  });

  it('refuses invalid batches before any call', async () => {
    const { repo, calls } = make({ onRpc: goodRpc });
    const cases: string[][] = [[], [''], ['   '], ['x'.repeat(41)], Array.from({ length: 51 }, (_, i) => `Name ${i}`), ['ok', String.fromCharCode(0x200b)]];
    for (const names of cases) {
      expect(await repo.add(GYM, ME, names, 'trainee', NO_FLAGS)).toEqual({ ok: false, failure: { kind: 'invalid' } });
    }
    expect(await repo.add('bad', ME, ['a'], 'trainee', NO_FLAGS)).toEqual({ ok: false, failure: { kind: 'invalid' } });
    expect(await repo.add(GYM, 'bad', ['a'], 'trainee', NO_FLAGS)).toEqual({ ok: false, failure: { kind: 'invalid' } });
    expect(calls).toHaveLength(0);
  });

  it('accepts 40 and 50 names', async () => {
    const { repo } = make({ onRpc: goodRpc });
    const r = await repo.add(GYM, ME, ['y'.repeat(40)], 'trainee', NO_FLAGS);
    expect(r.ok && r.value[0]?.ok).toBe(true);
  });

  it('inserts with created_by and flags (editPlan implies editTargets), then asks for a join code', async () => {
    const { repo, calls } = make({ onRpc: goodRpc });
    const result = await repo.add(GYM, ME, ['Ahmed  Samir', 'Mona'], 'trainee', perms);
    expect(result.ok).toBe(true);
    const inserts = calls.filter((c) => c.kind === 'insert');
    expect(inserts.map((c) => c.payload)).toEqual([
      { gym_id: GYM, display_name: 'Ahmed Samir', role: 'trainee', can_edit_targets: true, can_edit_plan: true, can_build_own_plan: true, created_by: ME },
      { gym_id: GYM, display_name: 'Mona', role: 'trainee', can_edit_targets: true, can_edit_plan: true, can_build_own_plan: true, created_by: ME },
    ]);
    const rpcs = calls.filter((c) => c.kind === 'rpc');
    expect(rpcs.map((c) => [c.name, c.payload])).toEqual([
      ['create_invite', { p_membership_id: id(1), p_kind: 'join' }],
      ['create_invite', { p_membership_id: id(2), p_kind: 'join' }],
    ]);
    if (!result.ok) return;
    expect(result.value.map((r) => (r.ok ? [r.code.name, r.code.code] : null))).toEqual([
      ['Ahmed Samir', 'K7QM3D'],
      ['Mona', 'PX4WNA'],
    ]);
  });

  it('gives a captain no flags, whatever was passed', async () => {
    const { repo, calls } = make({ onRpc: goodRpc });
    await repo.add(GYM, ME, ['Karim'], 'captain', { editTargets: true, editPlan: true, buildOwnPlan: true });
    expect(calls.find((c) => c.kind === 'insert')?.payload).toMatchObject({ role: 'captain', can_edit_targets: false, can_edit_plan: false, can_build_own_plan: false });
  });

  it('reports a failing insert per name and carries on', async () => {
    const { repo, calls } = make({
      onRpc: goodRpc,
      onInsert: (_row, n) => (n === 1 ? { data: null, error: { code: '42501', message: 'forbidden' } } : { data: { id: id(n) }, error: null }),
    });
    const result = await repo.add(GYM, ME, ['A', 'B'], 'trainee', NO_FLAGS);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value[0]).toEqual({ ok: false, name: 'A', failure: { kind: 'forbidden', reason: 'forbidden' } });
    expect(result.value[1]?.ok).toBe(true);
    expect(calls.filter((c) => c.kind === 'rpc')).toHaveLength(1); // no code for the one that was not inserted
  });

  it('reports a failing create_invite per name with its membership id, and carries on', async () => {
    const { repo } = make({
      onRpc: (rpcName, args, n) => (n === 1 ? { data: null, error: { code: '42501', message: 'person_in_other_gym' } } : goodRpc(rpcName, args, n)),
    });
    const result = await repo.add(GYM, ME, ['A', 'B'], 'trainee', NO_FLAGS);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const [first, second] = result.value as [AddResult, AddResult];
    expect(first).toMatchObject({ ok: false, name: 'A', membershipId: id(1), failure: { kind: 'forbidden' } });
    expect(second.ok).toBe(true);
  });

  it.each([
    ['a lowercase code', { code: 'k7qm3d', expires_at: '2026-11-11T10:00:00Z' }],
    ['markup', { code: '<script>', expires_at: '2026-11-11T10:00:00Z' }],
    ['an ambiguous letter', { code: 'K7QM3O', expires_at: '2026-11-11T10:00:00Z' }],
    ['no code', { expires_at: '2026-11-11T10:00:00Z' }],
    ['no expiry', { code: 'K7QM3D' }],
    ['a string', 'K7QM3D'],
    ['nothing', null],
  ])('never turns %s into a code', async (_label, data) => {
    const { repo } = make({ onRpc: () => ({ data, error: null }) });
    const result = await repo.add(GYM, ME, ['A'], 'trainee', NO_FLAGS);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value[0]).toMatchObject({ ok: false, name: 'A', membershipId: id(1), failure: { kind: 'server' } });
    expect(JSON.stringify(result.value)).not.toContain('script');
  });
});

describe('MembersRepository codes, update and end', () => {
  it('newCode passes the kind', async () => {
    const { repo, calls } = make({ onRpc: () => ({ data: { code: 'K7QM3D', expires_at: '2026-11-11T10:00:00Z' }, error: null }) });
    const result = await repo.newCode(id(1), 'Ahmed', 'recover');
    expect(result).toEqual({ ok: true, value: { membershipId: id(1), name: 'Ahmed', code: 'K7QM3D', expiresAt: new Date('2026-11-11T10:00:00Z') } });
    expect(calls[0]).toMatchObject({ kind: 'rpc', name: 'create_invite', payload: { p_membership_id: id(1), p_kind: 'recover' } });
  });

  it('revokeInvite passes p_invite_id', async () => {
    const { repo, calls } = make();
    expect(await repo.revokeInvite(id(101))).toEqual({ ok: true, value: undefined });
    expect(calls[0]).toMatchObject({ kind: 'rpc', name: 'revoke_invite', payload: { p_invite_id: id(101) } });
  });

  it('a change to captain clears the plan flags', async () => {
    const { repo, calls } = make();
    await repo.update(id(1), { role: 'captain', permissions: { editTargets: true, editPlan: true, buildOwnPlan: true } });
    expect(calls[0]).toMatchObject({
      kind: 'update',
      table: 'memberships',
      payload: { role: 'captain', can_edit_targets: false, can_edit_plan: false, can_build_own_plan: false },
      filters: [['id', id(1)]],
    });
  });

  it('a trainee change keeps the implication and the cleaned name', async () => {
    const { repo, calls } = make();
    await repo.update(id(1), { name: ' Mona   Y ', permissions: { editTargets: false, editPlan: true, buildOwnPlan: false } });
    expect(calls[0]?.payload).toEqual({ display_name: 'Mona Y', can_edit_targets: true, can_edit_plan: true, can_build_own_plan: false });
  });

  it('refuses an invalid name and does nothing for an empty change', async () => {
    const { repo, calls } = make();
    expect(await repo.update(id(1), { name: 'x'.repeat(41) })).toEqual({ ok: false, failure: { kind: 'invalid' } });
    expect(await repo.update(id(1), { name: '' })).toEqual({ ok: false, failure: { kind: 'invalid' } });
    expect(await repo.update(id(1), {})).toEqual({ ok: true, value: undefined });
    expect(calls).toHaveLength(0);
  });

  it('treats 0 rows back as forbidden', async () => {
    const { repo } = make({ onUpdate: () => ({ data: [], error: null }) });
    expect(await repo.update(id(1), { name: 'A' })).toEqual({ ok: false, failure: { kind: 'forbidden', reason: 'forbidden' } });
    expect(await repo.end(id(1))).toEqual({ ok: false, failure: { kind: 'forbidden', reason: 'forbidden' } });
  });

  it('end sends status ended', async () => {
    const { repo, calls } = make();
    expect(await repo.end(id(1))).toEqual({ ok: true, value: undefined });
    expect(calls[0]).toMatchObject({ kind: 'update', payload: { status: 'ended' }, filters: [['id', id(1)]] });
  });

  it('maps the last-owner conflict (23514)', async () => {
    const { repo } = make({ onUpdate: () => ({ data: null, error: { code: '23514', message: 'new row violates check constraint' } }) });
    expect(await repo.end(id(1))).toEqual({ ok: false, failure: { kind: 'conflict' } });
  });

  it('refuses ids that are not UUIDs without a call', async () => {
    const { repo, calls } = make();
    const bad = ['', 'x', "1'; drop table memberships;--", '../../etc'];
    for (const value of bad) {
      expect((await repo.newCode(value, 'A', 'join')).ok).toBe(false);
      expect((await repo.revokeInvite(value)).ok).toBe(false);
      expect((await repo.update(value, { name: 'A' })).ok).toBe(false);
      expect((await repo.end(value)).ok).toBe(false);
    }
    expect(calls).toHaveLength(0);
  });
});

describe('rules mirrored from the server', () => {
  it('canManage: owners anyone, captains trainees only', () => {
    expect(canManage('owner', 'owner')).toBe(true);
    expect(canManage('owner', 'captain')).toBe(true);
    expect(canManage('captain', 'trainee')).toBe(true);
    expect(canManage('captain', 'captain')).toBe(false);
    expect(canManage('captain', 'owner')).toBe(false);
  });
  it('normalizePermissions and validName', () => {
    expect(normalizePermissions({ editTargets: false, editPlan: true, buildOwnPlan: false }).editTargets).toBe(true);
    expect(validName('x'.repeat(40))).toHaveLength(40);
    expect(validName('x'.repeat(41))).toBeNull();
    expect(validName('')).toBeNull();
    expect(validName(5)).toBeNull();
  });
});
