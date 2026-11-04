import type { ComponentChildren } from 'preact';

export const CONTACT_EMAIL = 'mohager.dev@gmail.com';

/**
 * Splits a translated sentence at one `{slot}` (left unfilled by t()) and puts a
 * node there. Keeps the sentence order of each language.
 */
export function withSlot(text: string, slot: string, node: ComponentChildren): ComponentChildren {
  const token = `{${slot}}`;
  const at = text.indexOf(token);
  if (at < 0) return text;
  return (
    <>
      {text.slice(0, at)}
      {node}
      {text.slice(at + token.length)}
    </>
  );
}

export function ContactLink() {
  return <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>;
}

/** Click handler for same-origin links: plain left clicks run the callback instead of reloading. */
export function plainClick(callback: () => void) {
  return (event: MouseEvent) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    callback();
  };
}
