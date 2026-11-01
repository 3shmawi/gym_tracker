import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Android 14+ only, once, at the first rest: notifications are on but
/// can't ring on time until "Alarms & reminders" is turned on. True when
/// the member wants the settings page.
Future<bool> showRestOnTimeSheet(BuildContext context) async =>
    await showAppSheet<bool>(
      context: context,
      builder: (_) => const RestOnTimeSheet(),
    ) ??
    false;

/// The sheet's content: why, then Open settings / Not now.
class RestOnTimeSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.restOnTimeTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.title.copyWith(color: palette.textPrimary),
            ),
          ),
          Text(
            l10n.restOnTimeBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
          AppPrimaryButton(
            key: const Key('rest_on_time_open'),
            icon: Icons.alarm_on,
            label: l10n.restOnTimeOpen,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          AppSecondaryButton(
            key: const Key('rest_on_time_later'),
            label: l10n.restOnTimeLater,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
