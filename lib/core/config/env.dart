/// Compile-time configuration, read from `env/<flavor>.json` via
/// `--dart-define-from-file`. Never put real secrets here: anything compiled
/// into the app can be extracted. Server-side secrets live in Supabase.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  /// Cloudflare Turnstile **site** key (publishable). The secret key lives only
  /// in Supabase → Authentication → Attack Protection. Empty: no captcha is
  /// asked for (the project must then have captcha protection off).
  static const turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const clarityProjectId = String.fromEnvironment('CLARITY_PROJECT_ID');
}
