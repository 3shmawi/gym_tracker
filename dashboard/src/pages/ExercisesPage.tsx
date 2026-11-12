import { useState } from 'preact/hooks';
import { linkHandler, pathOf, type Route } from '../app/router';
import { cleanName } from '../core/text';
import { asListed, matchesQuery } from '../exercises/catalog';
import { LIBRARY } from '../exercises/library';
import type { MediaRepository } from '../exercises/media';
import type { ExerciseLike, GymMedia } from '../exercises/types';
import { useCustomExercises, useGymMedia } from '../exercises/useGymMedia';
import type { ManagedGym } from '../gyms/gyms';
import { useI18n, type I18n } from '../i18n';
import { Icon } from '../ui/icons';
import { ExerciseThumb } from '../ui/Picture';
import { ErrorView, LoadingView, StateBlock } from '../ui/states';

type Tab = 'all' | 'mine' | 'no_video' | 'no_pictures';
const TABS: readonly Tab[] = ['all', 'mine', 'no_pictures', 'no_video'];
const SEARCH_MAX = 60;
const LISTED = LIBRARY.map(asListed);

const hasMine = (media: GymMedia, e: ExerciseLike) => media.pictures.has(e.id) || media.videos.has(e.id);
const hasNoVideo = (media: GymMedia, e: ExerciseLike) => !media.videos.has(e.id) && !e.libraryVideo;
const inTab = (media: GymMedia, e: ExerciseLike, tab: Tab) =>
  tab === 'all' || (tab === 'mine' ? hasMine(media, e) : tab === 'no_pictures' ? !media.pictures.has(e.id) : hasNoVideo(media, e));

/** Both names, the one of the page's language first. */
export function exerciseNames(lang: I18n['lang'], e: Pick<ExerciseLike, 'en' | 'ar'>): { primary: string; secondary: string; secondaryLang: 'en' | 'ar' } {
  return lang === 'ar' ? { primary: e.ar, secondary: e.en, secondaryLang: 'en' } : { primary: e.en, secondary: e.ar, secondaryLang: 'ar' };
}

export function ExercisesPage({ gym, media, cloudName }: { readonly gym: ManagedGym; readonly media: MediaRepository; readonly cloudName: string | null }) {
  const { t, lang } = useI18n();
  const { data, reload } = useGymMedia(media, gym.id);
  const custom = useCustomExercises(media, gym.id);
  const [tab, setTab] = useState<Tab>('all');
  const [query, setQuery] = useState('');

  const head = (
    <div class="stack-sm">
      <h1 class="h1">{t('ex.title')}</h1>
      <p class="sub">{t('ex.subtitle')}</p>
    </div>
  );
  if (data.state === 'loading') {
    return (
      <section class="stack" data-gym={gym.id}>
        {head}
        <LoadingView />
      </section>
    );
  }
  if (data.state === 'failed') {
    return (
      <section class="stack" data-gym={gym.id}>
        {head}
        <ErrorView failure={data.failure} onRetry={() => void reload()} />
      </section>
    );
  }

  const m = data.media;
  const needle = cleanName(query);
  // The library, then what members wrote into plans (and that has media already).
  const own = (custom ?? []).filter((e) => e.custom);
  const all = [...LISTED, ...own];
  const rows = all.filter((e) => inTab(m, e, tab) && matchesQuery(e, needle));
  const withPictures = all.filter((e) => m.pictures.has(e.id)).length;
  const withVideo = all.filter((e) => m.videos.has(e.id)).length;
  const countOf = (k: Tab) => all.filter((e) => inTab(m, e, k)).length;
  const tabLabel: Record<Tab, string> = { all: t('ex.tabAll'), mine: t('ex.tabMine'), no_video: t('ex.tabNoVideo'), no_pictures: t('ex.tabNoPictures') };

  const empty =
    needle !== '' ? (
      <StateBlock icon="search" title={t('ex.noMatchTitle', { query: needle })}>
        <p class="sub">{t('ex.noMatchBody')}</p>
        <button type="button" class="btn" onClick={() => { setQuery(''); }}>{t('ex.clearSearch')}</button>
      </StateBlock>
    ) : (
      <StateBlock icon="dumbbell" title={t('ex.noneHereTitle')}>
        <p class="sub">{t('ex.noneHereBody')}</p>
        <button type="button" class="btn" onClick={() => { setTab('all'); }}>{t('ex.showAll')}</button>
      </StateBlock>
    );

  return (
    <section class="stack" data-gym={gym.id}>
      {head}
      <div class="toolbar">
        <div class="field search">
          <label class="sr-only" for="exercise-search">{t('ex.search')}</label>
          <input
            id="exercise-search"
            class="in"
            type="search"
            placeholder={t('ex.search')}
            maxLength={SEARCH_MAX}
            value={query}
            onInput={(event) => { setQuery(event.currentTarget.value); }}
          />
        </div>
        <div class="seg" role="group" aria-label={t('ex.show')}>
          {TABS.map((k) => (
            <button key={k} type="button" class={tab === k ? 'on' : ''} aria-pressed={tab === k} onClick={() => { setTab(k); }}>
              {tabLabel[k]} <span class="num">{countOf(k)}</span>
            </button>
          ))}
        </div>
      </div>
      <p class="cap" role="status">
        {t('ex.summary', { shown: rows.length, total: all.length, pictures: withPictures, videos: withVideo })}
      </p>

      {rows.length === 0 ? (
        <div class="panel">{empty}</div>
      ) : (
        <ul class="ex-list">
          {rows.map((e) => {
            const names = exerciseNames(lang, e);
            const pics = m.pictures.get(e.id) ?? [];
            const video = m.videos.has(e.id) ? 'yours' : e.libraryVideo ? 'library' : 'none';
            const route: Route = { name: 'exercise', gymId: gym.id, exerciseId: e.id };
            return (
              <li key={e.id}>
                <a class="panel ex-row" href={pathOf(route)} onClick={linkHandler(route)}>
                  <ExerciseThumb cloudName={cloudName} cover={pics[0]} />
                  <span class="meta">
                    <b>{names.primary}</b>
                    <span class="cap">
                      <span lang={names.secondaryLang}>{names.secondary}</span>
                      {e.muscle ? ` · ${t(`ex.muscle.${e.muscle}`)}` : null}
                      {e.custom ? ' ' : null}
                      {e.custom ? <span class="badge own">{t('plan.ownExercise')}</span> : null}
                    </span>
                  </span>
                  <span class="badges ex-badges">
                    <span class={`badge${pics.length > 0 ? ' keep' : ''}`}>
                      {pics.length === 0 ? t('ex.picsApp') : pics.length === 1 ? t('ex.picsOne') : t('ex.picsMany', { count: pics.length })}
                    </span>
                    <span class={`badge${video === 'yours' ? ' keep' : video === 'none' ? ' warn' : ''}`}>
                      {video === 'yours' ? t('ex.videoYours') : video === 'library' ? t('ex.videoLibrary') : t('ex.videoNone')}
                    </span>
                  </span>
                  <span class="flip" aria-hidden="true"><Icon name="chevronRight" /></span>
                </a>
              </li>
            );
          })}
        </ul>
      )}
      <p class="cap">{t('ex.note')}</p>
      {cloudName ? <p class="cap">{t('ex.credit')}</p> : null}
    </section>
  );
}
