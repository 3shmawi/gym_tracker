import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { azmBrand, contrastOf, deriveBrand, LINEAR, mix, nearErrorRed, parseBrandColor, passes, ratioText, readTyped, REFERENCE, toHex, toRgb, type Mode, type Rgb } from '../src/gyms/brandColor';

// The same vectors the app's Dart rule and pgTAP read: the preview must show
// exactly what the phone shows.
interface Vectors {
  linear: number[];
  valid: string[];
  invalid: string[];
  colours: { picked: string; light: Record<string, string | number>; dark: Record<string, string | number> }[];
}
const vectors = JSON.parse(readFileSync(resolve(process.cwd(), '../docs/features/brand_colour_vectors.json'), 'utf8')) as Vectors;

/** A short name for a value in a failure message. */
const show = (v: unknown): string => (typeof v === 'string' ? v.slice(0, 40) : typeof v);

describe('the brand colour rule', () => {
  it('uses the shared luminance table, all 256 values', () => {
    expect([...LINEAR]).toEqual(vectors.linear);
  });

  it('gives the shared values for every shared colour, in both modes', () => {
    expect(vectors.colours.length).toBeGreaterThanOrEqual(60);
    for (const c of vectors.colours) {
      expect(deriveBrand(c.picked, 'light'), `${c.picked} light`).toEqual(c.light);
      expect(deriveBrand(c.picked, 'dark'), `${c.picked} dark`).toEqual(c.dark);
    }
  });

  it('accepts the valid stored codes and nothing else', () => {
    for (const v of vectors.valid) expect(parseBrandColor(v), v).toBe(v);
    const hostile: unknown[] = [...vectors.invalid, null, undefined, 42, 4.2, true, ['#facc15'], { hex: '#facc15' }, '#facc15'.repeat(100000), '\u0000#facc15', '<script>alert(1)</script>', "'; drop table gyms;--"];
    for (const v of hostile) expect(parseBrandColor(v), show(v)).toBeNull();
  });

  it('guarantees on a sweep of the cube: fills 3:1, text 4.5:1, a readable tint, a glow no stronger than Azm', () => {
    const text: Record<Mode, Rgb> = { light: [0x0c, 0x16, 0x10], dark: [0xf2, 0xf7, 0xf3] };
    for (const mode of ['light', 'dark'] as const) {
      for (let r = 0; r < 256; r += 17) {
        for (let g = 0; g < 256; g += 17) {
          for (let b = 0; b < 256; b += 17) {
            const v = deriveBrand(toHex([r, g, b]), mode);
            const why = `${r},${g},${b} ${mode}`;
            expect(passes(toRgb(v.brand), REFERENCE[mode], 3, 1), `brand ${why}`).toBe(true);
            expect(passes(toRgb(v.onBrand), toRgb(v.brand), 9, 2), `onBrand ${why}`).toBe(true);
            expect(passes(toRgb(v.primary), REFERENCE[mode], 9, 2), `primary ${why}`).toBe(true);
            expect(passes(toRgb(v.onPrimary), toRgb(v.primary), 9, 2), `onPrimary ${why}`).toBe(true);
            expect(passes(text[mode], mix(toRgb(v.brand), REFERENCE[mode], 80), 9, 2), `tint ${why}`).toBe(true);
          }
        }
      }
    }
  });

  it('a colour that already passes is used as picked; the readability numbers never round up', () => {
    expect(deriveBrand('#1e3a8a', 'light')).toMatchObject({ brand: '#1e3a8a', adjusted: 0 });
    expect(deriveBrand('#facc15', 'dark')).toMatchObject({ brand: '#facc15', adjusted: 0 });
    expect(deriveBrand('#facc15', 'light').adjusted).toBeGreaterThan(0);
    const c = contrastOf(deriveBrand('#facc15', 'light'), 'light');
    expect(c.fill).toBeGreaterThanOrEqual(3);
    expect(c.onFill).toBeGreaterThanOrEqual(4.5);
    expect(c.accent).toBeGreaterThanOrEqual(4.5);
    expect(ratioText(4.59)).toBe('4.5');
    expect(ratioText(2.999)).toBe('2.9');
    expect(ratioText(3)).toBe('3.0');
  });

  it('Azm colours are the approved constants, not generated', () => {
    expect(azmBrand('dark')).toMatchObject({ brand: '#22c55e', onBrand: '#04210f', primary: '#22c55e' });
    expect(azmBrand('light')).toMatchObject({ brand: '#22c55e', primary: '#15803d', onPrimary: '#ffffff' });
  });
});

describe('what the owner types', () => {
  it('any letter case and spaces around are fine; the saved form is lower case', () => {
    expect(readTyped('#FACC15')).toEqual({ ok: true, hex: '#facc15' });
    expect(readTyped('  #FaCc15 ')).toEqual({ ok: true, hex: '#facc15' });
  });
  it('refuses other shapes and colours without colour, and says which', () => {
    const shapes: unknown[] = ['', 'FACC15', '#FFF', '#FACC155', 'red', 'rgb(1,2,3)', '#GGGGGG', '#٢٢c55e', "#facc15'; drop table gyms;--", '<img src=x onerror=alert(1)>', 42, null, undefined, {}, '#facc15'.repeat(5000)];
    for (const bad of shapes) {
      expect(readTyped(bad), show(bad)).toEqual({ ok: false, problem: 'format' });
    }
    for (const grey of ['#000000', '#FFFFFF', '#808080', '#1F2937']) expect(readTyped(grey), grey).toEqual({ ok: false, problem: 'no_colour' });
  });
  it('a colour near the error red gets a note; others do not', () => {
    expect(nearErrorRed('#dc2626')).toBe(true);
    expect(nearErrorRed('#ff0000')).toBe(true);
    for (const c of ['#facc15', '#1e3a8a', '#f97316', '#ec4899', '#22c55e']) expect(nearErrorRed(c), c).toBe(false);
  });
});
