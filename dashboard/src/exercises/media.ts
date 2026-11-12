import type { SupabaseClient } from '@supabase/supabase-js';
import { CodedError } from '../core/failure';
import { failed, guard, unwrap, type Result } from '../core/result';
import { cleanName } from '../core/text';
import { isGymId } from '../gyms/gyms';
import { EXERCISE_KEY, MAX_PICTURES, PUBLIC_ID, searchWords } from './pictures';
import type { CatalogPicture, GymMedia, VideoRef } from './types';
import { isValidVideo } from './youtube';

// A gym's exercise media. Every rule lives in the database; this file only
// asks, and checks what it sends and what comes back:
// - exercise_images (0013): public read; search with `keywords && words`
//   (values of an array filter, never SQL);
// - gym_exercise_images (0015): read = the gym's members; save = the RPC
//   set_gym_exercise_images (security invoker: the policies decide; one
//   transaction replaces the list; owner/captain with a permanent session);
// - gym_exercise_videos (0017): read the same; insert (gym_id, exercise_id,
//   video_id, start, end), update (video_id, start, end), delete. Not an
//   upsert: PostgREST's upsert writes every sent column in DO UPDATE SET,
//   and gym_id / exercise_id have no update grant (42501).

/** Same rule as the tables' exercise_id check: a library id or a plan id, ≤ 64. */
export const EXERCISE_ID = /^(?:[a-z][a-z0-9_]*|ex-[a-z0-9]{1,20}(?:-[0-9]{1,4})?)$/;
export const isExerciseId = (value: unknown): value is string => typeof value === 'string' && value.length <= 64 && EXERCISE_ID.test(value);

/** Rows read at most (the database caps a gym at 1200 pictures and 300 videos). */
export const MAX_PICTURE_ROWS = 1200;
export const MAX_VIDEO_ROWS = 300;
/** Search results at most (as the app). */
export const MAX_SEARCH_ROWS = 60;
/** Rows fetched for the "any word" fallback, before ranking and cutting to MAX_SEARCH_ROWS. */
const MAX_ANY_ROWS = 400;
const TITLE_MAX = 80;

interface PictureRow {
  exercise_id: unknown;
  public_id: unknown;
  position: unknown;
}
interface VideoRow {
  exercise_id: unknown;
  video_id: unknown;
  start_seconds: unknown;
  end_seconds: unknown;
}
interface CatalogRow {
  public_id: unknown;
  exercise_key: unknown;
  frame: unknown;
  title_en: unknown;
  keywords?: unknown;
}

/** How many of the searched words an exercise's keywords hold. */
function matchedWords(row: CatalogRow, words: readonly string[]): number {
  const keywords = Array.isArray(row.keywords) ? (row.keywords as unknown[]) : [];
  return words.filter((w) => keywords.includes(w)).length;
}

const intOrNull = (v: unknown): number | null => (typeof v === 'number' && Number.isInteger(v) ? v : null);

/** Rows outside the rules are dropped, never shown. */
export function toGymMedia(pictureRows: readonly PictureRow[], videoRows: readonly VideoRow[]): GymMedia {
  const byExercise = new Map<string, { id: string; position: number }[]>();
  for (const row of pictureRows) {
    if (!isExerciseId(row.exercise_id) || typeof row.public_id !== 'string' || !PUBLIC_ID.test(row.public_id)) continue;
    const position = intOrNull(row.position);
    if (position === null || position < 1 || position > MAX_PICTURES) continue;
    const list = byExercise.get(row.exercise_id) ?? [];
    if (!list.some((p) => p.id === row.public_id)) list.push({ id: row.public_id, position });
    byExercise.set(row.exercise_id, list);
  }
  const pictures = new Map<string, readonly string[]>();
  for (const [exercise, list] of byExercise) {
    pictures.set(exercise, [...list].sort((a, b) => a.position - b.position).slice(0, MAX_PICTURES).map((p) => p.id));
  }
  const videos = new Map<string, VideoRef>();
  for (const row of videoRows) {
    if (!isExerciseId(row.exercise_id) || typeof row.video_id !== 'string') continue;
    const start = intOrNull(row.start_seconds);
    const end = intOrNull(row.end_seconds);
    if (!isValidVideo(row.video_id, start, end)) continue;
    videos.set(row.exercise_id, { id: row.video_id, start, end });
  }
  return { pictures, videos };
}

export function toCatalogPicture(row: CatalogRow): CatalogPicture | null {
  const { public_id: id, exercise_key: key, frame, title_en: title } = row;
  if (typeof id !== 'string' || typeof key !== 'string' || !PUBLIC_ID.test(id) || !EXERCISE_KEY.test(key)) return null;
  if (frame !== 'tension' && frame !== 'relaxation') return null;
  if (id !== `exercises/${key}-${frame}`) return null;
  const clean = Array.from(cleanName(title)).slice(0, TITLE_MAX).join('');
  return { publicId: id, exerciseKey: key, frame, title: clean };
}

const refuse = (code: string, reason: string) => new CodedError(code, reason);

export class MediaRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  /** The gym's pictures and videos, every exercise. */
  async load(gymId: string): Promise<Result<GymMedia>> {
    if (!isGymId(gymId)) return failed({ kind: 'not_found' });
    return guard(async () => {
      const [pictures, videos] = await Promise.all([
        this.supabase
          .from('gym_exercise_images')
          .select('exercise_id, public_id, position')
          .eq('gym_id', gymId)
          .order('exercise_id')
          .order('position')
          .limit(MAX_PICTURE_ROWS)
          .overrideTypes<PictureRow[], { merge: false }>(),
        this.supabase
          .from('gym_exercise_videos')
          .select('exercise_id, video_id, start_seconds, end_seconds')
          .eq('gym_id', gymId)
          .limit(MAX_VIDEO_ROWS)
          .overrideTypes<VideoRow[], { merge: false }>(),
      ]);
      return toGymMedia(unwrap(pictures) ?? [], unwrap(videos) ?? []);
    });
  }

  /**
   * Library pictures for the typed words; both frames of a move next to each
   * other. Exercises that have **all** the words come first and alone: "Flat
   * Dumbbell Press" finds the flat dumbbell press, not every dumbbell or
   * press exercise. Only when none has them all, exercises with **any** of the
   * words are listed, the ones with the most words first.
   */
  async search(text: string): Promise<Result<CatalogPicture[]>> {
    const words = searchWords(text);
    return guard(async () => {
      if (words.length === 0) return [];
      const all = unwrap(
        await this.supabase
          .from('exercise_images')
          .select('public_id, exercise_key, frame, title_en')
          .contains('keywords', words)
          .order('exercise_key')
          .order('frame', { ascending: false })
          .limit(MAX_SEARCH_ROWS)
          .overrideTypes<CatalogRow[], { merge: false }>(),
      );
      let rows: CatalogRow[] = all ?? [];
      if (rows.length === 0 && words.length > 1) {
        const any = unwrap(
          await this.supabase
            .from('exercise_images')
            .select('public_id, exercise_key, frame, title_en, keywords')
            .overlaps('keywords', words)
            .order('exercise_key')
            .order('frame', { ascending: false })
            .limit(MAX_ANY_ROWS)
            .overrideTypes<CatalogRow[], { merge: false }>(),
        );
        // Stable sort: the server's order (exercise, then frame) is kept among equals.
        rows = [...(any ?? [])].sort((a, b) => matchedWords(b, words) - matchedWords(a, words)).slice(0, MAX_SEARCH_ROWS);
      }
      return rows.flatMap((row) => {
        const picture = toCatalogPicture(row);
        return picture ? [picture] : [];
      });
    });
  }

  /** The library rows of these pictures (for their titles); unknown ids are left out. */
  async describe(publicIds: readonly string[]): Promise<Result<CatalogPicture[]>> {
    const ids = [...new Set(publicIds)].filter((p) => PUBLIC_ID.test(p)).slice(0, MAX_PICTURES);
    return guard(async () => {
      if (ids.length === 0) return [];
      const rows = unwrap(
        await this.supabase
          .from('exercise_images')
          .select('public_id, exercise_key, frame, title_en')
          .in('public_id', ids)
          .limit(MAX_PICTURES)
          .overrideTypes<CatalogRow[], { merge: false }>(),
      );
      return (rows ?? []).flatMap((row) => {
        const picture = toCatalogPicture(row);
        return picture && ids.includes(picture.publicId) ? [picture] : [];
      });
    });
  }

  /** Replaces the exercise's pictures (array order = position; [] removes them all). */
  async savePictures(gymId: string, exerciseId: string, publicIds: readonly string[]): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(gymId) || !isExerciseId(exerciseId)) throw refuse('22023', 'invalid_list');
      if (publicIds.length > MAX_PICTURES) throw refuse('23514', 'too_many_pictures');
      if (!publicIds.every((p) => PUBLIC_ID.test(p)) || new Set(publicIds).size !== publicIds.length) throw refuse('22023', 'invalid_list');
      unwrap(
        await this.supabase.rpc('set_gym_exercise_images', {
          p_gym_id: gymId,
          p_exercise_id: exerciseId,
          p_public_ids: [...publicIds],
        }),
      );
    });
  }

  /** Sets the gym's video: an update when one is there, else an insert (and the other way round on a race). */
  async saveVideo(gymId: string, exerciseId: string, video: VideoRef, hasOne: boolean): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(gymId) || !isExerciseId(exerciseId) || !isValidVideo(video.id, video.start, video.end)) throw refuse('22023', 'invalid_video');
      const values = { video_id: video.id, start_seconds: video.start, end_seconds: video.end };
      const update = async (): Promise<boolean> => {
        const rows = unwrap(
          await this.supabase
            .from('gym_exercise_videos')
            .update(values)
            .eq('gym_id', gymId)
            .eq('exercise_id', exerciseId)
            .select('exercise_id')
            .overrideTypes<{ exercise_id: string }[], { merge: false }>(),
        );
        return (rows ?? []).length > 0;
      };
      const insert = async (): Promise<'ok' | 'exists'> => {
        const { error } = await this.supabase.from('gym_exercise_videos').insert({ gym_id: gymId, exercise_id: exerciseId, ...values });
        if (!error) return 'ok';
        if ((error as { code?: unknown }).code === '23505') return 'exists';
        throw error;
      };
      if (hasOne && (await update())) return;
      if ((await insert()) === 'ok') return;
      // Someone added one meanwhile: change it instead. No row now means RLS hid it.
      if (!(await update())) throw refuse('42501', 'forbidden');
    });
  }

  /** Removes the gym's video; members then see the library's video, if it has one. */
  async removeVideo(gymId: string, exerciseId: string): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(gymId) || !isExerciseId(exerciseId)) throw refuse('22023', 'invalid_video');
      unwrap(await this.supabase.from('gym_exercise_videos').delete().eq('gym_id', gymId).eq('exercise_id', exerciseId));
    });
  }
}
