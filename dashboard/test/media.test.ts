/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-return */
import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import { MediaRepository, toCatalogPicture, toGymMedia } from '../src/exercises/media';
import { addAll, addPicture, movePicture, pictureBase, pictureUrl, removePicture, sameList, searchWords, togglePicture } from '../src/exercises/pictures';
import { saveFailureKey } from '../src/exercises/useGymMedia';

const GYM = 'b0000000-0000-4000-8000-000000000001';
const pid = (n: number, frame: 'tension' | 'relaxation' = 'tension') => `exercises/ek-${String(n).padStart(4, '0')}-${frame}`;

// ---------------------------------------------------------------- fake ----

interface Call {
  table?: string;
  op: string;
  columns?: string;
  payload?: unknown;
  filters: [string, string, unknown][];
  rpc?: string;
  args?: unknown;
}

type Answer = { data: unknown; error: unknown };

/** A recording stand-in for the parts of SupabaseClient MediaRepository uses. */
function fake(answer: (call: Call, n: number) => Answer = () => ({ data: [], error: null })) {
  const calls: Call[] = [];
  const builder = (call: Call): any => {
    const b: any = {
      select: (columns: string) => ((call.columns = columns), b),
      insert: (payload: unknown) => ((call.op = 'insert'), (call.payload = payload), b),
      update: (payload: unknown) => ((call.op = 'update'), (call.payload = payload), b),
      delete: () => ((call.op = 'delete'), b),
      upsert: (payload: unknown) => ((call.op = 'upsert'), (call.payload = payload), b),
      eq: (c: string, v: unknown) => (call.filters.push(['eq', c, v]), b),
      in: (c: string, v: unknown) => (call.filters.push(['in', c, v]), b),
      overlaps: (c: string, v: unknown) => (call.filters.push(['overlaps', c, v]), b),
      order: (c: string, o?: unknown) => (call.filters.push(['order', c, o ?? null]), b),
      limit: (n: number) => (call.filters.push(['limit', 'rows', n]), b),
      overrideTypes: () => b,
      then: (resolve: (v: Answer) => void) => {
        calls.push(call);
        resolve(answer(call, calls.length));
      },
    };
    return b;
  };
  const client = {
    from: (table: string) => builder({ table, op: 'select', filters: [] }),
    rpc: (name: string, args: unknown) => builder({ op: 'rpc', rpc: name, args, filters: [] }),
  } as unknown as SupabaseClient;
  return { client, calls };
}

// ------------------------------------------------------------- pictures ----

describe('picture rules', () => {
  it('builds URLs only from a library id and a valid cloud name, with fixed transformations', () => {
    expect(pictureUrl('azm-media', pid(55), 'thumb')).toBe('https://res.cloudinary.com/azm-media/image/upload/c_limit,w_160,f_webp,q_auto/exercises/ek-0055-tension.png');
    expect(pictureUrl('azm-media', pid(55), 'large')).toContain('/c_limit,w_640,f_webp,q_auto/');
    expect(pictureUrl(null, pid(55), 'thumb')).toBeNull();
    for (const bad of ['https://evil.example/x.png', 'exercises/../x', 'exercises/EK-1', 'exercises/a b', 'exercises/a%2f', 'other/ek-1', 'exercises/']) {
      expect(pictureUrl('azm-media', bad, 'thumb'), bad).toBeNull();
    }
    for (const cloud of ['Azm', 'azm/x', 'evil.example', '']) expect(pictureBase(cloud), cloud).toBeNull();
  });

  it('makes search words like the app', () => {
    expect(searchWords('  Dumbbell PRESS, press!! صدر ')).toEqual(['dumbbell', 'press', 'صدر']);
    expect(searchWords("'; drop table x; --")).toEqual(['drop', 'table', 'x']);
    expect(searchWords('a b c d e f g')).toEqual(['a', 'b', 'c', 'd', 'e']);
    expect(searchWords('x'.repeat(31))).toEqual([]);
    expect(searchWords('<img src=x>')).toEqual(['img', 'src', 'x']);
    expect(searchWords(42)).toEqual([]);
  });

  it('keeps a list of at most 6 different pictures, cover first', () => {
    let list: readonly string[] = [];
    for (let i = 1; i <= 8; i++) list = addPicture(list, pid(i));
    expect(list).toHaveLength(6);
    expect(addPicture(list.slice(0, 2), pid(1))).toEqual(list.slice(0, 2));
    expect(addPicture([], 'https://evil.example/x')).toEqual([]);
    expect(togglePicture([pid(1)], pid(1))).toEqual([]);
    expect(togglePicture([pid(1)], pid(2))).toEqual([pid(1), pid(2)]);
    expect(removePicture([pid(1), pid(2)], pid(1))).toEqual([pid(2)]);
  });

  it('moves a picture one place; the ends stay put', () => {
    const list = [pid(1), pid(2), pid(3)];
    expect(movePicture(list, pid(3), -1)).toEqual([pid(1), pid(3), pid(2)]);
    expect(movePicture(list, pid(1), 1)).toEqual([pid(2), pid(1), pid(3)]);
    expect(movePicture(list, pid(1), -1)).toBe(list);
    expect(movePicture(list, pid(3), 1)).toBe(list);
    expect(movePicture(list, pid(9), 1)).toBe(list);
  });

  it('adds both frames while there is room', () => {
    expect(addAll([pid(1)], [pid(2, 'tension'), pid(2, 'relaxation')])).toEqual([pid(1), pid(2, 'tension'), pid(2, 'relaxation')]);
    const five = [1, 3, 4, 5, 6].map((n) => pid(n));
    expect(addAll(five, [pid(2, 'tension'), pid(2, 'relaxation')])).toHaveLength(6);
    expect(sameList([pid(1)], [pid(1)])).toBe(true);
    expect(sameList([pid(1), pid(2)], [pid(2), pid(1)])).toBe(false);
  });
});

// ------------------------------------------------------------ reading ----

describe('reading a gym\'s choices', () => {
  it('orders pictures by position and drops rows outside the rules', () => {
    const media = toGymMedia(
      [
        { exercise_id: 'leg_press', public_id: pid(2), position: 2 },
        { exercise_id: 'leg_press', public_id: pid(1), position: 1 },
        { exercise_id: 'leg_press', public_id: pid(1), position: 3 }, // same picture twice
        { exercise_id: 'leg_press', public_id: 'https://evil.example/x.png', position: 4 },
        { exercise_id: 'leg_press', public_id: pid(7), position: 9 },
        { exercise_id: '../etc', public_id: pid(3), position: 1 },
        { exercise_id: 'pec_deck', public_id: pid(4), position: '1' },
      ],
      [
        { exercise_id: 'leg_press', video_id: 'dQw4w9WgXcQ', start_seconds: 15, end_seconds: null },
        { exercise_id: 'pec_deck', video_id: 'javascript:x', start_seconds: null, end_seconds: null },
        { exercise_id: 'abs', video_id: 'dQw4w9WgXcQ', start_seconds: 90, end_seconds: 30 },
      ],
    );
    expect([...media.pictures.entries()]).toEqual([['leg_press', [pid(1), pid(2)]]]);
    expect([...media.videos.entries()]).toEqual([['leg_press', { id: 'dQw4w9WgXcQ', start: 15, end: null }]]);
  });

  it('takes library pictures only when the id, key and frame agree, and cleans titles', () => {
    expect(toCatalogPicture({ public_id: pid(55), exercise_key: 'ek-0055', frame: 'tension', title_en: 'Bench\u202e Press' })).toEqual({ publicId: pid(55), exerciseKey: 'ek-0055', frame: 'tension', title: 'Bench Press' });
    expect(toCatalogPicture({ public_id: pid(55), exercise_key: 'ek-0056', frame: 'tension', title_en: 'x' })).toBeNull();
    expect(toCatalogPicture({ public_id: pid(55), exercise_key: 'ek-0055', frame: 'middle', title_en: 'x' })).toBeNull();
    expect(toCatalogPicture({ public_id: 1, exercise_key: 'ek-0055', frame: 'tension', title_en: 'x' })).toBeNull();
    expect(toCatalogPicture({ public_id: pid(55), exercise_key: 'ek-0055', frame: 'tension', title_en: 'y'.repeat(200) })?.title).toHaveLength(80);
  });

  it('load: explicit columns, the gym filter and the row caps', async () => {
    const { client, calls } = fake((call) => ({ data: call.table === 'gym_exercise_images' ? [{ exercise_id: 'abs', public_id: pid(1), position: 1 }] : [], error: null }));
    const result = await new MediaRepository(client).load(GYM);
    expect(result.ok && result.value.pictures.get('abs')).toEqual([pid(1)]);
    const pics = calls.find((c) => c.table === 'gym_exercise_images');
    expect(pics?.columns).toBe('exercise_id, public_id, position');
    expect(pics?.filters).toContainEqual(['eq', 'gym_id', GYM]);
    expect(pics?.filters).toContainEqual(['limit', 'rows', 1200]);
    const vids = calls.find((c) => c.table === 'gym_exercise_videos');
    expect(vids?.columns).toBe('exercise_id, video_id, start_seconds, end_seconds');
    expect(vids?.filters).toContainEqual(['limit', 'rows', 300]);
  });

  it('load: a crafted gym id never reaches the server', async () => {
    const { client, calls } = fake();
    const result = await new MediaRepository(client).load("x' or 1=1 --");
    expect(result).toEqual({ ok: false, failure: { kind: 'not_found' } });
    expect(calls).toHaveLength(0);
  });

  it('load: a failure becomes a Failure, never a throw', async () => {
    const { client } = fake(() => ({ data: null, error: { code: '42501', message: 'permission denied for table gym_exercise_images' } }));
    expect(await new MediaRepository(client).load(GYM)).toEqual({ ok: false, failure: { kind: 'forbidden' } });
  });
});

describe('searching the picture library', () => {
  it('sends the words as values of the "any word" filter, 60 rows at most', async () => {
    const rows = [
      { public_id: pid(55, 'tension'), exercise_key: 'ek-0055', frame: 'tension', title_en: 'Bench Press' },
      { public_id: 'exercises/../../x', exercise_key: 'ek-0055', frame: 'tension', title_en: 'bad' },
    ];
    const { client, calls } = fake(() => ({ data: rows, error: null }));
    const result = await new MediaRepository(client).search("Bench'; DROP TABLE x;--");
    expect(result.ok && result.value.map((p) => p.publicId)).toEqual([pid(55)]);
    expect(calls[0]?.table).toBe('exercise_images');
    expect(calls[0]?.columns).toBe('public_id, exercise_key, frame, title_en');
    expect(calls[0]?.filters).toContainEqual(['overlaps', 'keywords', ['bench', 'drop', 'table', 'x']]);
    expect(calls[0]?.filters).toContainEqual(['limit', 'rows', 60]);
  });

  it('asks nothing for empty or symbol-only text', async () => {
    const { client, calls } = fake();
    expect(await new MediaRepository(client).search('  ;;; ')).toEqual({ ok: true, value: [] });
    expect(calls).toHaveLength(0);
  });

  it('describe: only library ids, at most 6', async () => {
    const { client, calls } = fake(() => ({ data: [], error: null }));
    await new MediaRepository(client).describe([pid(1), 'https://evil.example', pid(1), ...[2, 3, 4, 5, 6, 7, 8].map((n) => pid(n))]);
    expect(calls[0]?.filters).toContainEqual(['in', 'public_id', [1, 2, 3, 4, 5, 6].map((n) => pid(n))]);
  });
});

// ------------------------------------------------------------ writing ----

describe('saving pictures', () => {
  it('replaces the list in one RPC call, in order', async () => {
    const { client, calls } = fake(() => ({ data: null, error: null }));
    const result = await new MediaRepository(client).savePictures(GYM, 'leg_press', [pid(2), pid(1)]);
    expect(result.ok).toBe(true);
    expect(calls).toEqual([{ op: 'rpc', rpc: 'set_gym_exercise_images', args: { p_gym_id: GYM, p_exercise_id: 'leg_press', p_public_ids: [pid(2), pid(1)] }, filters: [] }]);
  });

  it('an empty list removes them all', async () => {
    const { client, calls } = fake(() => ({ data: null, error: null }));
    await new MediaRepository(client).savePictures(GYM, 'leg_press', []);
    expect((calls[0]?.args as { p_public_ids: unknown }).p_public_ids).toEqual([]);
  });

  it.each([
    ['a 7th picture', GYM, 'leg_press', [1, 2, 3, 4, 5, 6, 7].map((n) => pid(n)), 'conflict'],
    ['the same picture twice', GYM, 'leg_press', [pid(1), pid(1)], 'invalid'],
    ['a URL', GYM, 'leg_press', ['https://evil.example/x.png'], 'invalid'],
    ['a hostile exercise id', GYM, "leg_press'; --", [pid(1)], 'invalid'],
    ['a path as exercise id', GYM, '../plans', [pid(1)], 'invalid'],
    ['a crafted gym id', 'not-a-gym', 'leg_press', [pid(1)], 'invalid'],
  ])('refuses %s before any request', async (_name, gym, exercise, ids, kind) => {
    const { client, calls } = fake();
    const result = await new MediaRepository(client).savePictures(gym, exercise, ids);
    expect(result.ok).toBe(false);
    expect(!result.ok && result.failure.kind).toBe(kind);
    expect(calls).toHaveLength(0);
  });

  it('turns the server\'s refusals into fixed messages', async () => {
    const answers: [unknown, string][] = [
      [{ code: '42501', message: 'forbidden' }, 'media.errForbidden'],
      [{ code: '23514', message: 'too_many_pictures_in_gym' }, 'media.errGymPictures'],
      [{ code: '23514', message: 'too_many_pictures' }, 'pic.full'],
      [{ code: '23503', message: 'insert or update on table violates foreign key constraint' }, 'media.errInvalid'],
      [{ code: '22023', message: 'duplicate_picture' }, 'media.errInvalid'],
      [{ code: 'XX000', message: '<b>internal</b>' }, 'media.errServer'],
      [{ code: 'PGRST301', message: 'JWT expired' }, 'fail.session'],
    ];
    for (const [error, key] of answers) {
      const { client } = fake(() => ({ data: null, error }));
      const result = await new MediaRepository(client).savePictures(GYM, 'leg_press', [pid(1)]);
      expect(result.ok ? null : saveFailureKey(result.failure), JSON.stringify(error)).toBe(key);
    }
  });
});

describe('saving the video', () => {
  const VIDEO = { id: 'dQw4w9WgXcQ', start: 15, end: null };

  it('changes the existing row in place (no upsert, only the updatable columns)', async () => {
    const { client, calls } = fake(() => ({ data: [{ exercise_id: 'leg_press' }], error: null }));
    expect((await new MediaRepository(client).saveVideo(GYM, 'leg_press', VIDEO, true)).ok).toBe(true);
    expect(calls).toHaveLength(1);
    expect(calls[0]?.op).toBe('update');
    expect(calls[0]?.payload).toEqual({ video_id: 'dQw4w9WgXcQ', start_seconds: 15, end_seconds: null });
    expect(calls[0]?.filters).toEqual([['eq', 'gym_id', GYM], ['eq', 'exercise_id', 'leg_press']]);
    expect(calls.some((c) => c.op === 'upsert')).toBe(false);
  });

  it('adds a row when the gym has none', async () => {
    const { client, calls } = fake(() => ({ data: null, error: null }));
    expect((await new MediaRepository(client).saveVideo(GYM, 'leg_press', VIDEO, false)).ok).toBe(true);
    expect(calls.map((c) => c.op)).toEqual(['insert']);
    expect(calls[0]?.payload).toEqual({ gym_id: GYM, exercise_id: 'leg_press', video_id: 'dQw4w9WgXcQ', start_seconds: 15, end_seconds: null });
  });

  it('someone added one meanwhile (23505): changes it instead', async () => {
    const { client, calls } = fake((call) => (call.op === 'insert' ? { data: null, error: { code: '23505', message: 'duplicate key' } } : { data: [{ exercise_id: 'leg_press' }], error: null }));
    expect((await new MediaRepository(client).saveVideo(GYM, 'leg_press', VIDEO, false)).ok).toBe(true);
    expect(calls.map((c) => c.op)).toEqual(['insert', 'update']);
  });

  it('the row went away meanwhile: adds it again', async () => {
    const { client, calls } = fake((call) => ({ data: call.op === 'update' ? [] : null, error: null }));
    expect((await new MediaRepository(client).saveVideo(GYM, 'leg_press', VIDEO, true)).ok).toBe(true);
    expect(calls.map((c) => c.op)).toEqual(['update', 'insert']);
  });

  it('RLS hides the row and refuses the insert: forbidden', async () => {
    const { client } = fake((call) => (call.op === 'insert' ? { data: null, error: { code: '42501', message: 'new row violates row-level security policy' } } : { data: [], error: null }));
    const result = await new MediaRepository(client).saveVideo(GYM, 'leg_press', VIDEO, true);
    expect(!result.ok && result.failure.kind).toBe('forbidden');
  });

  it('the gym has 300 videos', async () => {
    const { client } = fake(() => ({ data: null, error: { code: '23514', message: 'too_many_videos_in_gym' } }));
    const result = await new MediaRepository(client).saveVideo(GYM, 'leg_press', VIDEO, false);
    expect(result.ok ? null : saveFailureKey(result.failure)).toBe('media.errGymVideos');
  });

  it.each([
    ['a URL as id', { id: 'https://youtu.be/dQw4w9WgXcQ', start: null, end: null }],
    ['a short id', { id: 'dQw4w9WgXc', start: null, end: null }],
    ['end before start', { id: 'dQw4w9WgXcQ', start: 90, end: 30 }],
    ['a negative start', { id: 'dQw4w9WgXcQ', start: -1, end: null }],
  ])('refuses %s before any request', async (_name, video) => {
    const { client, calls } = fake();
    expect((await new MediaRepository(client).saveVideo(GYM, 'leg_press', video, false)).ok).toBe(false);
    expect(calls).toHaveLength(0);
  });

  it('removes the gym\'s video of one exercise only', async () => {
    const { client, calls } = fake(() => ({ data: null, error: null }));
    expect((await new MediaRepository(client).removeVideo(GYM, 'leg_press')).ok).toBe(true);
    expect(calls[0]?.op).toBe('delete');
    expect(calls[0]?.filters).toEqual([['eq', 'gym_id', GYM], ['eq', 'exercise_id', 'leg_press']]);
    const crafted = fake();
    expect((await new MediaRepository(crafted.client).removeVideo(GYM, '*')).ok).toBe(false);
    expect(crafted.calls).toHaveLength(0);
  });
});
