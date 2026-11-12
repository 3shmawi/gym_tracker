import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/backup/domain/usecases/backup_offer.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// True when the offer should show now (set after a finished workout, cleared
/// when it was shown).
final backupOfferProvider = NotifierProvider<BackupOffer, bool>(
  BackupOffer.new,
);

class BackupOffer extends Notifier<bool> {
  @override
  bool build() => false;

  /// Called when a workout was saved.
  Future<void> afterWorkout() async {
    try {
      final settings = ref.read(backupSettingsProvider);
      final history = await ref
          .read(localWorkoutRepositoryProvider)
          .loadHistory();
      if (!ref.mounted) return;
      final finished = switch (history) {
        Success(:final value) => value.length,
        Failed() => 0,
      };
      final show = shouldOfferBackup(
        finishedWorkouts: finished,
        dismissals: settings.offerDismissals,
        enabled: settings.enabled,
        flagOn: ref.read(trainingBackupEnabledProvider),
      );
      if (show) state = true;
    } on Object {
      // An offer is never worth breaking the end of a workout.
    }
  }

  void shown() {
    state = false;
    unawaited(Analytics.capture('backup_offer_shown', {'place': 'summary'}));
  }

  Future<void> dismissed() async {
    final settings = ref.read(backupSettingsProvider);
    await settings.setOfferDismissals(settings.offerDismissals + 1);
    unawaited(Analytics.capture('backup_offer_dismissed'));
  }
}

/// Wraps the home screen: when the offer is due it opens the sheet.
class BackupOfferHost extends ConsumerWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(backupOfferProvider, (_, due) {
      if (!due) return;
      final offer = ref.read(backupOfferProvider.notifier)..shown();
      unawaited(_open(context, offer));
    });
    return child;
  }

  Future<void> _open(BuildContext context, BackupOffer offer) async {
    final accept = await showAppSheet<bool>(
      context: context,
      builder: (sheet) => const BackupOfferSheet(),
    );
    if (accept ?? false) {
      if (context.mounted) unawaited(context.push<void>(AppRoutes.backup));
    } else {
      await offer.dismissed();
    }
  }
}

/// "Keep your training safe": what it does, in three short lines.
class BackupOfferSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.backupOfferTitle,
              style: AppTextStyles.title.copyWith(color: palette.textPrimary),
            ),
          ),
          Text(
            l10n.backupOfferBody,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
          AppPrimaryButton(
            key: const Key('backup_offer_accept'),
            label: l10n.backupOfferAccept,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          AppSecondaryButton(
            key: const Key('backup_offer_later'),
            label: l10n.backupOfferLater,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
