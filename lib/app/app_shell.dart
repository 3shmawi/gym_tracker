import 'package:flutter/material.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/update/app_update_listener.dart';
import 'package:gym_tracker/core/widgets/offline_banner.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
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
          child: OfflineBanner(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
