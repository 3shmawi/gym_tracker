import { cleanName } from '../core/text';
import { LIBRARY } from './library';
import type { ExerciseLike, LibraryExercise } from './types';

// Lookups over the app's exercise library (src/exercises/library.ts).

const BY_ID = new Map(LIBRARY.map((e) => [e.id, e]));

/** True only for an id of the library (the router refuses anything else). */
export function isLibraryId(value: string): boolean {
  return BY_ID.has(value);
}

/** Ids the app gives to an exercise a person writes into a plan ("ex-" + base 36, maybe "-n"). */
const CUSTOM_ID = /^ex-[a-z0-9]{1,20}(?:-[0-9]{1,4})?$/;

/** True for the id of an exercise written into a plan (never a library id). */
export function isCustomId(value: string): boolean {
  return value.length <= 64 && CUSTOM_ID.test(value) && !BY_ID.has(value);
}

/** The library's exercise in the shape the Exercises tab lists. */
export function asListed(e: LibraryExercise): ExerciseLike {
  return { id: e.id, en: e.en, ar: e.ar, muscle: e.muscle, libraryVideo: e.libraryVideo, custom: false };
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
export function matchesQuery(exercise: Pick<ExerciseLike, 'id' | 'en' | 'ar'>, query: string): boolean {
  const words = foldForSearch(query).split(' ').filter(Boolean);
  if (words.length === 0) return true;
  const haystack = foldForSearch(`${exercise.en} ${exercise.ar} ${exercise.id} ${exercise.id.replace(/_/g, ' ')}`);
  return words.every((w) => haystack.includes(w));
}
