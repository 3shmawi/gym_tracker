import type { SupabaseClient } from '@supabase/supabase-js';
import { CodedError } from '../core/failure';
import { failed, guard, unwrap, type Result } from '../core/result';
import { isGymId } from '../gyms/gyms';
import { isValidName, parsePlan, planProblem, toBody, type Plan, type PlanName } from './model';

// A gym's plan templates (migration 0019, D4). Table plan_templates: the gym's
// owner and captains read and write (private.i_manage, permanent session);
// the body is checked by private.plan_problem, the name by plan_name_ok, at
// most 50 per gym; created_by / updated_by / version are set by the database.
// Applying one to a member is the RPC apply_plan_template, which goes through
// save_plan and records plans.template_id / template_version.

export interface Template {
  readonly id: string;
  readonly name: PlanName;
  /** null: a body the dashboard can't read (shown, not usable). */
  readonly plan: Plan | null;
  readonly version: number;
  readonly updatedAt: Date | null;
}

/** Which template a member's plan came from (nulls when none). */
export interface TemplateLink {
  readonly templateId: string | null;
  readonly templateVersion: number | null;
}

/** A plan made from a template, as the "apply to everyone" list needs it. */
export interface LinkedPlan {
  readonly membershipId: string;
  readonly version: number;
  readonly plan: Plan | null;
}

export const MAX_TEMPLATES = 50;
const TEMPLATE_COLUMNS = 'id, name, body, version, updated_at';
const NO_LINK: TemplateLink = { templateId: null, templateVersion: null };

interface TemplateRow {
  id: unknown;
  name: unknown;
  body: unknown;
  version: unknown;
  updated_at: unknown;
}

function readName(v: unknown): PlanName | null {
  if (typeof v !== 'object' || v === null) return null;
  const o = v as Record<string, unknown>;
  if (typeof o.ar !== 'string' || typeof o.en !== 'string') return null;
  const name = { ar: o.ar, en: o.en };
  return isValidName(name) ? name : null;
}

export function toTemplate(row: TemplateRow): Template | null {
  if (typeof row.id !== 'string' || !isGymId(row.id)) return null;
  const name = readName(row.name);
  const version = typeof row.version === 'number' && Number.isInteger(row.version) && row.version >= 1 ? row.version : null;
  if (!name || version === null) return null;
  const at = typeof row.updated_at === 'string' ? new Date(row.updated_at) : null;
  return { id: row.id, name, plan: parsePlan(row.body), version, updatedAt: at && !Number.isNaN(at.getTime()) ? at : null };
}

// Before 0019 is deployed the columns don't exist: answer "no template".
const MISSING = new Set(['42703', 'PGRST204', 'PGRST205', '42P01']);
const isMissing = (error: unknown) => typeof error === 'object' && error !== null && MISSING.has(String((error as { code?: unknown }).code));

export class TemplatesRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async list(gymId: string): Promise<Result<Template[]>> {
    if (!isGymId(gymId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const { data, error } = await this.supabase
        .from('plan_templates')
        .select(TEMPLATE_COLUMNS)
        .eq('gym_id', gymId)
        .order('created_at')
        .limit(MAX_TEMPLATES)
        .overrideTypes<TemplateRow[], { merge: false }>();
      if (error && isMissing(error)) return [];
      return (unwrap({ data, error }) ?? []).flatMap((row) => {
        const t = toTemplate(row);
        return t ? [t] : [];
      });
    });
  }

  async create(gymId: string, name: PlanName, plan: Plan): Promise<Result<Template>> {
    return guard(async () => {
      if (!isGymId(gymId) || !isValidName(name) || planProblem(plan) !== null) throw new CodedError('22023', 'invalid_template');
      const row = unwrap(
        await this.supabase.from('plan_templates').insert({ gym_id: gymId, name: { ar: name.ar, en: name.en }, body: toBody(plan) }).select(TEMPLATE_COLUMNS).single<TemplateRow>(),
      );
      const t = row ? toTemplate(row) : null;
      if (!t) throw new CodedError('XX000', 'bad_row');
      return t;
    });
  }

  async rename(id: string, name: PlanName): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(id) || !isValidName(name)) throw new CodedError('22023', 'invalid_template');
      const rows = unwrap(await this.supabase.from('plan_templates').update({ name: { ar: name.ar, en: name.en } }).eq('id', id).select('id').overrideTypes<{ id: string }[], { merge: false }>());
      if ((rows ?? []).length === 0) throw new CodedError('42501', 'forbidden');
    });
  }

  /** Changes a template's body (its version grows by one). */
  async updateBody(id: string, plan: Plan): Promise<Result<number>> {
    return guard(async () => {
      if (!isGymId(id) || planProblem(plan) !== null) throw new CodedError('22023', 'invalid_template');
      const rows = unwrap(await this.supabase.from('plan_templates').update({ body: toBody(plan) }).eq('id', id).select('version').overrideTypes<{ version: number }[], { merge: false }>());
      const v = rows?.[0]?.version;
      if (typeof v !== 'number') throw new CodedError('42501', 'forbidden');
      return v;
    });
  }

  async remove(id: string): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(id)) throw new CodedError('22023', 'invalid_template');
      const rows = unwrap(await this.supabase.from('plan_templates').delete().eq('id', id).select('id').overrideTypes<{ id: string }[], { merge: false }>());
      if ((rows ?? []).length === 0) throw new CodedError('42501', 'forbidden');
    });
  }

  /** Replaces a member's plan with the template (base version 0 when they have none). */
  async apply(membershipId: string, templateId: string, baseVersion: number): Promise<Result<{ version: number }>> {
    return guard(async () => {
      if (!isGymId(membershipId) || !isGymId(templateId) || !Number.isInteger(baseVersion) || baseVersion < 0) throw new CodedError('22023', 'invalid_template');
      const data = unwrap(await this.supabase.rpc('apply_plan_template', { p_membership_id: membershipId, p_template_id: templateId, p_base_version: baseVersion })) as { version?: unknown } | null;
      return { version: typeof data?.version === 'number' ? data.version : baseVersion + 1 };
    });
  }

  /** The template a member's plan came from; "none" before 0019 is deployed. */
  async link(membershipId: string): Promise<Result<TemplateLink>> {
    if (!isGymId(membershipId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const { data, error } = await this.supabase.from('plans').select('template_id, template_version').eq('membership_id', membershipId).maybeSingle<{ template_id: unknown; template_version: unknown }>();
      if (error && isMissing(error)) return NO_LINK;
      const row = unwrap({ data, error });
      if (!row || typeof row.template_id !== 'string' || !isGymId(row.template_id)) return NO_LINK;
      return { templateId: row.template_id, templateVersion: typeof row.template_version === 'number' ? row.template_version : null };
    });
  }

  /** Every plan (that this person may read) made from the template. */
  async linkedPlans(templateId: string): Promise<Result<LinkedPlan[]>> {
    if (!isGymId(templateId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const rows = unwrap(
        await this.supabase.from('plans').select('membership_id, version, body').eq('template_id', templateId).limit(500).overrideTypes<{ membership_id: unknown; version: unknown; body: unknown }[], { merge: false }>(),
      );
      return (rows ?? []).flatMap((r) =>
        typeof r.membership_id === 'string' && isGymId(r.membership_id) && typeof r.version === 'number' ? [{ membershipId: r.membership_id, version: r.version, plan: parsePlan(r.body) }] : [],
      );
    });
  }
}
