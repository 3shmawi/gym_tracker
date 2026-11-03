import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/app/app_shell.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/settings/presentation/settings_controller.dart';

/// Root widget: the ProviderScope, then the shell.
class App extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      ProviderScope(overrides: gymProviderOverrides, child: const _AppView());
}

class _AppView extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(settings: ref.watch(settingsControllerProvider));
  }
}
