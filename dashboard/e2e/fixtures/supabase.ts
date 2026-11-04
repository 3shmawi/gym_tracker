import { test as base, expect, type Page, type Route } from '@playwright/test';

// A fake Supabase for the end-to-end tests. Every request to the placeholder
// project is answered here; any other off-site request fails the test, so a
// test can never reach a real project or a third party.

export const SUPABASE = 'https://abcdefghijklmnopqrst.supabase.co';
export const USER_ID = '11111111-1111-4111-8111-111111111111';
export const PERSON_ID = '22222222-2222-4222-8222-222222222222';
export const GYM_A = { id: '33333333-3333-4333-8333-333333333333', name: 'Power Gym' };
export const GYM_B = { id: '44444444-4444-4444-8444-444444444444', name: 'جيم النخبة' };
export const EMAIL = 'captain@example.com';
export const GOOD_CODE = '481270';

export interface MockOptions {
  /** Gyms the person manages, with role. Default: both gyms. */
  gyms?: { id: string; name: string; role: 'owner' | 'captain' }[];
  /** People row exists (false = signed in but manages nothing). */
  hasPerson?: boolean;
  /** What /otp answers. */
  otp?: 'ok' | 'unknown_user' | 'rate_limited' | 'server_error';
  /** What /verify answers for a wrong code. */
  wrongCode?: 'otp_expired' | 'invalid';
  /** Make REST calls fail with 500 (until `recover()` is called). */
  restFails?: boolean;
}

export interface Mock {
  /** Every request body sent to /auth/v1/otp, parsed. */
  readonly otpRequests: Record<string, unknown>[];
  readonly verifyRequests: Record<string, unknown>[];
  readonly logoutRequests: string[];
  recover(): void;
}

function b64url(value: object): string {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

export function fakeSession(email = EMAIL, anonymous = false) {
  const now = Math.floor(Date.now() / 1000);
  const claims = { sub: USER_ID, aud: 'authenticated', role: 'authenticated', email, is_anonymous: anonymous, exp: now + 3600, iat: now };
  return {
    access_token: `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(claims)}.signature`,
    token_type: 'bearer',
    expires_in: 3600,
    expires_at: now + 3600,
    refresh_token: 'refresh-token-e2e',
    user: {
      id: USER_ID,
      aud: 'authenticated',
      role: 'authenticated',
      email,
      is_anonymous: anonymous,
      app_metadata: { provider: 'email' },
      user_metadata: {},
      created_at: '2026-11-01T00:00:00Z',
    },
  };
}

const json = (route: Route, status: number, body: unknown, headers: Record<string, string> = {}) =>
  route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*', ...headers }, body: JSON.stringify(body) });

export async function mockSupabase(page: Page, options: MockOptions = {}): Promise<Mock> {
  const gyms = options.gyms ?? [
    { ...GYM_A, role: 'owner' as const },
    { ...GYM_B, role: 'captain' as const },
  ];
  let restFails = options.restFails ?? false;
  const mock: Mock = {
    otpRequests: [],
    verifyRequests: [],
    logoutRequests: [],
    recover: () => {
      restFails = false;
    },
  };

  // Nothing leaves the machine except the local preview server and the fake project.
  await page.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.hostname === 'localhost' || url.hostname === '127.0.0.1') return route.continue();
    if (url.origin !== SUPABASE) return route.abort('blockedbyclient');
    const method = route.request().method();
    if (method === 'OPTIONS') {
      return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    }
    const path = url.pathname;

    if (path === '/auth/v1/otp') {
      mock.otpRequests.push(route.request().postDataJSON() as Record<string, unknown>);
      switch (options.otp ?? 'ok') {
        case 'ok':
          return json(route, 200, {});
        case 'unknown_user':
          return json(route, 422, { code: 'otp_disabled', error_code: 'otp_disabled', msg: 'Signups not allowed for otp' });
        case 'rate_limited':
          return json(route, 429, { code: 'over_email_send_rate_limit', error_code: 'over_email_send_rate_limit', msg: 'email rate limit exceeded' });
        case 'server_error':
          return json(route, 500, { msg: 'boom' });
      }
    }
    if (path === '/auth/v1/verify') {
      const body = route.request().postDataJSON() as Record<string, unknown>;
      mock.verifyRequests.push(body);
      if (body.token === GOOD_CODE) return json(route, 200, fakeSession(typeof body.email === 'string' ? body.email : EMAIL));
      return options.wrongCode === 'otp_expired'
        ? json(route, 403, { code: 'otp_expired', error_code: 'otp_expired', msg: 'Token has expired or is invalid' })
        : json(route, 403, { code: 'otp_invalid', error_code: 'otp_invalid', msg: 'Token has expired or is invalid' });
    }
    if (path === '/auth/v1/logout') {
      mock.logoutRequests.push(url.search);
      return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
    }
    if (path === '/auth/v1/user') return json(route, 200, fakeSession().user);
    if (path === '/auth/v1/token') return json(route, 200, fakeSession());

    if (path.startsWith('/rest/v1/') && restFails) return json(route, 500, { code: 'XX000', message: 'boom' });
    if (path === '/rest/v1/people') {
      return json(route, 200, options.hasPerson === false ? [] : [{ id: PERSON_ID }]);
    }
    if (path === '/rest/v1/memberships') {
      if (method === 'HEAD') {
        const gymId = (url.searchParams.get('gym_id') ?? '').replace(/^eq\./, '');
        const count = gymId === GYM_A.id ? 42 : 17;
        return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': `*/${count}` } });
      }
      return json(route, 200, gyms.map((g) => ({ role: g.role, gym: { id: g.id, name: g.name } })));
    }
    return json(route, 404, { code: 'PGRST205', message: `not mocked: ${method} ${path}` });
  });
  return mock;
}

/** Puts a stored session in the browser before the page loads (as supabase-js keeps it). */
export async function signedInBefore(page: Page, anonymous = false): Promise<void> {
  const key = `sb-abcdefghijklmnopqrst-auth-token`;
  const value = JSON.stringify(fakeSession(EMAIL, anonymous));
  await page.addInitScript(([k, v]) => {
    window.localStorage.setItem(k, v);
  }, [key, value] as const);
}

/** Language and theme for a test, as the dashboard stores them. */
export async function prefs(page: Page, lang: 'en' | 'ar', theme: 'light' | 'dark'): Promise<void> {
  await page.addInitScript((v) => {
    window.localStorage.setItem('azm.dashboard.prefs.v1', v);
  }, JSON.stringify({ lang, theme }));
}

export const test = base;
export { expect };
