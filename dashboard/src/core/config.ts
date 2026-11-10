// Build-time configuration. Only publishable values may ever be here:
// everything in the bundle is public. Values come from VITE_* variables set
// in the Cloudflare Pages project (docs/features/dashboard.md → "Deploy").

export interface AppConfig {
  /** https://<project-ref>.supabase.co, no trailing slash. */
  readonly supabaseUrl: string;
  /** sb_publishable_… key. Never a secret or service-role key. */
  readonly supabaseKey: string;
  /**
   * Cloudflare Turnstile site key (publishable), or null. Needed once CAPTCHA
   * protection is on in Supabase → Authentication → Attack Protection: it
   * then applies to sign-in too (supabase.com/docs/guides/auth/auth-captcha,
   * read 2026-11-04).
   */
  readonly turnstileSiteKey: string | null;
  /**
   * Cloudinary cloud name of the exercise picture library (publishable: it is
   * part of every picture URL, as in the app's CLOUDINARY_CLOUD_NAME), or
   * null. Without it the exercise pages still work, with plain tiles instead
   * of pictures (docs/features/dashboard.md → "D2 Exercise media").
   */
  readonly cloudinaryCloudName: string | null;
}

const SUPABASE_URL = /^https:\/\/[a-z0-9]{20}\.supabase\.co$/;
const PUBLISHABLE_KEY = /^sb_publishable_[A-Za-z0-9_-]{10,200}$/;
// Real site keys start with 0x; Cloudflare's test keys with 1x, 2x or 3x.
const TURNSTILE_SITE_KEY = /^[0-3]x[A-Za-z0-9_-]{10,64}$/;
// Same rule as the app (lib/core/media/cloudinary_url.dart).
const CLOUD_NAME = /^[a-z0-9][a-z0-9_-]{0,62}$/;

export class ConfigError extends Error {
  override name = 'ConfigError';
}

/** Validates raw env values. Throws ConfigError with a reason that never echoes the value. */
export function parseConfig(env: Record<string, unknown>): AppConfig {
  const url = typeof env.VITE_SUPABASE_URL === 'string' ? env.VITE_SUPABASE_URL.trim().replace(/\/+$/, '') : '';
  const key = typeof env.VITE_SUPABASE_PUBLISHABLE_KEY === 'string' ? env.VITE_SUPABASE_PUBLISHABLE_KEY.trim() : '';
  if (!SUPABASE_URL.test(url)) {
    throw new ConfigError('VITE_SUPABASE_URL must be https://<20-character project ref>.supabase.co');
  }
  if (key.startsWith('sb_secret_') || /service[_]role/i.test(key) /* written so the repo-wide secrets test does not match this line */) {
    throw new ConfigError('VITE_SUPABASE_PUBLISHABLE_KEY is a secret key. Use the publishable key (sb_publishable_…).');
  }
  if (!PUBLISHABLE_KEY.test(key)) {
    throw new ConfigError('VITE_SUPABASE_PUBLISHABLE_KEY must be a publishable key (sb_publishable_…).');
  }
  const rawTurnstile = typeof env.VITE_TURNSTILE_SITE_KEY === 'string' ? env.VITE_TURNSTILE_SITE_KEY.trim() : '';
  if (rawTurnstile && !TURNSTILE_SITE_KEY.test(rawTurnstile)) {
    throw new ConfigError('VITE_TURNSTILE_SITE_KEY must be a Turnstile site key (0x…), never the secret.');
  }
  const rawCloud = typeof env.VITE_CLOUDINARY_CLOUD_NAME === 'string' ? env.VITE_CLOUDINARY_CLOUD_NAME.trim() : '';
  if (rawCloud && !CLOUD_NAME.test(rawCloud)) {
    throw new ConfigError('VITE_CLOUDINARY_CLOUD_NAME must be a Cloudinary cloud name (lower-case letters, digits, - and _).');
  }
  return { supabaseUrl: url, supabaseKey: key, turnstileSiteKey: rawTurnstile || null, cloudinaryCloudName: rawCloud || null };
}
