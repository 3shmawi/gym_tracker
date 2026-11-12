import { useMemo, useState } from 'preact/hooks';
import { matchesQuery } from '../exercises/catalog';
import { LIBRARY } from '../exercises/library';
import type { LibraryExercise } from '../exercises/types';
import { useI18n, type MessageKey } from '../i18n';
import { cleanPlanName, nameFrom, nameProblem, LIMITS, type PlanName } from '../plans/model';
import { Dialog } from './Dialog';
import { Icon } from './icons';

// The plan editor's dialogs: a name in both languages, a confirmation, and
// "Add an exercise" (from the library, D2's list, or written by hand).

const problemKey = (raw: string): MessageKey | null => {
  const p = nameProblem(raw, false);
  return p === 'too_long' ? 'name.tooLong' : null;
};

export function NameDialog({ title, initial, onSave, onClose }: { readonly title: string; readonly initial: PlanName | null; readonly onSave: (name: PlanName) => void; readonly onClose: () => void }) {
  const { t } = useI18n();
  const [ar, setAr] = useState(initial?.ar ?? '');
  const [en, setEn] = useState(initial?.en ?? '');
  const [tried, setTried] = useState(false);
  const arProblem = problemKey(ar);
  const enProblem = problemKey(en);
  const empty = cleanPlanName(ar) === '' && cleanPlanName(en) === '';
  const save = () => {
    setTried(true);
    const name = nameFrom(ar, en);
    if (name) onSave(name);
  };
  return (
    <Dialog titleId="name-title" onClose={onClose}>
      <h2 class="h2" id="name-title">{title}</h2>
      <form
        class="stack-sm"
        onSubmit={(event) => {
          event.preventDefault();
          save();
        }}
      >
        <div class="field">
          <label for="name-ar">{t('name.ar')}</label>
          <input id="name-ar" class={`in${arProblem ? ' bad' : ''}`} lang="ar" dir="rtl" value={ar} maxLength={LIMITS.maxNameLength * 4} aria-invalid={arProblem !== null} aria-describedby="name-hint name-ar-err" onInput={(e) => { setAr(e.currentTarget.value); }} />
          <span id="name-ar-err" class="live-slot">{arProblem ? <span class="errt"><Icon name="alert" />{t(arProblem)}</span> : null}</span>
        </div>
        <div class="field">
          <label for="name-en">{t('name.en')}</label>
          <input id="name-en" class={`in${enProblem ? ' bad' : ''}`} lang="en" dir="ltr" value={en} maxLength={LIMITS.maxNameLength * 4} aria-invalid={enProblem !== null} aria-describedby="name-hint name-en-err" onInput={(e) => { setEn(e.currentTarget.value); }} />
          <span id="name-en-err" class="live-slot">{enProblem ? <span class="errt"><Icon name="alert" />{t(enProblem)}</span> : null}</span>
        </div>
        <span class="hint" id="name-hint">{t('name.hint')}</span>
        <span class="live-slot" role="alert">{tried && empty ? <span class="errt"><Icon name="alert" />{t('name.empty')}</span> : null}</span>
        <div class="acts">
          <button type="button" class="btn" onClick={onClose}>{t('name.cancel')}</button>
          <button type="submit" class="btn pri" disabled={arProblem !== null || enProblem !== null}>{t('name.save')}</button>
        </div>
      </form>
    </Dialog>
  );
}

export function ConfirmDialog({ title, body, action, onConfirm, onClose }: { readonly title: string; readonly body: string; readonly action: string; readonly onConfirm: () => void; readonly onClose: () => void }) {
  const { t } = useI18n();
  return (
    <Dialog titleId="confirm-title" onClose={onClose}>
      <h2 class="h2 plain" id="confirm-title">{title}</h2>
      <p class="sub">{body}</p>
      <div class="acts">
        <button type="button" class="btn" onClick={onClose}>{t('name.cancel')}</button>
        <button type="button" class="btn danger" onClick={onConfirm}>{action}</button>
      </div>
    </Dialog>
  );
}

const SEARCH_MAX = 60;

export function ExercisePicker({ dayName, inDay, onPick, onOwn, onClose }: { readonly dayName: string; readonly inDay: ReadonlySet<string>; readonly onPick: (e: LibraryExercise) => void; readonly onOwn: (name: PlanName) => void; readonly onClose: () => void }) {
  const { t, lang } = useI18n();
  const [tab, setTab] = useState<'library' | 'own'>('library');
  const [query, setQuery] = useState('');
  const rows = useMemo(() => LIBRARY.filter((e) => matchesQuery(e, query)), [query]);
  const [ar, setAr] = useState('');
  const [en, setEn] = useState('');
  const own = nameFrom(ar, en);
  const tooLong = problemKey(ar) ?? problemKey(en);
  return (
    <Dialog titleId="pick-title" onClose={onClose} initialFocus="#pick-search">
      <h2 class="h2 plain" id="pick-title">{t('pick.title', { day: dayName })}</h2>
      <div class="seg" role="group" aria-label={t('plan.addExercise')}>
        <button type="button" class={tab === 'library' ? 'on' : ''} aria-pressed={tab === 'library'} onClick={() => { setTab('library'); }}>{t('pick.library')}</button>
        <button type="button" class={tab === 'own' ? 'on' : ''} aria-pressed={tab === 'own'} onClick={() => { setTab('own'); }}>{t('pick.own')}</button>
      </div>
      {tab === 'library' ? (
        <>
          <div class="field">
            <label for="pick-search">{t('pick.search')}</label>
            <input id="pick-search" class="in" type="search" maxLength={SEARCH_MAX} value={query} onInput={(e) => { setQuery(e.currentTarget.value); }} />
          </div>
          {rows.length === 0 ? (
            <p class="cap" role="status">{t('pick.none', { query: cleanPlanName(query) })}</p>
          ) : (
            <ul class="pick-list">
              {rows.map((e) => {
                const here = inDay.has(e.id);
                const primary = lang === 'ar' ? e.ar : e.en;
                const secondary = lang === 'ar' ? e.en : e.ar;
                return (
                  <li key={e.id} class="pick-row">
                    <span class="meta">
                      <b>{primary}</b>
                      <span class="cap" lang={lang === 'ar' ? 'en' : 'ar'}>{secondary}</span>
                    </span>
                    {here ? (
                      <span class="badge">{t('pick.inDay')}</span>
                    ) : (
                      <button type="button" class="btn sm" aria-label={t('pick.addName', { name: primary })} onClick={() => { onPick(e); }}>
                        <Icon name="plus" />
                        {t('pick.add')}
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </>
      ) : (
        <form
          class="stack-sm"
          onSubmit={(event) => {
            event.preventDefault();
            if (own) onOwn(own);
          }}
        >
          <div class="field">
            <label for="own-ar">{t('name.ar')}</label>
            <input id="own-ar" class="in" lang="ar" dir="rtl" value={ar} maxLength={LIMITS.maxNameLength * 4} onInput={(e) => { setAr(e.currentTarget.value); }} aria-describedby="own-hint" />
          </div>
          <div class="field">
            <label for="own-en">{t('name.en')}</label>
            <input id="own-en" class="in" lang="en" dir="ltr" value={en} maxLength={LIMITS.maxNameLength * 4} onInput={(e) => { setEn(e.currentTarget.value); }} aria-describedby="own-hint" />
          </div>
          <span class="hint" id="own-hint">{t('name.hint')}</span>
          <span class="live-slot" role="alert">{tooLong ? <span class="errt"><Icon name="alert" />{t(tooLong)}</span> : null}</span>
          <button type="submit" class="btn pri self-start" disabled={!own}>{t('pick.addOwn')}</button>
        </form>
      )}
      <div class="acts">
        <button type="button" class="btn" onClick={onClose}>{t('pick.close')}</button>
      </div>
    </Dialog>
  );
}
