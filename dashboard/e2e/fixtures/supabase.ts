import { readFileSync } from 'node:fs';
import { test as base, expect, type Page, type Route } from '@playwright/test';

// A fake Supabase for the end-to-end tests. Every request to the placeholder
// project is answered here; any other off-site request fails the test, so a
// test can never reach a real project or a third party.

export const SUPABASE = 'https://abcdefghijklmnopqrst.supabase.co';
/** The picture CDN the e2e build points at (playwright.config.ts). */
export const CLOUDINARY = 'https://res.cloudinary.com';
export const CLOUD_PATH = '/azm-e2e/image/upload/';
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

export interface FakePictureRow {
  gym_id: string;
  exercise_id: string;
  public_id: string;
  position: number;
}

export interface FakeVideoRow {
  gym_id: string;
  exercise_id: string;
  video_id: string;
  start_seconds: number | null;
  end_seconds: number | null;
}

export interface FakeCatalogRow {
  public_id: string;
  exercise_key: string;
  frame: 'tension' | 'relaxation';
  title_en: string;
  keywords: string[];
}

/** A small slice of the picture library (exercise_images, 0013). */
export const CATALOG: FakeCatalogRow[] = [
  ['ek-0055', 'Dumbbell Bench Press', ['dumbbell', 'bench', 'press', 'chest', 'صدر', 'دمبل']],
  ['ek-0056', 'Incline Dumbbell Press', ['incline', 'dumbbell', 'press', 'chest', 'صدر', 'دمبل']],
  ['ek-0101', 'Barbell Squat', ['barbell', 'squat', 'legs', 'رجل', 'اسكوات']],
  ['ek-0102', 'Leg Press', ['leg', 'press', 'machine', 'legs', 'رجل']],
].flatMap(([key, title, words]) =>
  (['tension', 'relaxation'] as const).map((frame) => ({ public_id: `exercises/${key as string}-${frame}`, exercise_key: key as string, frame, title_en: title as string, keywords: words as string[] })),
);

export interface FakePlan {
  body: unknown;
  version: number;
  updated_by: string | null;
  updated_at: string;
  /** D4 (migration 0019): which template the plan came from. */
  template_id?: string | null;
  template_version?: number | null;
}

export interface FakeTemplate {
  id: string;
  gym_id: string;
  name: { ar: string; en: string };
  body: unknown;
  version: number;
  updated_at: string;
}

/** A small plan in the app's JSON (two days, a superset, a plate exercise). */
export function samplePlan(): { days: unknown[] } {
  const ex = (id: string, en: string, ar: string, over: Record<string, unknown> = {}) => ({ id, name: { ar, en }, sets: 3, reps: 12, rest: 90, step: 2.5, superset: false, ...over });
  return {
    days: [
      { id: 'day-1', name: { ar: 'صدر وضهر', en: 'Chest & Back' }, exercises: [ex('flat_db_press', 'Flat Dumbbell Press', 'دفع دمبل مستوي'), ex('pec_deck', 'Pec Deck', 'فراشة', { superset: true }), ex('abs', 'Abs', 'بطن', { reps: 15, step: 5 })] },
      { id: 'day-2', name: { ar: 'رجل', en: 'Legs' }, exercises: [ex('leg_press', 'Leg Press', 'دفع جهاز', { unit: 'plate', step: 5 })] },
    ],
  };
}

export interface FakeProgress {
  summary?: Record<string, unknown>;
  weeks?: Record<string, unknown>[];
  sessions?: Record<string, unknown>[];
  points?: Record<string, unknown>[];
}

export interface FakeUpload {
  path: string;
  contentType: string;
  size: number;
  /** The first bytes, to check what was really sent. */
  head: number[];
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
  gyms?: { id: string; name: string; role: 'owner' | 'captain'; logo?: boolean; historyAfterEnd?: 'readable' | 'locked'; brandColor?: string | null }[];
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
  /** The gyms' exercise pictures and videos (D2). Default: none. */
  pictures?: FakePictureRow[];
  videos?: FakeVideoRow[];
  /** Extra rows of the picture library, e.g. hostile ones. */
  catalogExtra?: Record<string, unknown>[];
  /** What set_gym_exercise_images answers. */
  savePictures?: 'ok' | 'forbidden' | 'too_many_pictures_in_gym';
  /** What writes to gym_exercise_videos answer. */
  saveVideo?: 'ok' | 'forbidden';
  /** Make the media reads fail with 500. */
  mediaFails?: boolean;
  /** D3: members' plans by membership id. */
  plans?: Record<string, FakePlan>;
  /** What save_plan answers (ok = the real rules of the fake). */
  savePlan?: 'ok' | 'forbidden' | 'invalid' | 'server_error';
  /** Make the plan reads fail with 500. */
  plansFail?: boolean;
  /** D4: the gyms' plan templates. */
  templates?: FakeTemplate[];
  /** D5: rows of the four progress views, per membership id. */
  progress?: Record<string, FakeProgress>;
  /** D5: make the progress views fail with 500. */
  progressFails?: boolean;
  /** Answer as before migration 0019 (no plan_templates table, no template columns). */
  noTemplates?: boolean;
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
  /** D2: the live media tables, and every picture URL the page asked the CDN for. */
  readonly pictures: FakePictureRow[];
  readonly videos: FakeVideoRow[];
  readonly cdn: string[];
  /** D3: the live plans table (membership id → row). */
  readonly plans: Record<string, FakePlan>;
  /** D4: the live plan_templates table. */
  readonly templates: FakeTemplate[];
  /** D5: the gyms as the server holds them now, uploads and removals in gym-logos. */
  readonly gymRows: Record<string, { name: string; logo_path: string | null; history_after_end: string; brand_color: string | null }>;
  readonly uploads: FakeUpload[];
  readonly removed: string[];
  /** Changes failure options in the middle of a test. */
  set(change: Pick<MockOptions, 'failInsertAt' | 'createInvite' | 'patch' | 'logoFile' | 'savePictures' | 'saveVideo' | 'mediaFails' | 'savePlan' | 'plansFail' | 'progressFails'>): void;
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
    savePictures: options.savePictures ?? 'ok',
    saveVideo: options.saveVideo ?? 'ok',
    mediaFails: options.mediaFails ?? false,
    savePlan: options.savePlan ?? 'ok',
    plansFail: options.plansFail ?? false,
    progressFails: options.progressFails ?? false,
  };
  const uploaded = new Map<string, Buffer>();
  const catalog: Record<string, unknown>[] = [...CATALOG.map((r) => ({ ...r })), ...(options.catalogExtra ?? [])];
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
    pictures: options.pictures ?? [],
    videos: options.videos ?? [],
    cdn: [],
    plans: options.plans ?? {},
    templates: options.templates ?? [],
    gymRows: Object.fromEntries(gyms.map((g) => [g.id, { name: g.name, logo_path: g.logo ? `${g.id}/logo.png` : null, history_after_end: g.historyAfterEnd ?? 'readable', brand_color: g.brandColor ?? null }])),
    uploads: [],
    removed: [],
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
    if (url.origin === CLOUDINARY && route.request().method() === 'GET') {
      mock.cdn.push(url.pathname + url.search);
      if (!url.pathname.startsWith(CLOUD_PATH)) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ status: 200, contentType: 'image/png', body: LOGO_PNG });
    }
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
            gym: { id: g.id, ...mock.gymRows[g.id] },
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
    // ---- D4: plan templates (0019) ----
    if (path === '/rest/v1/plan_templates') {
      if (options.noTemplates) return error(route, 404, 'PGRST205', "Could not find the table 'public.plan_templates' in the schema cache");
      const isManager = (gymId: string) => gyms.some((g) => g.id === gymId);
      const id = wanted(url, 'id');
      if (method === 'GET') {
        const gymId = wanted(url, 'gym_id');
        return json(route, 200, mock.templates.filter((t) => t.gym_id === gymId && isManager(gymId)).map((t) => ({ id: t.id, name: t.name, body: t.body, version: t.version, updated_at: t.updated_at })));
      }
      if (method === 'POST') {
        if (!isManager(String(record.gym_id))) return error(route, 403, '42501', 'new row violates row-level security policy');
        if (Object.keys(record).some((k) => !['gym_id', 'name', 'body'].includes(k))) return error(route, 403, '42501', 'permission denied for table plan_templates');
        if (mock.templates.filter((t) => t.gym_id === record.gym_id).length >= 50) return error(route, 400, '23514', 'too_many_templates_in_gym');
        const row: FakeTemplate = { id: uid(++idCounter), gym_id: String(record.gym_id), name: record.name as FakeTemplate['name'], body: record.body, version: 1, updated_at: new Date().toISOString() };
        mock.templates.push(row);
        return json(route, 201, { id: row.id, name: row.name, body: row.body, version: row.version, updated_at: row.updated_at });
      }
      const row = mock.templates.find((t) => t.id === id && isManager(t.gym_id));
      if (method === 'PATCH') {
        if (!row) return json(route, 200, []);
        if (record.name) row.name = record.name as FakeTemplate['name'];
        if (record.body) {
          row.body = record.body;
          row.version++;
        }
        return json(route, 200, [{ id: row.id, version: row.version }]);
      }
      if (method === 'DELETE') {
        if (!row) return json(route, 200, []);
        mock.templates.splice(mock.templates.indexOf(row), 1);
        for (const p of Object.values(mock.plans)) if (p.template_id === row.id) p.template_id = null;
        return json(route, 200, [{ id: row.id }]);
      }
    }
    if (path === '/rest/v1/rpc/apply_plan_template') {
      mock.rpcs.push({ name: 'apply_plan_template', body: record });
      const target = mock.members.find((m) => m.id === record.p_membership_id);
      const tpl = mock.templates.find((t) => t.id === record.p_template_id);
      const me = gyms.find((g) => g.id === target?.gym_id);
      if (!target || !tpl || !me || tpl.gym_id !== target.gym_id || (me.role === 'captain' && target.role !== 'trainee')) return error(route, 403, '42501', 'forbidden');
      const current = mock.plans[target.id];
      if ((current?.version ?? 0) !== record.p_base_version) return error(route, 400, 'P0001', 'plan_changed');
      const version = (current?.version ?? 0) + 1;
      mock.plans[target.id] = { body: tpl.body, version, updated_by: M.owner, updated_at: new Date().toISOString(), template_id: tpl.id, template_version: tpl.version };
      return json(route, 200, { version, updated_by: M.owner, updated_at: mock.plans[target.id]?.updated_at, template_id: tpl.id, template_version: tpl.version });
    }
    // ---- D3: plans (0007) ----
    if (path === '/rest/v1/plans' && method === 'GET') {
      if (behaviour.plansFail) return json(route, 500, { code: 'XX000', message: 'boom' });
      const select = url.searchParams.get('select') ?? '';
      if (options.noTemplates && select.includes('template_')) return error(route, 400, '42703', 'column plans.template_id does not exist');
      const byTemplate = wanted(url, 'template_id');
      if (byTemplate) {
        return json(route, 200, Object.entries(mock.plans).filter(([, p]) => p.template_id === byTemplate).map(([id, p]) => ({ membership_id: id, version: p.version, body: p.body })));
      }
      const one = wanted(url, 'membership_id');
      const inList = /^in\.\((.*)\)$/.exec(url.searchParams.get('membership_id') ?? '');
      const ids = inList ? (inList[1] ?? '').split(',').map((w) => w.replace(/^"|"$/g, '')) : [one];
      const rows = ids.flatMap((id) => {
        const p = mock.plans[id];
        return p ? [{ membership_id: id, ...p }] : [];
      });
      // The Exercises tab reads only the day lists (select=days:body->days).
      if (select.includes('days:body->days')) return json(route, 200, rows.map((r) => ({ days: (r.body as { days?: unknown } | null)?.days ?? null })));
      return json(route, 200, rows);
    }
    if (path === '/rest/v1/rpc/save_plan') {
      mock.rpcs.push({ name: 'save_plan', body: record });
      const target = mock.members.find((m) => m.id === record.p_membership_id);
      const me = gyms.find((g) => g.id === target?.gym_id);
      // i_manage_role: owners manage anyone, captains trainees only.
      if (!target || !me || (me.role === 'captain' && target.role !== 'trainee') || behaviour.savePlan === 'forbidden') return error(route, 403, '42501', 'forbidden');
      if (behaviour.savePlan === 'server_error') return error(route, 500, 'XX000', 'boom');
      const body = record.p_body as { days?: unknown[] } | undefined;
      if (behaviour.savePlan === 'invalid' || !Array.isArray(body?.days) || body.days.length === 0) return error(route, 400, '22023', 'invalid_plan: bad day count');
      const current = mock.plans[target.id];
      const version = (current?.version ?? 0) + 1;
      // Like the real save_plan: the template link (0019) is kept.
      mock.plans[target.id] = { body, version, updated_by: M.owner, updated_at: new Date().toISOString(), template_id: current?.template_id ?? null, template_version: current?.template_version ?? null };
      return json(route, 200, { version, updated_by: M.owner, updated_at: mock.plans[target.id]?.updated_at });
    }
    // ---- D2: exercise media (0013, 0015, 0017) ----
    const isManager = (gymId: string) => gyms.some((g) => g.id === gymId);
    if (path === '/rest/v1/exercise_images' && method === 'GET') {
      const ov = /^ov\.\{(.*)\}$/.exec(url.searchParams.get('keywords') ?? '');
      const cs = /^cs\.\{(.*)\}$/.exec(url.searchParams.get('keywords') ?? '');
      const inList = /^in\.\((.*)\)$/.exec(url.searchParams.get('public_id') ?? '');
      let rows = catalog;
      if (ov) {
        const words = (ov[1] ?? '').split(',').map((w) => w.replace(/^"|"$/g, ''));
        rows = rows.filter((r) => Array.isArray(r.keywords) && (r.keywords as string[]).some((k) => words.includes(k)));
      }
      if (cs) {
        const words = (cs[1] ?? '').split(',').map((w) => w.replace(/^"|"$/g, ''));
        rows = rows.filter((r) => Array.isArray(r.keywords) && words.every((w) => (r.keywords as string[]).includes(w)));
      }
      if (inList) {
        const ids = (inList[1] ?? '').split(',').map((w) => w.replace(/^"|"$/g, ''));
        rows = rows.filter((r) => ids.includes(String(r.public_id)));
      }
      return json(route, 200, rows.map((r) => ({ public_id: r.public_id, exercise_key: r.exercise_key, frame: r.frame, title_en: r.title_en, keywords: r.keywords })));
    }
    if (path === '/rest/v1/gym_exercise_images' && method === 'GET') {
      if (behaviour.mediaFails) return json(route, 500, { code: 'XX000', message: 'boom' });
      const gymId = wanted(url, 'gym_id');
      return json(route, 200, mock.pictures.filter((r) => r.gym_id === gymId).sort((a, b) => a.exercise_id.localeCompare(b.exercise_id) || a.position - b.position).map((r) => ({ exercise_id: r.exercise_id, public_id: r.public_id, position: r.position })));
    }
    if (path === '/rest/v1/rpc/set_gym_exercise_images') {
      mock.rpcs.push({ name: 'set_gym_exercise_images', body: record });
      if (behaviour.savePictures === 'forbidden' || !isManager(String(record.p_gym_id))) return error(route, 403, '42501', 'forbidden');
      if (behaviour.savePictures === 'too_many_pictures_in_gym') return error(route, 400, '23514', 'too_many_pictures_in_gym');
      const ids = record.p_public_ids as string[];
      if (ids.some((id) => !catalog.some((c) => c.public_id === id))) return error(route, 409, '23503', 'insert or update on table "gym_exercise_images" violates foreign key constraint');
      const gymId = String(record.p_gym_id);
      const exerciseId = String(record.p_exercise_id);
      for (let i = mock.pictures.length - 1; i >= 0; i--) {
        const r = mock.pictures[i];
        if (r && r.gym_id === gymId && r.exercise_id === exerciseId) mock.pictures.splice(i, 1);
      }
      ids.forEach((id, i) => mock.pictures.push({ gym_id: gymId, exercise_id: exerciseId, public_id: id, position: i + 1 }));
      return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
    }
    if (path === '/rest/v1/gym_exercise_videos') {
      const gymId = wanted(url, 'gym_id');
      const exerciseId = wanted(url, 'exercise_id');
      if (method === 'GET') {
        if (behaviour.mediaFails) return json(route, 500, { code: 'XX000', message: 'boom' });
        return json(route, 200, mock.videos.filter((r) => r.gym_id === gymId).map((r) => ({ exercise_id: r.exercise_id, video_id: r.video_id, start_seconds: r.start_seconds, end_seconds: r.end_seconds })));
      }
      if (behaviour.saveVideo === 'forbidden') return error(route, 403, '42501', 'new row violates row-level security policy');
      if (method === 'POST') {
        if (!isManager(String(record.gym_id))) return error(route, 403, '42501', 'new row violates row-level security policy');
        if (mock.videos.some((v) => v.gym_id === record.gym_id && v.exercise_id === record.exercise_id)) return error(route, 409, '23505', 'duplicate key value violates unique constraint "gym_exercise_videos_one_per_exercise"');
        mock.videos.push({ gym_id: String(record.gym_id), exercise_id: String(record.exercise_id), video_id: String(record.video_id), start_seconds: (record.start_seconds as number | null) ?? null, end_seconds: (record.end_seconds as number | null) ?? null });
        return route.fulfill({ status: 201, headers: { 'access-control-allow-origin': '*' } });
      }
      if (method === 'PATCH') {
        // Only the columns 0017 lets anyone update.
        if (Object.keys(record).some((k) => !['video_id', 'start_seconds', 'end_seconds'].includes(k))) return error(route, 403, '42501', 'permission denied for table gym_exercise_videos');
        const row = mock.videos.find((v) => v.gym_id === gymId && v.exercise_id === exerciseId);
        if (!row) return json(route, 200, []);
        Object.assign(row, record);
        return json(route, 200, [{ exercise_id: row.exercise_id }]);
      }
      if (method === 'DELETE') {
        const i = mock.videos.findIndex((v) => v.gym_id === gymId && v.exercise_id === exerciseId);
        if (i >= 0) mock.videos.splice(i, 1);
        return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
      }
    }
    // ---- D5: progress views (0012) and gym settings (0005, 0008) ----
    if (path.startsWith('/rest/v1/member_') && method === 'GET') {
      if (behaviour.progressFails) return json(route, 500, { code: 'XX000', message: 'boom' });
      // RLS of the views: active members only; a captain sees trainees only.
      const visible = (id: string) => {
        const m = mock.members.find((x) => x.id === id);
        const me = gyms.find((g) => g.id === m?.gym_id);
        return !!m && !!me && m.status === 'active' && (me.role === 'owner' || m.role === 'trainee');
      };
      const one = wanted(url, 'membership_id');
      const gymId = wanted(url, 'gym_id');
      const ids = one ? [one] : mock.members.filter((m) => m.gym_id === gymId).map((m) => m.id);
      const rows = ids.filter(visible).flatMap((id) => {
        const p = options.progress?.[id] ?? {};
        switch (path) {
          case '/rest/v1/member_progress_summary': {
            const base = { membership_id: id, level: 'beginner', best_level: 'beginner', streak_weeks: 0, comeback: false, weeks_to_next: 4, workouts_total: 0, first_workout_at: null, last_workout_at: null };
            return [{ ...base, ...p.summary }];
          }
          case '/rest/v1/member_weekly_attendance':
            return p.weeks ?? [];
          case '/rest/v1/member_session_stats':
            return p.sessions ?? [];
          case '/rest/v1/member_exercise_progress':
            return p.points ?? [];
          default:
            return [];
        }
      });
      return json(route, 200, rows);
    }
    if (path === '/rest/v1/gyms' && method === 'PATCH') {
      const id = wanted(url, 'id');
      const row = mock.gymRows[id];
      if (!row || !gyms.some((g) => g.id === id)) return json(route, 200, []);
      if (Object.keys(record).some((k) => !['name', 'logo_path', 'history_after_end', 'brand_color'].includes(k))) return error(route, 403, '42501', 'permission denied for table gyms');
      if (typeof record.name === 'string' && (record.name.length < 1 || Array.from(record.name).length > 60 || record.name !== record.name.trim())) return error(route, 400, '23514', 'new row for relation "gyms" violates check constraint "gyms_name_check"');
      // Migration 0021: '#rrggbb' in lower case, channels at least 40 apart, or null; owners only.
      if ('brand_color' in record) {
        if (gyms.find((g) => g.id === id)?.role !== 'owner') return json(route, 200, []);
        const c = record.brand_color;
        const rgb = typeof c === 'string' && /^#[0-9a-f]{6}$/.test(c) ? [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16)) : null;
        if (c !== null && (!rgb || Math.max(...rgb) - Math.min(...rgb) < 40)) return error(route, 400, '23514', 'new row for relation "gyms" violates check constraint "gyms_brand_color_ok"');
      }
      Object.assign(row, record);
      return json(route, 200, [{ id }]);
    }
    if (path.startsWith('/storage/v1/object/gym-logos/') && (method === 'POST' || method === 'PUT')) {
      const objectPath = path.replace('/storage/v1/object/gym-logos/', '');
      // supabase-js sends a Blob as multipart/form-data: the file part carries the bytes and its type.
      let bytes = route.request().postDataBuffer() ?? Buffer.alloc(0);
      let type = route.request().headers()['content-type'] ?? '';
      const boundary = /boundary=(.+)$/.exec(type)?.[1];
      if (boundary) {
        const marker = Buffer.from(`--${boundary}`);
        let start = 0;
        for (;;) {
          const at = bytes.indexOf(marker, start);
          if (at < 0) break;
          const next = bytes.indexOf(marker, at + marker.length);
          const part = bytes.subarray(at + marker.length, next < 0 ? bytes.length : next);
          const split = part.indexOf('\r\n\r\n');
          const headers = part.subarray(0, Math.max(0, split)).toString('latin1');
          const partType = /content-type:\s*([^\r\n]+)/i.exec(headers)?.[1];
          if (partType && split >= 0 && next >= 0) {
            type = partType.trim();
            bytes = part.subarray(split + 4, part.length - 2);
            break;
          }
          start = at + marker.length;
        }
      }
      if (!/^[0-9a-f-]{36}\/logo\.(png|jpe?g)$/.test(objectPath) || !gyms.some((g) => objectPath.startsWith(`${g.id}/`))) return json(route, 403, { statusCode: '403', error: 'Unauthorized', message: 'new row violates row-level security policy' });
      if (bytes.length > 524_288) return json(route, 413, { statusCode: '413', error: 'Payload too large', message: 'The object exceeded the maximum allowed size' });
      mock.uploads.push({ path: objectPath, contentType: type, size: bytes.length, head: [...bytes.subarray(0, 8)] });
      uploaded.set(objectPath, bytes);
      return json(route, 200, { Key: `gym-logos/${objectPath}`, Id: uid(++idCounter) });
    }
    if (path === '/storage/v1/object/gym-logos' && method === 'DELETE') {
      for (const pref of (record.prefixes as string[] | undefined) ?? []) {
        mock.removed.push(pref);
        uploaded.delete(pref);
      }
      return json(route, 200, []);
    }
    if (path.startsWith('/storage/v1/object/') && method === 'GET') {
      const objectPath = path.replace(/^\/storage\/v1\/object\/(authenticated\/)?gym-logos\//, '');
      const mine = uploaded.get(objectPath);
      if (mine) {
        mock.storage.push(path.replace('/storage/v1/object/', ''));
        return route.fulfill({ status: 200, contentType: objectPath.endsWith('png') ? 'image/png' : 'image/jpeg', headers: { 'access-control-allow-origin': '*' }, body: mine });
      }
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
