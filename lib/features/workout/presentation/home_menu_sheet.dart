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
    this.detail,
    this.secondary = false,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A short line under the label saying what is there.
  final String? detail;

  /// Account and app rows (gym, settings): in the second card, under the
  /// training rows.
  final bool secondary;
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
              detail: e.detail,
              secondary: e.secondary,
              onTap: () {
                Navigator.of(sheet).pop();
                e.onTap();
              },
            ),
        ],
      ),
    );

/// Two cards of rows like Settings: training (plan, progress, Move) first,
/// then the gym and settings. Each row: a tinted icon tile, the name, a
/// short detail line and a chevron; at least 56 high. Pure UI.
class HomeMenuSheet extends StatelessWidget {
  const new({required this.entries, super.key});

  final List<HomeMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final groups = [
      [
        for (final e in entries)
          if (!e.secondary) e,
      ],
      [
        for (final e in entries)
          if (e.secondary) e,
      ],
    ].where((g) => g.isNotEmpty);
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
        spacing: AppDimens.sm2,
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
          for (final group in groups)
            AppCard(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.sm2,
                vertical: AppDimens.xs,
              ),
              child: Column(
                children: [
                  for (final (i, e) in group.indexed)
                    _MenuRow(entry: e, divider: i < group.length - 1),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const new({required this.entry, required this.divider});

  final HomeMenuEntry entry;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final tile = AppDimens.scaled(40);
    final detail = entry.detail;
    return Semantics(
      button: true,
      label: detail == null ? entry.label : '${entry.label}, $detail',
      excludeSemantics: true,
      child: InkWell(
        key: entry.key,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        onTap: entry.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: palette.fillSubtle))
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppDimens.targetLog),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm),
              child: Row(
                spacing: AppDimens.sm2,
                children: [
                  Container(
                    width: tile,
                    height: tile,
                    decoration: BoxDecoration(
                      color: palette.brandTint,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    ),
                    child: Icon(
                      entry.icon,
                      size: AppDimens.iconMd,
                      color: scheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.label,
                          style: AppTextStyles.body.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail,
                            style: AppTextStyles.caption.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // chevron_right mirrors itself in RTL: it points to the
                  // end edge in both languages.
                  Icon(
                    Icons.chevron_right,
                    size: AppDimens.iconMd,
                    color: palette.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
