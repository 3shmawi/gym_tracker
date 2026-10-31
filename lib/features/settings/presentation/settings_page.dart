import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/features/settings/presentation/settings_controller.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';

class SettingsPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    return SettingsView(
      settings: ref.watch(settingsControllerProvider),
      onLocaleChanged: controller.setLocale,
      onThemeModeChanged: controller.setThemeMode,
    );
  }
}
