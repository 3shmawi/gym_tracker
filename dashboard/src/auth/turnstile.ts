// Cloudflare Turnstile for the "send me a code" request, used only when a
// site key is configured (Supabase CAPTCHA protection covers sign-in). The
// script is Cloudflare's, loaded from challenges.cloudflare.com, which the
// CSP then allows for script-src and frame-src (build/headers.ts).
// Docs: developers.cloudflare.com/turnstile/get-started/client-side-rendering/
// (explicit rendering), read 2026-11-04.

const SCRIPT_URL = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
const TIMEOUT_MS = 20_000;

interface TurnstileApi {
  render(container: HTMLElement, options: Record<string, unknown>): string;
  reset(widgetId: string): void;
  remove(widgetId: string): void;
}

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

export interface Captcha {
  /** A fresh token for one request. Rejects on error or after 20 s. */
  token(container: HTMLElement, lang: 'en' | 'ar'): Promise<string>;
}

let loading: Promise<TurnstileApi> | null = null;

function loadScript(): Promise<TurnstileApi> {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  loading ??= new Promise<TurnstileApi>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = SCRIPT_URL;
    script.async = true;
    script.onload = () => {
      if (window.turnstile) resolve(window.turnstile);
      else reject(new TypeError('turnstile unavailable'));
    };
    script.onerror = () => {
      loading = null;
      reject(new TypeError('turnstile failed to load'));
    };
    document.head.appendChild(script);
  });
  return loading;
}

export class TurnstileCaptcha implements Captcha {
  constructor(private readonly siteKey: string) {}

  async token(container: HTMLElement, lang: 'en' | 'ar'): Promise<string> {
    const api = await loadScript();
    return new Promise<string>((resolve, reject) => {
      let widgetId: string | null = null;
      const done = (fn: () => void) => {
        clearTimeout(timer);
        if (widgetId !== null) api.remove(widgetId);
        fn();
      };
      const timer = setTimeout(() => {
        done(() => {
          reject(new TypeError('turnstile timed out'));
        });
      }, TIMEOUT_MS);
      widgetId = api.render(container, {
        sitekey: this.siteKey,
        language: lang,
        appearance: 'interaction-only',
        callback: (token: unknown) => {
          done(() => {
            if (typeof token === 'string' && token) resolve(token);
            else reject(new TypeError('turnstile: no token'));
          });
        },
        'error-callback': () => {
          done(() => {
            reject(new TypeError('turnstile error'));
          });
        },
        'expired-callback': () => {
          done(() => {
            reject(new TypeError('turnstile expired'));
          });
        },
      });
    });
  }
}
