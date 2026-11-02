import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/workspace_sheet.dart';

/// Opens "Where are you training?" over the current screen and applies the
/// choice. From the home bar and from the profile.
Future<void> openWorkspaceSwitcher(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(gymControllerProvider.notifier);
  // The phone's copy: quick, and works offline.
  final snapshot = await ref
      .read(gymControllerProvider.future)
      .catchError((Object _) => const GymSnapshot());
  if (!context.mounted) return;
  await showWorkspaceSheet(
    context,
    snapshot: snapshot,
    onPick: (workspace) => unawaited(controller.switchTo(workspace)),
    onJoinAnother: () => unawaited(context.push<void>(AppRoutes.joinScan)),
  );
}
