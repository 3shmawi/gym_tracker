import type { ComponentChildren } from 'preact';
import { useEffect } from 'preact/hooks';
import type { Failure } from '../core/failure';
import { loadPrefs } from '../core/prefs';
import { I18nContext, makeI18n, useI18n } from '../i18n';
import { Icon, type IconName } from './icons';
import { ContactLink, plainClick, withSlot } from './rich';
import { Footer } from './Shell';

function StateBlock({ icon, tone, title, children }: { readonly icon: IconName; readonly tone?: 'err'; readonly title: string; readonly children: ComponentChildren }) {
  return (
    <section class="state">
      <div class={`ic${tone ? ` ${tone}` : ''}`}>
        <Icon name={icon} />
      </div>
      <h2 class="h2">{title}</h2>
      {children}
    </section>
  );
}

export function LoadingView() {
  const { t } = useI18n();
  return (
    <div class="loading" aria-busy="true">
      <span class="sr-only">{t('state.loading')}</span>
      <div class="skel h28" />
      <div class="skel h16" />
      <div class="panel">
        {[0, 1, 2, 3].map((i) => (
          <div class="skel-row" key={i}>
            <div class="skel dot" />
            <div class="skel h14" />
          </div>
        ))}
      </div>
    </div>
  );
}

export function ErrorView({ failure, onRetry }: { readonly failure: Failure; readonly onRetry: () => void }) {
  const { t } = useI18n();
  const offline = failure.kind === 'offline';
  return (
    <StateBlock icon={offline ? 'offline' : 'alert'} tone="err" title={t('state.errorTitle')}>
      <p class="sub">{offline ? t('state.offline') : t('state.errorBody')}</p>
      <button type="button" class="btn pri" onClick={onRetry}>{t('state.retry')}</button>
      <span class="cap">{withSlot(t('state.stuck'), 'contact', <ContactLink />)}</span>
    </StateBlock>
  );
}

export function ForbiddenView({ onPickAnother, onSignOut }: { readonly onPickAnother: () => void; readonly onSignOut: () => void }) {
  const { t } = useI18n();
  return (
    <StateBlock icon="lock" title={t('state.forbiddenTitle')}>
      <p class="sub">{t('state.forbiddenBody')}</p>
      <div class="acts">
        <a class="btn pri" href="/gyms" onClick={plainClick(onPickAnother)}>{t('state.pickAnother')}</a>
        <button type="button" class="btn" onClick={onSignOut}>{t('app.signOut')}</button>
      </div>
    </StateBlock>
  );
}

export function SessionEndedView({ onSignIn }: { readonly onSignIn: () => void }) {
  const { t } = useI18n();
  return (
    <StateBlock icon="signOut" title={t('state.sessionTitle')}>
      <p class="sub">{t('state.sessionBody')}</p>
      <button type="button" class="btn pri" onClick={onSignIn}>{t('state.signIn')}</button>
    </StateBlock>
  );
}

export function NotFoundView({ onHome }: { readonly onHome: () => void }) {
  const { t } = useI18n();
  return (
    <StateBlock icon="search" title={t('state.notFoundTitle')}>
      <p class="sub">{t('state.notFoundBody')}</p>
      <a class="btn pri" href="/" onClick={plainClick(onHome)}>{t('state.home')}</a>
    </StateBlock>
  );
}

export function NoGymView({ onSignOut }: { readonly onSignOut: () => void }) {
  const { t } = useI18n();
  return (
    <StateBlock icon="lock" title={t('noGym.title')}>
      <p class="sub">{withSlot(t('noGym.body'), 'contact', <ContactLink />)}</p>
      <button type="button" class="btn" onClick={onSignOut}>{t('app.signOut')}</button>
    </StateBlock>
  );
}

/** Shown when the build has no valid settings. Renders outside App: no Supabase, own language. */
export function ConfigErrorPage() {
  const prefs = loadPrefs();
  const i18n = makeI18n(prefs.lang);
  useEffect(() => {
    const root = document.documentElement;
    root.lang = i18n.lang;
    root.dir = i18n.dir;
    root.dataset.theme = prefs.theme;
    document.title = i18n.t('app.name');
  }, [i18n, prefs.theme]);
  const { t } = i18n;
  return (
    <I18nContext.Provider value={i18n}>
      <div class="app">
        <main class="standalone">
          <div class="card roomy">
            <StateBlock icon="gear" tone="err" title={t('state.configTitle')}>
              <p class="sub">{withSlot(t('state.configBody'), 'contact', <ContactLink />)}</p>
            </StateBlock>
          </div>
        </main>
        <Footer />
      </div>
    </I18nContext.Provider>
  );
}
