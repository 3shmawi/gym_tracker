/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-return */
import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import { checkLogoFile, GymSettingsRepository, LOGO_MAX_BYTES, logoPath, validGymName } from '../src/gyms/settings';

const GYM = 'b0000000-0000-4000-8000-000000000001';
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);
const SVG = new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
const RLO = String.fromCharCode(0x202e);

describe('gym name', () => {
  it('1 to 60 characters, cleaned; hostile text stays text', () => {
    expect(validGymName('  Iron   House ')).toBe('Iron House');
    expect(validGymName('x'.repeat(60))).toBe('x'.repeat(60));
    expect(validGymName('x'.repeat(61))).toBeNull();
    expect(validGymName('💪'.repeat(60))).toBe('💪'.repeat(60));
    expect(validGymName('')).toBeNull();
    expect(validGymName(`${RLO}${String.fromCharCode(0)}  `)).toBeNull();
    expect(validGymName(`Iron${RLO}House`)).toBe('IronHouse');
    expect(validGymName("'; DROP TABLE gyms; --")).toBe("'; DROP TABLE gyms; --");
    expect(validGymName('<img src=x onerror=alert(1)>')).toBe('<img src=x onerror=alert(1)>');
    expect(validGymName(42)).toBeNull();
  });
});

describe('logo file checks (before any request)', () => {
  it('accepts PNG and JPEG by their bytes', () => {
    expect(checkLogoFile({ size: 1000, type: 'image/png' }, PNG)).toEqual({ ok: true, type: 'image/png' });
    expect(checkLogoFile({ size: 1000, type: 'image/jpeg' }, JPEG)).toEqual({ ok: true, type: 'image/jpeg' });
    expect(checkLogoFile({ size: 1000, type: '' }, JPEG)).toEqual({ ok: true, type: 'image/jpeg' });
  });
  it('refuses empty, too big, SVG, renamed files and a lying type', () => {
    expect(checkLogoFile({ size: 0, type: 'image/png' }, new Uint8Array())).toEqual({ ok: false, problem: 'empty' });
    expect(checkLogoFile({ size: LOGO_MAX_BYTES + 1, type: 'image/png' }, PNG)).toEqual({ ok: false, problem: 'too_big' });
    expect(checkLogoFile({ size: 100, type: 'image/svg+xml' }, SVG)).toEqual({ ok: false, problem: 'wrong_type' });
    // An SVG or a script renamed logo.png: the bytes decide.
    expect(checkLogoFile({ size: 100, type: 'image/png' }, SVG)).toEqual({ ok: false, problem: 'wrong_type' });
    // PNG bytes the browser calls JPEG: refused (contradiction).
    expect(checkLogoFile({ size: 100, type: 'image/jpeg' }, PNG)).toEqual({ ok: false, problem: 'wrong_type' });
    expect(checkLogoFile({ size: 100, type: 'image/gif' }, new TextEncoder().encode('GIF89a'))).toEqual({ ok: false, problem: 'wrong_type' });
  });
  it('the object path comes from the gym id and the type only, never the file name', () => {
    expect(logoPath(GYM, 'image/png')).toBe(`${GYM}/logo.png`);
    expect(logoPath(GYM, 'image/jpeg')).toBe(`${GYM}/logo.jpg`);
    for (const bad of ['../other', `${GYM}/x`, '', GYM.toUpperCase()]) expect(logoPath(bad, 'image/png'), bad).toBeNull();
  });
});

interface Call { kind: string; payload?: unknown; filters: [string, unknown][]; path?: string; paths?: string[] }
function fake(rows: unknown[] = [{ id: GYM }]) {
  const calls: Call[] = [];
  const b = (call: Call): any => {
    const x: any = {
      update: (p: unknown) => ((call.payload = p), x),
      eq: (c: string, v: unknown) => (call.filters.push([c, v]), x),
      select: () => x,
      overrideTypes: () => x,
      then: (resolve: (v: unknown) => void) => {
        calls.push(call);
        resolve({ data: rows, error: null });
      },
    };
    return x;
  };
  const storage = {
    from: () => ({
      upload: (path: string) => {
        calls.push({ kind: 'upload', path, filters: [] });
        return Promise.resolve({ data: { path }, error: null });
      },
      remove: (paths: string[]) => {
        calls.push({ kind: 'remove', paths, filters: [] });
        return Promise.resolve({ data: [], error: null });
      },
    }),
  };
  return { client: { from: () => b({ kind: 'update', filters: [] }), storage } as unknown as SupabaseClient, calls };
}

describe('GymSettingsRepository', () => {
  it('renames with the cleaned name only; RLS hiding the row = forbidden', async () => {
    const { client, calls } = fake();
    expect(await new GymSettingsRepository(client).rename(GYM, '  Iron  House ')).toEqual({ ok: true, value: 'Iron House' });
    expect(calls[0]).toMatchObject({ payload: { name: 'Iron House' }, filters: [['id', GYM]] });
    const hidden = fake([]);
    expect(await new GymSettingsRepository(hidden.client).rename(GYM, 'X')).toMatchObject({ ok: false, failure: { kind: 'forbidden' } });
  });

  it('refuses a bad name, a crafted gym id or a bad history value before any request', async () => {
    const { client, calls } = fake();
    const repo = new GymSettingsRepository(client);
    expect((await repo.rename(GYM, 'x'.repeat(61))).ok).toBe(false);
    expect((await repo.rename("x' or 1=1", 'Gym')).ok).toBe(false);
    expect((await repo.setHistory(GYM, 'public')).ok).toBe(false);
    expect(calls).toHaveLength(0);
    expect((await repo.setHistory(GYM, 'locked')).ok).toBe(true);
    expect(calls[0]?.payload).toEqual({ history_after_end: 'locked' });
  });

  it('logo: uploads to <gym>/logo.<type>, points the gym at it, removes the old one', async () => {
    const { client, calls } = fake();
    const r = await new GymSettingsRepository(client).setLogo(GYM, new Blob([PNG]), 'image/png', `${GYM}/logo.jpg`);
    expect(r).toEqual({ ok: true, value: `${GYM}/logo.png` });
    expect(calls.map((c) => c.kind)).toEqual(['upload', 'update', 'remove']);
    expect(calls[2]?.paths).toEqual([`${GYM}/logo.jpg`]);
    // Never another gym's file.
    const other = fake();
    await new GymSettingsRepository(other.client).setLogo(GYM, new Blob([PNG]), 'image/png', 'c0000000-0000-4000-8000-000000000001/logo.png');
    expect(other.calls.map((c) => c.kind)).toEqual(['upload', 'update']);
  });

  it('logo: too big or empty is refused before any request; remove clears the path first', async () => {
    const { client, calls } = fake();
    const repo = new GymSettingsRepository(client);
    expect((await repo.setLogo(GYM, new Blob([new Uint8Array(LOGO_MAX_BYTES + 1)]), 'image/png', null)).ok).toBe(false);
    expect((await repo.setLogo(GYM, new Blob([]), 'image/png', null)).ok).toBe(false);
    expect(calls).toHaveLength(0);
    expect((await repo.removeLogo(GYM, `${GYM}/logo.png`)).ok).toBe(true);
    expect(calls.map((c) => c.kind)).toEqual(['update', 'remove']);
    expect(calls[0]?.payload).toEqual({ logo_path: null });
  });

  it('brand colour: only a valid lower-case colour or null is ever sent, alone', async () => {
    const { client, calls } = fake();
    const repo = new GymSettingsRepository(client);
    expect(await repo.setBrandColor(GYM, '#facc15')).toEqual({ ok: true, value: '#facc15' });
    expect(calls[0]).toMatchObject({ payload: { brand_color: '#facc15' }, filters: [['id', GYM]] });
    expect(Object.keys(calls[0]?.payload as object)).toEqual(['brand_color']);
    expect(await repo.setBrandColor(GYM, null)).toEqual({ ok: true, value: null });
    expect(calls[1]?.payload).toEqual({ brand_color: null });
  });

  it('brand colour: hostile values and a crafted gym id are refused before any request', async () => {
    const { client, calls } = fake();
    const repo = new GymSettingsRepository(client);
    for (const bad of ['#FACC15', '#fff', 'red', '#808080', '#000000', '', ' #facc15', "#facc15'; drop table gyms;--", '<script>', '#facc15'.repeat(100000), '{"brand_color":"#facc15","is_demo":true}']) {
      expect((await repo.setBrandColor(GYM, bad)).ok, bad.slice(0, 30)).toBe(false);
    }
    expect((await repo.setBrandColor("x' or 1=1", '#facc15')).ok).toBe(false);
    expect((await repo.setBrandColor('c0000000-0000-4000-8000-00000000000Z', null)).ok).toBe(false);
    expect(calls).toHaveLength(0);
  });

  it('brand colour: RLS hiding the row (a captain, another gym) = forbidden', async () => {
    const hidden = fake([]);
    expect(await new GymSettingsRepository(hidden.client).setBrandColor(GYM, '#facc15')).toMatchObject({ ok: false, failure: { kind: 'forbidden' } });
  });
});
