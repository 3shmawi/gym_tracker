import { useEffect, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import { useI18n } from '../i18n';
import type { Member } from '../members/members';
import type { Plan } from '../plans/model';
import type { PlansRepository } from '../plans/plans';
import { planFailureKey } from '../plans/text';
import { Dialog } from './Dialog';
import { Icon } from './icons';

// Copy one member's saved plan to other members (decision doc §20, board
// "Dashboard 5"). Each target gets its own copy through save_plan, one after
// the other; a member who has a plan gets it replaced, after the warning.

type Outcome = { readonly ok: true } | { readonly ok: false; readonly failure: Failure };

export function CopyPlanDialog({ sourceName, plan, candidates, plans, online, onClose }: {
  readonly sourceName: string;
  readonly plan: Plan;
  /** Members this manager may write a plan for (not the source, not ended). */
  readonly candidates: readonly Member[];
  readonly plans: PlansRepository;
  readonly online: boolean;
  readonly onClose: () => void;
}) {
  const { t } = useI18n();
  const [versions, setVersions] = useState<ReadonlyMap<string, number> | 'loading' | 'failed'>('loading');
  const [picked, setPicked] = useState<ReadonlySet<string>>(new Set());
  const [results, setResults] = useState<ReadonlyMap<string, Outcome>>(new Map());
  const [working, setWorking] = useState<{ done: number; total: number } | null>(null);

  const load = () => {
    setVersions('loading');
    void plans.versions(candidates.map((m) => m.id)).then((r) => {
      setVersions(r.ok ? r.value : 'failed');
    });
  };
  useEffect(load, [plans, candidates]);

  const toggle = (id: string) => {
    const next = new Set(picked);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setPicked(next);
  };

  const copy = async (ids: readonly string[]) => {
    const next = new Map(results);
    setWorking({ done: 0, total: ids.length });
    let done = 0;
    for (const id of ids) {
      const r = await plans.replace(id, plan);
      next.set(id, r.ok ? { ok: true } : { ok: false, failure: r.failure });
      done++;
      setWorking({ done, total: ids.length });
      setResults(new Map(next));
    }
    setWorking(null);
  };

  const ran = results.size > 0;
  const failedIds = [...results.entries()].filter(([, r]) => !r.ok).map(([id]) => id);
  const okCount = [...results.values()].filter((r) => r.ok).length;
  const withPlan = typeof versions === 'object' ? [...picked].filter((id) => versions.has(id)).length : 0;
  const count = picked.size;

  return (
    <Dialog titleId="copy-title" onClose={working ? () => undefined : onClose}>
      <h2 class="h2 plain" id="copy-title">{t('copy.title', { name: sourceName })}</h2>
      <p class="cap">{t('copy.body')}</p>
      {candidates.length === 0 ? (
        <p class="sub">{t('copy.noOne')}</p>
      ) : versions === 'loading' ? (
        <p class="cap" role="status" aria-busy="true">{t('copy.loading')}</p>
      ) : versions === 'failed' ? (
        <div class="banner err" role="alert">
          <Icon name="alert" />
          <span class="grow">{t('state.errorTitle')}</span>
          <button type="button" class="btn sm" onClick={load}>{t('state.retry')}</button>
        </div>
      ) : (
        <fieldset class="perms bare copy-list">
          <legend class="sr-only">{t('plan.copy')}</legend>
          {candidates.map((m) => {
            const result = results.get(m.id);
            const has = versions.has(m.id);
            return (
              <label key={m.id} class="chk copy-row">
                <input type="checkbox" checked={picked.has(m.id)} disabled={ran || working !== null} aria-label={t('copy.select', { name: m.name })} onChange={() => { toggle(m.id); }} />
                <span class="grow">
                  <b class="plain">{m.name}</b>
                  <span class={`cap${has && picked.has(m.id) && !ran ? ' warn-text' : ''}`}>
                    {has ? t('copy.hasPlan') : t('copy.noPlan')}
                    {m.status === 'pending' ? ` · ${t('copy.pending')}` : ''}
                  </span>
                  {result ? (
                    result.ok ? (
                      <span class="okt"><Icon name="check" />{t('copy.ok')}</span>
                    ) : (
                      <span class="errt"><Icon name="alert" />{t('copy.failed', { why: t(planFailureKey(result.failure)) })}</span>
                    )
                  ) : null}
                </span>
              </label>
            );
          })}
        </fieldset>
      )}
      <div class="live-slot" role="status">
        {working ? <span class="cap">{t('copy.working', { done: working.done, total: working.total })}</span> : null}
        {!working && ran ? <b>{t('copy.done', { ok: okCount, total: results.size })}</b> : null}
      </div>
      {!ran && withPlan > 0 ? (
        <p class="warn-text" role="status">{withPlan === 1 ? t('copy.replaceOne') : t('copy.replaceMany', { count: withPlan })}</p>
      ) : null}
      {!online ? <p class="cap">{t('plan.offlineHint')}</p> : null}
      <div class="acts">
        {ran ? (
          <>
            {failedIds.length > 0 ? (
              <button type="button" class="btn" disabled={working !== null || !online} onClick={() => void copy(failedIds)}>
                {t('copy.retry', { count: failedIds.length })}
              </button>
            ) : null}
            <button type="button" class="btn pri" disabled={working !== null} onClick={onClose}>{t('copy.close')}</button>
          </>
        ) : (
          <>
            <button type="button" class="btn" disabled={working !== null} onClick={onClose}>{t('copy.cancel')}</button>
            <button type="button" class="btn pri" disabled={count === 0 || working !== null || !online || typeof versions !== 'object'} onClick={() => void copy([...picked])}>
              {count === 1 ? t('copy.goOne') : t('copy.goMany', { count })}
            </button>
          </>
        )}
      </div>
    </Dialog>
  );
}
