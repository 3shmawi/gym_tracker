import type { SupabaseClient } from '@supabase/supabase-js';
import { CodedError, toFailure, type Failure } from '../core/failure';
import { failed, guard, ok, unwrap, type Result } from '../core/result';
import { cleanName } from '../core/text';
import { isGymId } from '../gyms/gyms';

// Members and invite codes of one gym. Every rule lives in RLS and the RPCs
// (migrations 0005, 0006); this file only asks. The UI mirrors the rules so a
// refused action shows a message instead of a crash:
// - read: "managers read gym memberships" / "managers read invites";
// - add: insert a pending row ("managers add pending members": owners add
//   captains, captains add trainees), then create_invite(membership, 'join');
// - change: update display_name/role/status/flags ("managers update members",
//   i_manage_role: captains change trainees only); memberships_guard keeps an
//   active owner and allows only pending|active → ended;
// - codes: create_invite(…, 'join' | 'recover') revokes the older unused
//   ones; revoke_invite(id). The plain code comes back once, never again.

export type Role = 'owner' | 'captain' | 'trainee';
export type Status = 'pending' | 'active' | 'ended';

export interface Permissions {
  readonly editTargets: boolean;
  readonly editPlan: boolean;
  readonly buildOwnPlan: boolean;
}

export type InviteState =
  | { readonly state: 'none' } //                      pending, no usable code
  | { readonly state: 'sent'; readonly inviteId: string; readonly expiresAt: Date; readonly kind: 'join' | 'recover' }
  | { readonly state: 'expired'; readonly expiresAt: Date };

export interface Member {
  readonly id: string;
  readonly name: string;
  readonly role: Role;
  readonly status: Status;
  readonly permissions: Permissions;
  readonly joinedAt: Date | null;
  readonly endedAt: Date | null;
  readonly createdAt: Date;
  /** The newest invite of this member, for "code sent / expired / none". */
  readonly invite: InviteState;
}

export interface NewCode {
  readonly membershipId: string;
  readonly name: string;
  readonly code: string;
  readonly expiresAt: Date;
}

/** One line of "Add trainees": a code, or why this name got none. */
export type AddResult =
  | { readonly ok: true; readonly code: NewCode }
  | { readonly ok: false; readonly name: string; readonly failure: Failure; readonly membershipId?: string };

export const NAME_MAX = 40;
export const BATCH_MAX = 50;
/** Same alphabet as the server (0006 generate_invite_code) and make_invites. */
export const CODE_RE = /^[A-HJKMNP-Z2-9]{6}$/;

/** Server rule: editing the whole plan includes editing targets (memberships_plan_implies_targets). */
export function normalizePermissions(p: Permissions): Permissions {
  return { editTargets: p.editTargets || p.editPlan, editPlan: p.editPlan, buildOwnPlan: p.buildOwnPlan };
}

/** A name as the table accepts it: cleaned, 1–40 characters (btrim'd). */
export function validName(raw: unknown): string | null {
  const name = cleanName(raw);
  const length = Array.from(name).length;
  return length >= 1 && length <= NAME_MAX ? name : null;
}

/** What the UI may offer, mirroring i_manage_role: owners change anyone, captains trainees only. */
export function canManage(myRole: 'owner' | 'captain', target: Role): boolean {
  return myRole === 'owner' || target === 'trainee';
}

interface MembershipRow {
  id: string;
  display_name: unknown;
  role: string;
  status: string;
  can_edit_targets: boolean;
  can_edit_plan: boolean;
  can_build_own_plan: boolean;
  joined_at: string | null;
  ended_at: string | null;
  created_at: string;
}

interface InviteRow {
  id: string;
  membership_id: string;
  kind: string;
  created_at: string;
  expires_at: string;
  used_at: string | null;
  revoked_at: string | null;
}

const MEMBER_COLUMNS =
  'id, display_name, role, status, can_edit_targets, can_edit_plan, can_build_own_plan, joined_at, ended_at, created_at';
// Never code_hmac: it has no select grant (0006) and the UI never needs it.
const INVITE_COLUMNS = 'id, membership_id, kind, created_at, expires_at, used_at, revoked_at';

const isRole = (v: string): v is Role => v === 'owner' || v === 'captain' || v === 'trainee';
const isStatus = (v: string): v is Status => v === 'pending' || v === 'active' || v === 'ended';
const date = (v: string | null): Date | null => (v ? new Date(v) : null);

export function inviteStateOf(invites: readonly InviteRow[], now: Date): InviteState {
  const newest = [...invites].sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
  if (!newest || newest.revoked_at || newest.used_at) return { state: 'none' };
  const expiresAt = new Date(newest.expires_at);
  if (expiresAt.getTime() <= now.getTime()) return { state: 'expired', expiresAt };
  const kind = newest.kind === 'recover' ? 'recover' : 'join';
  return { state: 'sent', inviteId: newest.id, expiresAt, kind };
}

export function toMember(row: MembershipRow, invites: readonly InviteRow[], now: Date): Member | null {
  if (!isRole(row.role) || !isStatus(row.status) || !isGymId(row.id)) return null;
  return {
    id: row.id,
    name: cleanName(row.display_name),
    role: row.role,
    status: row.status,
    permissions: { editTargets: row.can_edit_targets, editPlan: row.can_edit_plan, buildOwnPlan: row.can_build_own_plan },
    joinedAt: date(row.joined_at),
    endedAt: date(row.ended_at),
    createdAt: new Date(row.created_at),
    invite: row.status === 'ended' ? { state: 'none' } : inviteStateOf(invites, now),
  };
}

export class MembersRepository {
  constructor(
    private readonly supabase: SupabaseClient,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async list(gymId: string): Promise<Result<Member[]>> {
    if (!isGymId(gymId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const [rows, invites] = await Promise.all([
        this.supabase.from('memberships').select(MEMBER_COLUMNS).eq('gym_id', gymId).overrideTypes<MembershipRow[], { merge: false }>(),
        this.supabase.from('invites').select(INVITE_COLUMNS).eq('gym_id', gymId).overrideTypes<InviteRow[], { merge: false }>(),
      ]);
      const members = unwrap(rows) ?? [];
      const byMember = new Map<string, InviteRow[]>();
      for (const invite of unwrap(invites) ?? []) {
        const list = byMember.get(invite.membership_id) ?? [];
        list.push(invite);
        byMember.set(invite.membership_id, list);
      }
      const now = this.now();
      return members
        .flatMap((row) => {
          const member = toMember(row, byMember.get(row.id) ?? [], now);
          return member ? [member] : [];
        })
        .sort(byStatusThenName);
    });
  }

  /**
   * "Add trainees" (or one captain, owners only): one pending membership and
   * one join code per name, in order. Not one transaction (no such RPC for
   * managers): each name reports its own result, so a dropped connection
   * leaves the rest "waiting" with no code, and they can be retried.
   */
  async add(gymId: string, myPersonId: string, rawNames: readonly string[], role: 'trainee' | 'captain', permissions: Permissions): Promise<Result<AddResult[]>> {
    if (!isGymId(gymId) || !isGymId(myPersonId)) return failed({ kind: 'invalid' });
    const names = rawNames.map(validName);
    if (names.length === 0 || names.length > BATCH_MAX || names.some((n) => n === null)) return failed({ kind: 'invalid' });
    const flags = role === 'trainee' ? normalizePermissions(permissions) : { editTargets: false, editPlan: false, buildOwnPlan: false };
    const results: AddResult[] = [];
    for (const name of names as string[]) {
      const { data, error } = await this.supabase
        .from('memberships')
        .insert({
          gym_id: gymId,
          display_name: name,
          role,
          can_edit_targets: flags.editTargets,
          can_edit_plan: flags.editPlan,
          can_build_own_plan: flags.buildOwnPlan,
          created_by: myPersonId,
        })
        .select('id')
        .single<{ id: string }>();
      if (error) {
        results.push({ ok: false, name, failure: toFailure(error) });
        continue;
      }
      const code = await this.newCode(data.id, name, 'join');
      results.push(code.ok ? { ok: true, code: code.value } : { ok: false, name, failure: code.failure, membershipId: data.id });
    }
    return ok(results);
  }

  /** A new code for a member: 'join' while waiting, 'recover' for a new phone. Older unused codes stop working. */
  async newCode(membershipId: string, name: string, kind: 'join' | 'recover'): Promise<Result<NewCode>> {
    if (!isGymId(membershipId)) return failed({ kind: 'invalid' });
    return guard(async () => {
      const data = unwrap(await this.supabase.rpc('create_invite', { p_membership_id: membershipId, p_kind: kind })) as unknown;
      const value = (typeof data === 'object' && data !== null ? data : {}) as Record<string, unknown>;
      const code = value.code;
      const expires = value.expires_at;
      // Never draw a QR from something that isn't a code.
      if (typeof code !== 'string' || !CODE_RE.test(code) || typeof expires !== 'string') {
        throw new CodedError('XX000', 'bad_invite_response');
      }
      return { membershipId, name: cleanName(name), code, expiresAt: new Date(expires) };
    });
  }

  async revokeInvite(inviteId: string): Promise<Result<void>> {
    if (!isGymId(inviteId)) return failed({ kind: 'invalid' });
    return guard(async () => {
      unwrap(await this.supabase.rpc('revoke_invite', { p_invite_id: inviteId }));
    });
  }

  /** Name, role (owners only) and permissions (trainees only). */
  async update(membershipId: string, change: { name?: string; role?: Role; permissions?: Permissions }): Promise<Result<void>> {
    if (!isGymId(membershipId)) return failed({ kind: 'invalid' });
    const patch: Record<string, unknown> = {};
    if (change.name !== undefined) {
      const name = validName(change.name);
      if (!name) return failed({ kind: 'invalid' });
      patch.display_name = name;
    }
    if (change.role !== undefined) patch.role = change.role;
    if (change.role !== undefined && change.role !== 'trainee') {
      // memberships_flags_trainee_only: managers carry no plan flags.
      Object.assign(patch, { can_edit_targets: false, can_edit_plan: false, can_build_own_plan: false });
    } else if (change.permissions) {
      const p = normalizePermissions(change.permissions);
      Object.assign(patch, { can_edit_targets: p.editTargets, can_edit_plan: p.editPlan, can_build_own_plan: p.buildOwnPlan });
    }
    if (Object.keys(patch).length === 0) return ok(undefined);
    return this.updateRow(membershipId, patch);
  }

  /** Ends a membership (pending or active). The person keeps their history. */
  async end(membershipId: string): Promise<Result<void>> {
    if (!isGymId(membershipId)) return failed({ kind: 'invalid' });
    return this.updateRow(membershipId, { status: 'ended' });
  }

  /** The signed-in person's id (people.id), needed as created_by. */
  async myPersonId(userId: string): Promise<Result<string | null>> {
    return guard(async () => {
      const row = unwrap(await this.supabase.from('people').select('id').eq('auth_user_id', userId).maybeSingle<{ id: string }>());
      return row && isGymId(row.id) ? row.id : null;
    });
  }

  // An update that RLS filters out changes 0 rows without an error: ask for
  // the row back and treat "nothing came back" as forbidden.
  private async updateRow(membershipId: string, patch: Record<string, unknown>): Promise<Result<void>> {
    return guard(async () => {
      const rows = unwrap(await this.supabase.from('memberships').update(patch).eq('id', membershipId).select('id'));
      if (!Array.isArray(rows) || rows.length === 0) throw new CodedError('42501', 'forbidden');
    });
  }
}

const statusOrder: Record<Status, number> = { active: 0, pending: 1, ended: 2 };
const roleOrder: Record<Role, number> = { owner: 0, captain: 1, trainee: 2 };

function byStatusThenName(a: Member, b: Member): number {
  return statusOrder[a.status] - statusOrder[b.status] || roleOrder[a.role] - roleOrder[b.role] || a.name.localeCompare(b.name);
}
