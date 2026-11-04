// Every error from Supabase (Auth, PostgREST, RPCs) is turned into one of
// these kinds before the UI sees it. The UI shows a message per kind and
// never the raw server text (it may echo input or internals).

export type FailureKind =
  | 'offline' //            no network, or the request never reached the server
  | 'forbidden' //          RLS / RPC said no (42501), or a manager right is missing
  | 'session_ended' //      the session is gone or its token was refused
  | 'not_found' //          the row is not there (or not visible to us)
  | 'conflict' //           a constraint said no (e.g. the last owner)
  | 'invalid' //            the server refused the input
  | 'rate_limited' //       too many requests: wait
  | 'code_wrong' //         email code wrong
  | 'code_expired' //       email code expired
  | 'server'; //            anything else

export interface Failure {
  readonly kind: FailureKind;
  /** Seconds to wait, when the server said so. */
  readonly retryAfter?: number;
  /** A stable server reason (e.g. 'person_in_other_gym'), never free text. */
  readonly reason?: string;
}

const REASON = /^[a-z][a-z_]{2,40}$/;

interface ErrorLike {
  name?: unknown;
  code?: unknown;
  status?: unknown;
  message?: unknown;
}

function asErrorLike(e: unknown): ErrorLike {
  return typeof e === 'object' && e !== null ? e : {};
}

/** Classifies any thrown or returned error. Never throws. */
export function toFailure(error: unknown, online: boolean = typeof navigator === 'undefined' || navigator.onLine): Failure {
  if (!online) return { kind: 'offline' };
  const e = asErrorLike(error);
  const code = typeof e.code === 'string' ? e.code : '';
  const status = typeof e.status === 'number' ? e.status : 0;
  const name = typeof e.name === 'string' ? e.name : '';
  const message = typeof e.message === 'string' ? e.message : '';

  // Network: fetch rejected (TypeError), or Auth's retryable fetch error.
  if (name === 'AuthRetryableFetchError' || error instanceof TypeError || /Failed to fetch|NetworkError|Load failed/i.test(message)) {
    return { kind: 'offline' };
  }

  // Auth error codes (supabase.com/docs/guides/auth/debugging/error-codes).
  switch (code) {
    // Supabase answers 403 otp_expired for a wrong code too ("Token has
    // expired or is invalid", supabase/auth internal/api/verify.go, read
    // 2026-11-04), so the UI says "wrong or expired".
    case 'otp_expired':
      return { kind: 'code_expired' };
    case 'invalid_credentials':
    case 'otp_invalid':
      return { kind: 'code_wrong' };
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return { kind: 'rate_limited' };
    case 'session_not_found':
    case 'session_expired':
    case 'refresh_token_not_found':
    case 'refresh_token_already_used':
    case 'bad_jwt':
    case 'PGRST301':
    case 'PGRST303':
      return { kind: 'session_ended' };
    case '42501':
      return { kind: 'forbidden', ...reasonOf(message) };
    case '23514':
      // memberships_guard (0005): "a gym needs at least one active owner".
      if (/active owner/i.test(message)) return { kind: 'conflict', reason: 'last_owner' };
      return { kind: 'conflict', ...reasonOf(message) };
    case '23505':
    case 'P0001':
      return { kind: 'conflict', ...reasonOf(message) };
    case '22023':
    case '22P02':
    case '23502':
    case 'PGRST204':
      return { kind: 'invalid', ...reasonOf(message) };
    case 'PGRST116':
      return { kind: 'not_found' };
    default:
      break;
  }
  if (status === 429) return { kind: 'rate_limited' };
  if (status === 401) return { kind: 'session_ended' };
  if (status === 403) return { kind: 'forbidden' };
  if (status === 404) return { kind: 'not_found' };
  return { kind: 'server' };
}

// RPCs raise short snake_case reasons ('forbidden', 'invalid_membership',
// 'person_in_other_gym'). Keep one only when it has exactly that shape.
function reasonOf(message: string): { reason?: string } {
  const first = message.split(':')[0]?.trim() ?? '';
  return REASON.test(first) ? { reason: first } : {};
}

/** An error with a Postgres/PostgREST-style code, for answers we refuse ourselves. */
export class CodedError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'CodedError';
  }
}
