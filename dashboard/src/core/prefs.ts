// The only browser storage the dashboard writes itself: language and theme.
// Neither is personal data. The session is stored by supabase-js only.
// Storage may be blocked (private mode): every access is guarded.

export type Lang = 'en' | 'ar';
export type Theme = 'light' | 'dark';

export interface Prefs {
  readonly lang: Lang;
  readonly theme: Theme;
}

const KEY = 'azm.dashboard.prefs.v1';

function systemTheme(): Theme {
  try {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  } catch {
    return 'light';
  }
}

function systemLang(): Lang {
  try {
    return navigator.language.toLowerCase().startsWith('ar') ? 'ar' : 'en';
  } catch {
    return 'en';
  }
}

export function loadPrefs(): Prefs {
  const fallback: Prefs = { lang: systemLang(), theme: systemTheme() };
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return fallback;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return fallback;
    const { lang, theme } = parsed as Record<string, unknown>;
    return {
      lang: lang === 'ar' || lang === 'en' ? lang : fallback.lang,
      theme: theme === 'dark' || theme === 'light' ? theme : fallback.theme,
    };
  } catch {
    return fallback;
  }
}

export function savePrefs(prefs: Prefs): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify({ lang: prefs.lang, theme: prefs.theme }));
  } catch {
    // Storage blocked: the choice lasts for this tab only.
  }
}
