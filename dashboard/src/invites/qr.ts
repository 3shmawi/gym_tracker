import jsQR from 'jsqr';
import qrcode from 'qrcode-generator';
import { CODE_RE } from '../members/members';

// The invite QR, with the same rules as scripts/make_invites (decision §2 #4,
// §15): the link https://azmm.pages.dev/join/<code>, error correction H, the
// logo box at most 20 % of the symbol's side (18 % by default), and every QR
// decoded again before it may be printed. A card whose QR doesn't read back
// is never printed.

export const JOIN_URL_BASE = 'https://azmm.pages.dev/join/';
export const LOGO_SIDE_MAX = 0.2;
export const LOGO_SIDE_DEFAULT = 0.18;
/** Quiet zone in modules (the QR spec asks for 4). */
export const QUIET = 4;

export function joinUrl(code: string): string {
  if (!CODE_RE.test(code)) throw new RangeError('not a valid invite code');
  return JOIN_URL_BASE + code;
}

/** The QR's modules, true = dark. Level H, smallest version that fits. */
export function qrMatrix(text: string): boolean[][] {
  const qr = qrcode(0, 'H');
  qr.addData(text, 'Byte');
  qr.make();
  const n = qr.getModuleCount();
  return Array.from({ length: n }, (_, r) => Array.from({ length: n }, (_, c) => qr.isDark(r, c)));
}

/** Side of the logo box in pixels for a symbol of `symbolPx`, never above 20 %. */
export function logoBoxPx(symbolPx: number, fraction = LOGO_SIDE_DEFAULT): number {
  if (!(fraction > 0 && fraction <= LOGO_SIDE_MAX)) throw new RangeError('logo fraction must be in (0, 0.2]');
  return Math.floor(symbolPx * fraction);
}

export interface Raster {
  readonly data: Uint8ClampedArray<ArrayBuffer>;
  readonly width: number;
  readonly height: number;
  /** Where the symbol (without quiet zone) starts and its size, in pixels. */
  readonly symbolOffset: number;
  readonly symbolPx: number;
}

/**
 * Black-on-white RGBA pixels of the matrix with a quiet zone, and an
 * optional white logo box in the middle (the logo is drawn inside it later).
 * Pure: unit tests decode this without a canvas.
 */
export function rasterize(matrix: readonly (readonly boolean[])[], scale: number, logoFraction: number | null): Raster {
  const n = matrix.length;
  const size = (n + 2 * QUIET) * scale;
  const data = new Uint8ClampedArray(size * size * 4).fill(255);
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (!matrix[r]?.[c]) continue;
      for (let y = 0; y < scale; y++) {
        const row = ((r + QUIET) * scale + y) * size;
        for (let x = 0; x < scale; x++) {
          const i = (row + (c + QUIET) * scale + x) * 4;
          data[i] = data[i + 1] = data[i + 2] = 0;
        }
      }
    }
  }
  const symbolOffset = QUIET * scale;
  const symbolPx = n * scale;
  if (logoFraction !== null) {
    const box = logoBoxPx(symbolPx, logoFraction);
    const start = symbolOffset + Math.floor((symbolPx - box) / 2);
    for (let y = start; y < start + box; y++) {
      for (let x = start; x < start + box; x++) {
        const i = (y * size + x) * 4;
        data[i] = data[i + 1] = data[i + 2] = 255;
      }
    }
  }
  return { data, width: size, height: size, symbolOffset, symbolPx };
}

/** What a phone camera would read, or null. */
export function decode(data: Uint8ClampedArray, width: number, height: number): string | null {
  const found = jsQR(data, width, height, { inversionAttempts: 'dontInvert' });
  return found ? found.data : null;
}

export interface DrawnQr {
  readonly canvas: HTMLCanvasElement;
  /** True only when the drawn QR, logo included, decodes to exactly the link. */
  readonly verified: boolean;
}

/**
 * Draws the QR (and the logo, if any) on a new canvas and decodes the
 * canvas's own pixels. The logo is a decoded bitmap (never a URL), so the
 * page needs no img-src beyond 'self'.
 */
export function drawQr(code: string, logo: ImageBitmap | HTMLImageElement | null, scale = 12): DrawnQr {
  const url = joinUrl(code);
  const matrix = qrMatrix(url);
  const raster = rasterize(matrix, scale, logo ? LOGO_SIDE_DEFAULT : null);
  const canvas = document.createElement('canvas');
  canvas.width = raster.width;
  canvas.height = raster.height;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) return { canvas, verified: false };
  ctx.putImageData(new ImageData(raster.data, raster.width, raster.height), 0, 0);
  if (logo) {
    const box = logoBoxPx(raster.symbolPx);
    const pad = Math.max(2, Math.round(box * 0.08));
    const start = raster.symbolOffset + Math.floor((raster.symbolPx - box) / 2);
    ctx.drawImage(logo, start + pad, start + pad, box - 2 * pad, box - 2 * pad);
  }
  const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height);
  return { canvas, verified: decode(pixels.data, pixels.width, pixels.height) === url };
}
