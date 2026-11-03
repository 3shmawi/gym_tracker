import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_fonts.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';

/// Building blocks of the gym account screens (design boards 1–4, `extra.css`).
/// Shared here so the UI style can change in `core/ui/` only.

/// A gym's logo tile (design `.lg`): up to two letters on a blue or amber
/// gradient. The server's logo image is not downloaded yet, so every gym
/// shows its initials, like the design.
class AppLogoTile extends StatelessWidget {
  const new({
    required this.initials,
    this.colorIndex = 0,
    this.size = 44,
    super.key,
  }) : icon = null;

  /// The "solo" tile: an icon on a quiet chip (`.lg.s`).
  const new icon(this.icon, {this.size = 44, super.key})
    : initials = '',
      colorIndex = 0;

  final String initials;
  final IconData? icon;

  /// Even: blue, odd: amber.
  final int colorIndex;

  /// Design pixels; the corner radius follows (13 at 44, 28 at 96).
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final side = AppDimens.scaled(size);
    final radius = BorderRadius.circular(side * (size >= 90 ? 0.29 : 0.3));
    final solo = icon != null;
    final amber = colorIndex.isOdd;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: solo ? palette.fillSubtle : null,
            gradient: solo
                ? null
                : LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: amber
                        ? const [AppColors.gymAmberStart, AppColors.gymAmberEnd]
                        : const [AppColors.gymBlueStart, AppColors.gymBlueEnd],
                  ),
          ),
          child: Center(
            child: solo
                ? Icon(icon, size: side * 0.5, color: palette.textPrimary)
                : Text(
                    initials,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: AppFonts.latin,
                      fontWeight: FontWeight.w800,
                      fontSize: AppDimens.scaled(size >= 90 ? 34 : 17),
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Meaning of an [AppOrb].
enum AppOrbTone { primary, error, warning, muted }

/// The big round icon on state screens (design `.orb`).
class AppOrb extends StatelessWidget {
  const new({
    required this.icon,
    this.tone = AppOrbTone.primary,
    this.size = 104,
    super.key,
  });

  final IconData icon;
  final AppOrbTone tone;

  /// Design pixels: 104 on full screens, 56 in sheets.
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      AppOrbTone.primary => Theme.of(context).colorScheme.primary,
      AppOrbTone.error => palette.error,
      AppOrbTone.warning => palette.trendDown,
      AppOrbTone.muted => palette.textSecondary,
    };
    final side = AppDimens.scaled(size);
    final lite = AppUi.isLite(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lite ? palette.fillSubtle : null,
            gradient: lite
                ? null
                : RadialGradient(
                    center: const Alignment(-0.4, -0.5),
                    radius: 1.1,
                    colors: [palette.keyFill, palette.fillSubtle],
                  ),
            border: Border.all(color: palette.keyFill),
            boxShadow: lite || tone == AppOrbTone.muted
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.53),
                      blurRadius: 50,
                      offset: const Offset(0, 20),
                      spreadRadius: -20,
                    ),
                  ],
          ),
          child: Center(
            child: Icon(
              icon,
              size: side * (size >= 90 ? 0.42 : 0.5),
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with a leading tile, a name, a detail line and a trailing control
/// (design `.li`): at least 56 high, a hairline under it.
class AppListRow extends StatelessWidget {
  const new({
    required this.leading,
    required this.title,
    this.detail,
    this.note,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.selected,
    this.muted = false,
    super.key,
  });

  final Widget leading;
  final String title;
  final String? detail;

  /// A last line in the calm blue (`trendKeep`), e.g. "Pictures from your
  /// gym" (design board 5.1).
  final String? note;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The hairline under the row; off for the last row of a group.
  final bool divider;

  /// For radio rows: announced as selected / not selected.
  final bool? selected;

  /// A row that cannot be opened (a locked gym): quieter name.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: onTap != null,
      selected: selected,
      container: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppDimens.targetLog),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: divider
                  ? Border(bottom: BorderSide(color: palette.fillSubtle))
                  : null,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.xs),
              child: Row(
                spacing: AppDimens.sm2,
                children: [
                  leading,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: AppDimens.scaled(15.5),
                            color: muted
                                ? palette.textSecondary
                                : palette.textPrimary,
                            height: 1.3,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail!,
                            style: AppTextStyles.caption.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        if (note != null)
                          Text(
                            note!,
                            style: AppTextStyles.caption.copyWith(
                              color: palette.trendKeep,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 26-px radio mark of a switcher row: a green check when [selected], a
/// hollow ring otherwise (design `.chk` / `.ring2`).
class AppRadioMark extends StatelessWidget {
  const new({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final side = AppDimens.scaled(26);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppColors.primary : null,
            border: selected
                ? null
                : Border.all(color: palette.textTertiary, width: 2),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: AppDimens.scaled(18),
                  color: AppColors.onPrimary,
                )
              : null,
        ),
      ),
    );
  }
}

/// How serious a [AppBanner] is.
enum AppBannerTone { info, warning, error }

/// A tinted note with an icon (design `.banner`): 18 radius, 10 × 14 padding.
class AppBanner extends StatelessWidget {
  const new({
    required this.icon,
    required this.text,
    this.tone = AppBannerTone.info,
    super.key,
  });

  final IconData icon;
  final String text;
  final AppBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      AppBannerTone.info => palette.trendKeep,
      AppBannerTone.warning => palette.trendDown,
      AppBannerTone.error => palette.error,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppDimens.scaled(18)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.scaled(14),
          vertical: AppDimens.scaled(10),
        ),
        child: Row(
          spacing: AppDimens.scaled(10),
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: AppDimens.scaled(20),
                color: palette.textPrimary,
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.body.copyWith(
                  color: palette.textPrimary,
                  fontSize: AppDimens.scaled(13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small caption over a group of rows (design `.sec-h`).
class AppSectionLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          top: AppDimens.xs + 2,
          start: AppDimens.xs,
          end: AppDimens.xs,
        ),
        child: Text(
          text,
          style: AppTextStyles.caption.copyWith(
            color: context.palette.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The scanner's frame: four white corner marks around a 236-px square
/// (design `.vf`); red after a refused code.
class AppViewfinder extends StatelessWidget {
  const new({this.refused = false, super.key});

  final bool refused;

  static const _arm = 46.0;

  @override
  Widget build(BuildContext context) {
    final color = refused ? context.palette.error : Colors.white;
    final side = AppDimens.scaled(236);
    final arm = AppDimens.scaled(_arm);
    final radius = Radius.circular(AppDimens.scaled(16));
    final line = BorderSide(color: color, width: 4);
    Widget corner(Alignment at) {
      final top = at.y < 0;
      final left = at.x < 0;
      return Align(
        alignment: at,
        child: SizedBox.square(
          dimension: arm,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: top ? line : BorderSide.none,
                bottom: top ? BorderSide.none : line,
                left: left ? line : BorderSide.none,
                right: left ? BorderSide.none : line,
              ),
              borderRadius: BorderRadius.only(
                topLeft: top && left ? radius : Radius.zero,
                topRight: top && !left ? radius : Radius.zero,
                bottomLeft: !top && left ? radius : Radius.zero,
                bottomRight: !top && !left ? radius : Radius.zero,
              ),
            ),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          children: [
            corner(Alignment.topLeft),
            corner(Alignment.topRight),
            corner(Alignment.bottomLeft),
            corner(Alignment.bottomRight),
          ],
        ),
      ),
    );
  }
}

/// What is behind the viewfinder when there is no live picture (tests, a
/// screen that shows a refusal): the design's dark green glow, rounded 32.
class AppCameraBackdrop extends StatelessWidget {
  const new({this.dimmed = false, this.child, super.key});

  final bool dimmed;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.scaled(32)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 0.9,
            colors: [AppColors.cameraCenter, AppColors.cameraEdge],
            stops: [0, 0.8],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?child,
            if (dimmed) const ColoredBox(color: Color(0xBB000000)),
          ],
        ),
      ),
    );
  }
}

/// A big tappable card with an icon, a name and a line of help (design
/// `.choice`): 96 high at least. [highlighted] outlines it in green.
class AppChoiceCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.highlighted = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primary = Theme.of(context).colorScheme.primary;
    final tile = AppDimens.scaled(56);
    return Semantics(
      button: true,
      label: '$title. $detail',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              border: highlighted
                  ? Border.all(color: primary.withValues(alpha: 0.55))
                  : null,
            ),
            child: AppCard(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: AppDimens.scaled(60)),
                child: Row(
                  spacing: AppDimens.scaled(14),
                  children: [
                    SizedBox.square(
                      dimension: tile,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppDimens.scaled(18),
                          ),
                          color: highlighted
                              ? primary.withValues(alpha: 0.18)
                              : palette.fillSubtle,
                        ),
                        child: Icon(
                          icon,
                          size: AppDimens.scaled(32),
                          color: highlighted ? primary : palette.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.title.copyWith(
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                          ),
                          Text(
                            detail,
                            style: AppTextStyles.body.copyWith(
                              color: palette.textSecondary,
                              fontSize: AppDimens.scaled(13.5),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: palette.textSecondary,
                      textDirection: Directionality.of(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
