import type { ComponentChildren } from 'preact';
import { useLayoutEffect, useRef } from 'preact/hooks';

const FOCUSABLE = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * A modal dialog: focus moves in when it opens and back to what had it when
 * it closes, Tab stays inside, Escape closes. The first button (the safe
 * choice, "Cancel"/"Stay") gets the focus, unless `initialFocus` (a selector
 * inside the dialog) names a better start, such as a search box.
 */
export function Dialog({ titleId, onClose, initialFocus, children }: { readonly titleId: string; readonly onClose: () => void; readonly initialFocus?: string; readonly children: ComponentChildren }) {
  const box = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;

  // Layout effect: runs before the next key press, so a fast Tab can't move
  // focus elsewhere before the dialog notes where focus should go back to.
  useLayoutEffect(() => {
    const before = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const first = initialFocus ? box.current?.querySelector<HTMLElement>(initialFocus) : null;
    (first ?? box.current?.querySelector<HTMLElement>(FOCUSABLE))?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        close.current();
        return;
      }
      if (event.key !== 'Tab' || !box.current) return;
      const items = [...box.current.querySelectorAll<HTMLElement>(FOCUSABLE)];
      const first = items[0];
      const last = items[items.length - 1];
      if (!first || !last) return;
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      before?.focus();
    };
  }, []);

  return (
    <div class="scrim">
      <div ref={box} class="dialog" role="dialog" aria-modal="true" aria-labelledby={titleId}>
        {children}
      </div>
    </div>
  );
}
