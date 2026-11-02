import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';

class SettingsSectionHeader extends StatelessWidget {
  const new(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        AppDimens.lg,
        AppDimens.md,
        AppDimens.xs,
      ),
      child: Text(
        title,
        style: AppTextStyles.label.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A single-choice row with a check mark when selected.
class SettingsChoiceTile extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Selection is shown by the check mark and weight, not by text color,
    // so the label keeps full contrast on any surface (glass included).
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(
        label,
        style: AppTextStyles.body.copyWith(
          color: scheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: selected
          ? Icon(AdaptiveIcons.check(context), color: scheme.primary)
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// A row that opens another screen (chevron at the end, mirrored in RTL).
class SettingsLinkTile extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(
        label,
        style: AppTextStyles.body.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Directionality.of(context) == TextDirection.rtl
            ? Icons.chevron_left
            : Icons.chevron_right,
        color: scheme.outline,
      ),
      onTap: onTap,
    );
  }
}
