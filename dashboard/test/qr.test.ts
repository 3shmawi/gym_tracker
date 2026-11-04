import { describe, expect, it } from 'vitest';
import { decode, joinUrl, logoBoxPx, LOGO_SIDE_MAX, qrMatrix, rasterize } from '../src/invites/qr';

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function randomCode(seed: number): string {
  let s = seed;
  let out = '';
  for (let i = 0; i < 6; i++) {
    s = (s * 1103515245 + 12345) % 2147483648;
    out += ALPHABET.charAt(s % ALPHABET.length);
  }
  return out;
}

describe('joinUrl', () => {
  it('builds the path link the apps claim', () => {
    expect(joinUrl('K7QM3D')).toBe('https://azmm.pages.dev/join/K7QM3D');
  });
  it.each(['', 'k7qm3d', 'K7QM3', 'K7QM3DD', 'K7QM0D', 'K7QMID', 'https://evil.example', '<script>', '../../x'])(
    'refuses %j',
    (bad) => {
      expect(() => joinUrl(bad)).toThrow(RangeError);
    },
  );
});

describe('logo box', () => {
  it('is 18 % by default and never above 20 %', () => {
    expect(logoBoxPx(300)).toBe(54);
    expect(logoBoxPx(300, LOGO_SIDE_MAX)).toBe(60);
    expect(() => logoBoxPx(300, 0.21)).toThrow(RangeError);
    expect(() => logoBoxPx(300, 0)).toThrow(RangeError);
    expect(() => logoBoxPx(300, Number.NaN)).toThrow(RangeError);
  });
});

describe('every QR reads back', () => {
  it.each(Array.from({ length: 25 }, (_, i) => randomCode(i + 1)))('%s without and with the logo box', (code) => {
    const url = joinUrl(code);
    const matrix = qrMatrix(url);
    for (const logo of [null, 0.18, 0.2]) {
      const r = rasterize(matrix, 6, logo);
      expect(decode(r.data, r.width, r.height)).toBe(url);
    }
  });

  it('a damaged QR does not read back (the check can fail)', () => {
    const url = joinUrl('K7QM3D');
    const r = rasterize(qrMatrix(url), 6, null);
    // Wipe the middle third: far beyond what level H recovers.
    const third = Math.floor(r.width / 3);
    for (let y = third; y < 2 * third; y++) for (let x = 0; x < r.width; x++) r.data.fill(255, (y * r.width + x) * 4, (y * r.width + x) * 4 + 3);
    expect(decode(r.data, r.width, r.height)).not.toBe(url);
  });
});
