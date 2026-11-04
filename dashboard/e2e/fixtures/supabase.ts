import { readFileSync } from 'node:fs';
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
/** The server's code alphabet (0006 generate_invite_code). */
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const LOGO_PNG = readFileSync(new URL('../../public/logo-96.png', import.meta.url));
const uid = (n: number) => `aaaaaaaa-0000-4000-8000-${String(n).padStart(12, '0')}`;
const DAY = 86_400_000;

export interface FakeMember {
  id: string;
  gym_id: string;
  display_name: string;
  role: 'owner' | 'captain' | 'trainee';
  status: 'pending' | 'active' | 'ended';
  can_edit_targets: boolean;
  can_edit_plan: boolean;
  can_build_own_plan: boolean;
  joined_at: string | null;
  ended_at: string | null;
  created_at: string;
}

export interface FakeInvite {
  id: string;
  gym_id: string;
  membership_id: string;
  kind: 'join' | 'recover';
  created_at: string;
  expires_at: string;
  used_at: string | null;
  revoked_at: string | null;
}

/** Member ids of the seed data (gym A), for tests. */
export const M = {
  owner: uid(1),
  captain: uid(2),
  ahmed: uid(3), //   active trainee, weights and reps
  mona: uid(4), //    active trainee, whole plan
  youssef: uid(5), // active trainee, nothing
  layla: uid(6), //   waiting, code sent
  karim: uid(7), //   waiting, code expired
  hana: uid(8), //    ended
} as const;

/** Gym A's people: an owner, a captain, three active trainees, two waiting, one ended. */
export function seedMembers(gymId: string = GYM_A.id, now = Date.now()): { members: FakeMember[]; invites: FakeInvite[] } {
  const iso = (ms: number) => new Date(ms).toISOString();
  const row = (id: string, name: string, role: FakeMember['role'], status: FakeMember['status'], flags: [boolean, boolean, boolean] = [false, false, false]): FakeMember => ({
    id,
    gym_id: gymId,
    display_name: name,
    role,
    status,
    can_edit_targets: flags[0],
    can_edit_plan: flags[1],
    can_build_own_plan: flags[2],
    joined_at: status === 'active' ? iso(now - 30 * DAY) : null,
    ended_at: status === 'ended' ? iso(now - 3 * DAY) : null,
    created_at: iso(now - 40 * DAY),
  });
  const invite = (n: number, membership: string, expiresInDays: number): FakeInvite => ({
    id: uid(100 + n),
    gym_id: gymId,
    membership_id: membership,
    kind: 'join',
    created_at: iso(now - DAY),
    expires_at: iso(now + expiresInDays * DAY),
    used_at: null,
    revoked_at: null,
  });
  return {
    members: [
      row(M.owner, 'Sara Owner', 'owner', 'active'),
      row(M.captain, 'Omar Captain', 'captain', 'active'),
      row(M.ahmed, 'Ahmed Hassan', 'trainee', 'active', [true, false, false]),
      row(M.mona, 'Mona Ali', 'trainee', 'active', [true, true, false]),
      row(M.youssef, 'Youssef Khaled', 'trainee', 'active'),
      row(M.layla, 'Layla Ibrahim', 'trainee', 'pending'),
      row(M.karim, 'Karim Nabil', 'trainee', 'pending'),
      row(M.hana, 'Hana Adel', 'trainee', 'ended'),
    ],
    invites: [invite(1, M.layla, 5), invite(2, M.karim, -2)],
  };
}

export interface MockOptions {
  /** Gyms the person manages, with role. Default: both gyms. */
  gyms?: { id: string; name: string; role: 'owner' | 'captain'; logo?: boolean; historyAfterEnd?: 'readable' | 'locked' }[];
  /** Members and invites of the gyms (default: gym A's seed). */
  members?: FakeMember[];
  invites?: FakeInvite[];
  /** 1-based numbers of the memberships inserts that fail with a server error. */
  failInsertAt?: number[];
  /** What create_invite answers. */
  createInvite?: 'ok' | 'forbidden' | 'person_in_other_gym';
  /** What PATCH /memberships answers: ok, the last-owner guard, or [] (RLS filtered the row out). */
  patch?: 'ok' | 'last_owner' | 'rls_empty';
  /** Milliseconds the write calls (insert, create_invite) wait before answering, so progress can be seen. */
  delayMs?: number;
  /** The gym logo in the storage bucket: a PNG (default) or 404. */
  logoFile?: 'png' | 'missing';
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
  /** Every request to the fake project, in order. */
  readonly requests: { method: string; path: string; search: string; body: unknown }[];
  /** Bodies of POST /memberships (new pending members). */
  readonly inserts: Record<string, unknown>[];
  /** PATCH /memberships: the member id and the body. */
  readonly patches: { id: string; body: Record<string, unknown> }[];
  /** RPC calls: name and body. */
  readonly rpcs: { name: string; body: Record<string, unknown> }[];
  /** Storage object paths asked for. */
  readonly storage: string[];
  /** The live tables. */
  readonly members: FakeMember[];
  readonly invites: FakeInvite[];
  /** Codes handed out by create_invite, in order. */
  readonly codes: string[];
  /** Changes failure options in the middle of a test. */
  set(change: Pick<MockOptions, 'failInsertAt' | 'createInvite' | 'patch' | 'logoFile'>): void;
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
  const behaviour = {
    failInsertAt: options.failInsertAt ?? [],
    createInvite: options.createInvite ?? 'ok',
    patch: options.patch ?? 'ok',
    logoFile: options.logoFile ?? 'png',
  };
  const seed = seedMembers();
  const mock: Mock = {
    otpRequests: [],
    verifyRequests: [],
    logoutRequests: [],
    requests: [],
    inserts: [],
    patches: [],
    rpcs: [],
    storage: [],
    members: options.members ?? seed.members,
    invites: options.invites ?? seed.invites,
    codes: [],
    set: (change) => {
      Object.assign(behaviour, change);
    },
    recover: () => {
      restFails = false;
    },
  };
  let insertCount = 0;
  let idCounter = 1000;
  let codeSeed = 20_261_104;
  const newCode = (): string => {
    for (;;) {
      let code = '';
      for (let i = 0; i < 6; i++) {
        codeSeed = (codeSeed * 1_103_515_245 + 12_345) % 2_147_483_648;
        code += CODE_ALPHABET.charAt(Math.floor(codeSeed / 65_536) % CODE_ALPHABET.length);
      }
      if (!mock.codes.includes(code)) return code;
    }
  };
  const wanted = (url: URL, name: string) => (url.searchParams.get(name) ?? '').replace(/^eq\./, '');
  const error = (route: Route, status: number, code: string, message: string) => json(route, status, { code, message, details: null, hint: null });

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
    const bodyText = route.request().postData();
    let body: unknown = bodyText;
    try {
      if (bodyText) body = JSON.parse(bodyText) as unknown;
    } catch {
      // Not JSON: keep the text.
    }
    mock.requests.push({ method, path, search: url.search, body });
    const record = (body ?? {}) as Record<string, unknown>;

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
      // The real server answers otp_expired for wrong codes too (verify.go).
      return options.wrongCode !== 'invalid'
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
        const gymId = wanted(url, 'gym_id');
        const count = gymId === GYM_A.id ? 42 : 17;
        return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', 'content-range': `*/${count}` } });
      }
      if (method === 'GET' && (url.searchParams.get('select') ?? '').includes('gym:gyms')) {
        return json(
          route,
          200,
          gyms.map((g) => ({
            role: g.role,
            gym: { id: g.id, name: g.name, logo_path: g.logo ? `${g.id}/logo.png` : null, history_after_end: g.historyAfterEnd ?? 'readable' },
          })),
        );
      }
      if (method === 'GET') {
        const gymId = wanted(url, 'gym_id');
        return json(route, 200, mock.members.filter((m) => m.gym_id === gymId));
      }
      if (method === 'POST') {
        if (options.delayMs) await new Promise((resolve) => setTimeout(resolve, options.delayMs));
        insertCount++;
        if (behaviour.failInsertAt.includes(insertCount)) return error(route, 500, 'XX000', 'boom');
        mock.inserts.push(record);
        const row: FakeMember = {
          id: uid(++idCounter),
          gym_id: String(record.gym_id),
          display_name: String(record.display_name),
          role: record.role as FakeMember['role'],
          status: 'pending',
          can_edit_targets: record.can_edit_targets === true,
          can_edit_plan: record.can_edit_plan === true,
          can_build_own_plan: record.can_build_own_plan === true,
          joined_at: null,
          ended_at: null,
          created_at: new Date().toISOString(),
        };
        mock.members.push(row);
        // .select('id').single() asks for one object (Accept: application/vnd.pgrst.object+json).
        return json(route, 201, { id: row.id });
      }
      if (method === 'PATCH') {
        const id = wanted(url, 'id');
        mock.patches.push({ id, body: record });
        if (behaviour.patch === 'last_owner') return error(route, 400, '23514', 'a gym needs at least one active owner');
        const row = mock.members.find((m) => m.id === id);
        if (behaviour.patch === 'rls_empty' || !row) return json(route, 200, []);
        Object.assign(row, record);
        if (record.status === 'ended') row.ended_at = new Date().toISOString();
        return json(route, 200, [{ id }]);
      }
    }
    if (path === '/rest/v1/invites' && method === 'GET') {
      const gymId = wanted(url, 'gym_id');
      return json(route, 200, mock.invites.filter((i) => i.gym_id === gymId));
    }
    if (path === '/rest/v1/rpc/create_invite') {
      mock.rpcs.push({ name: 'create_invite', body: record });
      if (options.delayMs) await new Promise((resolve) => setTimeout(resolve, options.delayMs));
      if (behaviour.createInvite === 'forbidden') return error(route, 403, '42501', 'forbidden');
      if (behaviour.createInvite === 'person_in_other_gym') return error(route, 400, '22023', 'person_in_other_gym');
      const member = mock.members.find((m) => m.id === record.p_membership_id);
      if (!member) return error(route, 400, '22023', 'invalid_membership');
      const now = Date.now();
      for (const old of mock.invites) {
        if (old.membership_id === member.id && !old.used_at && !old.revoked_at) old.revoked_at = new Date(now).toISOString();
      }
      const code = newCode();
      mock.codes.push(code);
      const invite: FakeInvite = {
        id: uid(++idCounter),
        gym_id: member.gym_id,
        membership_id: member.id,
        kind: record.p_kind === 'recover' ? 'recover' : 'join',
        created_at: new Date(now).toISOString(),
        expires_at: new Date(now + 7 * DAY).toISOString(),
        used_at: null,
        revoked_at: null,
      };
      mock.invites.push(invite);
      return json(route, 200, { invite_id: invite.id, code, expires_at: invite.expires_at });
    }
    if (path === '/rest/v1/rpc/revoke_invite') {
      mock.rpcs.push({ name: 'revoke_invite', body: record });
      const invite = mock.invites.find((i) => i.id === record.p_invite_id);
      if (invite) invite.revoked_at = new Date().toISOString();
      return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
    }
    if (path.startsWith('/storage/v1/object/') && method === 'GET') {
      mock.storage.push(path.replace('/storage/v1/object/', ''));
      if (behaviour.logoFile === 'missing') return json(route, 404, { statusCode: '404', error: 'not_found', message: 'Object not found' });
      return route.fulfill({ status: 200, contentType: 'image/png', headers: { 'access-control-allow-origin': '*' }, body: LOGO_PNG });
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
