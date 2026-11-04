import type { SupabaseClient } from '@supabase/supabase-js';
import { LOGO_PATH } from '../gyms/gyms';

// The picture in the middle of the QR: the gym's logo from the private
// bucket gym-logos (migration 0008: members read <gym_id>/*), else the app
// icon. It is decoded to a bitmap and drawn on a canvas: no blob: or data:
// URL is ever shown, so the CSP's img-src stays 'self'.

const LOGO_MAX_BYTES = 512 * 1024; // the bucket's own limit
const TYPES = new Set(['image/png', 'image/jpeg']);

export async function loadLogo(supabase: SupabaseClient, logoPath: string | null): Promise<ImageBitmap | null> {
  if (logoPath && LOGO_PATH.test(logoPath)) {
    try {
      const { data, error } = await supabase.storage.from('gym-logos').download(logoPath);
      if (!error && data.size <= LOGO_MAX_BYTES && TYPES.has(data.type)) return await createImageBitmap(data);
    } catch {
      // Fall back to the app icon below.
    }
  }
  return appIcon();
}

async function appIcon(): Promise<ImageBitmap | null> {
  try {
    const response = await fetch('/logo-96.png');
    return response.ok ? await createImageBitmap(await response.blob()) : null;
  } catch {
    return null;
  }
}
