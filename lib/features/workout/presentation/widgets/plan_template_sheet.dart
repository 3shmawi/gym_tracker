import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Pick a ready plan" (no plan yet): full body 3 days, upper/lower 4 days,
/// the 5-day split. Returns the one tapped, or null.
Future<PlanTemplateId?> showPlanTemplateSheet(BuildContext context) =>
    showAppSheet<PlanTemplateId>(
      context: context,
      builder: (sheet) =>
          PlanTemplatePicker(onPick: (id) => Navigator.of(sheet).pop(id)),
    );

/// The sheet's content (also on its own in tests and screenshots).
class PlanTemplatePicker extends StatelessWidget {
  const new({required this.onPick, super.key});

  final ValueChanged<PlanTemplateId> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final locale = Localizations.localeOf(context).languageCode;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppDimens.md,
            0,
            AppDimens.md,
            AppDimens.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppDimens.sm2,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.planTemplatesTitle,
                  style: AppTextStyles.title.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                l10n.planTemplatesBody,
                style: AppTextStyles.body.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              for (final id in PlanTemplateId.values)
                AppChoiceCard(
                  key: Key('template_${id.id}'),
                  icon: switch (id) {
                    PlanTemplateId.fullBody3 => Icons.accessibility_new,
                    PlanTemplateId.upperLower4 => Icons.swap_vert,
                    PlanTemplateId.split5 => Icons.view_week_outlined,
                  },
                  title: switch (id) {
                    PlanTemplateId.fullBody3 => l10n.planTemplateFullBody,
                    PlanTemplateId.upperLower4 => l10n.planTemplateUpperLower,
                    PlanTemplateId.split5 => l10n.planTemplateSplit5,
                  },
                  detail: [
                    switch (id) {
                      PlanTemplateId.fullBody3 => l10n.planTemplateFullBodyBody,
                      PlanTemplateId.upperLower4 =>
                        l10n.planTemplateUpperLowerBody,
                      PlanTemplateId.split5 => l10n.planTemplateSplit5Body,
                    },
                    // The days, as the plan names them.
                    id.plan.days.map((d) => d.name.of(locale)).join(' · '),
                  ].join('\n'),
                  // The easiest start is suggested.
                  highlighted: id == PlanTemplateId.fullBody3,
                  onTap: () => onPick(id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
