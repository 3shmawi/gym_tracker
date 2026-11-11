import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { MAX_TEMPLATES, type Template, type TemplatesRepository } from '../plans/templates';
import { nameIn } from '../plans/text';
import { Icon } from '../ui/icons';
import { formatDate } from '../ui/memberText';
import { ConfirmDialog, NameDialog } from '../ui/PlanDialogs';
import { ErrorView, LoadingView, StateBlock } from '../ui/states';

// The gym's plan templates (D4): list, rename, delete. Making one is on a
// member's plan ("Save as template"); applying one is there too.

type Loaded = { readonly state: 'loading' } | { readonly state: 'failed'; readonly failure: Failure } | { readonly state: 'ready'; readonly templates: readonly Template[] };
type Modal = { readonly kind: 'rename' | 'delete'; readonly template: Template } | null;

export function useTemplates(repo: TemplatesRepository, gymId: string) {
  const [data, setData] = useState<Loaded>({ state: 'loading' });
  const token = useRef(0);
  const reload = useCallback(async () => {
    const mine = ++token.current;
    setData({ state: 'loading' });
    const r = await repo.list(gymId);
    if (mine !== token.current) return;
    setData(r.ok ? { state: 'ready', templates: r.value } : { state: 'failed', failure: r.failure });
  }, [repo, gymId]);
  useEffect(() => {
    void reload();
    return () => {
      token.current++;
    };
  }, [reload]);
  return { data, reload };
}

export function TemplatesPage({ gym, templates, online }: { readonly gym: ManagedGym; readonly templates: TemplatesRepository; readonly online: boolean }) {
  const { t, lang } = useI18n();
  const { data, reload } = useTemplates(templates, gym.id);
  const [modal, setModal] = useState<Modal>(null);
  const [note, setNote] = useState<{ tone: 'ok' | 'err'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const head = (
    <div class="stack-sm">
      <h1 class="h1">{t('tpl.title')}</h1>
      <p class="sub">{t('tpl.subtitle')}</p>
    </div>
  );
  if (data.state === 'loading') return <section class="stack">{head}<LoadingView /></section>;
  if (data.state === 'failed') return <section class="stack">{head}<ErrorView failure={data.failure} onRetry={() => void reload()} /></section>;

  const run = async (action: () => Promise<{ ok: boolean; failure?: Failure }>, okText: string) => {
    setBusy(true);
    setNote(null);
    const r = await action();
    setBusy(false);
    setModal(null);
    if (r.ok) {
      setNote({ tone: 'ok', text: okText });
      await reload();
    } else setNote({ tone: 'err', text: r.failure?.kind === 'forbidden' ? t('tpl.errForbidden') : r.failure?.kind === 'offline' ? t('plan.errOffline') : t('tpl.errServer') });
  };

  const list = data.templates;
  return (
    <section class="stack">
      {head}
      <p class="cap">{t('tpl.count', { count: list.length, max: MAX_TEMPLATES })}</p>
      <div class="live-slot" role={note?.tone === 'err' ? 'alert' : 'status'}>
        {note ? <div class={`banner ${note.tone === 'ok' ? 'ok' : 'err'}`}><Icon name={note.tone === 'ok' ? 'check' : 'alert'} /><span>{note.text}</span></div> : null}
      </div>
      {list.length === 0 ? (
        <div class="panel">
          <StateBlock icon="copy" title={t('tpl.emptyTitle')}>
            <p class="sub">{t('tpl.emptyBody')}</p>
          </StateBlock>
        </div>
      ) : (
        <ul class="ex-list">
          {list.map((tpl) => {
            const name = nameIn(lang, tpl.name);
            const other = lang === 'ar' ? tpl.name.en : tpl.name.ar;
            const exercises = tpl.plan?.days.reduce((n, d) => n + d.exercises.length, 0) ?? 0;
            return (
              <li key={tpl.id} class="panel tpl-row">
                <span class="meta grow">
                  <b class="plain">{name}</b>
                  <span class="cap plain" lang={lang === 'ar' ? 'en' : 'ar'}>{other}</span>
                  <span class="cap">
                    {tpl.plan ? t('tpl.summary', { days: tpl.plan.days.length, exercises }) : t('tpl.unreadable')}
                    {tpl.updatedAt ? ` · ${t('tpl.changedAt', { date: formatDate(lang, tpl.updatedAt) })}` : ''}
                  </span>
                </span>
                <div class="acts-row">
                  <button type="button" class="btn sm" aria-label={t('tpl.renameName', { name })} disabled={busy || !online} onClick={() => { setModal({ kind: 'rename', template: tpl }); }}>
                    <Icon name="pencil" />
                    {t('tpl.rename')}
                  </button>
                  <button type="button" class="btn sm danger" aria-label={t('tpl.deleteName', { name })} disabled={busy || !online} onClick={() => { setModal({ kind: 'delete', template: tpl }); }}>
                    {t('tpl.delete')}
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
      {!online ? <p class="cap">{t('plan.offlineHint')}</p> : null}
      {modal?.kind === 'rename' ? (
        <NameDialog title={t('tpl.renameTitle')} initial={modal.template.name} onClose={() => { setModal(null); }} onSave={(name) => void run(() => templates.rename(modal.template.id, name), t('tpl.renamed'))} />
      ) : null}
      {modal?.kind === 'delete' ? (
        <ConfirmDialog title={t('tpl.deleteTitle', { name: nameIn(lang, modal.template.name) })} body={t('tpl.deleteBody')} action={t('tpl.delete')} onClose={() => { setModal(null); }} onConfirm={() => void run(() => templates.remove(modal.template.id), t('tpl.deleted'))} />
      ) : null}
    </section>
  );
}
