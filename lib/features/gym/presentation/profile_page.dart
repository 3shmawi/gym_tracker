import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/profile_view.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_controller.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_sheet.dart';
import 'package:gym_tracker/features/gym/presentation/workspace_switcher.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// `/profile`: my account. Only for signed-in people (the router sends
/// everyone else to `/welcome`).
class ProfilePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(accountActionsProvider);
    final offer = ref.watch(soloOfferProvider).value;
    final imported =
        ref.watch(soloImportStatusProvider).value?.choice ==
        SoloImportChoice.done;
    return ProfileView(
      session: ref.watch(accountSessionProvider),
      state: ref.watch(gymControllerProvider),
      onRetry: () => ref.invalidate(gymControllerProvider),
      onSwitch: () => unawaited(openWorkspaceSwitcher(context, ref)),
      onDelete: () => unawaited(context.push<void>(AppRoutes.deleteAccount)),
      onSoloImport: offer == null
          ? null
          : () => unawaited(showSoloImportSheet(context, offer)),
      soloImported: imported,
      onAddEmail: (email) async => switch (await actions.addEmail(email)) {
        Success() => null,
        Failed(:final failure) => failure,
      },
      onSignOut: () async {
        final backup = ref.read(backupStatusProvider);
        final backupOn = backup.state != BackupState.off;
        final answer = await askSignOut(
          context,
          backupOn: backupOn,
          // Only when everything is on the account: nothing is lost.
          canRemove: backup.state == BackupState.upToDate,
        );
        if (answer == SignOutAnswer.stay) return;
        final result = await actions.signOut();
        if (!context.mounted) return;
        switch (result) {
          case Success():
            if (answer == SignOutAnswer.signOutAndRemove) {
              await ref.read(backupSyncProvider).removeTrainingFromPhone();
            }
            if (!context.mounted) return;
            context.go(AppRoutes.home);
          case Failed(:final failure):
            _say(context, failure);
        }
      },
    );
  }

  void _say(BuildContext context, AppFailure failure) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(failure.message(context.l10n))));
  }
}
