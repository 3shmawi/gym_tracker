import { describe, expect, it } from 'vitest';
import { toFailure } from '../src/core/failure';

describe('toFailure', () => {
  it('maps auth codes', () => {
    expect(toFailure({ code: 'otp_expired' }, true).kind).toBe('code_expired');
    expect(toFailure({ code: 'over_email_send_rate_limit' }, true).kind).toBe('rate_limited');
    expect(toFailure({ code: 'invalid_credentials' }, true).kind).toBe('code_wrong');
  });
  it('maps Postgres codes and keeps a snake_case reason only', () => {
    expect(toFailure({ code: '42501', message: 'forbidden' }, true)).toEqual({ kind: 'forbidden', reason: 'forbidden' });
    expect(toFailure({ code: '23514', message: 'invalid_membership: detail' }, true)).toEqual({ kind: 'conflict', reason: 'invalid_membership' });
    expect(toFailure({ code: '42501', message: 'Row <b>level</b> security failed' }, true)).toEqual({ kind: 'forbidden' });
  });
  it('treats fetch TypeError and the offline flag as offline', () => {
    expect(toFailure(new TypeError('Failed to fetch'), true).kind).toBe('offline');
    expect(toFailure({ code: 'otp_expired' }, false).kind).toBe('offline');
  });
  it('maps HTTP status', () => {
    expect(toFailure({ status: 401 }, true).kind).toBe('session_ended');
    expect(toFailure({ status: 429 }, true).kind).toBe('rate_limited');
  });
  it('falls back to server for anything unknown', () => {
    expect(toFailure({ code: 'weird' }, true).kind).toBe('server');
    expect(toFailure(undefined, true).kind).toBe('server');
    expect(toFailure('boom', true).kind).toBe('server');
  });
});

describe('last owner', () => {
  it('memberships_guard 23514 gets the last_owner reason; other 23514 does not', () => {
    expect(toFailure({ code: '23514', message: 'a gym needs at least one active owner' }, true)).toEqual({ kind: 'conflict', reason: 'last_owner' });
    expect(toFailure({ code: '23514', message: 'new row violates check constraint "memberships_flags_trainee_only"' }, true)).toEqual({ kind: 'conflict' });
  });
});
