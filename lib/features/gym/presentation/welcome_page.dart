import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_view.dart';

/// `/welcome`: join a gym or train alone. Neither choice makes an account.
class WelcomePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WelcomeView(
      onJoin: () => unawaited(context.push<void>(AppRoutes.joinScan)),
      onHaveCode: () => unawaited(context.push<void>(AppRoutes.join)),
      onSolo: () {
        // Answered once: the next launch goes straight to the workout.
        unawaited(ref.read(gymLocalRepositoryProvider).saveOnboardingDone());
        context.go(AppRoutes.home);
      },
    );
  }
}
