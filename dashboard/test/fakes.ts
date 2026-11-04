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
