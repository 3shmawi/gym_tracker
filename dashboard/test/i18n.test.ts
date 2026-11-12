import { describe, expect, it } from 'vitest';
import { dirOf, makeI18n, numberLocale, messageKeys, messageTables, translate } from '../src/i18n';

const placeholders = (text: string) => [...text.matchAll(/\{([a-zA-Z]+)\}/g)].map((m) => m[1]).sort();

describe('i18n tables', () => {
  it('has the same keys in English and Arabic', () => {
    expect(Object.keys(messageTables.ar).sort()).toEqual(Object.keys(messageTables.en).sort());
  });

  it('has the same {placeholders} for every key', () => {
    for (const key of messageKeys) {
      expect(placeholders(messageTables.ar[key]), key).toEqual(placeholders(messageTables.en[key]));
    }
  });

  it('has no empty text', () => {
    for (const key of messageKeys) {
      expect(messageTables.en[key].trim().length, key).toBeGreaterThan(0);
      expect(messageTables.ar[key].trim().length, key).toBeGreaterThan(0);
    }
  });

  it('fills placeholders and leaves unknown ones', () => {
    expect(translate('en', 'signIn.emailHint', { length: 6 })).toContain('6-digit');
    expect(translate('en', 'noGym.body')).toContain('{contact}');
  });

  it('Arabic uses Western digits (123), in the texts and in filled numbers', () => {
    const easternDigits = /[\u0660-\u0669\u06F0-\u06F9]/;
    for (const key of messageKeys) expect(messageTables.ar[key], key).not.toMatch(easternDigits);
    expect(translate('ar', 'set.readOnly')).not.toMatch(easternDigits);
    expect(new Intl.NumberFormat(numberLocale('ar')).format(1234.5)).toBe('1,234.5');
    expect(numberLocale('en')).toBe('en');
  });

  it('sets the direction from the language', () => {
    expect(dirOf('ar')).toBe('rtl');
    expect(makeI18n('en').dir).toBe('ltr');
  });
});
