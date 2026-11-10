import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import type { Failure } from '../core/failure';
import type { MessageKey } from '../i18n';
import type { MediaRepository } from './media';
import type { GymMedia, VideoRef } from './types';

export type MediaState =
  | { readonly state: 'loading' }
  | { readonly state: 'failed'; readonly failure: Failure }
  | { readonly state: 'ready'; readonly media: GymMedia };

/** Loads a gym's pictures and videos; `apply…` updates the copy after a save, without a new request. */
export function useGymMedia(repo: MediaRepository, gymId: string) {
  const [data, setData] = useState<MediaState>({ state: 'loading' });
  const token = useRef(0);

  const reload = useCallback(async () => {
    const mine = ++token.current;
    setData({ state: 'loading' });
    const result = await repo.load(gymId);
    if (mine !== token.current) return;
    setData(result.ok ? { state: 'ready', media: result.value } : { state: 'failed', failure: result.failure });
  }, [repo, gymId]);

  useEffect(() => {
    void reload();
    return () => {
      token.current++;
    };
  }, [reload]);

  const applyPictures = useCallback((exerciseId: string, publicIds: readonly string[]) => {
    setData((d) => {
      if (d.state !== 'ready') return d;
      const pictures = new Map(d.media.pictures);
      if (publicIds.length === 0) pictures.delete(exerciseId);
      else pictures.set(exerciseId, [...publicIds]);
      return { state: 'ready', media: { ...d.media, pictures } };
    });
  }, []);

  const applyVideo = useCallback((exerciseId: string, video: VideoRef | null) => {
    setData((d) => {
      if (d.state !== 'ready') return d;
      const videos = new Map(d.media.videos);
      if (video) videos.set(exerciseId, video);
      else videos.delete(exerciseId);
      return { state: 'ready', media: { ...d.media, videos } };
    });
  }, []);

  return { data, reload, applyPictures, applyVideo };
}

/** One fixed message per failure of a save; never the server's own text. */
export function saveFailureKey(failure: Failure): MessageKey {
  switch (failure.kind) {
    case 'offline':
      return 'media.errOffline';
    case 'forbidden':
      return 'media.errForbidden';
    case 'session_ended':
      return 'fail.session';
    case 'rate_limited':
      return 'fail.rateLimited';
    case 'conflict':
      if (failure.reason === 'too_many_pictures_in_gym') return 'media.errGymPictures';
      if (failure.reason === 'too_many_videos_in_gym') return 'media.errGymVideos';
      if (failure.reason === 'too_many_pictures') return 'pic.full';
      return 'media.errInvalid';
    case 'invalid':
    case 'not_found':
      return 'media.errInvalid';
    default:
      return 'media.errServer';
  }
}
