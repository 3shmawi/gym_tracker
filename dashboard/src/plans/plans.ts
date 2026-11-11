import type { SupabaseClient } from '@supabase/supabase-js';
import { CodedError } from '../core/failure';
import { failed, guard, unwrap, type Result } from '../core/result';
import { isGymId } from '../gyms/gyms';
import { parsePlan, planProblem, toBody, type Plan } from './model';

// A member's plan (migration 0007, 0016). Read: table `plans`
// ("read plans of my membership or my gym": private.can_read_plan, which for a
// manager is i_manage_role: owners read anyone's, captains trainees'). Write:
// only the RPC save_plan(p_membership_id, p_base_version, p_body), security
// definer, which checks the caller, validates the body (private.plan_problem)
// and bumps `version`. The app then shows "Your captain updated your plan".
//
// save_plan checks `base_version` only for a trainee; a manager's save always
// wins. So the dashboard reads the version again just before it saves and
// stops with `plan_changed` when someone saved meanwhile (the page then shows
// what changed). The window between that read and the save is the only gap;
// closing it needs a server change (see docs/features/dashboard.md, D3).

export interface StoredPlan {
  /** null: the member has no plan yet (version 0). */
  readonly plan: Plan | null;
  readonly version: number;
  /** A stored body the dashboard can't read safely (it is then not editable). */
  readonly unreadable: boolean;
  /** Membership id of who saved last, and when. */
  readonly updatedBy: string | null;
  readonly updatedAt: Date | null;
}

interface PlanRow {
  body: unknown;
  version: unknown;
  updated_by: unknown;
  updated_at: unknown;
}

const NONE: StoredPlan = { plan: null, version: 0, unreadable: false, updatedBy: null, updatedAt: null };

export function toStoredPlan(row: PlanRow | null): StoredPlan {
  if (!row) return NONE;
  const version = typeof row.version === 'number' && Number.isInteger(row.version) && row.version >= 1 ? row.version : null;
  if (version === null) return { ...NONE, unreadable: true };
  const plan = parsePlan(row.body);
  const updatedBy = typeof row.updated_by === 'string' && isGymId(row.updated_by) ? row.updated_by : null;
  const at = typeof row.updated_at === 'string' ? new Date(row.updated_at) : null;
  return { plan, version, unreadable: plan === null, updatedBy, updatedAt: at && !Number.isNaN(at.getTime()) ? at : null };
}

export interface Saved {
  readonly version: number;
}

const PLAN_COLUMNS = 'body, version, updated_by, updated_at';
/** Members read at most in one copy (a gym's list is far smaller). */
export const MAX_MEMBERS = 500;

export class PlansRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async get(membershipId: string): Promise<Result<StoredPlan>> {
    if (!isGymId(membershipId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const row = unwrap(
        await this.supabase.from('plans').select(PLAN_COLUMNS).eq('membership_id', membershipId).maybeSingle<PlanRow>(),
      );
      return toStoredPlan(row);
    });
  }

  /** The stored version only (0 when there is no plan). */
  async version(membershipId: string): Promise<Result<number>> {
    if (!isGymId(membershipId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const row = unwrap(await this.supabase.from('plans').select('version').eq('membership_id', membershipId).maybeSingle<{ version: unknown }>());
      return row && typeof row.version === 'number' ? row.version : 0;
    });
  }

  /** Stored versions of several members' plans in one read (missing = no plan). */
  async versions(membershipIds: readonly string[]): Promise<Result<ReadonlyMap<string, number>>> {
    const ids = [...new Set(membershipIds)].filter(isGymId).slice(0, MAX_MEMBERS);
    return guard(async () => {
      const out = new Map<string, number>();
      if (ids.length === 0) return out;
      const rows = unwrap(
        await this.supabase.from('plans').select('membership_id, version').in('membership_id', ids).limit(MAX_MEMBERS).overrideTypes<{ membership_id: unknown; version: unknown }[], { merge: false }>(),
      );
      for (const r of rows ?? []) {
        if (typeof r.membership_id === 'string' && ids.includes(r.membership_id) && typeof r.version === 'number') out.set(r.membership_id, r.version);
      }
      return out;
    });
  }

  /** Replaces a member's plan with this one, whatever they have now (copy, §20). */
  async replace(membershipId: string, plan: Plan): Promise<Result<Saved>> {
    const current = await this.version(membershipId);
    if (!current.ok) return current;
    return this.save(membershipId, current.value, plan);
  }

  /**
   * Saves through save_plan. `baseVersion` is the version the captain edited
   * (0 for a first plan); when the stored one differs, nothing is sent and the
   * result is `conflict` / `plan_changed`.
   */
  async save(membershipId: string, baseVersion: number, plan: Plan): Promise<Result<Saved>> {
    return guard(async () => {
      if (!isGymId(membershipId) || !Number.isInteger(baseVersion) || baseVersion < 0) throw new CodedError('22023', 'invalid_plan: bad request');
      const problem = planProblem(plan);
      if (problem !== null) throw new CodedError('22023', `invalid_plan: ${problem}`);
      const stored = await this.version(membershipId);
      if (!stored.ok) throw toThrowable(stored.failure);
      if (stored.value !== baseVersion) throw new CodedError('P0001', 'plan_changed');
      const data = unwrap(
        await this.supabase.rpc('save_plan', { p_membership_id: membershipId, p_base_version: baseVersion, p_body: toBody(plan) }),
      ) as { version?: unknown } | null;
      const version = typeof data?.version === 'number' ? data.version : baseVersion + 1;
      return { version };
    });
  }
}

// guard() classifies thrown errors; a Failure we already have is re-thrown as
// an error of the same kind.
function toThrowable(failure: { kind: string }): unknown {
  switch (failure.kind) {
    case 'offline':
      return new TypeError('Failed to fetch');
    case 'forbidden':
      return new CodedError('42501', 'forbidden');
    case 'session_ended':
      return new CodedError('PGRST301', 'session');
    default:
      return new CodedError('XX000', 'server');
  }
}
