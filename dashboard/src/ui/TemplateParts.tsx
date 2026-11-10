import { useEffect, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import { useI18n } from '../i18n';
import type { Member } from '../members/members';
import type { PlanExercise } from '../plans/model';
import type { PlansRepository } from '../plans/plans';
import { copyTargets, type ExerciseDiff } from '../plans/templateDiff';
import type { LinkedPlan, Template, TemplatesRepository } from '../plans/templates';
import { nameIn, planFailureKey } from '../plans/text';
import { Dialog } from './Dialog';
import { Icon } from './icons';

// D4 pieces of the plan page (board "Dashboard 5, 6"): the "From template"
// banner, "Replace with template", and "Apply a change to everyone on this
// template". Views only: they get data and callbacks, the page saves.

export function useTargetsText() {
  const { t } = useI18n();
  return (e: PlanExercise) => t('tpl.values', { sets: e.sets, reps: e.reps, rest: e.rest });
}

export function TemplateBanner({ template, memberName, changes, newer, gone, canApply, onApply }: {
  readonly template: Template | null;
  readonly memberName: string;
  readonly changes: number;
  readonly newer: boolean;
  readonly gone: boolean;
  readonly canApply: boolean;
  readonly onApply: () => void;
}) {
  const { t, lang } = useI18n();
  if (gone) {
    return <div class="banner info"><Icon name="info" /><span>{t('tpl.gone')}</span></div>;
  }
  if (!template) return null;
  const count = changes === 0 ? t('tpl.changesNone', { name: memberName }) : changes === 1 ? t('tpl.changesOne', { name: memberName }) : t('tpl.changesMany', { count: changes, name: memberName });
  return (
    <div class="banner info tpl-banner" role="status">
      <span class="row-icon">
        <Icon name="copy" />
        <span class="plain-text"><b>{t('tpl.from', { template: nameIn(lang, template.name) })}</b> {count}</span>
      </span>
      {newer ? <span class="cap">{t('tpl.newer')}</span> : null}
      {canApply ? (
        <span>
          <button type="button" class="btn sm" onClick={onApply}>{t('tpl.applyAll')}</button>
        </span>
      ) : null}
    </div>
  );
}

export function ReplaceDialog({ memberName, templates, online, busy, onPick, onClose }: {
  readonly memberName: string;
  readonly templates: readonly Template[];
  readonly online: boolean;
  readonly busy: boolean;
  readonly onPick: (t: Template) => void;
  readonly onClose: () => void;
}) {
  const { t, lang } = useI18n();
  const usable = templates.filter((x) => x.plan !== null);
  const [picked, setPicked] = useState<string | null>(usable[0]?.id ?? null);
  const chosen = usable.find((x) => x.id === picked);
  return (
    <Dialog titleId="replace-title" onClose={onClose}>
      <h2 class="h2 plain" id="replace-title">{t('tpl.replaceTitle', { name: memberName })}</h2>
      {usable.length === 0 ? (
        <p class="sub">{t('tpl.replaceNone')}</p>
      ) : (
        <>
          <p class="cap">{t('tpl.replaceBody', { name: memberName })}</p>
          <fieldset class="perms bare copy-list">
            <legend class="sr-only">{t('tpl.replace')}</legend>
            {usable.map((x) => {
              const exercises = x.plan?.days.reduce((n, d) => n + d.exercises.length, 0) ?? 0;
              return (
                <label key={x.id} class="chk copy-row">
                  <input type="radio" name="tpl" checked={picked === x.id} aria-label={t('tpl.pick', { name: nameIn(lang, x.name) })} onChange={() => { setPicked(x.id); }} />
                  <span class="grow">
                    <b class="plain">{nameIn(lang, x.name)}</b>
                    <span class="cap">{t('tpl.summary', { days: x.plan?.days.length ?? 0, exercises })}</span>
                  </span>
                </label>
              );
            })}
          </fieldset>
          <p class="warn-text">{t('copy.replaceOne')}</p>
        </>
      )}
      {!online ? <p class="cap">{t('plan.offlineHint')}</p> : null}
      <div class="acts">
        <button type="button" class="btn" disabled={busy} onClick={onClose}>{t('copy.cancel')}</button>
        {chosen ? (
          <button type="button" class="btn pri" disabled={busy || !online} onClick={() => { onPick(chosen); }}>{t('tpl.replaceGo')}</button>
        ) : null}
      </div>
    </Dialog>
  );
}

type Outcome = { readonly ok: true } | { readonly ok: false; readonly failure: Failure } | { readonly ok: 'missing' };

/**
 * One change (an exercise's targets in this member's saved plan) applied to
 * every other member whose plan comes from the same template: one save_plan
 * each, results per member; optionally the template too.
 */
export function ApplyToAllDialog({ template, memberId, diffs, everyone, plans, templates, online, onClose }: {
  readonly template: Template;
  readonly memberId: string;
  readonly diffs: readonly ExerciseDiff[];
  readonly everyone: readonly Member[];
  readonly plans: PlansRepository;
  readonly templates: TemplatesRepository;
  readonly online: boolean;
  readonly onClose: () => void;
}) {
  const { t, lang } = useI18n();
  const values = useTargetsText();
  const [linked, setLinked] = useState<readonly LinkedPlan[] | 'loading' | 'failed'>('loading');
  const [change, setChange] = useState<string>(diffs[0] ? `${diffs[0].dayId}/${diffs[0].exerciseId}` : '');
  const [picked, setPicked] = useState<ReadonlySet<string>>(new Set());
  const [alsoTemplate, setAlsoTemplate] = useState(true);
  const [results, setResults] = useState<ReadonlyMap<string, Outcome>>(new Map());
  const [working, setWorking] = useState(false);

  const load = () => {
    setLinked('loading');
    void templates.linkedPlans(template.id).then((r) => {
      if (!r.ok) {
        setLinked('failed');
        return;
      }
      const others = r.value.filter((p) => p.membershipId !== memberId && everyone.some((m) => m.id === p.membershipId && m.status !== 'ended'));
      setLinked(others);
      setPicked(new Set(others.map((p) => p.membershipId)));
    });
  };
  useEffect(load, [templates, template.id, memberId, everyone]);

  const diff = diffs.find((d) => `${d.dayId}/${d.exerciseId}` === change);
  const nameOf = (id: string) => everyone.find((m) => m.id === id)?.name ?? id;

  const go = async (ids: readonly string[]) => {
    if (!diff || typeof linked !== 'object') return;
    // The template itself changes once, on the first run (not on a retry).
    const firstRun = results.size === 0;
    setWorking(true);
    const next = new Map(results);
    for (const id of ids) {
      const p = linked.find((x) => x.membershipId === id);
      const current = await plans.get(id);
      if (!p || !current.ok || !current.value.plan) {
        next.set(id, current.ok ? { ok: 'missing' } : { ok: false, failure: current.failure });
        setResults(new Map(next));
        continue;
      }
      const changed = copyTargets(current.value.plan, diff.dayId, diff.exerciseId, diff.mine);
      if (!changed.ok) {
        next.set(id, { ok: 'missing' });
      } else {
        const r = await plans.save(id, current.value.version, changed.plan);
        next.set(id, r.ok ? { ok: true } : { ok: false, failure: r.failure });
      }
      setResults(new Map(next));
    }
    if (alsoTemplate && template.plan && firstRun) {
      const tpl = copyTargets(template.plan, diff.dayId, diff.exerciseId, diff.mine);
      if (tpl.ok) await templates.updateBody(template.id, tpl.plan);
    }
    setWorking(false);
  };

  const ran = results.size > 0;
  const failedIds = [...results.entries()].filter(([, r]) => r.ok === false).map(([id]) => id);
  const okCount = [...results.values()].filter((r) => r.ok === true).length;

  return (
    <Dialog titleId="apply-title" onClose={working ? () => undefined : onClose}>
      <h2 class="h2 plain" id="apply-title">{t('tpl.applyTitle', { template: nameIn(lang, template.name) })}</h2>
      <fieldset class="perms bare">
        <legend class="h3">{t('tpl.applyPickChange')}</legend>
        {diffs.map((d) => {
          const key = `${d.dayId}/${d.exerciseId}`;
          return (
            <label key={key} class="chk">
              <input type="radio" name="change" checked={change === key} disabled={ran || working} onChange={() => { setChange(key); }} />
              <span class="plain-text">{t('tpl.applyChange', { exercise: nameIn(lang, d.mine.name), value: values(d.mine) })}</span>
            </label>
          );
        })}
      </fieldset>
      <h3 class="h3">{t('tpl.applyMembers')}</h3>
      {linked === 'loading' ? (
        <p class="cap" role="status" aria-busy="true">{t('copy.loading')}</p>
      ) : linked === 'failed' ? (
        <div class="banner err" role="alert"><Icon name="alert" /><span class="grow">{t('state.errorTitle')}</span><button type="button" class="btn sm" onClick={load}>{t('state.retry')}</button></div>
      ) : linked.length === 0 ? (
        <p class="sub">{t('tpl.applyNone')}</p>
      ) : (
        <fieldset class="perms bare apply-list">
          <legend class="sr-only">{t('tpl.applyMembers')}</legend>
          {linked.map((p) => {
            const r = results.get(p.membershipId);
            return (
              <label key={p.membershipId} class="chk copy-row">
                <input type="checkbox" checked={picked.has(p.membershipId)} disabled={ran || working} aria-label={t('copy.select', { name: nameOf(p.membershipId) })} onChange={() => {
                  const next = new Set(picked);
                  if (next.has(p.membershipId)) next.delete(p.membershipId);
                  else next.add(p.membershipId);
                  setPicked(next);
                }} />
                <span class="grow">
                  <b class="plain">{nameOf(p.membershipId)}</b>
                  {r?.ok === true ? <span class="okt"><Icon name="check" />{t('copy.ok')}</span> : null}
                  {r?.ok === 'missing' ? <span class="cap">{t('tpl.applyMissing')}</span> : null}
                  {r?.ok === false ? <span class="errt"><Icon name="alert" />{t('copy.failed', { why: t(planFailureKey(r.failure)) })}</span> : null}
                </span>
              </label>
            );
          })}
        </fieldset>
      )}
      {!ran ? (
        <label class="chk">
          <input type="checkbox" checked={alsoTemplate} onChange={() => { setAlsoTemplate(!alsoTemplate); }} />
          <span>{t('tpl.applyAlsoTemplate')}</span>
        </label>
      ) : null}
      <div class="live-slot" role="status">
        {ran && !working ? <b>{t('tpl.applyDone', { ok: okCount, total: results.size })}</b> : null}
      </div>
      {!online ? <p class="cap">{t('plan.offlineHint')}</p> : null}
      <div class="acts">
        {ran ? (
          <>
            {failedIds.length > 0 ? <button type="button" class="btn" disabled={working || !online} onClick={() => void go(failedIds)}>{t('copy.retry', { count: failedIds.length })}</button> : null}
            <button type="button" class="btn pri" disabled={working} onClick={onClose}>{t('copy.close')}</button>
          </>
        ) : (
          <>
            <button type="button" class="btn" disabled={working} onClick={onClose}>{t('copy.cancel')}</button>
            <button type="button" class="btn pri" disabled={working || !online || !diff || typeof linked !== 'object' || picked.size === 0} onClick={() => void go([...picked])}>
              {t('tpl.applyGo', { count: picked.size })}
            </button>
          </>
        )}
      </div>
    </Dialog>
  );
}
