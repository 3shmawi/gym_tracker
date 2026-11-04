import { drawQr, type DrawnQr } from '../invites/qr';

/** The logo for the QR centre; a failed load means "no logo", never a failed page. */
export async function logoFor(loadLogo: (path: string | null) => Promise<ImageBitmap | null>, path: string | null): Promise<ImageBitmap | null> {
  try {
    return await loadLogo(path);
  } catch {
    return null;
  }
}

/** drawQr that never throws: a QR that can't be drawn counts as "not read back". */
export function drawChecked(code: string, logo: ImageBitmap | null): DrawnQr {
  try {
    return drawQr(code, logo);
  } catch {
    return { canvas: document.createElement('canvas'), verified: false };
  }
}
