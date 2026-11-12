import type { Lang } from '../core/prefs';

// The gym week, exactly like the app (GetLevel._week) and the server
// (private.gym_week, migration 0012): Saturday to Friday, by the calendar date
// in Africa/Cairo, numbered from Saturday 1 January 2000.

const DAY_MS = 86_400_000;
const EPOCH = Date.UTC(2000, 0, 1); // a Saturday
const CAIRO = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' });
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** The calendar date in Cairo as days since 1 Jan 2000. */
function cairoDay(at: Date): number {
  const [y, m, d] = CAIRO.format(at).split('-').map(Number);
  return Math.round((Date.UTC(y ?? 2000, (m ?? 1) - 1, d ?? 1) - EPOCH) / DAY_MS);
}

/** Week number of a moment (private.gym_week). */
export function gymWeek(at: Date): number {
  return Math.floor(cairoDay(at) / 7);
}

/** Week number of a week_start date ('YYYY-MM-DD', a Saturday), or null when it isn't one. */
export function weekOfStart(weekStart: string): number | null {
  const m = DATE.exec(weekStart);
  if (!m) return null;
  const days = Math.round((Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) - EPOCH) / DAY_MS);
  return Number.isFinite(days) && days % 7 === 0 ? days / 7 : null;
}

/** The Saturday that starts a week, as 'YYYY-MM-DD' (private.gym_week_start). */
export function startOfWeek(week: number): string {
  return new Date(EPOCH + week * 7 * DAY_MS).toISOString().slice(0, 10);
}

/** Locale with Western digits, like the app. */
export const latn = (lang: Lang) => (lang === 'ar' ? 'ar-EG-u-nu-latn' : 'en-GB');

/** "Sat 1 Nov – Fri 7 Nov" (dates of the week; Western digits). */
export function weekLabel(lang: Lang, week: number): string {
  const f = new Intl.DateTimeFormat(latn(lang), { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });
  const start = new Date(EPOCH + week * 7 * DAY_MS);
  const end = new Date(start.getTime() + 6 * DAY_MS);
  return `${f.format(start)} – ${f.format(end)}`;
}

/** "1 Nov" (the week's Saturday), for chart ticks. */
export function weekTick(lang: Lang, week: number): string {
  return new Intl.DateTimeFormat(latn(lang), { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(EPOCH + week * 7 * DAY_MS));
}

/** A moment as a date in Cairo ("1 Nov 2026"), Western digits. */
export function dateLabel(lang: Lang, at: Date): string {
  return new Intl.DateTimeFormat(latn(lang), { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Africa/Cairo' }).format(at);
}

/** A number with Western digits (up to 1 decimal). */
export function num(lang: Lang, value: number, digits = 0): string {
  return new Intl.NumberFormat(latn(lang), { maximumFractionDigits: digits }).format(value);
}
