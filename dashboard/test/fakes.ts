/* eslint-disable @typescript-eslint/no-explicit-any, @typescript-eslint/no-unsafe-return */
import type { SupabaseClient } from '@supabase/supabase-js';
import { vi } from 'vitest';

/** A thenable query builder: every method returns itself; awaiting gives `result`. */
export function chain(result: unknown): any {
  const c: any = new Proxy(
    {},
    {
      get(_target, prop) {
        if (prop === 'then') return (resolve: (v: unknown) => void) => { resolve(result); };
        return () => c;
      },
    },
  );
  return c;
}

export interface AuthFake {
  signInWithOtp: ReturnType<typeof vi.fn>;
  verifyOtp: ReturnType<typeof vi.fn>;
  getSession: ReturnType<typeof vi.fn>;
  signOut: ReturnType<typeof vi.fn>;
  onAuthStateChange: ReturnType<typeof vi.fn>;
}

export function fakeAuthClient(overrides: Partial<AuthFake> = {}): { client: SupabaseClient; auth: AuthFake } {
  const auth: AuthFake = {
    signInWithOtp: vi.fn(() => Promise.resolve({ error: null })),
    verifyOtp: vi.fn(() => Promise.resolve({ data: { session: null }, error: null })),
    getSession: vi.fn(() => Promise.resolve({ data: { session: null }, error: null })),
    signOut: vi.fn(() => Promise.resolve({ error: null })),
    onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
    ...overrides,
  };
  return { client: { auth } as unknown as SupabaseClient, auth };
}

export function fakeDataClient(opts: { person: { id: string } | null; rows: unknown[]; counts?: number }): SupabaseClient {
  return {
    from: (table: string) =>
      table === 'people'
        ? chain({ data: opts.person, error: null })
        : { select: (_cols: string, o?: { head?: boolean }) => chain(o?.head ? { count: opts.counts ?? 3, error: null } : { data: opts.rows, error: null }) },
  } as unknown as SupabaseClient;
}

export interface RecordedCall {
  readonly kind: 'select' | 'insert' | 'update' | 'rpc';
  readonly table?: string;
  readonly columns?: string;
  readonly payload?: unknown;
  readonly filters?: readonly (readonly [string, unknown])[];
  readonly name?: string;
}

export interface MembersFakeOptions {
  readonly memberships?: unknown[];
  readonly invites?: unknown[];
  /** What an insert answers; default: a new row with id `row-<n>`. */
  readonly onInsert?: (row: Record<string, unknown>, n: number) => { data: unknown; error: unknown };
  readonly onUpdate?: (patch: Record<string, unknown>) => { data: unknown; error: unknown };
  readonly onRpc?: (name: string, args: Record<string, unknown>, n: number) => { data: unknown; error: unknown };
}

/** A recording stand-in for the parts of SupabaseClient that MembersRepository uses. */
export function fakeMembersClient(options: MembersFakeOptions = {}): { client: SupabaseClient; calls: RecordedCall[] } {
  const calls: RecordedCall[] = [];
  let inserts = 0;
  let rpcs = 0;
  const from = (table: string) => {
    let op: 'select' | 'insert' | 'update' = 'select';
    let columns = '';
    let payload: unknown;
    const filters: [string, unknown][] = [];
    const answer = (): { data: unknown; error: unknown } => {
      if (op === 'insert') return (options.onInsert ?? ((_row, n) => ({ data: { id: `a0000000-0000-4000-8000-${String(n).padStart(12, '0')}` }, error: null })))(payload as Record<string, unknown>, ++inserts);
      if (op === 'update') return (options.onUpdate ?? (() => ({ data: [{ id: 'x' }], error: null })))(payload as Record<string, unknown>);
      return { data: (table === 'invites' ? options.invites : options.memberships) ?? [], error: null };
    };
    const b: any = {
      select: (cols?: string) => {
        columns = cols ?? '';
        if (op === 'select') calls.push({ kind: 'select', table, columns, filters });
        return b;
      },
      insert: (row: unknown) => {
        op = 'insert';
        payload = row;
        calls.push({ kind: 'insert', table, payload: row });
        return b;
      },
      update: (patch: unknown) => {
        op = 'update';
        payload = patch;
        calls.push({ kind: 'update', table, payload: patch, filters });
        return b;
      },
      eq: (column: string, value: unknown) => {
        filters.push([column, value]);
        return b;
      },
      single: () => b,
      overrideTypes: () => b,
      then: (resolve: (v: unknown) => void) => {
        resolve(answer());
      },
    };
    return b;
  };
  const rpc = (name: string, args: Record<string, unknown>) => {
    calls.push({ kind: 'rpc', name, payload: args });
    const out = (options.onRpc ?? (() => ({ data: null, error: null })))(name, args, ++rpcs);
    return Promise.resolve(out);
  };
  return { client: { from, rpc } as unknown as SupabaseClient, calls };
}
