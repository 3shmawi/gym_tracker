import { createContext } from 'preact';
import { useContext } from 'preact/hooks';
import type { Lang } from '../core/prefs';
import { ar } from './ar';
import { en, type MessageKey } from './en';

export type { MessageKey };

const tables: Record<Lang, Record<MessageKey, string>> = { en, ar };

export type Params = Readonly<Record<string, string | number>>;

/** Looks up a message and fills {placeholders}. Values are plain text. */
export function translate(lang: Lang, key: MessageKey, params: Params = {}): string {
  const template = tables[lang][key];
  return template.replace(/\{([a-zA-Z]+)\}/g, (whole, name: string) => {
    const value = params[name];
    return value === undefined ? whole : formatValue(lang, value);
  });
}

function formatValue(lang: Lang, value: string | number): string {
  return typeof value === 'number' ? new Intl.NumberFormat(lang === 'ar' ? 'ar-EG' : 'en').format(value) : value;
}

export function dirOf(lang: Lang): 'ltr' | 'rtl' {
  return lang === 'ar' ? 'rtl' : 'ltr';
}

export interface I18n {
  readonly lang: Lang;
  readonly dir: 'ltr' | 'rtl';
  readonly t: (key: MessageKey, params?: Params) => string;
}

export function makeI18n(lang: Lang): I18n {
  return { lang, dir: dirOf(lang), t: (key, params) => translate(lang, key, params) };
}

export const I18nContext = createContext<I18n>(makeI18n('en'));

export function useI18n(): I18n {
  return useContext(I18nContext);
}

/** All keys, for tests. */
export const messageKeys = Object.keys(en) as MessageKey[];
export const messageTables = tables;
