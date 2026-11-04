import { describe, expect, it } from 'vitest';
import { cleanName, initials, maskEmail, normalizeCode, normalizeEmail } from '../src/core/text';

const ch = (...codes: number[]) => String.fromCharCode(...codes);

describe('cleanName', () => {
  it('removes bidi overrides, zero-width and control characters', () => {
    const raw = `Po${ch(0x202e)}wer${ch(0x200b)} G${ch(0)}ym${ch(0x2066)}${ch(0xfeff)}`;
    expect(cleanName(raw)).toBe('Power Gym');
  });
  it('collapses spaces and trims', () => {
    expect(cleanName('  a \n\t b  ')).toBe('a b');
  });
  it('returns empty for non-strings', () => {
    expect(cleanName(null)).toBe('');
    expect(cleanName(42)).toBe('');
    expect(cleanName({})).toBe('');
  });
  it('keeps Arabic text', () => {
    expect(cleanName('جيم النخبة')).toBe('جيم النخبة');
  });
});

describe('initials and maskEmail', () => {
  it('takes two letters', () => {
    expect(initials('power gym extra')).toBe('PG');
    expect(initials('')).toBe('');
  });
  it('masks the local part', () => {
    expect(maskEmail('manager@example.com')).toBe('m•••@example.com');
    expect(maskEmail('nonsense')).toBe('•••');
  });
});

describe('normalizeEmail hostile input', () => {
  it('rejects empty, too long, partial and injection-like values', () => {
    expect(normalizeEmail('')).toBeNull();
    expect(normalizeEmail(`${'a'.repeat(300)}@example.com`)).toBeNull();
    expect(normalizeEmail('a@b')).toBeNull();
    expect(normalizeEmail('"><script>')).toBeNull();
    expect(normalizeEmail("' OR 1=1 --@x.com")).toBeNull();
    expect(normalizeEmail(`a${ch(0x202e)}@example.com`)).toBeNull();
  });
  it('rejects wrong types', () => {
    expect(normalizeEmail(42)).toBeNull();
    expect(normalizeEmail(null)).toBeNull();
    expect(normalizeEmail({ toString: () => 'a@example.com' })).toBeNull();
  });
  it('lowercases and trims; look-alikes pass the format check (the server decides)', () => {
    expect(normalizeEmail('  Manager@Example.COM ')).toBe('manager@example.com');
    const lookalike = `${ch(0x0430)}dmin@example.com`;
    expect(normalizeEmail(lookalike)).toBe(lookalike);
  });
});

describe('normalizeCode', () => {
  it('accepts spaces, dashes and Arabic-Indic digits', () => {
    expect(normalizeCode('123 456', 6)).toBe('123456');
    expect(normalizeCode('123-456', 6)).toBe('123456');
    expect(normalizeCode(ch(0x661, 0x662, 0x663, 0x664, 0x665, 0x666), 6)).toBe('123456');
  });
  it('rejects letters and wrong lengths', () => {
    expect(normalizeCode('12345a', 6)).toBeNull();
    expect(normalizeCode('12345', 6)).toBeNull();
    expect(normalizeCode('1234567', 6)).toBeNull();
    expect(normalizeCode(123456, 6)).toBeNull();
  });
});
