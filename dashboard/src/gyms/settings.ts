import type { SupabaseClient } from '@supabase/supabase-js';
import { CodedError } from '../core/failure';
import { guard, unwrap, type Result } from '../core/result';
import { cleanName } from '../core/text';
import { parseBrandColor } from './brandColor';
import { isGymId, LOGO_PATH } from './gyms';

// Gym settings (D5): what the gyms table lets the owner change (migration
// 0005: update grant on name, logo_path, history_after_end; 0020: policy
// "owners update their gym" = private.i_own, active owner, permanent session)
// and the logo in the private bucket gym-logos (0008: png/jpeg, ≤ 512 KB,
// path <gym_id>/logo.png|jpg|jpeg, members read; 0020: the owner writes).
// D6 adds brand_color (0021: '#rrggbb' in lower case, not black / white /
// grey, or null; the same owner-only policy).

export const GYM_NAME_MAX = 60;
export const LOGO_MAX_BYTES = 512 * 1024;
export type History = 'readable' | 'locked';
export type LogoType = 'image/png' | 'image/jpeg';

/** A gym name the table accepts: cleaned (hidden and control characters removed), 1–60 characters. */
export function validGymName(raw: unknown): string | null {
  const name = cleanName(raw);
  const n = Array.from(name).length;
  return n >= 1 && n <= GYM_NAME_MAX ? name : null;
}

export type LogoProblem = 'empty' | 'too_big' | 'wrong_type';

const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG = [0xff, 0xd8, 0xff];
const startsWith = (bytes: Uint8Array, sig: readonly number[]) => sig.every((b, i) => bytes[i] === b);

/**
 * What the file really is, from its first bytes (never from its name or the
 * type the browser guessed), or the problem. `head` is at least the first
 * 8 bytes of the file.
 */
export function checkLogoFile(file: { readonly size: number; readonly type: string }, head: Uint8Array): { readonly ok: true; readonly type: LogoType } | { readonly ok: false; readonly problem: LogoProblem } {
  if (file.size === 0 || head.length === 0) return { ok: false, problem: 'empty' };
  if (file.size > LOGO_MAX_BYTES) return { ok: false, problem: 'too_big' };
  const type: LogoType | null = startsWith(head, PNG) ? 'image/png' : startsWith(head, JPEG) ? 'image/jpeg' : null;
  if (!type) return { ok: false, problem: 'wrong_type' };
  // The browser's guess must not contradict the bytes (e.g. an SVG renamed .png).
  if (file.type !== '' && file.type !== type) return { ok: false, problem: 'wrong_type' };
  return { ok: true, type };
}

/** The object path for a logo: from the gym id and the checked type only, never from the file name. */
export function logoPath(gymId: string, type: LogoType): string | null {
  if (!isGymId(gymId)) return null;
  const path = `${gymId}/logo.${type === 'image/png' ? 'png' : 'jpg'}`;
  return LOGO_PATH.test(path) ? path : null;
}

const refuse = (code: string, reason: string) => new CodedError(code, reason);

export class GymSettingsRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  private async update(gymId: string, change: Record<string, unknown>): Promise<void> {
    const rows = unwrap(await this.supabase.from('gyms').update(change).eq('id', gymId).select('id').overrideTypes<{ id: string }[], { merge: false }>());
    // RLS filtered the row out: not a manager (or not with a permanent session).
    if ((rows ?? []).length === 0) throw refuse('42501', 'forbidden');
  }

  async rename(gymId: string, raw: string): Promise<Result<string>> {
    return guard(async () => {
      const name = validGymName(raw);
      if (!isGymId(gymId) || name === null) throw refuse('22023', 'invalid_name');
      await this.update(gymId, { name });
      return name;
    });
  }

  async setHistory(gymId: string, value: string): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(gymId) || (value !== 'readable' && value !== 'locked')) throw refuse('22023', 'invalid_history');
      await this.update(gymId, { history_after_end: value });
    });
  }

  /**
   * Sets the gym's colour for the app, or null for Azm's colours. Only a
   * value the table accepts is ever sent (`parseBrandColor`).
   */
  async setBrandColor(gymId: string, hex: string | null): Promise<Result<string | null>> {
    return guard(async () => {
      const value = hex === null ? null : parseBrandColor(hex);
      if (!isGymId(gymId) || (hex !== null && value === null)) throw refuse('22023', 'invalid_color');
      await this.update(gymId, { brand_color: value });
      return value;
    });
  }

  /**
   * Uploads a prepared logo (already checked and re-encoded) and points the gym
   * at it; a previous logo under another extension is removed afterwards.
   */
  async setLogo(gymId: string, blob: Blob, type: LogoType, oldPath: string | null): Promise<Result<string>> {
    return guard(async () => {
      const path = logoPath(gymId, type);
      if (!path || blob.size === 0 || blob.size > LOGO_MAX_BYTES) throw refuse('22023', 'invalid_logo');
      const { error } = await this.supabase.storage.from('gym-logos').upload(path, blob, { upsert: true, contentType: type, cacheControl: '60' });
      if (error) throw error;
      await this.update(gymId, { logo_path: path });
      if (oldPath && oldPath !== path && LOGO_PATH.test(oldPath) && oldPath.startsWith(`${gymId}/`)) {
        // Best effort: the gym already points at the new file.
        await this.supabase.storage.from('gym-logos').remove([oldPath]);
      }
      return path;
    });
  }

  async removeLogo(gymId: string, oldPath: string | null): Promise<Result<void>> {
    return guard(async () => {
      if (!isGymId(gymId)) throw refuse('22023', 'invalid_logo');
      await this.update(gymId, { logo_path: null });
      if (oldPath && LOGO_PATH.test(oldPath) && oldPath.startsWith(`${gymId}/`)) await this.supabase.storage.from('gym-logos').remove([oldPath]);
    });
  }
}

/**
 * Decodes the picture and draws it again (at most 512 px a side) in the same
 * type: what is uploaded is pixels only, so EXIF data (camera, GPS place,
 * time) never leaves the computer. Browser only (canvas).
 */
export async function reencodeLogo(file: Blob, type: LogoType): Promise<Blob | null> {
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, 512 / Math.max(bitmap.width, bitmap.height));
    const w = Math.max(1, Math.round(bitmap.width * scale));
    const h = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    if (type === 'image/jpeg') {
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, w, h);
    }
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close();
    const out = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob(resolve, type, 0.9);
    });
    return out && out.size > 0 && out.size <= LOGO_MAX_BYTES ? out : null;
  } catch {
    return null;
  }
}
