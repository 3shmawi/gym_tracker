import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/settings/presentation/widgets/settings_tiles.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// The Backup card of Settings (design board "Backup and restore": status).
/// Off: one row that opens the sign-in. On: what is backed up, when, what is
/// waiting, and the way to go on. In every state it says the training is safe
/// on the phone. Pure UI: the status comes in, taps go out.
class BackupCardView extends StatelessWidget {
  const new({
    required this.status,
    required this.onOpen,
    required this.onRetry,
    required this.onTurnOff,
    super.key,
  });

  final BackupStatus status;

  /// Opens the sign-in (turn backup on, or sign in again).
  final VoidCallback onOpen;
  final VoidCallback onRetry;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    if (status.state == BackupState.off) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSectionHeader(l10n.backupCardTitle),
          SettingsGroup(
            children: [
              SettingsRow(
                key: const Key('settings_backup'),
                label: l10n.settingsBackup,
                icon: Icons.cloud_upload_outlined,
                onTap: onOpen,
              ),
            ],
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.sm,
              AppDimens.xs,
              AppDimens.sm,
              0,
            ),
            child: Text(
              l10n.backupStatusOff,
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    final headline = switch (status.state) {
      BackupState.upToDate => l10n.backupStatusUpToDate,
      BackupState.waiting => l10n.backupStatusWaiting(status.pending),
      BackupState.failed => l10n.backupStatusFailed(status.problems),
      BackupState.signInAgain => l10n.backupStatusSignIn,
      BackupState.off => '',
    };
    final last = status.lastSyncedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(l10n.backupCardTitle),
        AppCard(
          key: const Key('backup_card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppDimens.xs,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  headline,
                  key: const Key('backup_status'),
                  style: AppTextStyles.body.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (last != null)
                Text(
                  l10n.backupStatusLast(
                    DateFormat.yMMMd(Localizations.localeOf(context).toString())
                        .add_jm()
                        .format(last.toLocal()),
                  ),
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              if (status.planConflict)
                Text(
                  l10n.backupStatusPlanConflict,
                  key: const Key('backup_plan_conflict'),
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              Text(
                l10n.backupSafe,
                style: AppTextStyles.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              SizedBox(height: AppDimens.xs),
              if (status.state == BackupState.signInAgain)
                AppPrimaryButton(
                  key: const Key('backup_sign_in_again'),
                  label: l10n.backupSignIn,
                  onPressed: onOpen,
                )
              else if (status.state == BackupState.waiting ||
                  status.state == BackupState.failed)
                AppSecondaryButton(
                  key: const Key('backup_retry'),
                  label: l10n.backupRetry,
                  onPressed: onRetry,
                ),
              AppSecondaryButton(
                key: const Key('backup_turn_off'),
                label: l10n.backupTurnOff,
                onPressed: onTurnOff,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wires the card to the app. Shown when the flag is on, or when the member
/// already turned backup on (so they can always see it and turn it off).
class BackupCard extends ConsumerWidget {
  const new({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backupStatusProvider);
    final show =
        ref.watch(trainingBackupEnabledProvider) ||
        status.state != BackupState.off;
    if (!show) return const SizedBox.shrink();
    final sync = ref.read(backupSyncProvider);
    return BackupCardView(
      status: status,
      onOpen: onOpen,
      onRetry: sync.run,
      onTurnOff: sync.disable,
    );
  }
}
