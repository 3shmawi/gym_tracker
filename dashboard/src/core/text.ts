// Text that comes from the database or the user is untrusted. It is always
// rendered as text (Preact escapes it), and names are cleaned of characters
// that change how the text around them is shown.

// Bidi embeddings/overrides/isolates and marks (U+061C, U+200E, U+200F,
// U+202A–U+202E, U+2066–U+2069), zero-width and joiner characters
// (U+200B–U+200D, U+2060, U+FEFF), and C0/C1 control characters.
const HIDDEN_CLASS = '[\\u0000-\\u001F\\u007F-\\u009F\\u061C\\u200B-\\u200F\\u202A-\\u202E\\u2060\\u2066-\\u2069\\uFEFF]';
const HIDDEN = new RegExp(HIDDEN_CLASS, 'gu');
const HAS_HIDDEN = new RegExp(HIDDEN_CLASS, 'u');

/** A display name, safe to show: hidden and control characters removed, spaces collapsed. */
export function cleanName(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  return raw.normalize('NFC').replace(HIDDEN, '').replace(/\s+/g, ' ').trim();
}

/** True when cleaning removed something other than spacing. */
export function hadHiddenCharacters(raw: string): boolean {
  return HAS_HIDDEN.test(raw.normalize('NFC'));
}

/** Initials for an avatar tile: first letter of the first two words. */
export function initials(name: string): string {
  const words = cleanName(name).split(' ').filter(Boolean);
  const letters = words.slice(0, 2).map((w) => Array.from(w)[0] ?? '');
  return letters.join('').toLocaleUpperCase();
}

/** Masks an email for display: m•••@example.com. */
export function maskEmail(email: string): string {
  const at = email.lastIndexOf('@');
  if (at < 1) return '\u2022\u2022\u2022';
  return `${Array.from(email)[0]}\u2022\u2022\u2022${email.slice(at)}`;
}

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,253}\.[^\s@]{2,63}$/;

/** A plain email check for the sign-in form; the server decides the rest. */
export function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const email = raw.trim().toLowerCase();
  if (email.length > 254 || HAS_HIDDEN.test(email)) return null;
  return EMAIL.test(email) ? email : null;
}

/** Digits only (Arabic-Indic and Persian digits converted), as typed or pasted. */
export function normalizeCode(raw: unknown, length: number): string | null {
  if (typeof raw !== 'string') return null;
  const digits = raw
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[\s-]/g, '');
  return new RegExp(`^[0-9]{${length}}$`).test(digits) ? digits : null;
}
