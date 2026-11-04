import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/legal/consent_view.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a legal page in the browser; tests pass a fake.
typedef LegalOpener = Future<void> Function(Uri url);

Future<void> openLegalPage(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Shows [ConsentView] instead of the app until the member agreed to the
/// current Terms and Privacy Policy ([ConsentStore.current]); then the app.
/// Sits above the router, so no screen or deep link opens before it.
class ConsentGate extends StatefulWidget {
  const new({
    required this.child,
    this.store,
    this.open = openLegalPage,
    super.key,
  });

  final Widget child;

  /// Defaults to [Dependencies.consentStore].
  final ConsentStore? store;
  final LegalOpener open;

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  ConsentStore get _store => widget.store ?? Dependencies.consentStore;
  late bool _agreed = _store.accepted() == ConsentStore.current;

  Future<void> _agree() async {
    await _store.accept(ConsentStore.current);
    unawaited(Analytics.capture('terms_accepted'));
    if (mounted) setState(() => _agreed = true);
  }

  void _open(Uri url) => unawaited(widget.open(url));

  @override
  Widget build(BuildContext context) {
    if (_agreed) return widget.child;
    // Its own Navigator: the gate sits above the app's router.
    return HeroControllerScope.none(
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => ConsentView(
            onAgree: () => unawaited(_agree()),
            onOpenPrivacy: () => _open(LegalLinks.privacy),
            onOpenTerms: () => _open(LegalLinks.terms),
            onOpenYouTubeTerms: () => _open(LegalLinks.youTubeTerms),
            onOpenGooglePrivacy: () => _open(LegalLinks.googlePrivacy),
          ),
        ),
      ),
    );
  }
}
