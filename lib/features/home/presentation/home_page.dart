import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/config/app_flavor.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

class HomePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final flavor = AppFlavor.current;
    return AppScaffold(
      title: l10n.appTitle,
      actions: [
        AppIconButton(
          key: const Key('home_settings_button'),
          tooltip: l10n.settingsTitle,
          icon: AdaptiveIcons.settings(context),
          onPressed: () => unawaited(context.push<void>(AppRoutes.settings)),
        ),
      ],
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppDimens.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.homeWelcome,
                style: AppTextStyles.headline,
                textAlign: TextAlign.center,
              ),
              if (!flavor.isProd) ...[
                SizedBox(height: AppDimens.md),
                Chip(label: Text(flavor.name.toUpperCase())),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
