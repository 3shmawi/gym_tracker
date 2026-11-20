import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
<<<<<<< yours
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/legal/consent_gate.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/backup/presentation/backup_card.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';
=======
import 'package:gym_tracker/core/legal/legal_links.dart';
>>>>>>> kit a50ee3f
import 'package:gym_tracker/features/settings/presentation/settings_controller.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';

/// Whether gym accounts are on (the `gym_join` flag). Override in tests.
final gymJoinEnabledProvider = FutureProvider<bool>(
  (ref) => FeatureFlags.isEnabled(Flags.gymJoin),
);

class SettingsPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    final gymsOn = ref.watch(gymJoinEnabledProvider).value ?? false;
    final signedIn = ref.watch(accountSessionProvider).isSignedIn;
    final moveCheck = ref.watch(moveCheckAllowedProvider).value ?? false;
    return SettingsView(
      onOpenLicenses: () => showLicensePage(context: context),
      onOpenPrivacy: () => unawaited(openLegalPage(LegalLinks.privacy)),
      onOpenTerms: () => unawaited(openLegalPage(LegalLinks.terms)),
      settings: ref.watch(settingsControllerProvider),
      onLocaleChanged: controller.setLocale,
      onThemeModeChanged: controller.setThemeMode,
<<<<<<< yours
      onOpenPlan: () => unawaited(context.push<void>(AppRoutes.plan)),
      backup: BackupCard(
        onOpen: () => unawaited(context.push<void>(AppRoutes.backup)),
      ),
      onOpenAccount: gymsOn && signedIn
          ? () => unawaited(context.push<void>(AppRoutes.profile))
          : null,
      onJoinGym: gymsOn && !signedIn
          ? () => unawaited(context.push<void>(AppRoutes.joinScan))
          : null,
      onOpenMoveCheck: moveCheck
          ? () => unawaited(context.push<void>(AppRoutes.moveCheck))
          : null,
=======
      onOpenPrivacy: _open(LegalLinks.privacy),
      onOpenTerms: _open(LegalLinks.terms),
      onOpenLicenses: () => showLicensePage(context: context),
>>>>>>> kit a50ee3f
    );
  }
}

/// Opens [url] in the browser; null (row hidden) while there's no website.
VoidCallback? _open(Uri? url) =>
    url == null ? null : () => unawaited(openLegalPage(url));
