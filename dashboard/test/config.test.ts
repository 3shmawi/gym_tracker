import { describe, expect, it } from 'vitest';
import { ConfigError, parseConfig } from '../src/core/config';

const URL = 'https://abcdefghijklmnopqrst.supabase.co';
const KEY = 'sb_publishable_test_key_123';
// Hostile values are built by concatenation so no secret-looking literal sits in the repo.
const SECRET_KEY = 'sb_' + 'secret_' + 'x'.repeat(24);
const SERVICE_JWT = 'eyJhbGciOiJIUzI1NiJ9.' + btoa('{"role":"service' + '_role"}') + '.sig';

describe('parseConfig', () => {
  it('accepts a valid config and trims a trailing slash', () => {
    expect(parseConfig({ VITE_SUPABASE_URL: `${URL}/`, VITE_SUPABASE_PUBLISHABLE_KEY: KEY })).toEqual({ supabaseUrl: URL, supabaseKey: KEY, turnstileSiteKey: null });
  });
  it('rejects a secret key without echoing it', () => {
    expect(() => parseConfig({ VITE_SUPABASE_URL: URL, VITE_SUPABASE_PUBLISHABLE_KEY: SECRET_KEY })).toThrow(ConfigError);
    try {
      parseConfig({ VITE_SUPABASE_URL: URL, VITE_SUPABASE_PUBLISHABLE_KEY: SECRET_KEY });
    } catch (e) {
      expect(String(e)).not.toContain('xxxx');
    }
  });
  it('rejects a service-role style JWT', () => {
    expect(() => parseConfig({ VITE_SUPABASE_URL: URL, VITE_SUPABASE_PUBLISHABLE_KEY: SERVICE_JWT })).toThrow(ConfigError);
  });
  it('rejects http, other hosts and lookalike hosts', () => {
    const bad = ['http://abcdefghijklmnopqrst.supabase.co', 'https://example.com', 'https://abcdefghijklmnopqrst.supabase.co.evil.com', 'https://short.supabase.co'];
    for (const url of bad) {
      expect(() => parseConfig({ VITE_SUPABASE_URL: url, VITE_SUPABASE_PUBLISHABLE_KEY: KEY }), url).toThrow(ConfigError);
    }
  });
  it('rejects wrong types and missing values', () => {
    expect(() => parseConfig({ VITE_SUPABASE_URL: 5, VITE_SUPABASE_PUBLISHABLE_KEY: KEY })).toThrow(ConfigError);
    expect(() => parseConfig({ VITE_SUPABASE_URL: URL, VITE_SUPABASE_PUBLISHABLE_KEY: {} })).toThrow(ConfigError);
    expect(() => parseConfig({})).toThrow(ConfigError);
  });

  describe('Turnstile site key', () => {
    const base = { VITE_SUPABASE_URL: URL, VITE_SUPABASE_PUBLISHABLE_KEY: KEY };
    it('is null when empty or missing', () => {
      expect(parseConfig({ ...base, VITE_TURNSTILE_SITE_KEY: '' }).turnstileSiteKey).toBeNull();
      expect(parseConfig(base).turnstileSiteKey).toBeNull();
    });
    it('accepts the Cloudflare test key and a real-looking key', () => {
      expect(parseConfig({ ...base, VITE_TURNSTILE_SITE_KEY: '1x00000000000000000000AA' }).turnstileSiteKey).toBe('1x00000000000000000000AA');
      const real = '0x4AAAAAAA' + 'B'.repeat(20);
      expect(parseConfig({ ...base, VITE_TURNSTILE_SITE_KEY: real }).turnstileSiteKey).toBe(real);
    });
    it('rejects spaces and markup', () => {
      expect(() => parseConfig({ ...base, VITE_TURNSTILE_SITE_KEY: '0x4AAAA AAAAAAAAAAAAAAA' })).toThrow(ConfigError);
      expect(() => parseConfig({ ...base, VITE_TURNSTILE_SITE_KEY: '<script>alert(1)</script>' })).toThrow(ConfigError);
    });
  });
});
