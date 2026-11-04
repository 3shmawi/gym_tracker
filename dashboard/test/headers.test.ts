import { describe, expect, it } from 'vitest';
import { contentSecurityPolicy, headersFile } from '../build/headers';

const supabaseUrl = 'https://abcdefghijklmnopqrst.supabase.co';

describe('security headers', () => {
  const csp = contentSecurityPolicy({ supabaseUrl });
  it('locks the CSP down', () => {
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain(supabaseUrl);
    expect(csp).toContain('wss://abcdefghijklmnopqrst.supabase.co');
    expect(csp).not.toContain('unsafe-inline');
    expect(csp).not.toContain('unsafe-eval');
    expect(csp.split(/[\s;]+/)).not.toContain('*');
  });
  it('writes a valid _headers file', () => {
    const file = headersFile({ supabaseUrl });
    expect(file).toContain('Strict-Transport-Security');
    for (const line of file.split('\n')) expect(line.length).toBeLessThanOrEqual(2000);
  });

  it('allows Turnstile only when enabled', () => {
    const on = contentSecurityPolicy({ supabaseUrl, turnstile: true });
    expect(on).toMatch(/script-src 'self' https:\/\/challenges\.cloudflare\.com/);
    expect(on).toContain('frame-src https://challenges.cloudflare.com');
    expect(on).not.toContain('unsafe-inline');
    const off = contentSecurityPolicy({ supabaseUrl, turnstile: false });
    expect(off).toContain("frame-src 'none'");
    expect(off).not.toContain('cloudflare');
  });
});
