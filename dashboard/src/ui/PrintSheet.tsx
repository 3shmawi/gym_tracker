import { useEffect, useState } from 'preact/hooks';
import { translate } from '../i18n';
import { joinUrl } from '../invites/qr';
import { formatDate } from './memberText';

// The print view (board 1.6): A4, 2×2 cards, the make_invites layout. It is
// rendered only while printing is requested; app.css hides everything else
// in @media print. Each card holds the canvas that drawQr() made and checked
// (the canvas IS the QR: no data:/blob: URL, the CSP forbids them). The codes
// live in component state only.

export interface PrintCard {
  readonly name: string;
  readonly code: string;
  readonly expiresAt: Date;
  /** A canvas whose QR was read back. Unverified cards never get here. */
  readonly canvas: HTMLCanvasElement;
}

export const CARDS_PER_PAGE = 4;

/** Asks the browser's print dialog; the sheet exists only between the request and `afterprint`. */
export function usePrint(): { readonly printing: boolean; readonly request: () => void } {
  const [state, setState] = useState({ printing: false, run: 0 });
  useEffect(() => {
    if (state.run === 0) return;
    const after = () => {
      setState((s) => ({ ...s, printing: false }));
    };
    window.addEventListener('afterprint', after);
    window.print();
    return () => {
      window.removeEventListener('afterprint', after);
    };
  }, [state.run]);
  return {
    printing: state.printing,
    request: () => {
      setState((s) => ({ printing: true, run: s.run + 1 }));
    },
  };
}

function QrSlot({ canvas, label }: { readonly canvas: HTMLCanvasElement; readonly label: string }) {
  return (
    <div
      class="qr"
      role="img"
      aria-label={label}
      ref={(el) => {
        if (el && canvas.parentNode !== el) el.replaceChildren(canvas);
      }}
    />
  );
}

function Card({ gymName, card }: { readonly gymName: string; readonly card: PrintCard }) {
  return (
    <div class="pcard">
      <div class="g plain">{gymName}</div>
      <div class="n plain">{card.name}</div>
      <QrSlot canvas={card.canvas} label={translate('en', 'print.qrLabel', { name: card.name })} />
      <div class="c" dir="ltr">{card.code}</div>
      <div class="l" lang="en" dir="ltr">{translate('en', 'print.scan')}</div>
      <div class="l" lang="ar" dir="rtl">{translate('ar', 'print.scan')}</div>
      <div class="l" lang="en" dir="ltr">{translate('en', 'print.single', { date: formatDate('en', card.expiresAt) })}</div>
      <div class="l" lang="ar" dir="rtl">{translate('ar', 'print.single', { date: formatDate('ar', card.expiresAt) })}</div>
      <div class="u" dir="ltr">{joinUrl(card.code)}</div>
    </div>
  );
}

export function PrintSheet({ gymName, cards }: { readonly gymName: string; readonly cards: readonly PrintCard[] }) {
  const pages: PrintCard[][] = [];
  for (let i = 0; i < cards.length; i += CARDS_PER_PAGE) pages.push(cards.slice(i, i + CARDS_PER_PAGE));
  return (
    <section class="print-sheet" aria-hidden="true">
      {pages.map((page, index) => (
        <div class="print-page" key={index}>
          {page.map((card) => (
            <Card key={card.code} gymName={gymName} card={card} />
          ))}
        </div>
      ))}
    </section>
  );
}
