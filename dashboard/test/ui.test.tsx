import { render } from 'preact';
import { act } from 'preact/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { AuthService, SignedIn } from '../src/auth/auth';
import type { Failure } from '../src/core/failure';
import { failed, ok, type Result } from '../src/core/result';
import type { ManagedGym } from '../src/gyms/gyms';
import { I18nContext, makeI18n, messageTables } from '../src/i18n';
import type { Lang } from '../src/core/prefs';
import { GymPickerPage } from '../src/pages/GymPickerPage';
import { MembersPage } from '../src/pages/MembersPage';
import { SignInPage } from '../src/pages/SignInPage';
import { Shell } from '../src/ui/Shell';
import { ErrorView, ForbiddenView, LoadingView, NoGymView, NotFoundView, SessionEndedView } from '../src/ui/states';
import type { ComponentChildren } from 'preact';
import type { Captcha } from '../src/auth/turnstile';

/* eslint-disable @typescript-eslint/no-unnecessary-type-parameters */
let host: HTMLElement;
beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
});
afterEach(() => {
  render(null, host);
  host.remove();
  vi.useRealTimers();
});

async function mount(node: ComponentChildren, lang: Lang = 'en') {
  await act(() => {
    render(<I18nContext.Provider value={makeI18n(lang)}>{node}</I18nContext.Provider>, host);
  });
}
const q = <T extends Element>(selector: string) => host.querySelector<T>(selector);
function m<T extends Element>(selector: string): T {
  const el = host.querySelector<T>(selector);
  if (!el) throw new Error(`missing ${selector}`);
  return el;
}
function must<T>(value: T | undefined): T {
  if (value === undefined) throw new Error('missing');
  return value;
}
const text = () => host.textContent;

async function type(input: HTMLInputElement, value: string) {
  await act(() => {
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
async function click(el: Element | null) {
  await act(() => {
    (el as HTMLElement).click();
  });
}
async function submit(selector = 'form') {
  await act(() => {
    q<HTMLFormElement>(selector)?.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
  });
}
const flush = () => act(async () => { await Promise.resolve(); });

const user: SignedIn = { userId: 'u1', email: 'm@example.com' };

function fakeAuth(over: { send?: Result<void>; verify?: Result<SignedIn> } = {}) {
  const sendCode = vi.fn(() => Promise.resolve(over.send ?? ok(undefined)));
  const verifyCode = vi.fn(() => Promise.resolve(over.verify ?? ok(user)));
  return { auth: { sendCode, verifyCode } as unknown as AuthService, sendCode, verifyCode };
}
const fail = (kind: Failure['kind']): Result<never> => failed({ kind });

async function toCodeStep(f: ReturnType<typeof fakeAuth>, onSignedIn = vi.fn(), online = true) {
  await mount(<SignInPage captcha={null} auth={f.auth} online={online} onSignedIn={onSignedIn} />);
  await type(m<HTMLInputElement>('#sign-in-email'), 'Manager@Example.com');
  await submit();
  await flush();
  return onSignedIn;
}

describe('SignInPage', () => {
  it('has an accessible email field', async () => {
    await mount(<SignInPage captcha={null} auth={fakeAuth().auth} online onSignedIn={vi.fn()} />);
    const input = m<HTMLInputElement>('#sign-in-email');
    expect(input.type).toBe('email');
    expect(input.autocomplete).toBe('email');
    expect(input.maxLength).toBe(254);
    expect(q('label[for="sign-in-email"]')?.textContent).toBe('Email');
    expect(text()).toContain('6-digit');
  });

  it('flags a bad email without calling the server', async () => {
    const f = fakeAuth();
    await mount(<SignInPage captcha={null} auth={f.auth} online onSignedIn={vi.fn()} />);
    await type(m<HTMLInputElement>('#sign-in-email'), 'captain@');
    await submit();
    expect(f.sendCode).not.toHaveBeenCalled();
    const input = m<HTMLInputElement>('#sign-in-email');
    expect(input.getAttribute('aria-invalid')).toBe('true');
    expect(input.getAttribute('aria-describedby')).toContain('sign-in-email-error');
    expect(text()).toContain(messageTables.en['signIn.emailInvalid']);
  });

  it('goes email -> code -> signed in', async () => {
    const f = fakeAuth();
    const onSignedIn = await toCodeStep(f);
    expect(f.sendCode).toHaveBeenCalledWith('manager@example.com');
    expect(text()).toContain('Check your email');
    expect(text()).toContain('m•••@example.com');
    expect(text()).not.toContain('manager@example.com');
    const code = m<HTMLInputElement>('#sign-in-code');
    expect(code.autocomplete).toBe('one-time-code');
    expect(code.inputMode).toBe('numeric');
    expect(code.maxLength).toBe(10);
    await type(code, '123 456');
    await submit();
    await flush();
    expect(f.verifyCode).toHaveBeenCalledWith('manager@example.com', '123456');
    expect(onSignedIn).toHaveBeenCalledWith(user);
  });

  it('accepts Arabic-Indic digits', async () => {
    const f = fakeAuth();
    await toCodeStep(f);
    await type(m<HTMLInputElement>('#sign-in-code'), String.fromCharCode(0x661, 0x662, 0x663, 0x664, 0x665, 0x666));
    await submit();
    await flush();
    expect(f.verifyCode).toHaveBeenCalledWith('manager@example.com', '123456');
  });

  it('asks for all digits before verifying', async () => {
    const f = fakeAuth();
    await toCodeStep(f);
    await type(m<HTMLInputElement>('#sign-in-code'), '12');
    await submit();
    expect(f.verifyCode).not.toHaveBeenCalled();
    expect(text()).toContain('Type the 6 digits');
  });

  it('shows a message per failure kind on the code step', async () => {
    const cases: [Failure['kind'], string][] = [
      ['code_wrong', messageTables.en['signIn.codeWrong']],
      ['rate_limited', messageTables.en['signIn.rateLimited']],
      ['offline', messageTables.en['state.offline']],
      ['server', messageTables.en['state.errorBody']],
      ['code_expired', messageTables.en['signIn.codeExpired']],
    ];
    for (const [kind, message] of cases) {
      render(null, host);
      const f = fakeAuth({ verify: fail(kind) });
      await toCodeStep(f);
      await type(m<HTMLInputElement>('#sign-in-code'), '123456');
      await submit();
      await flush();
      expect(text(), kind).toContain(message);
    }
  });

  it('offers a new code after expiry', async () => {
    const f = fakeAuth({ verify: fail('code_expired') });
    await toCodeStep(f);
    await type(m<HTMLInputElement>('#sign-in-code'), '123456');
    await submit();
    await flush();
    const button = [...host.querySelectorAll('button')].find((b) => b.textContent === 'Send a new code');
    expect(button).toBeDefined();
    await click(must(button));
    await flush();
    expect(f.sendCode).toHaveBeenCalledTimes(2);
    expect(q('#sign-in-code')).not.toBeNull();
  });

  it('maps send failures on the email step', async () => {
    const f = fakeAuth({ send: fail('rate_limited') });
    await mount(<SignInPage captcha={null} auth={f.auth} online onSignedIn={vi.fn()} />);
    await type(m<HTMLInputElement>('#sign-in-email'), 'a@example.com');
    await submit();
    await flush();
    expect(text()).toContain(messageTables.en['signIn.rateLimited']);
    expect(q('#sign-in-code')).toBeNull();
  });

  it('counts down before allowing a resend', async () => {
    vi.useFakeTimers();
    const f = fakeAuth();
    await toCodeStep(f);
    expect(text()).toContain('Send again in 1:00');
    await act(() => { vi.advanceTimersByTime(18_000); });
    expect(text()).toMatch(/Send again in 0:4[23]/);
    await act(() => { vi.advanceTimersByTime(43_000); });
    const resend = [...host.querySelectorAll('button')].find((b) => b.textContent === 'Send again');
    expect(resend).toBeDefined();
    await click(must(resend));
    await flush();
    expect(f.sendCode).toHaveBeenCalledTimes(2);
  });

  it('without captcha sends no token', async () => {
    const f = fakeAuth();
    await toCodeStep(f);
    expect(f.sendCode.mock.calls[0]).toEqual(['manager@example.com']);
  });

  it('with captcha gets a token first, and again on resend', async () => {
    const f = fakeAuth();
    const token = vi.fn(() => Promise.resolve('test-token'));
    const captcha: Captcha = { token };
    await mount(<SignInPage auth={f.auth} captcha={captcha} online onSignedIn={vi.fn()} />);
    expect(q('.captcha')).not.toBeNull();
    await type(m<HTMLInputElement>('#sign-in-email'), 'a@example.com');
    await submit();
    await flush();
    expect(f.sendCode).toHaveBeenCalledWith('a@example.com', 'test-token');
    expect(token).toHaveBeenCalledTimes(1);
  });

  it('shows the captcha error and does not send when the check fails', async () => {
    const f = fakeAuth();
    const captcha: Captcha = { token: vi.fn(() => Promise.reject(new TypeError('x'))) };
    await mount(<SignInPage auth={f.auth} captcha={captcha} online onSignedIn={vi.fn()} />);
    await type(m<HTMLInputElement>('#sign-in-email'), 'a@example.com');
    await submit();
    await flush();
    expect(f.sendCode).not.toHaveBeenCalled();
    expect(text()).toContain(messageTables.en['signIn.captchaFailed']);
    expect(q<HTMLButtonElement>('button[type=submit]')?.disabled).toBe(false);
  });

  it('goes back to the email step', async () => {
    await toCodeStep(fakeAuth());
    await click(must([...host.querySelectorAll('button')].find((b) => b.textContent === 'Use another email')));
    expect(q('#sign-in-email')).not.toBeNull();
  });

  it('disables sending while offline', async () => {
    const f = fakeAuth();
    await mount(<SignInPage captcha={null} auth={f.auth} online={false} onSignedIn={vi.fn()} />);
    expect(q<HTMLButtonElement>('button[type=submit]')?.disabled).toBe(true);
    expect(text()).toContain(messageTables.en['signIn.offlineHint']);
    await type(m<HTMLInputElement>('#sign-in-email'), 'a@example.com');
    await submit();
    expect(f.sendCode).not.toHaveBeenCalled();
  });

  it('renders Arabic text from ar.ts', async () => {
    await mount(<div dir="rtl"><SignInPage captcha={null} auth={fakeAuth().auth} online onSignedIn={vi.fn()} /></div>, 'ar');
    expect(q('[dir=rtl]')).not.toBeNull();
    expect(text()).toContain(messageTables.ar['signIn.title']);
    expect(text()).toContain(messageTables.ar['signIn.send']);
    expect(text()).not.toContain(messageTables.en['signIn.title']);
  });
});

const gym = (n: number, role: 'owner' | 'captain', name: string): ManagedGym => ({
  id: `0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4${String(n)}`,
  name,
  role,
  memberCount: n * 10,
});

describe('GymPickerPage', () => {
  it('lists gyms as real links, shows text only, and picks on click', async () => {
    const onPick = vi.fn();
    const gyms = [gym(1, 'owner', 'Power Gym'), gym(2, 'captain', '<img src=x onerror=alert(1)>')];
    await mount(<GymPickerPage gyms={gyms} onPick={onPick} />);
    const links = host.querySelectorAll('a');
    expect(links).toHaveLength(2);
    expect(links[0]?.getAttribute('href')).toBe(`/g/${gyms[0]?.id ?? ''}/members`);
    expect(host.querySelector('img')).toBeNull();
    expect(text()).toContain('<img src=x onerror=alert(1)>');
    expect(text()).toContain('PG');
    expect(text()).toContain('Owner');
    expect(text()).toContain('Captain');
    expect(text()).toContain('20 members');
    expect(links[1]?.querySelector('.lg.amber')).not.toBeNull();
    await click(links[1] ?? null);
    expect(onPick).toHaveBeenCalledWith(gyms[1]);
  });
});

describe('MembersPage', () => {
  it('shows the placeholder', async () => {
    await mount(<MembersPage gym={gym(1, 'owner', 'Power Gym')} />);
    expect(q('h1')?.textContent).toBe('Members');
    expect(text()).toContain(messageTables.en['members.comingSoon']);
  });
});

describe('state views', () => {
  it('LoadingView is busy with hidden text', async () => {
    await mount(<LoadingView />);
    expect(q('[aria-busy=true]')).not.toBeNull();
    expect(q('.sr-only')?.textContent).toBe('Loading…');
  });
  it('ErrorView never shows raw server text and retries', async () => {
    const onRetry = vi.fn();
    const hostile = { kind: 'server', reason: 'secret_internal' } as const;
    await mount(<ErrorView failure={hostile} onRetry={onRetry} />);
    expect(text()).toContain(messageTables.en['state.errorBody']);
    expect(text()).not.toContain('secret_internal');
    expect(q('a[href="mailto:mohager.dev@gmail.com"]')).not.toBeNull();
    await click(q('button'));
    expect(onRetry).toHaveBeenCalled();
  });
  it('ErrorView uses the offline wording', async () => {
    await mount(<ErrorView failure={{ kind: 'offline' }} onRetry={vi.fn()} />);
    expect(text()).toContain(messageTables.en['state.offline']);
  });
  it('the other views call back', async () => {
    const fn = vi.fn();
    await mount(<><ForbiddenView onPickAnother={fn} onSignOut={fn} /><SessionEndedView onSignIn={fn} /><NotFoundView onHome={fn} /><NoGymView onSignOut={fn} /></>);
    expect(host.querySelectorAll('h2')).toHaveLength(4);
    for (const el of host.querySelectorAll<HTMLElement>('button, a.btn')) await click(el);
    expect(fn).toHaveBeenCalledTimes(5);
  });
});

describe('Shell', () => {
  const base = { prefs: { lang: 'en', theme: 'light' } as const, online: true, email: 'manager@example.com', onSignOut: vi.fn() };
  const first = gym(1, 'owner', 'Power Gym');
  const gyms = [first, gym(2, 'captain', 'Elite')];

  it('shows header, masked email, footer and no nav by default', async () => {
    await mount(<Shell {...base} onPrefs={vi.fn()}>body</Shell>);
    expect(text()).toContain('m•••@example.com');
    expect(text()).not.toContain('manager@example.com');
    expect(text()).toContain('© 2026 Mohager');
    expect(q('a[href="https://azmm.pages.dev/privacy"]')).not.toBeNull();
    expect(q('a[href="https://azmm.pages.dev/terms"]')).not.toBeNull();
    expect(q('nav')).toBeNull();
    expect(q('img[src="/logo-96.png"]')?.getAttribute('alt')).toBe('');
  });

  it('toggles language and theme through onPrefs', async () => {
    const onPrefs = vi.fn();
    await mount(<Shell {...base} onPrefs={onPrefs}>x</Shell>);
    const lang = m<HTMLButtonElement>('button[lang=ar]');
    expect(lang.getAttribute('aria-label')).toBe('Switch to Arabic');
    await click(lang);
    expect(onPrefs).toHaveBeenCalledWith({ lang: 'ar', theme: 'light' });
    await click(q('button[aria-label="Dark theme"]'));
    expect(onPrefs).toHaveBeenCalledWith({ lang: 'en', theme: 'dark' });
  });

  it('shows the gym switcher only with more than one gym, plus nav', async () => {
    await mount(<Shell {...base} onPrefs={vi.fn()} gym={first} gyms={[first]} nav="members">x</Shell>);
    expect(q('a[href="/gyms"]')).toBeNull();
    expect(q('nav a[aria-current=page]')?.textContent).toBe('Members');
    await mount(<Shell {...base} onPrefs={vi.fn()} gym={first} gyms={gyms} nav="members">x</Shell>);
    expect(q('a[href="/gyms"]')?.getAttribute('aria-label')).toBe('Change gym, now Power Gym');
  });

  it('shows the offline banner only when offline', async () => {
    await mount(<Shell {...base} online={false} onPrefs={vi.fn()}>x</Shell>);
    expect(q('[role=status]')?.textContent).toContain(messageTables.en['state.offline']);
    await mount(<Shell {...base} onPrefs={vi.fn()}>x</Shell>);
    expect(q('[role=status]')?.textContent).toBe('');
  });

  it('opens the menu, closes on Escape and returns focus', async () => {
    await mount(<Shell {...base} onPrefs={vi.fn()}>x</Shell>);
    const button = m<HTMLButtonElement>('.menu-btn');
    expect(button.getAttribute('aria-expanded')).toBe('false');
    await click(button);
    expect(button.getAttribute('aria-expanded')).toBe('true');
    expect(q('#menu-panel')).not.toBeNull();
    await act(() => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    });
    expect(button.getAttribute('aria-expanded')).toBe('false');
    expect(q('#menu-panel')).toBeNull();
    expect(document.activeElement).toBe(button);
  });

  it('hides sign out when signed out', async () => {
    await mount(<Shell {...base} email={null} onSignOut={null} onPrefs={vi.fn()}>x</Shell>);
    expect([...host.querySelectorAll('button')].some((b) => b.textContent === 'Sign out')).toBe(false);
  });
});
