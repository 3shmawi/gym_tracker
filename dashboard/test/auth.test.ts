import { describe, expect, it, vi } from 'vitest';
import { AuthService } from '../src/auth/auth';
import { fakeAuthClient } from './fakes';

const session = (anonymous: boolean) => ({ user: { id: 'u1', email: 'm@example.com', is_anonymous: anonymous } });

describe('AuthService', () => {
  it('sendCode never creates users', async () => {
    const { client, auth } = fakeAuthClient();
    const result = await new AuthService(client).sendCode(' Manager@Example.com ');
    expect(result.ok).toBe(true);
    expect(auth.signInWithOtp).toHaveBeenCalledWith({ email: 'manager@example.com', options: { shouldCreateUser: false } });
  });
  it('treats 422 otp_disabled as success (does not reveal who exists)', async () => {
    const { client } = fakeAuthClient({ signInWithOtp: vi.fn(() => Promise.resolve({ error: { code: 'otp_disabled', status: 422 } })) });
    expect((await new AuthService(client).sendCode('a@example.com')).ok).toBe(true);
  });
  it('maps other send errors', async () => {
    const { client } = fakeAuthClient({ signInWithOtp: vi.fn(() => Promise.resolve({ error: { code: 'over_email_send_rate_limit', status: 429 } })) });
    const result = await new AuthService(client).sendCode('a@example.com');
    expect(result).toEqual({ ok: false, failure: expect.objectContaining({ kind: 'rate_limited' }) as unknown });
  });
  it('never calls the server for an invalid email or code', async () => {
    const { client, auth } = fakeAuthClient();
    const service = new AuthService(client);
    expect((await service.sendCode('nope')).ok).toBe(false);
    expect((await service.verifyCode('nope', '123456')).ok).toBe(false);
    expect((await service.verifyCode('a@example.com', '12')).ok).toBe(false);
    expect(auth.signInWithOtp).not.toHaveBeenCalled();
    expect(auth.verifyOtp).not.toHaveBeenCalled();
  });
  it('verifyCode uses type email and returns the user', async () => {
    const { client, auth } = fakeAuthClient({ verifyOtp: vi.fn(() => Promise.resolve({ data: { session: session(false) }, error: null })) });
    const result = await new AuthService(client).verifyCode('a@example.com', '123 456');
    expect(auth.verifyOtp).toHaveBeenCalledWith({ email: 'a@example.com', token: '123456', type: 'email' });
    expect(result).toEqual({ ok: true, value: { userId: 'u1', email: 'm@example.com' } });
  });
  it('rejects an anonymous session', async () => {
    const { client } = fakeAuthClient({ verifyOtp: vi.fn(() => Promise.resolve({ data: { session: session(true) }, error: null })) });
    const result = await new AuthService(client).verifyCode('a@example.com', '123456');
    expect(result.ok).toBe(false);
  });
  it('signs out this browser only', async () => {
    const { client, auth } = fakeAuthClient();
    await new AuthService(client).signOut();
    expect(auth.signOut).toHaveBeenCalledWith({ scope: 'local' });
  });
});
