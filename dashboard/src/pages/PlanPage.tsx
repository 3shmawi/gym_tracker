import type { ComponentChildren } from 'preact';
import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { linkHandler, pathOf, type PlanAction, type Route } from '../app/router';
import type { Failure } from '../core/failure';
import type { MediaRepository } from '../exercises/media';
import type { LibraryExercise } from '../exercises/types';
import { useGymMedia } from '../exercises/useGymMedia';
import type { ManagedGym } from '../gyms/gyms';
import { translate, useI18n } from '../i18n';
import { canManage, type Member, type MembersRepository } from '../members/members';
import { diffPlans } from '../plans/diff';
import * as edit from '../plans/edit';
import { LIMITS, newPlanId, planIds, planProblem, type Plan, type PlanName } from '../plans/model';
import type { PlansRepository, StoredPlan } from '../plans/plans';
import { resetToTemplate, targetDiffs, templateChanges, type ExerciseDiff } from '../plans/templateDiff';
import type { Template, TemplateLink, TemplatesRepository } from '../plans/templates';
import { ApplyToAllDialog, ReplaceDialog, TemplateBanner } from '../ui/TemplateParts';
import { changeLine, editErrorKey, nameIn, planFailureKey } from '../plans/text';
import { CopyPlanDialog } from '../ui/CopyPlanDialog';
import { Icon } from '../ui/icons';
import { formatDate } from '../ui/memberText';
import { ConfirmDialog, ExercisePicker, NameDialog } from '../ui/PlanDialogs';
import { PlanDayView } from '../ui/PlanDayView';
import { ErrorView, LoadingView, StateBlock } from '../ui/states';
import { useLeaveWarning, useMembersList } from './useMembersList';

interface Props {
  readonly gym: ManagedGym;
  readonly memberId: string;
  readonly members: MembersRepository;
  readonly plans: PlansRepository;
  readonly templates: TemplatesRepository;
  readonly media: MediaRepository;
  readonly cloudName: string | null;
  readonly online: boolean;
  /** A quick action (from the members list or the member page) whose dialog opens first. */
  readonly open?: PlanAction | undefined;
}

type Loaded = { readonly state: 'loading' } | { readonly state: 'failed'; readonly failure: Failure } | { readonly state: 'ready'; readonly stored: StoredPlan };

type Modal =
  | { readonly kind: 'add_day' }
  | { readonly kind: 'rename_day'; readonly dayId: string }
  | { readonly kind: 'delete_day'; readonly dayId: string }
  | { readonly kind: 'rename_ex'; readonly dayId: string; readonly exId: string }
  | { readonly kind: 'delete_ex'; readonly dayId: string; readonly exId: string }
  | { readonly kind: 'pick'; readonly dayId: string }
  | { readonly kind: 'copy' }
  | { readonly kind: 'save_template' }
  | { readonly kind: 'replace' }
  | { readonly kind: 'apply_all' };

type Note = { readonly tone: 'ok' | 'err'; readonly text: string } | null;

interface Conflict {
  readonly latest: StoredPlan;
  readonly base: Plan | null;
  readonly mine: Plan;
}

/** Loads a member's plan; `reload()` shows the skeleton. */
function useStoredPlan(plans: PlansRepository, memberId: string) {
  const [data, setData] = useState<Loaded>({ state: 'loading' });
  const token = useRef(0);
  const reload = useCallback(async () => {
    const mine = ++token.current;
    setData({ state: 'loading' });
    const r = await plans.get(memberId);
    if (mine !== token.current) return;
    setData(r.ok ? { state: 'ready', stored: r.value } : { state: 'failed', failure: r.failure });
  }, [plans, memberId]);
  useEffect(() => {
    void reload();
    return () => {
      token.current++;
    };
  }, [reload]);
  return { data, reload, set: (stored: StoredPlan) => { setData({ state: 'ready', stored }); } };
}

export function PlanPage(props: Props) {
  const { gym, memberId, members } = props;
  const { t } = useI18n();
  const list = useMembersList(members, gym.id);
  const stored = useStoredPlan(props.plans, memberId);
  const [justSaved, setJustSaved] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const memberRoute: Route = { name: 'member', gymId: gym.id, memberId };

  const member = list.data.state === 'ready' ? list.data.members.find((m) => m.id === memberId) : undefined;
  const back = (
    <a class="btn ghost sm back" href={pathOf(memberRoute)} onClick={linkHandler(memberRoute)}>
      <span class="flip" aria-hidden="true"><Icon name="chevronLeft" /></span>
      {member ? t('plan.back', { name: member.name }) : t('member.back')}
    </a>
  );

  if (list.data.state === 'loading' || stored.data.state === 'loading') {
    return (
      <section class="stack">
        {back}
        <LoadingView />
      </section>
    );
  }
  if (list.data.state === 'failed' || stored.data.state === 'failed') {
    const failure = list.data.state === 'failed' ? list.data.failure : stored.data.state === 'failed' ? stored.data.failure : { kind: 'server' as const };
    return (
      <section class="stack">
        {back}
        <ErrorView failure={failure} onRetry={() => { void list.reload(); void stored.reload(); }} />
      </section>
    );
  }
  if (!member) {
    return (
      <section class="stack">
        {back}
        <StateBlock icon="search" title={t('member.notFoundTitle')}>
          <p class="sub">{t('member.notFoundBody')}</p>
        </StateBlock>
      </section>
    );
  }
  return (
    <PlanEditor
      key={`${member.id}-${String(stored.data.stored.version)}`}
      {...props}
      member={member}
      everyone={list.data.members}
      stored={stored.data.stored}
      back={back}
      justSaved={justSaved}
      flash={flash}
      onReload={(message) => {
        setJustSaved(false);
        setFlash(message);
        void stored.reload();
      }}
      onStored={(s, saved) => {
        stored.set(s);
        setJustSaved(saved);
        setFlash(null);
      }}
    />
  );
}

interface EditorProps extends Props {
  readonly member: Member;
  readonly everyone: readonly Member[];
  readonly stored: StoredPlan;
  readonly back: ComponentChildren;
  readonly justSaved: boolean;
  /** A message kept across the reload that follows (after a template was applied). */
  readonly flash: string | null;
  /** Loads the plan again from the server, then shows `message`. */
  readonly onReload: (message: string) => void;
  /** A new stored plan: after our own save (`saved`), or loaded after a conflict. */
  readonly onStored: (stored: StoredPlan, saved: boolean) => void;
}

function PlanEditor({ open, gym, member, everyone, stored, plans, templates, media, cloudName, online, back, justSaved, flash, onReload, onStored }: EditorProps) {
  const { t, lang } = useI18n();
  const [draft, setDraft] = useState<Plan | null>(stored.plan);
  const [dayId, setDayId] = useState<string | null>(stored.plan?.days[0]?.id ?? null);
  // A quick action opens its dialog once; the address goes back to the plain plan.
  const [modal, setModal] = useState<Modal | null>(() => (open && canManage(gym.role, member.role) && member.status !== 'ended' && !stored.unreadable && (open !== 'copy' && open !== 'save_template' ? true : stored.plan !== null) ? { kind: open } : null));
  useEffect(() => {
    if (open) window.history.replaceState(null, '', pathOf({ name: 'member_plan', gymId: gym.id, memberId: member.id }));
  }, []);
  const [note, setNote] = useState<Note>(null);
  const [saving, setSaving] = useState(false);
  const [conflict, setConflict] = useState<Conflict | null>(null);
  const issued = useRef(new Set<string>());
  const gymMedia = useGymMedia(media, gym.id);
  const covers = gymMedia.data.state === 'ready' ? gymMedia.data.media.pictures : new Map<string, readonly string[]>();

  // D4: the gym's templates and the one this plan came from (none before 0019).
  const [tplList, setTplList] = useState<readonly Template[]>([]);
  const [link, setLink] = useState<TemplateLink>({ templateId: null, templateVersion: null });
  const [tplNote, setTplNote] = useState<Note>(null);
  const [tplBusy, setTplBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    void templates.list(gym.id).then((r) => { if (alive && r.ok) setTplList(r.value); });
    void templates.link(member.id).then((r) => { if (alive && r.ok) setLink(r.value); });
    return () => {
      alive = false;
    };
  }, [templates, gym.id, member.id, stored.version]);
  const template = link.templateId ? tplList.find((x) => x.id === link.templateId) ?? null : null;
  const templateGone = link.templateId !== null && tplList.length > 0 && template === null;

  const editable = canManage(gym.role, member.role) && member.status !== 'ended' && !stored.unreadable;
  const dirty = draft !== null && JSON.stringify(draft) !== JSON.stringify(stored.plan);
  useLeaveWarning(dirty, t('plan.leave'));

  const newId = (prefix: 'day' | 'ex') => {
    const taken = new Set([...(draft ? planIds(draft) : []), ...(stored.plan ? planIds(stored.plan) : []), ...issued.current]);
    const id = newPlanId(prefix, taken, Date.now());
    issued.current.add(id);
    return id;
  };

  const apply = (result: edit.EditResult) => {
    if (result.ok) {
      setDraft(result.plan);
      setNote(null);
      return true;
    }
    setNote({ tone: 'err', text: t(editErrorKey(result.error)) });
    return false;
  };

  const save = async () => {
    if (!draft) return;
    const problem = planProblem(draft);
    if (problem) {
      setNote({ tone: 'err', text: problem === 'too large' ? t('plan.tooLarge') : t('plan.invalid', { why: problem }) });
      return;
    }
    setSaving(true);
    setNote(null);
    const result = await plans.save(member.id, stored.version, draft);
    setSaving(false);
    if (result.ok) {
      onStored({ plan: draft, version: result.value.version, unreadable: false, updatedBy: null, updatedAt: new Date() }, true);
      return;
    }
    if (result.failure.kind === 'conflict' && result.failure.reason === 'plan_changed') {
      const latest = await plans.get(member.id);
      if (latest.ok) {
        setConflict({ latest: latest.value, base: stored.plan, mine: draft });
        return;
      }
    }
    setNote({ tone: 'err', text: t(planFailureKey(result.failure)) });
  };

  const days = draft?.days ?? [];
  const day = days.find((d) => d.id === dayId) ?? days[0] ?? null;
  const exerciseCount = days.reduce((n, d) => n + d.exercises.length, 0);
  const updatedByName = stored.updatedBy ? everyone.find((m) => m.id === stored.updatedBy)?.name : undefined;
  const candidates = everyone.filter((m) => m.id !== member.id && m.status !== 'ended' && canManage(gym.role, m.role));
  const tplPlan = template?.plan ?? null;
  const draftDiffs = draft && tplPlan ? targetDiffs(draft, tplPlan) : new Map<string, ExerciseDiff>();
  const savedDiffs = stored.plan && tplPlan ? [...targetDiffs(stored.plan, tplPlan).values()] : [];
  const changeCount = draft && tplPlan ? templateChanges(draft, tplPlan).length : 0;
  const dayDiffs = new Map([...draftDiffs.values()].filter((d) => d.dayId === day?.id).map((d) => [d.exerciseId, d]));

  const modalView = (() => {
    if (!modal) return null;
    // Replace / save as template / copy / apply need no draft; the edits do.
    const usesDraft = !['replace', 'save_template', 'copy', 'apply_all'].includes(modal.kind);
    if (usesDraft && !draft) return null;
    const cur: Plan = draft ?? { days: [] };
    const close = () => { setModal(null); };
    const dayOf = (id: string) => cur.days.find((d) => d.id === id);
    switch (modal.kind) {
      case 'add_day':
        return (
          <NameDialog title={t('name.titleAddDay')} initial={null} onClose={close} onSave={(name) => {
            const id = newId('day');
            if (apply(edit.addDay(cur, name, id))) setDayId(id);
            close();
          }} />
        );
      case 'rename_day': {
        const d = dayOf(modal.dayId);
        return d ? <NameDialog title={t('name.titleRenameDay')} initial={d.name} onClose={close} onSave={(name) => { apply(edit.renameDay(cur, d.id, name)); close(); }} /> : null;
      }
      case 'delete_day': {
        const d = dayOf(modal.dayId);
        return d ? (
          <ConfirmDialog title={t('name.deleteDayTitle', { name: nameIn(lang, d.name) })} body={t('name.deleteDayBody')} action={t('name.delete')} onClose={close} onConfirm={() => {
            const i = cur.days.findIndex((x) => x.id === d.id);
            if (apply(edit.deleteDay(cur, d.id))) setDayId(cur.days[i + 1]?.id ?? cur.days[i - 1]?.id ?? null);
            close();
          }} />
        ) : null;
      }
      case 'rename_ex': {
        const e = dayOf(modal.dayId)?.exercises.find((x) => x.id === modal.exId);
        return e ? <NameDialog title={t('name.titleRenameEx')} initial={e.name} onClose={close} onSave={(name) => { apply(edit.renameExercise(cur, modal.dayId, e.id, name)); close(); }} /> : null;
      }
      case 'delete_ex': {
        const e = dayOf(modal.dayId)?.exercises.find((x) => x.id === modal.exId);
        return e ? (
          <ConfirmDialog title={t('name.deleteExTitle', { name: nameIn(lang, e.name) })} body={t('name.deleteExBody')} action={t('name.delete')} onClose={close} onConfirm={() => { apply(edit.deleteExercise(cur, modal.dayId, e.id)); close(); }} />
        ) : null;
      }
      case 'pick': {
        const d = dayOf(modal.dayId);
        if (!d) return null;
        const addLibrary = (e: LibraryExercise) => {
          apply(edit.addExercise(cur, d.id, { id: e.id, name: { ar: e.ar, en: e.en }, sets: e.sets, reps: e.reps, rest: e.rest, step: e.step }));
          close();
        };
        const addOwn = (name: PlanName) => {
          apply(edit.addExercise(cur, d.id, { id: newId('ex'), name }));
          close();
        };
        return <ExercisePicker dayName={nameIn(lang, d.name)} inDay={new Set(d.exercises.map((x) => x.id))} onClose={close} onPick={addLibrary} onOwn={addOwn} />;
      }
      case 'save_template': {
        const base = { ar: member.name, en: member.name };
        return (
          <NameDialog title={t('tpl.saveAsTitle', { name: member.name })} initial={base} onClose={close} onSave={(name) => {
            close();
            if (!stored.plan) return;
            setTplBusy(true);
            void templates.create(gym.id, name, stored.plan).then((r) => {
              setTplBusy(false);
              if (r.ok) {
                setTplList([...tplList, r.value]);
                setTplNote({ tone: 'ok', text: t('tpl.saved', { name: nameIn(lang, name) }) });
              } else setTplNote({ tone: 'err', text: r.failure.kind === 'conflict' && r.failure.reason === 'too_many_templates_in_gym' ? t('tpl.full', { max: 50 }) : r.failure.kind === 'forbidden' ? t('tpl.errForbidden') : t('tpl.errServer') });
            });
          }} />
        );
      }
      case 'replace':
        return (
          <ReplaceDialog memberName={member.name} templates={tplList} online={online} busy={tplBusy} onClose={close} onPick={(tpl) => {
            setTplBusy(true);
            void templates.apply(member.id, tpl.id, stored.version).then((r) => {
              setTplBusy(false);
              close();
              if (r.ok) onReload(t('tpl.replaced', { name: member.name, template: nameIn(lang, tpl.name) }));
              else setTplNote({ tone: 'err', text: t(planFailureKey(r.failure)) });
            });
          }} />
        );
      case 'apply_all':
        return template && stored.plan ? (
          <ApplyToAllDialog template={template} memberId={member.id} diffs={savedDiffs} everyone={everyone} plans={plans} templates={templates} online={online} onClose={close} />
        ) : null;
      case 'copy':
        return stored.plan ? <CopyPlanDialog sourceName={member.name} plan={stored.plan} candidates={candidates} plans={plans} online={online} onClose={close} /> : null;
    }
  })();

  const header = (
    <div class="page-head">
      <div class="stack-sm grow">
        <h1 class="h1 plain">{t('plan.title', { name: member.name })}</h1>
        {draft ? (
          <p class="sub">
            <span>{t('plan.summary', { days: days.length, exercises: exerciseCount })}</span>
            {stored.updatedAt ? (
              <>
                {' · '}
                <span>{updatedByName ? t('plan.changedBy', { name: updatedByName, date: formatDate(lang, stored.updatedAt) }) : t('plan.changedAt', { date: formatDate(lang, stored.updatedAt) })}</span>
              </>
            ) : null}
          </p>
        ) : null}
      </div>
      {editable && stored.plan ? (
        <button type="button" class="btn" disabled={dirty || !online || tplBusy} aria-describedby={dirty ? 'copy-first' : undefined} onClick={() => { setModal({ kind: 'save_template' }); }}>
          {t('tpl.saveAs')}
        </button>
      ) : null}
      {editable ? (
        <button type="button" class="btn" disabled={dirty || !online || tplBusy} aria-describedby={dirty ? 'copy-first' : undefined} onClick={() => { setModal({ kind: 'replace' }); }}>
          {t('tpl.replace')}
        </button>
      ) : null}
      {editable && stored.plan ? (
        <button type="button" class="btn" disabled={dirty || !online} aria-describedby={dirty ? 'copy-first' : undefined} onClick={() => { setModal({ kind: 'copy' }); }}>
          {t('plan.copy')}
        </button>
      ) : null}
    </div>
  );

  if (conflict) {
    const theirs = diffPlans(conflict.base, conflict.latest.plan);
    const mine = diffPlans(conflict.base, conflict.mine);
    return (
      <section class="stack">
        {back}
        {header}
        <section class="panel" aria-labelledby="conflict-title" role="alert">
          <h2 class="h2" id="conflict-title">{t('conflict.title')}</h2>
          <p class="sub">{t('conflict.body')}</p>
          <div class="grid2">
            <div class="stack-sm">
              <h3 class="h3">{t('conflict.theirs')}</h3>
              <ChangeList lines={theirs.map((c) => changeLine({ t, lang }, c))} />
            </div>
            <div class="stack-sm">
              <h3 class="h3">{t('conflict.mine')}</h3>
              <ChangeList lines={mine.map((c) => changeLine({ t, lang }, c))} />
            </div>
          </div>
          <button type="button" class="btn pri self-start" onClick={() => { onStored(conflict.latest, false); }}>{t('conflict.load')}</button>
        </section>
      </section>
    );
  }

  if (stored.unreadable) {
    return (
      <section class="stack">
        {back}
        {header}
        <div class="panel">
          <StateBlock icon="alert" title={t('plan.unreadableTitle')}>
            <p class="sub">{t('plan.unreadableBody')}</p>
          </StateBlock>
        </div>
      </section>
    );
  }

  if (!draft) {
    return (
      <section class="stack">
        {back}
        {header}
        <div class="panel">
          <StateBlock icon="dumbbell" title={t('plan.emptyTitle')}>
            <p class="sub">{t('plan.emptyBody', { name: member.name })}</p>
            {editable ? (
              <button type="button" class="btn pri" onClick={() => {
                const id = newId('day');
                setDraft(edit.firstPlan({ ar: translate('ar', 'plan.firstDayAr'), en: translate('en', 'plan.firstDayEn') }, id));
                setDayId(id);
              }}>
                {t('plan.start')}
              </button>
            ) : null}
          </StateBlock>
        </div>
        {member.status === 'ended' ? <p class="cap">{t('plan.endedNote')}</p> : null}
        <div class="live-slot" role={tplNote?.tone === 'err' ? 'alert' : 'status'}>
          {tplNote ? <div class={`banner ${tplNote.tone === 'ok' ? 'ok' : 'err'}`}><Icon name={tplNote.tone === 'ok' ? 'check' : 'alert'} /><span class="plain-text">{tplNote.text}</span></div> : null}
        </div>
        {modalView}
      </section>
    );
  }

  return (
    <section class="stack">
      {back}
      {header}
      {member.status === 'ended' ? <div class="banner info"><Icon name="info" />{t('plan.endedNote')}</div> : null}
      {dirty ? <p class="cap" id="copy-first">{t('plan.copySaveFirst')}</p> : null}
      <TemplateBanner
        template={template}
        memberName={member.name}
        changes={changeCount}
        newer={template !== null && link.templateVersion !== null && template.version > link.templateVersion}
        gone={templateGone}
        canApply={editable && !dirty && savedDiffs.length > 0}
        onApply={() => { setModal({ kind: 'apply_all' }); }}
      />
      <div class="live-slot" role={tplNote?.tone === 'err' ? 'alert' : 'status'}>
        {tplNote ? <div class={`banner ${tplNote.tone === 'ok' ? 'ok' : 'err'}`}><Icon name={tplNote.tone === 'ok' ? 'check' : 'alert'} /><span class="plain-text">{tplNote.text}</span></div> : null}
        {!tplNote && flash ? <div class="banner ok"><Icon name="check" /><span class="plain-text">{flash}</span></div> : null}
      </div>

      <div class="toolbar">
        <div class="seg day-tabs" role="group" aria-label={t('plan.days')}>
          {days.map((d) => (
            <button key={d.id} type="button" class={d.id === day?.id ? 'on' : ''} aria-pressed={d.id === day?.id} onClick={() => { setDayId(d.id); }}>
              <span class="plain">{nameIn(lang, d.name)}</span> <span class="num">{d.exercises.length}</span>
            </button>
          ))}
        </div>
        {editable ? (
          <button type="button" class="btn sm" disabled={days.length >= LIMITS.maxDays} onClick={() => { setModal({ kind: 'add_day' }); }}>
            <Icon name="plus" />
            {t('plan.addDay')}
          </button>
        ) : null}
      </div>
      {editable && days.length >= LIMITS.maxDays ? <p class="cap">{t('plan.limitDays')}</p> : null}

      {day ? (
        <PlanDayView
          day={day}
          index={days.indexOf(day)}
          dayCount={days.length}
          editable={editable && !saving}
          covers={covers}
          cloudName={cloudName}
          onDay={(action) => {
            if (action === 'rename') setModal({ kind: 'rename_day', dayId: day.id });
            else if (action === 'delete') {
              if (days.length <= 1) setNote({ tone: 'err', text: t('plan.lastDay') });
              else setModal({ kind: 'delete_day', dayId: day.id });
            } else apply(edit.moveDay(draft, day.id, action === 'earlier' ? -1 : 1));
          }}
          onAdd={() => { setModal({ kind: 'pick', dayId: day.id }); }}
          onTargets={(exId, targets) => apply(edit.setTargets(draft, day.id, exId, targets))}
          onSuperset={(exId, on) => apply(edit.setSuperset(draft, day.id, exId, on))}
          differs={dayDiffs}
          onReset={(exId) => {
            const d = dayDiffs.get(exId);
            if (d) apply(resetToTemplate(draft, d));
          }}
          onExercise={(exId, action) => {
            if (action === 'rename') setModal({ kind: 'rename_ex', dayId: day.id, exId });
            else if (action === 'delete') setModal({ kind: 'delete_ex', dayId: day.id, exId });
            else apply(edit.moveExercise(draft, day.id, exId, action === 'earlier' ? -1 : 1));
          }}
        />
      ) : null}

      {editable ? (
        <div class="save-bar">
          <div class="acts-row">
            <button type="button" class="btn pri" disabled={!dirty || saving || !online} aria-describedby={!online ? 'plan-offline' : undefined} onClick={() => void save()}>
              {saving ? t('plan.saving') : t('plan.save')}
            </button>
            {dirty ? <button type="button" class="btn ghost" disabled={saving} onClick={() => { setDraft(stored.plan); setDayId(stored.plan?.days[0]?.id ?? null); setNote(null); }}>{t('plan.undo')}</button> : null}
            {dirty ? <span class="live" role="status">{t('plan.unsaved')}</span> : null}
          </div>
          {!online ? <p class="cap" id="plan-offline">{t('plan.offlineHint')}</p> : null}
        </div>
      ) : null}
      <div class="live-slot" role={note?.tone === 'err' ? 'alert' : 'status'}>
        {note ? (
          <div class={`banner ${note.tone === 'ok' ? 'ok' : 'err'}`}>
            <Icon name={note.tone === 'ok' ? 'check' : 'alert'} />
            <span>{note.text}</span>
          </div>
        ) : null}
        {!note && !dirty && justSaved ? (
          <div class="banner ok">
            <Icon name="check" />
            <span class="plain-text">{t('plan.saved', { name: member.name })}</span>
          </div>
        ) : null}
      </div>
      {modalView}
    </section>
  );
}

function ChangeList({ lines }: { readonly lines: readonly string[] }) {
  const { t } = useI18n();
  if (lines.length === 0) return <p class="cap">{t('conflict.none')}</p>;
  return (
    <ul class="change-list">
      {lines.map((line, i) => (
        <li key={i} class="plain-text">{line}</li>
      ))}
    </ul>
  );
}

