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
    // Below guard()'s 20 s, so this failure (with its reason) is the one
    // that is reported, not a bare timeout.
    this.timeout = const Duration(seconds: 15),
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

  /// What the last web view saw before it gave up (a Cloudflare error code,
  /// a load error, a blocked host). Never a URL path, query or token.
  static String lastNote = '';

  /// A fresh token, or an [UnknownFailure] saying why there is none. Never
  /// null or empty. Not a TimeoutFailure: a captcha that does not answer is
  /// not a network problem, so it is reported to monitoring and not retried.
  Future<String> token() async {
    lastNote = '';
    try {
      final value = await fetch(siteKey, baseUrl).timeout(timeout);
      if (value == null || value.isEmpty) {
        throw UnknownFailure(_reason('no token'));
      }
      return value;
    } on TimeoutException {
      throw UnknownFailure(_reason('timed out'));
    }
  }

  static String _reason(String what) =>
      lastNote.isEmpty ? 'turnstile: $what' : 'turnstile: $what ($lastNote)';

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
        if (parsed.failed) {
          lastNote = parsed.code.isEmpty
              ? 'widget error'
              : 'error ${parsed.code}';
          finish(null);
        }
        // `timedOut` / expired: keep waiting for the widget's retry; the
        // overall timeout ends the wait.
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (TurnstilePage.allowsNavigation(request.url, baseUrl: baseUrl)) {
            return NavigationDecision.navigate;
          }
          // Scheme and host only: a path or query could hold anything.
          final uri = Uri.tryParse(request.url);
          lastNote = 'blocked ${uri?.scheme ?? '?'}://${uri?.host ?? '?'}';
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (lastNote.isEmpty) lastNote = 'page loaded, no answer';
        },
        // Only the page itself failing to load ends the wait; a failed
        // sub-resource (an image, a probe Cloudflare expects to fail) does
        // not.
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? true) {
            lastNote = 'load error ${error.errorCode}';
            finish(null);
          }
        },
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
