import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { AppConfig } from './config';

/**
 * The one Supabase client. Auth options (supabase.com/docs/reference/javascript/initializing,
 * read 2026-11-04):
 * - persistSession: supabase-js keeps the session in the browser under sb-<ref>-auth-token
 *   (the only personal data the dashboard keeps in the browser);
 * - autoRefreshToken: keeps the permanent session alive;
 * - detectSessionInUrl: false, sign-in is by typed code, never a link, so a
 *   crafted URL can't plant a session.
 */
export function makeSupabase(config: AppConfig, fetchImpl?: typeof fetch): SupabaseClient {
  // createClient's generic defaults differ from SupabaseClient's; same object.
  // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
  const client: SupabaseClient = createClient(config.supabaseUrl, config.supabaseKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
    global: fetchImpl ? { fetch: fetchImpl } : {},
  });
  return client;
}
