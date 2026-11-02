import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:gym_tracker/core/network/app_failure.dart';

/// Gets a Cloudflare Turnstile token for the anonymous sign-in
/// (docs/decisions/gym_accounts.md §16): Supabase checks it with the Turnstile
/// secret that lives only in Supabase's Auth settings.
///
/// The widget runs invisibly in a headless web view. It is created, used once
/// and disposed for each token: a token works once and expires in minutes.
class TurnstileCaptcha {
  const new({
    required this.siteKey,
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 20),
    this.fetch = _fetchFromWidget,
  });

  /// Must be one of the widget's registered domains (Cloudflare dashboard →
  /// Turnstile → the widget → Domains). The app has no page of its own, so the
  /// website's host is used as the origin the widget believes it runs on.
  static const defaultBaseUrl = 'https://azmm.pages.dev';

  /// The publishable site key (`TURNSTILE_SITE_KEY`). Never the secret key.
  final String siteKey;
  final String baseUrl;
  final Duration timeout;

  /// Runs the widget; replaced in tests.
  final Future<String?> Function(String siteKey, String baseUrl) fetch;

  /// A fresh token, or a failure ([TimeoutFailure] when the widget does not
  /// answer, [UnknownFailure] when it refuses). Never null: an empty token
  /// would make the sign-in fail with a less clear error.
  Future<String> token() async {
    try {
      final value = await fetch(siteKey, baseUrl).timeout(timeout);
      if (value == null || value.isEmpty) {
        throw const UnknownFailure('turnstile: no token');
      }
      return value;
    } on TimeoutException catch (error) {
      throw TimeoutFailure(error);
    } on TurnstileException catch (error) {
      // Retryable errors (a network hiccup in the web view) are network
      // failures; the rest are the widget refusing this client.
      throw error.retryable ? NetworkFailure(error) : UnknownFailure(error);
    }
  }

  static Future<String?> _fetchFromWidget(
    String siteKey,
    String baseUrl,
  ) async {
    final turnstile = CloudflareTurnstile.invisible(
      siteKey: siteKey,
      baseUrl: baseUrl,
    );
    try {
      return await turnstile.getToken();
    } finally {
      await turnstile.dispose();
    }
  }
}
