import 'package:flutter/material.dart';
import 'package:gym_tracker/core/legal/consent_gate.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/update/app_update_listener.dart';
import 'package:gym_tracker/core/widgets/offline_banner.dart';
import 'package:gym_tracker/features/gym/presentation/gym_brand.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/video/presentation/mini_player_host.dart';
import 'package:gym_tracker/features/workout/presentation/rest_alarm_host.dart';
import 'package:gym_tracker/features/workout/presentation/workout_pill_host.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The MaterialApp, configured once: screen scaling, themes, localization
/// (Arabic → RTL automatically), routing and the update gate.
class AppShell extends StatelessWidget {
  const new({required this.settings, super.key});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AppScreenScale(
      builder: (context) => MaterialApp.router(
        onGenerateTitle: (context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        routerConfig: appRouter,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.themeMode,
        locale: settings.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => AppUpdateListener(
          // Nothing of the app opens before the member agreed (III.A).
          child: ConsentGate(
            // The gym's colour, for everything inside the app itself.
            child: BrandThemeHost(
              child: GymSyncHost(
                child: OfflineBanner(
                  child: MiniPlayerHost(
                    child: WorkoutPillHost(
                      child: RestAlarmHost(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
