import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

<<<<<<< yours
/// A group's name above its card (design board 4): small, bold, muted.
=======
/// A group's name above its card: small, bold, muted (the iOS settings
/// layout).
>>>>>>> kit a50ee3f
class SettingsSectionHeader extends StatelessWidget {
  const new(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(
      top: AppDimens.md,
      bottom: AppDimens.xs + 2,
    ),
    child: AppSectionLabel(title),
  );
}

/// A card of settings rows with hairlines between them (design board 4).
class SettingsGroup extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
<<<<<<< yours
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.sm2 + 2,
        vertical: 2,
      ),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: palette.fillSubtle),
            child,
          ],
        ],
      ),
    );
  }
}

/// One settings row (at least 52 high): an icon, the label at the start,
/// the current value at the end, and a chevron when it opens something.
class SettingsRow extends StatelessWidget {
  const new({
=======
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        AppDimens.lg,
        AppDimens.md,
        AppDimens.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppTextStyles.label.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A card of [SettingsRow]s with hairlines between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(horizontal: AppDimens.sm),
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: AppDimens.iconMd + AppDimens.md,
                  color: scheme.outlineVariant,
                ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// One settings row, at least a touch target high: an icon, the label at
/// the start, the current value at the end, and a chevron when it opens
/// something.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.label,
    this.icon,
    this.value,
    this.valueKey,
    this.valueDirection,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final String? value;

  /// For tests that read the value.
  final Key? valueKey;

  /// LTR for numbers like `1.2.3 (45)`, which would read reversed in Arabic.
  final TextDirection? valueDirection;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: math.max(kMinInteractiveDimension, AppDimens.buttonHeight),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm),
        child: Row(
          spacing: AppDimens.md,
          children: [
            if (icon case final icon?)
              Icon(icon, size: AppDimens.iconMd, color: scheme.primary),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Next to the chevron at the end edge; a long value wraps.
            if (value case final value?)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppDimens.settingsValue),
                child: Text(
                  value,
                  key: valueKey,
                  textDirection: valueDirection,
                  textAlign: TextAlign.end,
                  style: AppTextStyles.body.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            // Mirrors in RTL: points to the end edge in both languages.
            if (onTap != null)
              Icon(
                AdaptiveIcons.forward(context),
                size: AppDimens.iconMd,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: row,
        ),
      ),
    );
  }
}

/// A row of the choice sheet: the label, and a check mark when [selected].
/// Selection is shown by the check and weight, not by colour, so the label
/// keeps full contrast on any surface (glass included).
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
>>>>>>> kit a50ee3f
    required this.label,
    this.icon,
    this.value,
    this.onTap,
    this.valueKey,
    this.valueDirection,
    super.key,
  });

  /// The value's text direction; LTR for numbers like `1.2.3 (45)`, which
  /// came out reversed in Arabic.
  final TextDirection? valueDirection;

  final String label;
  final IconData? icon;
  final String? value;
  final VoidCallback? onTap;

  /// For tests that read the value.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
<<<<<<< yours
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: math.max(AppDimens.minTouchTarget, AppDimens.scaled(52)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm),
        child: Row(
          spacing: AppDimens.sm2,
          children: [
            if (icon != null)
              Icon(icon, size: AppDimens.iconMd, color: scheme.primary),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // At the end edge, next to the chevron; long values wrap.
            if (value case final value?)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppDimens.scaled(150)),
                child: Text(
                  value,
                  key: valueKey,
                  textDirection: valueDirection,
                  textAlign: TextAlign.end,
                  style: AppTextStyles.body.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            // chevron_right mirrors itself in RTL (matchTextDirection):
            // it points to the end edge in both languages.
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: AppDimens.iconMd,
                color: palette.textTertiary,
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: row,
=======
    final scheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                kMinInteractiveDimension,
                AppDimens.buttonHeight,
              ),
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.sm,
              ),
              child: Row(
                spacing: AppDimens.md,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        color: scheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(AdaptiveIcons.check(context), color: scheme.primary),
                ],
              ),
            ),
          ),
>>>>>>> kit a50ee3f
        ),
      ),
    );
  }
}

/// Opens a sheet to pick one of [choices] (language, theme). Returns the
<<<<<<< yours
/// picked index, or null when dismissed.
Future<int?> showSettingsChoice({
  required BuildContext context,
=======
/// picked index, or null when it's closed without a pick.
Future<int?> showSettingsChoice(
  BuildContext context, {
>>>>>>> kit a50ee3f
  required String title,
  required List<String> choices,
  required int selected,
}) => showAppSheet<int>(
<<<<<<< yours
  context: context,
  builder: (sheet) => SafeArea(
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
        spacing: AppDimens.xs,
        children: [
          Semantics(
=======
  context,
  builder: (sheet) => SingleChildScrollView(
    padding: EdgeInsetsDirectional.fromSTEB(
      AppDimens.md,
      0,
      AppDimens.md,
      AppDimens.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppDimens.xs,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: AppDimens.sm,
            vertical: AppDimens.sm,
          ),
          child: Semantics(
>>>>>>> kit a50ee3f
            header: true,
            child: Text(
              title,
              style: AppTextStyles.title.copyWith(
<<<<<<< yours
                color: sheet.palette.textPrimary,
              ),
            ),
          ),
          for (final (i, label) in choices.indexed)
            AppChoiceRow(
              key: Key('settings_choice_$i'),
              label: label,
              selected: i == selected,
              onTap: () => Navigator.of(sheet).pop(i),
            ),
        ],
      ),
=======
                color: Theme.of(sheet).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        for (final (i, label) in choices.indexed)
          SettingsChoiceRow(
            key: Key('settings_choice_$i'),
            label: label,
            selected: i == selected,
            onTap: () => Navigator.of(sheet).pop(i),
          ),
      ],
>>>>>>> kit a50ee3f
    ),
  ),
);

/// The installed app version and build number, e.g. `1.2.3 (45)`. Read from
/// the platform (pubspec `version: 1.2.3+45`), so it always matches what the
/// stores and the update gate see. Empty until it loads.
class SettingsVersionTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return SettingsRow(
          label: l10n.settingsVersion,
<<<<<<< yours
=======
          icon: AdaptiveIcons.info(context),
>>>>>>> kit a50ee3f
          valueKey: const Key('settings_version'),
          valueDirection: TextDirection.ltr,
          value: info == null
              ? null
              : l10n.settingsVersionValue(info.version, info.buildNumber),
        );
      },
    );
  }
}
