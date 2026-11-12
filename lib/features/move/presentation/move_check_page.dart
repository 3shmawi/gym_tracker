import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_check_view.dart';

/// `/move/check`: the pose check for testers. Opening it never starts the
/// camera (a link could open it); the camera starts on the button and
/// stops when the app leaves the foreground or the screen closes.
class MoveCheckPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MoveCheckPage> createState() => _MoveCheckPageState();
}

class _MoveCheckPageState extends ConsumerState<MoveCheckPage> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // The camera plugin leaves this to the app: release it as soon as the
      // app is not in front (a call, the app switcher, the lock screen).
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _stop();
      },
    );
  }

  void _stop() {
    if (!mounted) return;
    unawaited(ref.read(moveCheckControllerProvider.notifier).stop());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(moveCheckControllerProvider.notifier);
    return MoveCheckView(
      state: ref.watch(moveCheckControllerProvider),
      onStart: () => unawaited(controller.start()),
      onStop: () => unawaited(controller.stop()),
      onReset: controller.resetCount,
      onOpenSettings: () => unawaited(AppSettings.openAppSettings()),
    );
  }
}
