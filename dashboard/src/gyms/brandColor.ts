// The gym brand colour rule (docs/designs/gym_brand_colours.md, "The colour
// rule"), the same as the app's lib/core/theme/brand_color_rule.dart: from
// one picked colour, the values the app uses in light and dark mode, each
// with a guaranteed WCAG 2.2 contrast. Integers only after the luminance
// table, so both give the same bytes; both are checked against
// docs/features/brand_colour_vectors.json.

export type Rgb = readonly [number, number, number];
export type Mode = 'light' | 'dark';

export interface BrandValues {
  /** Fills: buttons, progress, the workout pill, selected marks (≥ 3:1). */
  readonly brand: string;
  /** Text and icons on `brand` (≥ 4.5:1). */
  readonly onBrand: string;
  /** Coloured text, icons and borders on surfaces (≥ 4.5:1). */
  readonly primary: string;
  /** Text on `primary` used as a fill (≥ 4.5:1). */
  readonly onPrimary: string;
  /** The two tinted corners of the background, never stronger than Azm's. */
  readonly glowStart: string;
  readonly glowEnd: string;
  /** How far `brand` moved from the picked colour, in percent (0 = as picked). */
  readonly adjusted: number;
}

const WHITE: Rgb = [255, 255, 255];
const BLACK: Rgb = [0, 0, 0];
const AZM: Rgb = [0x22, 0xc5, 0x5e];
const BACKGROUND: Record<Mode, Rgb> = { light: [0xee, 0xf4, 0xf0], dark: [0x07, 0x12, 0x0c] };
/** The surface each mode is checked against: the darker light one, the lighter dark one. */
export const REFERENCE: Record<Mode, Rgb> = { light: [0xee, 0xf4, 0xf0], dark: [0x14, 0x1e, 0x19] };
/** Channels this close together are black, white or a grey: not a brand. */
export const MIN_SPREAD = 40;

const STORED = /^#[0-9a-f]{6}$/;
const TYPED = /^#[0-9a-fA-F]{6}$/;

/** Linear value of each sRGB channel value × 1e6 (WCAG relative luminance). */
export const LINEAR: readonly number[] = Array.from({ length: 256 }, (_, v) => {
  const s = v / 255;
  return Math.round((s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)) * 1e6);
});

export const toRgb = (hex: string): Rgb => [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
export const toHex = (c: Rgb): string => `#${c.map((v) => v.toString(16).padStart(2, '0')).join('')}`;
export const hasColour = (c: Rgb): boolean => Math.max(...c) - Math.min(...c) >= MIN_SPREAD;

/** A stored value the app accepts: `#rrggbb`, lower case, not black / white / grey. Anything else is null. */
export function parseBrandColor(value: unknown): string | null {
  return typeof value === 'string' && STORED.test(value) && hasColour(toRgb(value)) ? value : null;
}

export type TypedProblem = 'format' | 'no_colour';

/** What the owner typed or picked, made ready to save (lower case), or why not. */
export function readTyped(raw: unknown): { readonly ok: true; readonly hex: string } | { readonly ok: false; readonly problem: TypedProblem } {
  const text = typeof raw === 'string' ? raw.trim() : '';
  if (!TYPED.test(text)) return { ok: false, problem: 'format' };
  const hex = text.toLowerCase();
  return hasColour(toRgb(hex)) ? { ok: true, hex } : { ok: false, problem: 'no_colour' };
}

/** Relative luminance × 1e10. */
const luminance = (c: Rgb): number => 2126 * (LINEAR[c[0]] ?? 0) + 7152 * (LINEAR[c[1]] ?? 0) + 722 * (LINEAR[c[2]] ?? 0);
const FLARE = 5e8;

/** Whether the contrast of a and b is at least num : den. */
export function passes(a: Rgb, b: Rgb, num: number, den: number): boolean {
  const x = luminance(a);
  const y = luminance(b);
  return den * (Math.max(x, y) + FLARE) >= num * (Math.min(x, y) + FLARE);
}

/** The contrast ratio, for showing (the checks use `passes`). */
export function ratio(a: Rgb, b: Rgb): number {
  const x = luminance(a);
  const y = luminance(b);
  return (Math.max(x, y) + FLARE) / (Math.min(x, y) + FLARE);
}

/** c moved k percent of the way to target. */
export const mix = (c: Rgb, target: Rgb, k: number): Rgb => [0, 1, 2].map((i) => Math.floor(((c[i] ?? 0) * (100 - k) + (target[i] ?? 0) * k + 50) / 100)) as unknown as Rgb;

const on = (fill: Rgb): Rgb => (passes(WHITE, fill, 9, 2) ? WHITE : BLACK);

function reach(c: Rgb, toward: Rgb, surface: Rgb, num: number, den: number): readonly [Rgb, number] {
  for (let k = 0; k <= 100; k++) {
    const v = mix(c, toward, k);
    if (passes(v, surface, num, den)) return [v, k];
  }
  return [toward, 100];
}

function glow(fill: Rgb, mode: Mode, from: number): Rgb {
  const background = BACKGROUND[mode];
  const limit = luminance(mix(AZM, background, 55));
  for (let k = from; k <= 100; k++) {
    const g = mix(fill, background, k);
    const l = luminance(g);
    if (mode === 'dark' ? l <= limit : l >= limit) return g;
  }
  return background;
}

/** The values for a picked colour (`#rrggbb`) in one mode. */
export function deriveBrand(hex: string, mode: Mode): BrandValues {
  const picked = toRgb(hex);
  const toward = mode === 'dark' ? WHITE : BLACK;
  const [brand, adjusted] = reach(picked, toward, REFERENCE[mode], 3, 1);
  const [primary] = reach(picked, toward, REFERENCE[mode], 9, 2);
  return {
    brand: toHex(brand),
    onBrand: toHex(on(brand)),
    primary: toHex(primary),
    onPrimary: toHex(on(primary)),
    glowStart: toHex(glow(brand, mode, 55)),
    glowEnd: toHex(glow(brand, mode, 70)),
    adjusted,
  };
}

/** Azm's own colours (not generated): what the app shows without a gym colour. */
export function azmBrand(mode: Mode): BrandValues {
  return mode === 'dark'
    ? { brand: '#22c55e', onBrand: '#04210f', primary: '#22c55e', onPrimary: '#04210f', glowStart: '#136331', glowEnd: '#354a48', adjusted: 0 }
    : { brand: '#22c55e', onBrand: '#04210f', primary: '#15803d', onPrimary: '#ffffff', glowStart: '#92dfae', glowEnd: '#b8c9c8', adjusted: 0 };
}

/** The three readability numbers the settings page shows for one mode. */
export function contrastOf(values: BrandValues, mode: Mode): { readonly fill: number; readonly onFill: number; readonly accent: number } {
  const surface = REFERENCE[mode];
  return { fill: ratio(toRgb(values.brand), surface), onFill: ratio(toRgb(values.onBrand), toRgb(values.brand)), accent: ratio(toRgb(values.primary), surface) };
}

/** Close to the red the app uses for errors and Delete: a note, not a refusal. */
export function nearErrorRed(hex: string): boolean {
  const [r, g, b] = toRgb(hex);
  return r > 150 && r - Math.max(g, b) > 90 && Math.abs(g - b) < 70;
}

/** A ratio as text, rounded down so it never claims more than it has: 4.57 → "4.5". */
export const ratioText = (value: number): string => (Math.floor(value * 10) / 10).toFixed(1);
