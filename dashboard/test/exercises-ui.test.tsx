import type { ComponentChildren } from 'preact';
import { render } from 'preact';
import { act } from 'preact/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Failure } from '../src/core/failure';
import type { Lang } from '../src/core/prefs';
import { failed, ok } from '../src/core/result';
import type { MediaRepository } from '../src/exercises/media';
import type { CatalogPicture, ExerciseLike, GymMedia, VideoRef } from '../src/exercises/types';
import type { ManagedGym } from '../src/gyms/gyms';
import { I18nContext, makeI18n, translate, type MessageKey } from '../src/i18n';
import { ExercisePage } from '../src/pages/ExercisePage';
import { ExercisesPage } from '../src/pages/ExercisesPage';

const GYM_ID = 'b0000000-0000-4000-8000-000000000001';
const gym: ManagedGym = { id: GYM_ID, name: 'Power Gym', role: 'captain', logoPath: null, historyAfterEnd: 'readable', brandColor: null, memberCount: 5 };
const pid = (n: number, frame: 'tension' | 'relaxation' = 'tension') => `exercises/ek-${String(n).padStart(4, '0')}-${frame}`;
const pic = (n: number, frame: 'tension' | 'relaxation', title: string): CatalogPicture => ({ publicId: pid(n, frame), exerciseKey: `ek-${String(n).padStart(4, '0')}`, frame, title });
const en = (key: MessageKey, params?: Record<string, string | number>) => translate('en', key, params);

const CATALOG: CatalogPicture[] = [
  pic(55, 'tension', 'Dumbbell Bench Press'),
  pic(55, 'relaxation', 'Dumbbell Bench Press'),
  pic(56, 'tension', 'Incline Dumbbell Press'),
  pic(56, 'relaxation', 'Incline Dumbbell Press'),
];

function gymMedia(pictures: [string, string[]][] = [], videos: [string, VideoRef][] = []): GymMedia {
  return { pictures: new Map(pictures), videos: new Map(videos) };
}

function fakeRepo(media: GymMedia = gymMedia(), over: Record<string, unknown> = {}) {
  const repo = {
    load: vi.fn(() => Promise.resolve(ok(media))),
    search: vi.fn(() => Promise.resolve(ok(CATALOG))),
    describe: vi.fn((ids: string[]) => Promise.resolve(ok(CATALOG.filter((p) => ids.includes(p.publicId))))),
    savePictures: vi.fn(() => Promise.resolve(ok(undefined))),
    saveVideo: vi.fn(() => Promise.resolve(ok(undefined))),
    removeVideo: vi.fn(() => Promise.resolve(ok(undefined))),
    customExercises: vi.fn(() => Promise.resolve(ok([]))),
    ...over,
  };
  return { ...repo, repo: repo as unknown as MediaRepository };
}

let host: HTMLElement;
beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
});
afterEach(async () => {
  await act(() => {
    render(null, host);
  });
  host.remove();
  vi.restoreAllMocks();
});

const flush = () => act(async () => { await Promise.resolve(); await Promise.resolve(); });
async function mount(node: ComponentChildren, lang: Lang = 'en') {
  await act(() => {
    render(<I18nContext.Provider value={makeI18n(lang)}>{node}</I18nContext.Provider>, host);
  });
  await flush();
}
const all = (selector: string) => [...host.querySelectorAll<HTMLElement>(selector)];
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
function m<T extends Element>(selector: string): T {
  const el = host.querySelector<T>(selector);
  if (!el) throw new Error(`missing ${selector}`);
  return el;
}
function byLabel(label: string): HTMLButtonElement {
  const found = [...host.querySelectorAll('button')].find((b) => b.getAttribute('aria-label') === label || b.textContent.trim() === label);
  if (!found) throw new Error(`no button ${label}`);
  return found;
}
async function click(el: Element) {
  await act(() => { (el as HTMLElement).click(); });
  await flush();
}
async function type(el: HTMLInputElement, value: string) {
  await act(() => {
    el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
async function submit(form: HTMLFormElement) {
  await act(() => { form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
  await flush();
}
const chosen = () => all('.pic-card').map((el) => el.dataset.pic);

// ---------------------------------------------------------------- list ----

describe('ExercisesPage', () => {
  it('lists all 36 library exercises with their state', async () => {
    const f = fakeRepo(gymMedia([['flat_db_press', [pid(55), pid(55, 'relaxation')]]], [['leg_press', { id: 'dQw4w9WgXcQ', start: null, end: null }]]));
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    expect(all('.ex-row')).toHaveLength(36);
    expect(host.textContent).toContain(en('ex.summary', { shown: 36, total: 36, pictures: 1, videos: 1 }));
    const press = all('.ex-row').find((r) => r.textContent.includes('Flat Dumbbell Press'));
    expect(press?.textContent).toContain(en('ex.picsMany', { count: 2 }));
    expect(press?.textContent).toContain(en('ex.videoLibrary'));
    expect(press?.getAttribute('href')).toBe(`/g/${GYM_ID}/exercises/flat_db_press`);
    const leg = all('.ex-row').find((r) => r.textContent.includes('Leg Press'));
    expect(leg?.textContent).toContain(en('ex.videoYours'));
    // The 13 new exercises of days 4 and 5 have no library video.
    expect(all('.ex-row').filter((r) => r.textContent.includes(en('ex.videoNone')))).toHaveLength(13);
  });

  it('searches in English and Arabic, and says when nothing matches', async () => {
    const f = fakeRepo();
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    const input = m<HTMLInputElement>('#exercise-search');
    await type(input, 'press');
    expect(all('.ex-row').every((r) => /press/i.test(r.textContent))).toBe(true);
    await type(input, 'اسكوات');
    expect(all('.ex-row').map((r) => r.textContent)).toEqual([expect.stringContaining('Barbell Back Squat')]);
    await type(input, '<img src=x onerror=alert(1)>');
    expect(all('.ex-row')).toHaveLength(0);
    expect(host.querySelector('img')).toBeNull();
    expect(host.textContent).toContain(en('ex.noMatchTitle', { query: '<img src=x onerror=alert(1)>' }));
    await click(byLabel(en('ex.clearSearch')));
    expect(all('.ex-row')).toHaveLength(36);
  });

  it('filters by "has your media" and "no video", with an empty state', async () => {
    const f = fakeRepo(gymMedia([['abs', [pid(1)]]]));
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    await click(byLabel(`${en('ex.tabMine')} 1`));
    expect(all('.ex-row')).toHaveLength(1);
    await click(byLabel(`${en('ex.tabNoVideo')} 13`));
    expect(all('.ex-row')).toHaveLength(13);
    const g = fakeRepo();
    await act(() => { render(null, host); });
    await mount(<ExercisesPage gym={gym} media={g.repo} cloudName={null} />);
    await click(byLabel(`${en('ex.tabMine')} 0`));
    expect(host.textContent).toContain(en('ex.noneHereTitle'));
  });

  it('shows the error with retry, then the list', async () => {
    const load = vi.fn().mockResolvedValueOnce(failed({ kind: 'server' })).mockResolvedValue(ok(gymMedia()));
    const f = fakeRepo(gymMedia(), { load });
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    expect(host.textContent).toContain(en('state.errorTitle'));
    await click(byLabel(en('state.retry')));
    expect(all('.ex-row')).toHaveLength(36);
  });

  it('shows covers from the picture CDN only when a cloud name is set', async () => {
    const f = fakeRepo(gymMedia([['abs', [pid(1)]]]));
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName="azm-media" />);
    const imgs = all('img');
    expect(imgs).toHaveLength(1);
    expect(imgs[0]?.getAttribute('src')).toBe('https://res.cloudinary.com/azm-media/image/upload/c_limit,w_160,f_webp,q_auto/exercises/ek-0001-tension.png');
    expect(imgs[0]?.getAttribute('referrerpolicy')).toBe('no-referrer');
  });

  it('works in Arabic: Arabic name first, English second', async () => {
    const f = fakeRepo();
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />, 'ar');
    const first = all('.ex-row')[0];
    expect(first?.querySelector('b')?.textContent).toBe('دفع دمبل مستوي');
    expect(first?.querySelector('[lang="en"]')?.textContent).toBe('Flat Dumbbell Press');
  });
});

// ------------------------------------------------------------ one page ----

const OWN: ExerciseLike = { id: 'ex-lq3k9a', en: 'Testt', ar: 'تيست', muscle: null, libraryVideo: false, custom: true };

describe('exercises written into plans', () => {
  it('are listed after the library, marked, and open to pictures and video', async () => {
    const f = fakeRepo(gymMedia(), { customExercises: vi.fn(() => Promise.resolve(ok([OWN]))) });
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    const rows = all('.ex-row');
    expect(rows).toHaveLength(37);
    const own = rows.find((r) => r.textContent.includes('Testt'));
    expect(own?.getAttribute('href')).toBe(`/g/${GYM_ID}/exercises/ex-lq3k9a`);
    expect(own?.textContent).toContain(en('plan.ownExercise'));
    expect(own?.textContent).toContain(en('ex.videoNone'));
    expect(host.textContent).toContain(en('ex.summary', { shown: 37, total: 37, pictures: 0, videos: 0 }));
  });

  it('are found by search in both languages', async () => {
    const f = fakeRepo(gymMedia(), { customExercises: vi.fn(() => Promise.resolve(ok([OWN]))) });
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    await type(m<HTMLInputElement>('#exercise-search'), 'تيست');
    expect(all('.ex-row')).toHaveLength(1);
  });

  it('a failed read leaves the library list as it was', async () => {
    const f = fakeRepo(gymMedia(), { customExercises: vi.fn(() => Promise.resolve(failed({ kind: 'offline' }))) });
    await mount(<ExercisesPage gym={gym} media={f.repo} cloudName={null} />);
    expect(all('.ex-row')).toHaveLength(36);
  });

  it('the page of one saves pictures under its own id', async () => {
    const f = fakeRepo(gymMedia(), { customExercises: vi.fn(() => Promise.resolve(ok([OWN]))) });
    await mount(<ExercisePage gym={gym} exerciseId="ex-lq3k9a" media={f.repo} cloudName={null} online />);
    expect(m('h1').textContent).toBe('Testt');
    await submit(m<HTMLFormElement>('form[role="search"]'));
    await click(byLabel(en('pic.addBothLabel', { name: 'Dumbbell Bench Press' })));
    await click(byLabel(en('pic.save')));
    expect(f.savePictures).toHaveBeenCalledWith(GYM_ID, 'ex-lq3k9a', [pid(55), pid(55, 'relaxation')]);
  });

  it('an unknown plan id with no media is not found; one with media opens by its id', async () => {
    const none = fakeRepo(gymMedia());
    await mount(<ExercisePage gym={gym} exerciseId="ex-zzzz" media={none.repo} cloudName={null} online />);
    expect(host.textContent).not.toContain('ex-zzzz');
    const has = fakeRepo(gymMedia([['ex-zzzz', [pid(55)]]]));
    await mount(<ExercisePage gym={gym} exerciseId="ex-zzzz" media={has.repo} cloudName={null} online />);
    expect(m('h1').textContent).toBe('ex-zzzz');
  });
});

describe('ExercisePage: pictures', () => {
  it('searches, adds both frames, reorders, sets the cover and saves the list in order', async () => {
    const f = fakeRepo();
    await mount(<ExercisePage gym={gym} exerciseId="flat_db_press" media={f.repo} cloudName={null} online />);
    expect(host.textContent).toContain(en('pic.emptyTitle'));
    // The search starts with the exercise's English name.
    expect(m<HTMLInputElement>('#pic-search').value).toBe('Flat Dumbbell Press');
    await submit(m<HTMLFormElement>('form[role="search"]'));
    expect(f.search).toHaveBeenCalledWith('Flat Dumbbell Press');
    await click(byLabel(en('pic.addBothLabel', { name: 'Dumbbell Bench Press' })));
    await click(byLabel(en('pic.frame', { frame: en('pic.end'), name: 'Incline Dumbbell Press' })));
    expect(chosen()).toEqual([pid(55), pid(55, 'relaxation'), pid(56, 'relaxation')]);
    expect(host.textContent).toContain(en('pic.unsaved'));
    expect(all('.pic-badge')[0]?.textContent).toBe(en('pic.cover'));

    const name = `Incline Dumbbell Press · ${en('pic.end')}`;
    await click(byLabel(en('pic.earlier', { name })));
    await click(byLabel(en('pic.earlier', { name })));
    expect(chosen()).toEqual([pid(56, 'relaxation'), pid(55), pid(55, 'relaxation')]);
    expect(byLabel(en('pic.earlier', { name })).disabled).toBe(true);

    await click(byLabel(en('pic.save')));
    expect(f.savePictures).toHaveBeenCalledWith(GYM_ID, 'flat_db_press', [pid(56, 'relaxation'), pid(55), pid(55, 'relaxation')]);
    expect(host.textContent).toContain(en('pic.saved'));
    expect(byLabel(en('pic.save')).disabled).toBe(true);
  });

  it('stops at 6 pictures and says so', async () => {
    const six = [1, 2, 3, 4, 5, 6].map((n) => pid(n));
    const f = fakeRepo(gymMedia([['abs', six]]));
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />);
    expect(host.textContent).toContain(en('pic.full', { max: 6 }));
    await submit(m<HTMLFormElement>('form[role="search"]'));
    for (const b of all('.res-frame')) expect((b as HTMLButtonElement).disabled).toBe(true);
  });

  it('removes one, removes all, and undo brings the saved list back', async () => {
    const f = fakeRepo(gymMedia([['flat_db_press', [pid(55), pid(55, 'relaxation')]]]));
    await mount(<ExercisePage gym={gym} exerciseId="flat_db_press" media={f.repo} cloudName={null} online />);
    expect(chosen()).toEqual([pid(55), pid(55, 'relaxation')]);
    await click(byLabel(en('pic.remove', { name: `Dumbbell Bench Press · ${en('pic.start')}` })));
    expect(chosen()).toEqual([pid(55, 'relaxation')]);
    await click(byLabel(en('pic.removeAll')));
    expect(chosen()).toEqual([]);
    await click(byLabel(en('pic.undo')));
    expect(chosen()).toEqual([pid(55), pid(55, 'relaxation')]);
  });

  it('a refused save keeps the draft and shows a fixed message, never the server text', async () => {
    const savePictures = vi.fn(() => Promise.resolve(failed({ kind: 'conflict', reason: 'too_many_pictures_in_gym' })));
    const f = fakeRepo(gymMedia(), { savePictures });
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />);
    await submit(m<HTMLFormElement>('form[role="search"]'));
    await click(byLabel(en('pic.frame', { frame: en('pic.start'), name: 'Dumbbell Bench Press' })));
    await click(byLabel(en('pic.save')));
    expect(m('[role="alert"]').textContent).toContain(en('media.errGymPictures'));
    expect(chosen()).toEqual([pid(55)]);
  });

  it('search: failed with retry, offline, nothing found', async () => {
    const search = vi.fn().mockResolvedValueOnce(failed({ kind: 'server' })).mockResolvedValueOnce(ok([]));
    const f = fakeRepo(gymMedia(), { search });
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />);
    await type(m<HTMLInputElement>('#pic-search'), 'zzz');
    await submit(m<HTMLFormElement>('form[role="search"]'));
    expect(m('[role="alert"]').textContent).toContain(en('pic.searchFailed'));
    await click(byLabel(en('state.retry')));
    expect(host.textContent).toContain(en('pic.searchNone', { query: 'zzz' }));

    await act(() => { render(null, host); });
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online={false} />);
    expect(host.textContent).toContain(en('pic.searchOffline'));
    expect(byLabel(en('pic.save')).disabled).toBe(true);
    expect(byLabel(en('vid.save')).disabled).toBe(true);
  });
});

describe('ExercisePage: video', () => {
  it('takes a pasted link, shows the id, saves only the id', async () => {
    const f = fakeRepo();
    await mount(<ExercisePage gym={gym} exerciseId="smith_shrug" media={f.repo} cloudName={null} online />);
    expect(host.textContent).toContain(en('vid.none'));
    const input = m<HTMLInputElement>('#vid-link');
    await type(input, '  https://youtu.be/dQw4w9WgXcQ?si=abc&t=1m30s  ');
    expect(host.textContent).toContain(en('vid.ok', { id: 'dQw4w9WgXcQ' }));
    expect(host.textContent).toContain(en('vid.startsAt', { time: '1:30' }));
    await click(byLabel(en('vid.save')));
    expect(f.saveVideo).toHaveBeenCalledWith(GYM_ID, 'smith_shrug', { id: 'dQw4w9WgXcQ', start: 90, end: null }, false);
    expect(host.textContent).toContain(en('vid.saved'));
    expect(host.textContent).toContain(en('vid.yours'));
    const open = m<HTMLAnchorElement>('a[target="_blank"]');
    expect(open.getAttribute('href')).toBe('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90');
    expect(open.getAttribute('rel')).toBe('noopener noreferrer');
  });

  it.each([
    'javascript:alert(1)',
    'https://www.youtube.com/live/dQw4w9WgXcQ',
    'https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ',
    'https://www.youtube.com/watch?v=dQw4w9WgX%63Q',
    '"><img src=x onerror=alert(1)>',
  ])('refuses %s: marked invalid, nothing can be saved', async (link) => {
    const f = fakeRepo();
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />);
    const input = m<HTMLInputElement>('#vid-link');
    await type(input, link);
    expect(input.getAttribute('aria-invalid')).toBe('true');
    expect(host.textContent).toContain(en('vid.bad'));
    expect(byLabel(en('vid.save')).disabled).toBe(true);
    expect(host.querySelector('img')).toBeNull();
    expect(f.saveVideo).not.toHaveBeenCalled();
  });

  it('the same video again cannot be saved; removing goes back to the library video', async () => {
    const f = fakeRepo(gymMedia([], [['abs', { id: 'dQw4w9WgXcQ', start: null, end: null }]]));
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />);
    await type(m<HTMLInputElement>('#vid-link'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(host.textContent).toContain(en('vid.same'));
    expect(byLabel(en('vid.save')).disabled).toBe(true);
    await click(byLabel(en('vid.remove')));
    expect(f.removeVideo).toHaveBeenCalledWith(GYM_ID, 'abs');
    expect(host.textContent).toContain(en('vid.removed'));
    expect(host.textContent).toContain(en('vid.library'));
  });

  it('a refused video save shows the fixed message', async () => {
    const saveVideo = vi.fn(() => Promise.resolve(failed({ kind: 'forbidden' })));
    const f = fakeRepo(gymMedia(), { saveVideo });
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />);
    await type(m<HTMLInputElement>('#vid-link'), 'https://youtu.be/dQw4w9WgXcQ');
    await click(byLabel(en('vid.save')));
    expect(m('[role="alert"]').textContent).toContain(en('media.errForbidden'));
  });

  it('works in Arabic (RTL text from the same keys)', async () => {
    const f = fakeRepo();
    await mount(<ExercisePage gym={gym} exerciseId="abs" media={f.repo} cloudName={null} online />, 'ar');
    expect(m('h1').textContent).toBe('بطن');
    expect(host.textContent).toContain(translate('ar', 'vid.title'));
    expect(m<HTMLInputElement>('#vid-link').getAttribute('dir')).toBe('ltr');
  });
});

describe('save failure messages', () => {
  it('are fixed keys of both languages', async () => {
    const { saveFailureKey } = await import('../src/exercises/useGymMedia');
    const kinds: Failure[] = [{ kind: 'offline' }, { kind: 'forbidden' }, { kind: 'session_ended' }, { kind: 'rate_limited' }, { kind: 'conflict' }, { kind: 'conflict', reason: 'too_many_videos_in_gym' }, { kind: 'invalid' }, { kind: 'server' }];
    for (const k of kinds) {
      const key = saveFailureKey(k);
      expect(translate('en', key)).not.toBe(key);
      expect(translate('ar', key)).not.toBe(key);
    }
  });
});
