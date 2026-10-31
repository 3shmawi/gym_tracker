import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Shown for unknown routes, e.g. an outdated deep link.
class NotFoundPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppDimens.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.notFoundTitle,
                style: AppTextStyles.headline,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppDimens.lg),
              AdaptiveButton(
                onPressed: () => context.go(AppRoutes.home),
                child: Text(l10n.notFoundGoHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
