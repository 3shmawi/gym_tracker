import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/presentation/join_controller.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';

/// `/join/joined`: shown right after a code was accepted. Opened any other
/// way (a link, a restored screen) there is nothing to show and it goes home.
class JoinedPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(joinControllerProvider);
    if (state is! JoinDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.home);
      });
      return const SizedBox.shrink();
    }
    return JoinedView(
      joined: state.joined,
      onStart: () {
        ref.read(joinControllerProvider.notifier).reset();
        context.go(AppRoutes.home);
      },
    );
  }
}
