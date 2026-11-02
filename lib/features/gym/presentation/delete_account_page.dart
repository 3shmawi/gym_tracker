import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/presentation/delete_account_view.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';

/// `/profile/delete`: deletes the account on the server, then the phone's gym
/// state. Everything the app offers a person with an account, and required by
/// Apple 5.1.1(v) and Google Play.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  var _eraseLocal = false;
  var _busy = false;
  AppFailure? _failure;

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await ref
        .read(accountActionsProvider)
        .deleteAccount(eraseLocalWorkouts: _eraseLocal);
    if (!mounted) return;
    switch (result) {
      case Success():
        context.go(AppRoutes.home);
      case Failed(:final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberships =
        ref.watch(gymControllerProvider).value?.memberships ?? const [];
    // An owner types the name of a gym they own, so a stray tap cannot end
    // it.
    final owned = [
      for (final m in memberships)
        if (m.isActive && m.role == GymRole.owner) m.gym.name,
    ]..sort();
    return DeleteAccountView(
      ownedGymName: owned.firstOrNull,
      eraseLocal: _eraseLocal,
      onEraseLocalChanged: (v) => setState(() => _eraseLocal = v),
      busy: _busy,
      failure: _failure,
      onDelete: () => unawaited(_delete()),
      onCancel: () => context.pop(),
    );
  }
}
