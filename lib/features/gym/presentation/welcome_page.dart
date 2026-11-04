import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/legal/consent_gate.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:gym_tracker/core/legal/legal_links_row.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_view.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Override in tests.
final consentStoreProvider = Provider<ConsentStore>(
  (ref) => Dependencies.consentStore,
);

/// `/welcome`: join a gym or train alone. Neither choice makes an account.
/// Either choice agrees to the Terms and Privacy Policy (the line under the
/// choices says so), so new members never see the separate consent sheet.
class WelcomePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    void agree() =>
        unawaited(acceptTerms(ref.read(consentStoreProvider), via: 'welcome'));
    void open(Uri url) => unawaited(openLegalPage(url));
    return WelcomeView(
      onJoin: () {
        agree();
        unawaited(context.push<void>(AppRoutes.joinScan));
      },
      onHaveCode: () {
        agree();
        unawaited(context.push<void>(AppRoutes.join));
      },
      onSolo: () {
        agree();
        // Answered once: the next launch goes straight to the workout.
        unawaited(ref.read(gymLocalRepositoryProvider).saveOnboardingDone());
        context.go(AppRoutes.home);
      },
      legalLinks: [
        LegalLink(
          'welcome_terms',
          l10n.legalTerms,
          () => open(LegalLinks.terms),
        ),
        LegalLink(
          'welcome_privacy',
          l10n.legalPrivacy,
          () => open(LegalLinks.privacy),
        ),
        LegalLink(
          'welcome_youtube_terms',
          l10n.legalYouTubeTerms,
          () => open(LegalLinks.youTubeTerms),
        ),
      ],
    );
  }
}
