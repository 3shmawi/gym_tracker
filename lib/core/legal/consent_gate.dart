import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/legal/consent_view.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a legal page in the browser; tests pass a fake.
typedef LegalOpener = Future<void> Function(Uri url);

Future<void> openLegalPage(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Records the member's agreement to the current Terms and Privacy Policy.
/// [via]: `welcome` (they chose how to start) or `sheet`.
Future<void> acceptTerms(ConsentStore store, {required String via}) async {
  if (store.accepted() == ConsentStore.current) return;
  await store.accept(ConsentStore.current);
  unawaited(Analytics.capture('terms_accepted', {'via': via}));
}

/// Until the member agreed to the current Terms and Privacy Policy
/// ([ConsentStore.current]), shows the "Before you start" sheet once over
/// whatever screen is open: it can't be swiped or popped away, only agreed.
/// On the welcome screen it waits: choosing how to start agrees (the line
/// under the choices says so).
class ConsentGate extends StatefulWidget {
  const new({
    required this.child,
    this.store,
    this.open = openLegalPage,
    this.router,
    this.navigatorKey,
    super.key,
  });

  final Widget child;

  /// Defaults to [Dependencies.consentStore].
  final ConsentStore? store;
  final LegalOpener open;

  /// Default: the app's router and its root navigator (tests pass their own).
  final GoRouter? router;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  ConsentStore get _store => widget.store ?? Dependencies.consentStore;
  GoRouter get _router => widget.router ?? appRouter;
  GlobalKey<NavigatorState> get _navigator =>
      widget.navigatorKey ?? rootNavigatorKey;

  bool get _agreed => _store.accepted() == ConsentStore.current;
  bool _showing = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (_agreed) return;
    _router.routerDelegate.addListener(_check);
    _listening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    if (_listening) _router.routerDelegate.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted || _showing) return;
    if (_agreed) {
      if (_listening) {
        _router.routerDelegate.removeListener(_check);
        _listening = false;
      }
      return;
    }
    final config = _router.routerDelegate.currentConfiguration;
    // Not routed yet, or the welcome screen (it asks itself).
    if (config.isEmpty || config.uri.path == AppRoutes.welcome) return;
    final context = _navigator.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      return;
    }
    _showing = true;
    unawaited(_show(context));
  }

  Future<void> _show(BuildContext context) async {
    void open(Uri url) => unawaited(widget.open(url));
    await showAppSheet<void>(
      context: context,
      dismissible: false,
      builder: (sheet) => PopScope(
        canPop: false,
        child: ConsentView(
          onAgree: () async {
            await acceptTerms(_store, via: 'sheet');
            if (sheet.mounted) Navigator.of(sheet).pop();
          },
          onOpenPrivacy: () => open(LegalLinks.privacy),
          onOpenTerms: () => open(LegalLinks.terms),
          onOpenYouTubeTerms: () => open(LegalLinks.youTubeTerms),
          onOpenGooglePrivacy: () => open(LegalLinks.googlePrivacy),
        ),
      ),
    );
    _showing = false;
    _check();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
