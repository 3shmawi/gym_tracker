import { useState } from 'preact/hooks';
import { pictureUrl, type PictureSize } from '../exercises/pictures';
import { Icon } from './icons';

/**
 * A library picture. The URL comes only from the fixed builder (a library id
 * and the configured cloud name); with no cloud name, or when the picture
 * fails to load, a plain tile shows instead. `alt` is the picture's name, or
 * '' when the text next to it already says it.
 */
export function Picture({ cloudName, publicId, size, alt, class: cls }: { readonly cloudName: string | null; readonly publicId: string; readonly size: PictureSize; readonly alt: string; readonly class?: string }) {
  const [broken, setBroken] = useState(false);
  const src = broken ? null : pictureUrl(cloudName, publicId, size);
  const box = `pic${cls ? ` ${cls}` : ''}`;
  if (src === null) {
    return (
      <span class={`${box} pic-none`} role={alt ? 'img' : undefined} aria-label={alt || undefined} aria-hidden={alt ? undefined : 'true'}>
        <Icon name="image" />
      </span>
    );
  }
  return (
    <span class={box}>
      <img
        src={src}
        alt={alt}
        loading="lazy"
        decoding="async"
        referrerpolicy="no-referrer"
        onError={() => {
          setBroken(true);
        }}
      />
    </span>
  );
}

/** The exercise tile of a list row: the gym's cover, else a plain dumbbell tile. */
export function ExerciseThumb({ cloudName, cover }: { readonly cloudName: string | null; readonly cover: string | undefined }) {
  if (cover) return <Picture cloudName={cloudName} publicId={cover} size="thumb" alt="" class="thumb" />;
  return (
    <span class="pic thumb pic-none" aria-hidden="true">
      <Icon name="dumbbell" />
    </span>
  );
}
