import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/presentation/join_controller.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_controller.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_sheet.dart';

/// `/join/joined`: shown right after a code was accepted. Opened any other
/// way (a link, a restored screen) there is nothing to show and it goes home.
///
/// If the phone has solo workouts or a plan and the person has not answered
/// yet, the "what about my solo data?" sheet opens over it, once.
class JoinedPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<JoinedPage> createState() => _JoinedPageState();
}

class _JoinedPageState extends ConsumerState<JoinedPage> {
  var _asked = false;

  Future<void> _offer() async {
    if (_asked) return;
    _asked = true;
    final data = await ref.read(soloOfferProvider.future);
    if (data == null || !mounted) return;
    await showSoloImportSheet(context, data);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(joinControllerProvider);
    if (state is! JoinDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.home);
      });
      return const SizedBox.shrink();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_offer());
    });
    return JoinedView(
      joined: state.joined,
      onStart: () {
        ref.read(joinControllerProvider.notifier).reset();
        context.go(AppRoutes.home);
      },
    );
  }
}
