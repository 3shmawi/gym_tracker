import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parsePath } from '../src/app/router';
import { foldForSearch, isLibraryId, libraryExercise, matchesQuery } from '../src/exercises/catalog';
import { LIBRARY } from '../src/exercises/library';
import { EXERCISE_ID } from '../src/exercises/media';

// Tests run from dashboard/ (npm test); the app's files are one level up.
const repo = resolve(process.cwd(), '..');
const catalogDart = readFileSync(resolve(repo, 'lib/features/library/data/exercise_catalog.dart'), 'utf8');
const videosDart = readFileSync(resolve(repo, 'lib/features/library/data/exercise_videos.dart'), 'utf8');

describe('the library copy', () => {
  it('is exactly what the generator makes from the app (run scripts/library_from_dart.mjs when this fails)', () => {
    const generated = execFileSync(process.execPath, ['scripts/library_from_dart.mjs'], { encoding: 'utf8' });
    expect(readFileSync('src/exercises/library.ts', 'utf8')).toBe(generated);
  });

  it('has every exercise of the app (no entry missed by the parser)', () => {
    const ids = [...catalogDart.matchAll(/^\s+id: '([a-z][a-z0-9_]*)',$/gm)].map((m) => m[1]);
    expect(LIBRARY.map((e) => e.id)).toEqual(ids);
    expect(LIBRARY.length).toBe(37);
  });

  it('knows every library video', () => {
    const withVideo = [...videosDart.matchAll(/'([a-z][a-z0-9_]*)':\s*YouTubeVideoRef\(/g)].map((m) => m[1]).sort();
    expect(LIBRARY.filter((e) => e.libraryVideo).map((e) => e.id).sort()).toEqual(withVideo);
    // The 13 exercises added for days 4 and 5, and Push-ups (Move games),
    // have no library video yet.
    expect(LIBRARY.filter((e) => !e.libraryVideo)).toHaveLength(14);
  });

  it('has unique ids the database accepts, and both names', () => {
    expect(new Set(LIBRARY.map((e) => e.id)).size).toBe(LIBRARY.length);
    for (const e of LIBRARY) {
      expect(EXERCISE_ID.test(e.id), e.id).toBe(true);
      expect(e.en.trim(), e.id).not.toBe('');
      expect(e.ar, e.id).toMatch(/[؀-ۿ]/);
    }
  });
});

describe('lookups', () => {
  it('finds library ids only', () => {
    expect(isLibraryId('flat_db_press')).toBe(true);
    expect(libraryExercise('flat_db_press')?.en).toBe('Flat Dumbbell Press');
    for (const bad of ['', 'FLAT_DB_PRESS', 'ex-abc', '../flat_db_press', 'flat_db_press ', '__proto__', 'constructor', 'toString']) {
      expect(isLibraryId(bad), bad).toBe(false);
    }
  });

  it('searches English, Arabic and ids; every word must match', () => {
    const press = libraryExercise('flat_db_press');
    if (!press) throw new Error('library changed');
    expect(matchesQuery(press, '')).toBe(true);
    expect(matchesQuery(press, 'PRESS flat')).toBe(true);
    expect(matchesQuery(press, 'دمبل')).toBe(true);
    expect(matchesQuery(press, 'flat_db')).toBe(true);
    expect(matchesQuery(press, 'db press')).toBe(true);
    expect(matchesQuery(press, 'press squat')).toBe(false);
  });

  it('folds Arabic letters typed either way', () => {
    expect(foldForSearch('إسكوات')).toBe(foldForSearch('اسكوات'));
    expect(foldForSearch('ترباسَ')).toBe('ترباس');
    expect(foldForSearch('Abs\u202e')).toBe('abs');
  });
});

describe('routes', () => {
  const GYM = '0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d';
  it('opens the exercises list and a library exercise', () => {
    expect(parsePath(`/g/${GYM}/exercises`)).toEqual({ name: 'exercises', gymId: GYM });
    expect(parsePath(`/g/${GYM}/exercises/`)).toEqual({ name: 'exercises', gymId: GYM });
    expect(parsePath(`/g/${GYM}/exercises/leg_press`)).toEqual({ name: 'exercise', gymId: GYM, exerciseId: 'leg_press' });
  });
  it('refuses unknown or hostile exercise ids', () => {
    for (const id of ['nope', 'LEG_PRESS', 'ex-', '%2e%2e', '..', 'leg_press%00', '<script>', '__proto__', 'leg_press/extra']) {
      expect(parsePath(`/g/${GYM}/exercises/${id}`).name, id).toBe('not_found');
    }
    expect(parsePath('/g/not-a-uuid/exercises').name).toBe('not_found');
  });
});
