// Picture ids and URLs, and the pure rules of a picture list (cover first,
// at most 6, each picture once). Same rules as the database (0015) and the
// app (lib/core/media/cloudinary_url.dart).

export const MAX_PICTURES = 6;
export const CLOUDINARY_HOST = 'res.cloudinary.com';

export const PUBLIC_ID = /^exercises\/[a-z0-9][a-z0-9-]{0,79}$/;
export const CLOUD_NAME = /^[a-z0-9][a-z0-9_-]{0,62}$/;
export const EXERCISE_KEY = /^ek-[a-z0-9]{1,20}$/;

/** Same widths as the app, so the CDN serves the same cached files. */
export type PictureSize = 'thumb' | 'large';
const WIDTH: Record<PictureSize, number> = { thumb: 160, large: 640 };

/** The path every picture URL starts with; the CSP allows only this prefix. */
export function pictureBase(cloudName: string): string | null {
  return CLOUD_NAME.test(cloudName) ? `https://${CLOUDINARY_HOST}/${cloudName}/image/upload/` : null;
}

/**
 * A picture URL from a library id and the cloud name, with fixed
 * transformations only; anything outside the rules gives null (the page then
 * shows a plain tile). Nothing a person types becomes part of the URL.
 */
export function pictureUrl(cloudName: string | null, publicId: string, size: PictureSize): string | null {
  if (cloudName === null || !PUBLIC_ID.test(publicId)) return null;
  const base = pictureBase(cloudName);
  if (base === null) return null;
  return `${base}c_limit,w_${WIDTH[size]},f_webp,q_auto/${publicId}.png`;
}

/** Search words as the app makes them: lower case, Latin/Arabic letters and digits, ≤ 5 words of ≤ 30. */
export const MAX_WORDS = 5;
export const MAX_WORD_LENGTH = 30;
export function searchWords(text: unknown): string[] {
  if (typeof text !== 'string') return [];
  const out: string[] = [];
  for (const w of text.toLowerCase().split(/[^a-z0-9؀-ۿ]+/u)) {
    if (w === '' || w.length > MAX_WORD_LENGTH || out.includes(w)) continue;
    out.push(w);
    if (out.length === MAX_WORDS) break;
  }
  return out;
}

// ---- the list being edited ----

/** Adds a picture at the end; no change when it is there already or the list is full. */
export function addPicture(list: readonly string[], publicId: string): readonly string[] {
  if (!PUBLIC_ID.test(publicId) || list.includes(publicId) || list.length >= MAX_PICTURES) return list;
  return [...list, publicId];
}

export function removePicture(list: readonly string[], publicId: string): readonly string[] {
  return list.filter((p) => p !== publicId);
}

/** Adds it, or takes it out when it is there. */
export function togglePicture(list: readonly string[], publicId: string): readonly string[] {
  return list.includes(publicId) ? removePicture(list, publicId) : addPicture(list, publicId);
}

/** Moves a picture by `by` places (−1 earlier, +1 later); no change at the ends. */
export function movePicture(list: readonly string[], publicId: string, by: -1 | 1): readonly string[] {
  const from = list.indexOf(publicId);
  const to = from + by;
  if (from < 0 || to < 0 || to >= list.length) return list;
  const next = [...list];
  next[from] = list[to] ?? publicId;
  next[to] = publicId;
  return next;
}

/** Adds every frame not there yet, in order, as long as there is room. */
export function addAll(list: readonly string[], publicIds: readonly string[]): readonly string[] {
  return publicIds.reduce<readonly string[]>((acc, id) => addPicture(acc, id), list);
}

export function sameList(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}
