import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { linkHandler, navigate, pathOf, type Route } from '../app/router';
import { cleanName } from '../core/text';
import { libraryExercise } from '../exercises/catalog';
import type { MediaRepository } from '../exercises/media';
import { addAll, MAX_PICTURES, movePicture, removePicture, sameList, searchWords, togglePicture } from '../exercises/pictures';
import type { CatalogPicture, LibraryExercise, VideoRef } from '../exercises/types';
import { saveFailureKey, useGymMedia } from '../exercises/useGymMedia';
import { formatSeconds, parseYouTubeLink, watchUrl } from '../exercises/youtube';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n, type MessageKey } from '../i18n';
import { Icon } from '../ui/icons';
import { Picture } from '../ui/Picture';
import { ErrorView, LoadingView, NotFoundView } from '../ui/states';
import { exerciseNames } from './ExercisesPage';
import { useLeaveWarning } from './useMembersList';

// The box holds more than the parser accepts (2048), so a longer paste is refused, not cut.
const LINK_MAX = 4096;
const SEARCH_MAX = 120;

interface Props {
  readonly gym: ManagedGym;
  readonly exerciseId: string;
  readonly media: MediaRepository;
  readonly cloudName: string | null;
  readonly online: boolean;
}

type Note = { readonly tone: 'ok' | 'err'; readonly key: MessageKey } | null;

export function ExercisePage({ gym, exerciseId, media, cloudName, online }: Props) {
  const { t } = useI18n();
  const exercise = libraryExercise(exerciseId);
  const { data, reload, applyPictures, applyVideo } = useGymMedia(media, gym.id);
  const back: Route = { name: 'exercises', gymId: gym.id };

  if (!exercise) return <NotFoundView onHome={() => { navigate(back); }} />;

  const backLink = (
    <a class="btn ghost sm back" href={pathOf(back)} onClick={linkHandler(back)}>
      <span class="flip" aria-hidden="true"><Icon name="chevronLeft" /></span>
      {t('ex.back')}
    </a>
  );
  if (data.state !== 'ready') {
    return (
      <section class="stack" data-gym={gym.id}>
        {backLink}
        <Heading exercise={exercise} />
        {data.state === 'loading' ? <LoadingView /> : <ErrorView failure={data.failure} onRetry={() => void reload()} />}
      </section>
    );
  }

  const saved = data.media.pictures.get(exercise.id) ?? [];
  const video = data.media.videos.get(exercise.id) ?? null;
  return (
    <section class="stack" data-gym={gym.id}>
      {backLink}
      <Heading exercise={exercise} />
      <PicturesPanel
        key={`p-${exercise.id}`}
        gymId={gym.id}
        exercise={exercise}
        saved={saved}
        media={media}
        cloudName={cloudName}
        online={online}
        onSaved={(list) => { applyPictures(exercise.id, list); }}
      />
      <VideoPanel
        key={`v-${exercise.id}`}
        gymId={gym.id}
        exercise={exercise}
        video={video}
        media={media}
        online={online}
        onSaved={(v) => { applyVideo(exercise.id, v); }}
      />
    </section>
  );
}

function Heading({ exercise }: { readonly exercise: LibraryExercise }) {
  const { t, lang } = useI18n();
  const names = exerciseNames(lang, exercise);
  return (
    <div class="stack-sm">
      <h1 class="h1">{names.primary}</h1>
      <p class="sub">
        <span lang={names.secondaryLang}>{names.secondary}</span>
        {' · '}
        {t(`ex.muscle.${exercise.muscle}`)}
        {' · '}
        <span class="num">{exercise.id}</span>
      </p>
    </div>
  );
}

// ------------------------------------------------------------- pictures ----

type Search =
  | { readonly state: 'idle' }
  | { readonly state: 'searching'; readonly query: string }
  | { readonly state: 'done'; readonly query: string; readonly results: readonly CatalogPicture[] }
  | { readonly state: 'failed'; readonly query: string; readonly offline: boolean };

interface PicturesProps {
  readonly gymId: string;
  readonly exercise: LibraryExercise;
  readonly saved: readonly string[];
  readonly media: MediaRepository;
  readonly cloudName: string | null;
  readonly online: boolean;
  readonly onSaved: (list: readonly string[]) => void;
}

function PicturesPanel({ gymId, exercise, saved, media, cloudName, online, onSaved }: PicturesProps) {
  const { t } = useI18n();
  const [draft, setDraft] = useState<readonly string[]>(saved);
  const [titles, setTitles] = useState<ReadonlyMap<string, CatalogPicture>>(new Map());
  const [saving, setSaving] = useState(false);
  const [note, setNote] = useState<Note>(null);
  const [search, setSearch] = useState<Search>({ state: 'idle' });
  const [query, setQuery] = useState(exercise.en);
  const [focus, setFocus] = useState<{ id: string; action: 'earlier' | 'later' } | null>(null);
  const listRef = useRef<HTMLOListElement>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const searchToken = useRef(0);

  const dirty = !sameList(draft, saved);
  useLeaveWarning(dirty, t('ex.leave'));

  // Titles of the saved pictures (for their names); search results add theirs.
  useEffect(() => {
    let alive = true;
    void media.describe(saved).then((result) => {
      if (!alive || !result.ok) return;
      setTitles((old) => {
        const next = new Map(old);
        for (const p of result.value) next.set(p.publicId, p);
        return next;
      });
    });
    return () => {
      alive = false;
    };
  }, [media, saved]);

  // Keep keyboard focus on the moved picture's button.
  useEffect(() => {
    if (!focus || !listRef.current) return;
    const item = [...listRef.current.querySelectorAll<HTMLElement>('[data-pic]')].find((el) => el.dataset.pic === focus.id);
    const wanted = item?.querySelector<HTMLButtonElement>(`[data-act="${focus.action}"]`);
    const other = item?.querySelector<HTMLButtonElement>(`[data-act="${focus.action === 'earlier' ? 'later' : 'earlier'}"]`);
    (wanted && !wanted.disabled ? wanted : other)?.focus();
    setFocus(null);
  }, [focus, draft]);

  const nameOf = (id: string) => {
    const p = titles.get(id);
    if (!p) return id.replace(/^exercises\//, '');
    return `${p.title} · ${p.frame === 'tension' ? t('pic.start') : t('pic.end')}`;
  };

  const change = (next: readonly string[]) => {
    setDraft(next);
    setNote(null);
  };

  const runSearch = async () => {
    const words = searchWords(query);
    if (words.length === 0) {
      setSearch({ state: 'idle' });
      return;
    }
    const mine = ++searchToken.current;
    const shown = cleanName(query);
    setSearch({ state: 'searching', query: shown });
    const result = await media.search(query);
    if (mine !== searchToken.current) return;
    if (!result.ok) {
      setSearch({ state: 'failed', query: shown, offline: result.failure.kind === 'offline' });
      return;
    }
    setTitles((old) => {
      const next = new Map(old);
      for (const p of result.value) next.set(p.publicId, p);
      return next;
    });
    setSearch({ state: 'done', query: shown, results: result.value });
  };

  const save = async () => {
    setSaving(true);
    setNote(null);
    const list = draft;
    const result = await media.savePictures(gymId, exercise.id, list);
    setSaving(false);
    if (result.ok) {
      onSaved(list);
      setNote({ tone: 'ok', key: 'pic.saved' });
    } else {
      setNote({ tone: 'err', key: saveFailureKey(result.failure) });
    }
  };

  const full = draft.length >= MAX_PICTURES;

  return (
    <section class="panel" aria-labelledby="pics-title">
      <div class="row-between">
        <h2 class="h2" id="pics-title" ref={headingRef} tabIndex={-1}>
          {t('pic.title')} <span class="cap num">{t('pic.count', { count: draft.length, max: MAX_PICTURES })}</span>
        </h2>
        <div class="acts-row">
          {dirty ? (
            <button type="button" class="btn sm ghost" onClick={() => { change(saved); }} disabled={saving}>{t('pic.undo')}</button>
          ) : null}
          {draft.length > 0 ? (
            <button type="button" class="btn sm danger" onClick={() => { change([]); headingRef.current?.focus(); }} disabled={saving}>{t('pic.removeAll')}</button>
          ) : null}
          <button type="button" class="btn pri sm" onClick={() => void save()} disabled={!dirty || saving || !online} aria-describedby={!online ? 'pics-offline' : undefined}>
            {saving ? t('pic.saving') : t('pic.save')}
          </button>
        </div>
      </div>
      <p class="cap">{t('pic.hint')}</p>
      {!online ? <p class="cap" id="pics-offline">{t('pic.offlineHint')}</p> : null}

      {draft.length === 0 ? (
        <div class="drop pic-empty">
          <b>{t('pic.emptyTitle')}</b>
          <span class="cap">{t('pic.emptyBody', { max: MAX_PICTURES })}</span>
        </div>
      ) : (
        <ol class="pic-grid" ref={listRef} aria-label={t('pic.title')}>
          {draft.map((id, i) => {
            const name = nameOf(id);
            return (
              <li key={id} class="pic-card" data-pic={id}>
                <div class="pic-frame">
                  <Picture cloudName={cloudName} publicId={id} size="large" alt={t('pic.position', { n: i + 1, count: draft.length, name })} />
                  <span class={`badge pic-badge${i === 0 ? ' cover' : ''}`} aria-hidden="true">{i === 0 ? t('pic.cover') : <span class="num">{i + 1}</span>}</span>
                </div>
                <span class="cap plain-text">{name}</span>
                <div class="acts-row">
                  <button type="button" class="ib" data-act="earlier" aria-label={t('pic.earlier', { name })} disabled={i === 0 || saving} onClick={() => { change(movePicture(draft, id, -1)); setFocus({ id, action: 'earlier' }); }}>
                    <span class="flip"><Icon name="chevronLeft" /></span>
                  </button>
                  <button type="button" class="ib" data-act="later" aria-label={t('pic.later', { name })} disabled={i === draft.length - 1 || saving} onClick={() => { change(movePicture(draft, id, 1)); setFocus({ id, action: 'later' }); }}>
                    <span class="flip"><Icon name="chevronRight" /></span>
                  </button>
                  <span class="sp" />
                  <button type="button" class="ib danger" aria-label={t('pic.remove', { name })} disabled={saving} onClick={() => { change(removePicture(draft, id)); headingRef.current?.focus(); }}>
                    <Icon name="close" />
                  </button>
                </div>
              </li>
            );
          })}
        </ol>
      )}

      {full ? (
        <div class="banner off" role="status">
          <Icon name="info" />
          <span>{t('pic.full', { max: MAX_PICTURES })}</span>
        </div>
      ) : null}
      {dirty && !note ? <p class="live" role="status">{t('pic.unsaved')}</p> : null}
      <div class="live-slot" role={note?.tone === 'err' ? 'alert' : 'status'}>
        {note ? (
          <div class={`banner ${note.tone === 'ok' ? 'ok' : 'err'}`}>
            <Icon name={note.tone === 'ok' ? 'check' : 'alert'} />
            <span>{t(note.key, { max: MAX_PICTURES })}</span>
          </div>
        ) : null}
      </div>

      <div class="pic-search stack-sm">
        <h3 class="h3">{t('pic.searchTitle')}</h3>
        <form
          role="search"
          class="toolbar"
          onSubmit={(event) => {
            event.preventDefault();
            void runSearch();
          }}
        >
          <div class="field grow">
            <label for="pic-search">{t('pic.searchLabel')}</label>
            <input id="pic-search" class="in" type="search" maxLength={SEARCH_MAX} value={query} onInput={(event) => { setQuery(event.currentTarget.value); }} />
          </div>
          <button type="submit" class="btn self-end" disabled={!online || search.state === 'searching'}>
            <Icon name="search" />
            {t('pic.searchGo')}
          </button>
        </form>
        <SearchResults
          search={search}
          online={online}
          draft={draft}
          cloudName={cloudName}
          onToggle={(id) => { change(togglePicture(draft, id)); }}
          onAddAll={(ids) => { change(addAll(draft, ids)); }}
          onRetry={() => void runSearch()}
        />
        {cloudName ? <p class="cap">{t('ex.credit')}</p> : null}
      </div>
    </section>
  );
}

interface ResultsProps {
  readonly search: Search;
  readonly online: boolean;
  readonly draft: readonly string[];
  readonly cloudName: string | null;
  readonly onToggle: (publicId: string) => void;
  readonly onAddAll: (publicIds: readonly string[]) => void;
  readonly onRetry: () => void;
}

function SearchResults({ search, online, draft, cloudName, onToggle, onAddAll, onRetry }: ResultsProps) {
  const { t } = useI18n();
  const groups = useMemo(() => {
    if (search.state !== 'done') return [];
    const byKey = new Map<string, CatalogPicture[]>();
    for (const p of search.results) {
      const list = byKey.get(p.exerciseKey) ?? [];
      list.push(p);
      byKey.set(p.exerciseKey, list);
    }
    // tension (start) before relaxation (end)
    return [...byKey.values()].map((list) => [...list].sort((a, b) => (a.frame === b.frame ? 0 : a.frame === 'tension' ? -1 : 1)));
  }, [search]);

  if (!online && search.state !== 'done') return <p class="cap" role="status">{t('pic.searchOffline')}</p>;
  switch (search.state) {
    case 'idle':
      return <p class="cap">{t('pic.searchIdle')}</p>;
    case 'searching':
      return <p class="cap" role="status" aria-busy="true">{t('pic.searching')}</p>;
    case 'failed':
      return (
        <div class="banner err" role="alert">
          <Icon name="alert" />
          <span>{search.offline ? t('pic.searchOffline') : t('pic.searchFailed')}</span>
          <button type="button" class="btn sm" onClick={onRetry}>{t('state.retry')}</button>
        </div>
      );
    case 'done':
      break;
  }
  if (groups.length === 0) return <p class="cap" role="status">{t('pic.searchNone', { query: search.query })}</p>;
  const full = draft.length >= MAX_PICTURES;
  return (
    <>
      <p class="sr-only" role="status">{t('pic.results', { count: search.results.length })}</p>
      <ul class="res-grid">
        {groups.map((frames) => {
          const first = frames[0];
          if (!first) return null;
          const ids = frames.map((f) => f.publicId);
          const allIn = ids.every((id) => draft.includes(id));
          const room = MAX_PICTURES - draft.length >= ids.filter((id) => !draft.includes(id)).length;
          return (
            <li key={first.exerciseKey} class="res-card">
              <b class="cap res-title" lang="en">{first.title}</b>
              <div class="res-frames">
                {frames.map((f) => {
                  const on = draft.includes(f.publicId);
                  const frameName = f.frame === 'tension' ? t('pic.start') : t('pic.end');
                  return (
                    <button
                      key={f.publicId}
                      type="button"
                      class={`res-frame${on ? ' on' : ''}`}
                      aria-pressed={on}
                      aria-label={t('pic.frame', { frame: frameName, name: f.title })}
                      disabled={!on && full}
                      onClick={() => { onToggle(f.publicId); }}
                    >
                      <Picture cloudName={cloudName} publicId={f.publicId} size="thumb" alt="" />
                      <span class="res-label">
                        {on ? <Icon name="check" /> : null}
                        {frameName}
                      </span>
                    </button>
                  );
                })}
              </div>
              {frames.length > 1 ? (
                <button type="button" class="btn sm" disabled={allIn || !room} aria-label={allIn ? undefined : t('pic.addBothLabel', { name: first.title })} onClick={() => { onAddAll(ids); }}>
                  {allIn ? t('pic.bothAdded') : t('pic.addBoth')}
                </button>
              ) : null}
            </li>
          );
        })}
      </ul>
    </>
  );
}

// ---------------------------------------------------------------- video ----

interface VideoProps {
  readonly gymId: string;
  readonly exercise: LibraryExercise;
  readonly video: VideoRef | null;
  readonly media: MediaRepository;
  readonly online: boolean;
  readonly onSaved: (video: VideoRef | null) => void;
}

function sameVideo(a: VideoRef | null, b: VideoRef | null): boolean {
  return a !== null && b !== null && a.id === b.id && a.start === b.start && a.end === b.end;
}

function VideoTimes({ video }: { readonly video: VideoRef }) {
  const { t } = useI18n();
  const parts: string[] = [];
  if (video.start !== null) parts.push(t('vid.startsAt', { time: formatSeconds(video.start) }));
  if (video.end !== null) parts.push(t('vid.endsAt', { time: formatSeconds(video.end) }));
  return parts.length > 0 ? <span>{` · ${parts.join(' · ')}`}</span> : null;
}

function VideoPanel({ gymId, exercise, video, media, online, onSaved }: VideoProps) {
  const { t } = useI18n();
  const [link, setLink] = useState('');
  const [busy, setBusy] = useState<'save' | 'remove' | null>(null);
  const [note, setNote] = useState<Note>(null);

  const typed = link.trim() !== '';
  const parsed = typed ? parseYouTubeLink(link) : null;
  const same = sameVideo(parsed, video);
  const open = video ? watchUrl(video) : null;

  const save = async () => {
    if (!parsed) return;
    setBusy('save');
    setNote(null);
    const result = await media.saveVideo(gymId, exercise.id, parsed, video !== null);
    setBusy(null);
    if (result.ok) {
      onSaved(parsed);
      setLink('');
      setNote({ tone: 'ok', key: 'vid.saved' });
    } else {
      setNote({ tone: 'err', key: saveFailureKey(result.failure) });
    }
  };

  const remove = async () => {
    setBusy('remove');
    setNote(null);
    const result = await media.removeVideo(gymId, exercise.id);
    setBusy(null);
    if (result.ok) {
      onSaved(null);
      setNote({ tone: 'ok', key: 'vid.removed' });
    } else {
      setNote({ tone: 'err', key: saveFailureKey(result.failure) });
    }
  };

  return (
    <section class="panel" aria-labelledby="vid-title">
      <h2 class="h2" id="vid-title">{t('vid.title')}</h2>
      {video ? (
        <div class="banner info">
          <Icon name="play" />
          <span class="grow">
            {t('vid.yours')}{' '}
            <span class="num">{t('vid.id', { id: video.id })}</span>
            <VideoTimes video={video} />
          </span>
          {open ? (
            <a class="btn sm" href={open} target="_blank" rel="noopener noreferrer">
              {t('vid.open')}
              <Icon name="external" />
              <span class="sr-only">{t('vid.newTab')}</span>
            </a>
          ) : null}
        </div>
      ) : (
        <div class="banner">
          <Icon name="info" />
          <span>{exercise.libraryVideo ? t('vid.library') : t('vid.none')}</span>
        </div>
      )}
      <div class="field">
        <label for="vid-link">{t('vid.paste')}</label>
        <input
          id="vid-link"
          class={`in${typed && !parsed ? ' bad' : ''}`}
          type="url"
          dir="ltr"
          inputMode="url"
          autoComplete="off"
          spellcheck={false}
          maxLength={LINK_MAX}
          placeholder="https://youtu.be/…"
          value={link}
          aria-invalid={typed && !parsed}
          aria-describedby="vid-hint vid-check"
          onInput={(event) => {
            setLink(event.currentTarget.value);
            setNote(null);
          }}
        />
        <span class="hint" id="vid-hint">{t('vid.pasteHint')}</span>
        <span id="vid-check" class="live-slot" role="status">
          {typed && parsed ? (
            <span class="okt">
              <Icon name="check" />
              <span>
                {same ? t('vid.same') : t('vid.ok', { id: parsed.id })}
                <VideoTimes video={parsed} />
              </span>
            </span>
          ) : null}
          {typed && !parsed ? (
            <span class="errt">
              <Icon name="alert" />
              <span>{t('vid.bad')}</span>
            </span>
          ) : null}
        </span>
      </div>
      <div class="acts-row">
        <button type="button" class="btn pri" disabled={!parsed || same || busy !== null || !online} onClick={() => void save()}>
          {busy === 'save' ? t('vid.saving') : t('vid.save')}
        </button>
        {video ? (
          <button type="button" class="btn danger" disabled={busy !== null || !online} onClick={() => void remove()}>
            {busy === 'remove' ? t('vid.saving') : t('vid.remove')}
          </button>
        ) : null}
      </div>
      {!online ? <p class="cap">{t('pic.offlineHint')}</p> : null}
      <div class="live-slot" role={note?.tone === 'err' ? 'alert' : 'status'}>
        {note ? (
          <div class={`banner ${note.tone === 'ok' ? 'ok' : 'err'}`}>
            <Icon name={note.tone === 'ok' ? 'check' : 'alert'} />
            <span>{t(note.key, { max: MAX_PICTURES })}</span>
          </div>
        ) : null}
      </div>
    </section>
  );
}
