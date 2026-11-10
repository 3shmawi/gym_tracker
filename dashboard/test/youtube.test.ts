import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { formatSeconds, isValidVideo, parseYouTubeLink, watchUrl } from '../src/exercises/youtube';

// The same vectors the app's test runs (docs/features/youtube_link_vectors.json).
// Tests run from dashboard/ (npm test), so the repo root is one level up.
interface Vector {
  readonly input: string;
  readonly valid: boolean;
  readonly id?: string;
  readonly start?: number;
  readonly end?: number;
  readonly note: string;
}
const file = JSON.parse(readFileSync(resolve(process.cwd(), '../docs/features/youtube_link_vectors.json'), 'utf8')) as { vectors: Vector[] };

describe('parseYouTubeLink: shared vectors', () => {
  it('has the vectors', () => {
    expect(file.vectors.length).toBeGreaterThanOrEqual(55);
  });
  for (const v of file.vectors) {
    it(`${v.valid ? 'accepts' : 'refuses'}: ${v.note}`, () => {
      const got = parseYouTubeLink(v.input);
      if (!v.valid) {
        expect(got).toBeNull();
        return;
      }
      expect(got).toEqual({ id: v.id, start: v.start ?? null, end: v.end ?? null });
    });
  }
});

describe('parseYouTubeLink: more hostile input', () => {
  const ID = 'dQw4w9WgXcQ';
  it.each([
    ['dot segments', `https://www.youtube.com/a/../watch?v=${ID}`],
    ['single dot', `https://www.youtube.com/./watch?v=${ID}`],
    ['data URL', `data:text/html,${ID}`],
    ['empty host', `https:///watch?v=${ID}`],
    ['trailing colon (empty port)', `https://www.youtube.com:/watch?v=${ID}`],
    ['tab inside', `https://www.youtube.com/watch?v=${ID}\tx`],
    ['newline inside', `https://youtu.be/${ID}\nhttps://evil.example`],
    ['RTL override', `https://youtu.be/${ID}‮`],
    ['HTML in the id place', 'https://youtu.be/<img src=x>'],
    ['quote in the id', `https://youtu.be/${ID.slice(0, 10)}'`],
    ['end only, zero', `https://youtu.be/${ID}?end=0`],
    ['end past 12 h', `https://youtu.be/${ID}?end=43201`],
    ['plus in t', `https://youtu.be/${ID}?t=1+2`],
    ['two t values', `https://youtu.be/${ID}?t=1&t=2`],
    ['host with trailing dot', `https://youtu.be./${ID}`],
  ])('refuses %s', (_name, input) => {
    expect(parseYouTubeLink(input)).toBeNull();
  });

  it('refuses things that are not text', () => {
    for (const value of [null, undefined, 42, {}, [], true]) expect(parseYouTubeLink(value)).toBeNull();
  });

  it('accepts an upper-case scheme and a fragment', () => {
    expect(parseYouTubeLink(`HTTPS://youtu.be/${ID}#x`)).toEqual({ id: ID, start: null, end: null });
  });

  it('accepts end without start', () => {
    expect(parseYouTubeLink(`https://youtu.be/${ID}?end=30`)).toEqual({ id: ID, start: null, end: 30 });
  });
});

describe('helpers', () => {
  it('checks ids and ranges like the database', () => {
    expect(isValidVideo('dQw4w9WgXcQ', null, null)).toBe(true);
    expect(isValidVideo('dQw4w9WgXcQ', 0, 1)).toBe(true);
    expect(isValidVideo('dQw4w9WgXcQ', 10, 10)).toBe(false);
    expect(isValidVideo('dQw4w9WgXc', null, null)).toBe(false);
    expect(isValidVideo('dQw4w9WgXcQ', -1, null)).toBe(false);
  });
  it('builds the watch link from the id only', () => {
    expect(watchUrl({ id: 'dQw4w9WgXcQ', start: 15, end: null })).toBe('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=15');
    expect(watchUrl({ id: 'dQw4w9WgXcQ', start: null, end: 30 })).toBe('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(watchUrl({ id: 'x"><script>', start: null, end: null })).toBeNull();
  });
  it('formats seconds', () => {
    expect(formatSeconds(5)).toBe('0:05');
    expect(formatSeconds(90)).toBe('1:30');
    expect(formatSeconds(3723)).toBe('1:02:03');
  });
});
