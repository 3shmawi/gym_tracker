import { cleanName } from '../core/text';
import { LIBRARY } from './library';
import type { LibraryExercise } from './types';

// Lookups over the app's exercise library (src/exercises/library.ts).

const BY_ID = new Map(LIBRARY.map((e) => [e.id, e]));

/** True only for an id of the library (the router refuses anything else). */
export function isLibraryId(value: string): boolean {
  return BY_ID.has(value);
}

export function libraryExercise(id: string): LibraryExercise | undefined {
  return BY_ID.get(id);
}

// Arabic letters that people type either way (أ إ آ → ا, ة → ه, ى → ي) and
// the tashkeel marks, so "اسكوات" finds "إسكوات".
const ARABIC_FOLD: Readonly<Record<string, string>> = { 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ة': 'ه', 'ى': 'ي' };
export function foldForSearch(text: string): string {
  return cleanName(text)
    .toLocaleLowerCase('en')
    .replace(/[ً-ْـ]/g, '')
    .replace(/[أإآةى]/g, (c) => ARABIC_FOLD[c] ?? c);
}

/** Matches the English name, the Arabic name or the id; every typed word must be found. */
export function matchesQuery(exercise: LibraryExercise, query: string): boolean {
  const words = foldForSearch(query).split(' ').filter(Boolean);
  if (words.length === 0) return true;
  const haystack = foldForSearch(`${exercise.en} ${exercise.ar} ${exercise.id} ${exercise.id.replace(/_/g, ' ')}`);
  return words.every((w) => haystack.includes(w));
}
