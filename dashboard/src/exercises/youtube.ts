import type { VideoRef } from './types';

// Turns a link the captain pastes into a video id (+ start / end seconds),
// with the same rules as the app (lib/core/media/youtube_link.dart) and the
// same shared test vectors (docs/features/youtube_link_vectors.json):
// - https only; no user info, no port; at most 2048 characters; spaces around
//   are trimmed; no `%`, backslash, space, control or non-ASCII character.
// - Hosts (case-insensitive): youtube.com, www.youtube.com, m.youtube.com,
//   youtu.be, youtube-nocookie.com, www.youtube-nocookie.com. Everything else
//   is refused (music.youtube.com, look-alikes, other sites).
// - Paths: /watch?v=ID, youtu.be/ID, /shorts/ID, /embed/ID (the only path on
//   the nocookie hosts). /live/ID, channels and playlists are refused.
// - The id: exactly 11 of [A-Za-z0-9_-]; given twice → refused.
// - Start: t= (90, 90s, 1m30s, 1h2m3s) or start= (seconds), not both; end:
//   end=. 0 ≤ start < end ≤ 12 h; t=0 is no start. Other parameters ignored.
//
// The link is split by hand, not with `new URL()`: the browser's parser
// resolves `..`, converts look-alike hosts to punycode and decodes parts,
// so what it returns is not always what was pasted. Dot segments (`.`, `..`)
// are refused outright.

export const MAX_LINK_LENGTH = 2048;
export const MAX_SECONDS = 43_200;
export const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

const WATCH_HOSTS = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com']);
const SHORT_HOST = 'youtu.be';
const NOCOOKIE_HOSTS = new Set(['youtube-nocookie.com', 'www.youtube-nocookie.com']);

const PRINTABLE_ASCII = /^[\x21-\x7E]+$/;
// scheme://authority path ?query #fragment
const SHAPE = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#.*)?$/;
const TIME = /^(?:(\d{1,2})h)?(?:(\d{1,4})m)?(?:(\d{1,5})s?)?$/;
const SECONDS = /^\d{1,5}$/;

/** A valid id and times (0 ≤ start < end ≤ 12 h); the database checks the same. */
export function isValidVideo(id: string, start: number | null, end: number | null): boolean {
  return (
    VIDEO_ID.test(id) &&
    (start === null || (start >= 0 && start <= MAX_SECONDS)) &&
    (end === null || (end > 0 && end <= MAX_SECONDS)) &&
    (start === null || end === null || end > start)
  );
}

export function parseYouTubeLink(input: unknown): VideoRef | null {
  if (typeof input !== 'string') return null;
  const text = input.trim();
  if (text === '' || text.length > MAX_LINK_LENGTH) return null;
  if (!PRINTABLE_ASCII.test(text) || text.includes('\\') || text.includes('%')) return null;

  const shape = SHAPE.exec(text);
  if (!shape) return null;
  const [, scheme = '', authority = '', path = '', query] = shape;
  if (scheme.toLowerCase() !== 'https') return null;
  // No user info, no port (a port also catches "host:" with nothing after).
  if (authority === '' || authority.includes('@') || authority.includes(':')) return null;
  const host = authority.toLowerCase();

  const segments = path.split('/').filter((s) => s !== '');
  if (segments.some((s) => s === '.' || s === '..')) return null;
  const params = parseQuery(query ?? '');

  let id: string | null = null;
  if (WATCH_HOSTS.has(host)) {
    if (segments.length === 1 && segments[0] === 'watch') id = single(params, 'v');
    else if (segments.length === 2 && (segments[0] === 'shorts' || segments[0] === 'embed')) id = segments[1] ?? null;
  } else if (host === SHORT_HOST) {
    if (segments.length === 1) id = segments[0] ?? null;
  } else if (NOCOOKIE_HOSTS.has(host)) {
    if (segments.length === 2 && segments[0] === 'embed') id = segments[1] ?? null;
  }
  if (id === null || !VIDEO_ID.test(id)) return null;

  const t = single(params, 't');
  const startParam = single(params, 'start');
  const endParam = single(params, 'end');
  if (t !== null && startParam !== null) return null;
  const start = t !== null ? parseTime(t) : startParam !== null ? parseSeconds(startParam) : null;
  const end = endParam === null ? null : parseSeconds(endParam);
  if ((t !== null || startParam !== null) && start === null) return null;
  if (endParam !== null && end === null) return null;
  const realStart = start === 0 ? null : start;
  if (!isValidVideo(id, realStart, end)) return null;
  return { id, start: realStart, end };
}

/** The YouTube page of a video, for "Open on YouTube". Built from the id only. */
export function watchUrl(video: VideoRef): string | null {
  if (!isValidVideo(video.id, video.start, video.end)) return null;
  const t = video.start !== null && video.start > 0 ? `&t=${video.start}` : '';
  return `https://www.youtube.com/watch?v=${video.id}${t}`;
}

/** 90 → "1:30", 3723 → "1:02:03" (digits only: shown in an LTR span). */
export function formatSeconds(total: number): string {
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

// `a=1&b&a=2` → { a: ['1', '2'], b: [''] }. `+` reads as a space, as in a form
// query; no value we accept contains one, so it only ever makes a value fail.
function parseQuery(query: string): Map<string, string[]> {
  const out = new Map<string, string[]>();
  if (query === '') return out;
  for (const pair of query.split('&')) {
    if (pair === '') continue;
    const eq = pair.indexOf('=');
    const name = (eq < 0 ? pair : pair.slice(0, eq)).replace(/\+/g, ' ');
    const value = (eq < 0 ? '' : pair.slice(eq + 1)).replace(/\+/g, ' ');
    const list = out.get(name);
    if (list) list.push(value);
    else out.set(name, [value]);
  }
  return out;
}

/** The one value of a parameter; null when absent, '' (never valid) when given twice. */
function single(params: Map<string, string[]>, name: string): string | null {
  const all = params.get(name);
  if (!all || all.length === 0) return null;
  if (all.length > 1) return '';
  return all[0] ?? null;
}

function parseSeconds(value: string): number | null {
  return SECONDS.test(value) ? Number(value) : null;
}

function parseTime(value: string): number | null {
  if (value === '') return null;
  const m = TIME.exec(value);
  if (!m) return null;
  return Number(m[1] ?? 0) * 3600 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0);
}
