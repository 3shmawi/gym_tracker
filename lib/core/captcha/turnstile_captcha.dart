import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/captcha/turnstile_page.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Gets a Cloudflare Turnstile token for the anonymous sign-in
/// (docs/decisions/gym_accounts.md §16): Supabase checks it with the Turnstile
/// secret that lives only in Supabase's Auth settings.
///
/// The widget runs in a 1-pixel web view that only opens Cloudflare's own
/// host; it is created for each token and thrown away (a token works once and
/// expires in minutes). The widget must be a type that needs no person
/// (invisible / non-interactive): the web view cannot show a challenge.
class TurnstileCaptcha {
  const new({
    required this.siteKey,
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 20),
    this.fetch = _fetchWithWebView,
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
  /// answer, [UnknownFailure] when it refuses). Never null or empty.
  Future<String> token() async {
    try {
      final value = await fetch(siteKey, baseUrl).timeout(timeout);
      if (value == null || value.isEmpty) {
        throw const UnknownFailure('turnstile: no token');
      }
      return value;
    } on TimeoutException catch (error) {
      throw TimeoutFailure(error);
    }
  }

  static Future<String?> _fetchWithWebView(
    String siteKey,
    String baseUrl,
  ) async {
    final page = TurnstilePage.html(siteKey);
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) throw const UnknownFailure('turnstile: no screen');
    final done = Completer<String?>();
    void finish(String? token) {
      if (!done.isCompleted) done.complete(token);
    }

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      TurnstilePage.channel,
      onMessageReceived: (message) {
        final parsed = TurnstilePage.parse(message.message);
        if (parsed == null) return;
        if (parsed.value != null) finish(parsed.value);
        if (parsed.failed) finish(null);
        // `timedOut` / expired: keep waiting for the widget's retry; the
        // overall timeout ends the wait.
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            TurnstilePage.allowsNavigation(request.url, baseUrl: baseUrl)
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (_) => finish(null),
      ),
    );
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: IgnorePointer(
          child: ExcludeSemantics(child: WebViewWidget(controller: controller)),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await controller.loadHtmlString(page, baseUrl: baseUrl);
      return await done.future;
    } finally {
      entry
        ..remove()
        ..dispose();
    }
  }
}
