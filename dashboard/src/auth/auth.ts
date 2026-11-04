import type { Session, SupabaseClient } from '@supabase/supabase-js';
import { failed, guard, ok, type Result } from '../core/result';
import { toFailure } from '../core/failure';
import { normalizeCode, normalizeEmail } from '../core/text';

/** Digits in the email code. Supabase: auth.email.otp_length, default 6 (6–10). */
export const CODE_LENGTH = 6;
/** Supabase sends at most one code per address every 60 s by default. */
export const RESEND_SECONDS = 60;

export interface SignedIn {
  readonly userId: string;
  readonly email: string;
}

/**
 * Email one-time-code sign-in (supabase.com/docs/guides/auth/auth-email-passwordless,
 * read 2026-11-04). The session is permanent (not anonymous), which
 * private.i_manage() requires before a manager can write.
 */
export class AuthService {
  constructor(private readonly supabase: SupabaseClient) {}

  /**
   * Asks for a code. Never creates a user (shouldCreateUser: false). An
   * unknown address answers the same as a known one, so the page can't be
   * used to find out who manages a gym.
   */
  async sendCode(rawEmail: string, captchaToken?: string): Promise<Result<void>> {
    const email = normalizeEmail(rawEmail);
    if (!email) return failed({ kind: 'invalid' });
    const { error } = await this.supabase.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false, ...(captchaToken ? { captchaToken } : {}) },
    });
    if (!error) return ok(undefined);
    // 422 otp_disabled "Signups not allowed for otp": no such user. Same answer as success.
    if (error.code === 'otp_disabled' || error.status === 422) return ok(undefined);
    return failed(toFailure(error));
  }

  async verifyCode(rawEmail: string, rawCode: string): Promise<Result<SignedIn>> {
    const email = normalizeEmail(rawEmail);
    const token = normalizeCode(rawCode, CODE_LENGTH);
    if (!email || !token) return failed({ kind: 'invalid' });
    const { data, error } = await this.supabase.auth.verifyOtp({ email, token, type: 'email' });
    if (error) return failed(toFailure(error));
    const session = data.session;
    if (!session || isAnonymous(session)) return failed({ kind: 'session_ended' });
    return ok(signedIn(session));
  }

  /** The stored session, if any, and only if it is a permanent one. */
  async current(): Promise<Result<SignedIn | null>> {
    return guard(async () => {
      const { data, error } = await this.supabase.auth.getSession();
      if (error) throw error;
      const session = data.session;
      if (!session) return null;
      if (isAnonymous(session)) {
        await this.signOut();
        return null;
      }
      return signedIn(session);
    });
  }

  /** Signs out this browser only; the person's app session elsewhere is kept. */
  async signOut(): Promise<void> {
    try {
      await this.supabase.auth.signOut({ scope: 'local' });
    } catch {
      // The local session is removed even when the network call fails.
    }
  }

  /** Calls back when the session ends (signed out, refresh refused). */
  onSignedOut(callback: () => void): () => void {
    const { data } = this.supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') callback();
    });
    return () => {
      data.subscription.unsubscribe();
    };
  }
}

function isAnonymous(session: Session): boolean {
  return session.user.is_anonymous === true;
}

function signedIn(session: Session): SignedIn {
  return { userId: session.user.id, email: session.user.email ?? '' };
}
