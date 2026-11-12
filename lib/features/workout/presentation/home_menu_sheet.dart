import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// One row of the home menu. To add a destination, add an entry where the
/// home screen builds its list: nothing else changes.
class HomeMenuEntry {
  const new({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Opens the home menu: where you train, your plan, progress, settings (and
/// joining a gym for people training alone). The sheet closes first, then
/// the entry runs.
Future<void> showHomeMenu(BuildContext context, List<HomeMenuEntry> entries) =>
    showAppSheet<void>(
      context: context,
      builder: (sheet) => HomeMenuSheet(
        entries: [
          for (final e in entries)
            HomeMenuEntry(
              key: e.key,
              icon: e.icon,
              label: e.label,
              onTap: () {
                Navigator.of(sheet).pop();
                e.onTap();
              },
            ),
        ],
      ),
    );

/// A short list of big rows (at least 56 high). Pure UI.
class HomeMenuSheet extends StatelessWidget {
  const new({required this.entries, super.key});

  final List<HomeMenuEntry> entries;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.homeMenuTitle,
              style: AppTextStyles.title.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: AppDimens.sm),
          for (final e in entries)
            Semantics(
              button: true,
              label: e.label,
              excludeSemantics: true,
              child: InkWell(
                key: e.key,
                borderRadius: BorderRadius.circular(AppDimens.scaled(16)),
                onTap: e.onTap,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: AppDimens.minTouchTarget + AppDimens.sm,
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: AppDimens.sm,
                      vertical: AppDimens.sm,
                    ),
                    child: Row(
                      spacing: AppDimens.md,
                      children: [
                        Icon(e.icon, color: palette.textSecondary),
                        Expanded(
                          child: Text(
                            e.label,
                            style: AppTextStyles.body.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
