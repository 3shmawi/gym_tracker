import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { linkHandler, pathOf, type Route } from '../app/router';
import type { Prefs } from '../core/prefs';
import { initials, maskEmail } from '../core/text';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n } from '../i18n';
import { Icon } from './icons';
import { CONTACT_EMAIL } from './rich';

export interface ShellProps {
  readonly prefs: Prefs;
  readonly onPrefs: (prefs: Prefs) => void;
  readonly online: boolean;
  readonly email: string | null;
  readonly onSignOut: (() => void) | null;
  readonly gym?: ManagedGym;
  readonly gyms?: readonly ManagedGym[];
  readonly nav?: 'members' | 'exercises' | 'templates' | 'settings';
  readonly children: ComponentChildren;
}

export function Footer() {
  const { t } = useI18n();
  return (
    <footer class="ftr">
      <span dir="ltr">{t('footer.copyright')}</span>
      <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
      <a href="https://azmm.pages.dev/privacy">{t('footer.privacy')}</a>
      <a href="https://azmm.pages.dev/terms">{t('footer.terms')}</a>
    </footer>
  );
}

export function Shell({ prefs, onPrefs, online, email, onSignOut, gym, gyms, nav, children }: ShellProps) {
  const { t, lang } = useI18n();
  const [open, setOpen] = useState(false);
  const menuButton = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      setOpen(false);
      menuButton.current?.focus();
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const otherLang = lang === 'ar' ? 'en' : 'ar';
  const toggleLang = () => {
    onPrefs({ ...prefs, lang: otherLang });
  };
  const toggleTheme = () => {
    onPrefs({ ...prefs, theme: prefs.theme === 'dark' ? 'light' : 'dark' });
  };
  const themeLabel = prefs.theme === 'dark' ? t('app.themeLight') : t('app.themeDark');
  const themeIcon = prefs.theme === 'dark' ? 'sun' : 'moon';
  const canSwitchGym = gym !== undefined && gyms !== undefined && gyms.length > 1;
  const masked = email ? maskEmail(email) : null;
  const closeMenu = () => {
    setOpen(false);
  };

  const gymSwitch = (inPanel: boolean) =>
    gym && canSwitchGym ? (
      <a
        class={`btn sm gym-switch${inPanel ? ' in-panel' : ''}`}
        href={pathOf({ name: 'gyms' })}
        aria-label={t('gyms.change', { gym: gym.name })}
        onClick={(event) => {
          closeMenu();
          linkHandler({ name: 'gyms' })(event);
        }}
      >
        <span class={`lg ini ${inPanel ? '' : 'small'}`} data-initials={initials(gym.name)} aria-hidden="true" />
        {inPanel ? (
          <span class="meta">
            <b class="gym-name">{gym.name}</b>
            <span class="cap">{gym.role === 'owner' ? t('gyms.roleOwner') : t('gyms.roleCaptain')}</span>
          </span>
        ) : (
          <span class="gym-name">{gym.name}</span>
        )}
        <Icon name="chevronDown" />
      </a>
    ) : null;

  const navLink = (key: 'members' | 'exercises' | 'templates' | 'settings') => {
    const route: Route = gym ? { name: key, gymId: gym.id } : { name: 'home' };
    const on = nav === key;
    return (
      <a
        class={on ? 'on' : undefined}
        href={pathOf(route)}
        aria-current={on ? 'page' : undefined}
        onClick={(event) => {
          closeMenu();
          if (gym) linkHandler(route)(event);
        }}
      >
        <Icon name={key === 'members' ? 'members' : key === 'exercises' ? 'dumbbell' : key === 'templates' ? 'copy' : 'gear'} />
        {key === 'members' ? t('nav.members') : key === 'exercises' ? t('nav.exercises') : key === 'templates' ? t('nav.templates') : t('nav.settings')}
      </a>
    );
  };
  const navLinks = (
    <>
      {navLink('members')}
      {navLink('exercises')}
      {navLink('templates')}
      {navLink('settings')}
    </>
  );

  return (
    <div class={`app${open ? ' menu-open' : ''}`}>
      <a class="skip" href="#main">{t('app.skipToContent')}</a>
      <header class="hdr">
        <button
          ref={menuButton}
          type="button"
          class="ib menu-btn"
          aria-label={open ? t('app.closeMenu') : t('app.openMenu')}
          aria-expanded={open}
          aria-controls="menu-panel"
          onClick={() => {
            setOpen(!open);
          }}
        >
          <Icon name={open ? 'close' : 'menu'} />
        </button>
        <a class="brand" href={pathOf({ name: 'home' })} onClick={linkHandler({ name: 'home' })}>
          <img src="/logo-96.png" alt="" width="36" height="36" />
          {t('app.name')}
        </a>
        <div class="hdr-tools">
          {gymSwitch(false)}
          <div class="sp" />
          <button type="button" class="btn ghost sm" lang={otherLang} aria-label={t('app.switchLanguageLabel')} onClick={toggleLang}>
            {t('app.switchLanguage')}
          </button>
          <button type="button" class="ib" aria-label={themeLabel} onClick={toggleTheme}>
            <Icon name={themeIcon} />
          </button>
          {masked ? <span class="cap num email">{masked}</span> : null}
          {onSignOut ? (
            <button type="button" class="btn sm" onClick={onSignOut}>{t('app.signOut')}</button>
          ) : null}
        </div>
      </header>

      {open ? (
        <nav id="menu-panel" class="nav menu-panel" aria-label={t('app.mainNav')}>
          {gymSwitch(true)}
          {nav ? navLinks : null}
          <div class="rule" />
          <button type="button" class="navitem" onClick={toggleLang} aria-label={t('app.switchLanguageLabel')}>
            <Icon name="language" />
            <span lang={otherLang}>{t('app.switchLanguage')}</span>
          </button>
          <button type="button" class="navitem" onClick={toggleTheme}>
            <Icon name={themeIcon} />
            {themeLabel}
          </button>
          {masked ? <div class="cap">{t('app.signedInAs', { email: masked })}</div> : null}
          {onSignOut ? (
            <button
              type="button"
              class="btn block"
              onClick={() => {
                closeMenu();
                onSignOut();
              }}
            >
              {t('app.signOut')}
            </button>
          ) : null}
        </nav>
      ) : null}

      <div class="offline-bar" role="status">
        {online ? null : (
          <div class="banner off">
            <Icon name="offline" />
            {t('state.offline')}
          </div>
        )}
      </div>

      <div class="body">
        {nav ? (
          <nav class="nav nav-side" aria-label={t('app.mainNav')}>
            {navLinks}
          </nav>
        ) : null}
        <main id="main" class="main" tabIndex={-1}>
          {children}
        </main>
      </div>
      <Footer />
    </div>
  );
}
