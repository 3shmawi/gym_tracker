import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';

/// Logging controls from the Design System (docs/design.md → Components).
/// Exported by `app_ui.dart`; screens never style these themselves.

/// The big primary action: log a set, start the workout. Full width,
/// [AppDimens.ctaHeight] high, brand fill, light haptic on press.
class AppPrimaryButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => _PillButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    fill: context.palette.brand,
    foreground: context.palette.onBrand,
    haptic: HapticFeedback.lightImpact,
  );
}

/// The quieter action next to [AppPrimaryButton] (skip, cancel, +15 s).
class AppSecondaryButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => _PillButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    fill: context.palette.fillSubtle,
    foreground: context.palette.textPrimary,
    haptic: HapticFeedback.selectionClick,
  );
}

class _PillButton extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.fill,
    required this.foreground,
    required this.haptic,
    this.outline,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color fill;
  final Color foreground;
  final Future<void> Function() haptic;

  /// A border instead of a fill (design `.cta.sec` with an error border).
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: AppDimens.ctaHeight,
          minWidth: double.infinity,
        ),
        child: Material(
          // Off (design `.cta.off`): a quiet chip with tertiary text, not a
          // faded brand button.
          color: enabled ? fill : context.palette.fillSubtle,
          shape: StadiumBorder(
            side: outline != null && enabled
                ? BorderSide(color: outline!)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    unawaited(haptic());
                    onPressed!();
                  }
                : null,
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.lg,
                vertical: AppDimens.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: foreground, size: AppDimens.iconMd),
                    SizedBox(width: AppDimens.sm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title.copyWith(
                        color: enabled
                            ? foreground
                            : context.palette.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

/// ± stepper for weight or reps: − key, big tabular value, + key.
///
/// Keys are [AppDimens.targetLog] (56) for a sweaty thumb, repeat every
/// 120 ms while held, and click on each step. In RTL the order mirrors
/// with the reading direction (− first). The value never grows past 1.15×
/// with large system text, and shrinks to fit instead of overflowing.
class AppStepper extends StatelessWidget {
  const new({
    required this.value,
    required this.unit,
    required this.onDecrement,
    required this.onIncrement,
    required this.decrementLabel,
    required this.incrementLabel,
    super.key,
  });

  /// Already formatted, e.g. "52.5".
  final String value;

  /// e.g. "kg", "reps" (localized).
  final String unit;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  /// Screen-reader labels, e.g. "Remove 2.5 kg" / "Add 2.5 kg".
  final String decrementLabel;
  final String incrementLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.fillSubtle,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppDimens.xs + 2),
        child: Row(
          children: [
            _StepKey(
              icon: Icons.remove,
              label: decrementLabel,
              onStep: onDecrement,
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: '$value $unit',
                child: ExcludeSemantics(
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.15,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              value,
                              style: AppTextStyles.numXL.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          SizedBox(width: AppDimens.xs + 2),
                          Text(
                            unit,
                            style: AppTextStyles.body.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _StepKey(
              icon: Icons.add,
              label: incrementLabel,
              onStep: onIncrement,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepKey extends StatefulWidget {
  const new({required this.icon, required this.label, required this.onStep});

  final IconData icon;
  final String label;
  final VoidCallback? onStep;

  @override
  State<_StepKey> createState() => _StepKeyState();
}

class _StepKeyState extends State<_StepKey> {
  static const repeatEvery = Duration(milliseconds: 120);
  Timer? _repeat;

  void _step() {
    unawaited(HapticFeedback.selectionClick());
    widget.onStep?.call();
  }

  void _startRepeat() {
    _repeat?.cancel();
    _repeat = Timer.periodic(repeatEvery, (_) => _step());
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onStep != null;
    final size = AppDimens.targetLog;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: enabled ? _step : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: enabled ? _step : null,
          onLongPressStart: enabled ? (_) => _startRepeat() : null,
          onLongPressEnd: enabled ? (_) => _stopRepeat() : null,
          onLongPressCancel: _stopRepeat,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: palette.keyFill,
              borderRadius: BorderRadius.circular(AppDimens.radiusMd + 4),
            ),
            child: Icon(
              widget.icon,
              size: AppDimens.iconMd + 4,
              color: enabled ? palette.textPrimary : palette.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Meaning carried by a badge. Never color alone: callers pass a word and
/// usually an arrow too ("↑ Increase").
enum AppTone { up, keep, down, fresh, neutral }

/// Small label for a trend or status: "↑ Increase", "First time".
class AppBadge extends StatelessWidget {
  const new({required this.label, required this.tone, super.key});

  final String label;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      AppTone.up => palette.trendUp,
      AppTone.keep => palette.trendKeep,
      AppTone.down => palette.trendDown,
      AppTone.fresh => palette.trendNew,
      AppTone.neutral => palette.textSecondary,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.sm + 1,
          vertical: AppDimens.xs,
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// A set in the current exercise: logged, the one being done now, or still
/// to come.
enum AppSetState { done, current, pending }

/// One set: "✓ 52.5×12" (done), "Set 2" (current), "3" (pending).
/// Tappable sets get a 48 px hit area around the smaller chip.
class AppSetChip extends StatelessWidget {
  const new({
    required this.label,
    required this.state,
    required this.semanticLabel,
    this.onTap,
    super.key,
  });

  final String label;
  final AppSetState state;

  /// Full sentence for screen readers, e.g. "Set 1, 52.5 kg, 12 reps,
  /// logged".
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (fill, border, text) = switch (state) {
      AppSetState.done => (
        palette.brandTint,
        Colors.transparent,
        palette.textPrimary,
      ),
      AppSetState.current => (
        Colors.transparent,
        palette.brand,
        palette.textPrimary,
      ),
      AppSetState.pending => (
        palette.fillSubtle,
        Colors.transparent,
        palette.textSecondary,
      ),
    };
    final chip = Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.sm2,
        vertical: AppDimens.xs + 2,
      ),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == AppSetState.done) ...[
            Icon(Icons.check, size: 16, color: text),
            const SizedBox(width: 4),
          ],
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              label,
              style: AppTextStyles.label.copyWith(
                color: text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.minTouchTarget,
              minWidth: AppDimens.minTouchTarget,
            ),
            child: Center(widthFactor: 1, child: chip),
          ),
        ),
      ),
    );
  }
}

/// Progress through steps as segments (plan days, exercises). Fills from
/// the start edge, so it mirrors in RTL. [current] may be fractional: 1.5
/// fills one segment and half the next.
class AppSegmentedProgress extends StatelessWidget {
  const new({
    required this.total,
    required this.current,
    required this.semanticLabel,
    super.key,
  });

  final int total;
  final double current;

  /// e.g. "Day 1 of 5".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          spacing: AppDimens.xs,
          children: [
            for (var i = 0; i < total; i++)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: LinearProgressIndicator(
                      value: (current - i).clamp(0, 1).toDouble(),
                      backgroundColor: palette.fillSubtle,
                      color: palette.brand,
                      minHeight: 6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens a bottom sheet in the app style: solid surface, top radius 32,
/// drag handle, safe area. Returns what the sheet pops.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final palette = context.palette;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    // Not dismissible: no handle, no swipe, no tap outside (only its own
    // button closes it).
    showDragHandle: dismissible,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: palette.surfaceSolid,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppDimens.radiusSheet),
      ),
    ),
    builder: builder,
  );
}

/// A choice in a list (sheet or card): label, optional detail, check mark
/// when selected. At least 56 high.
class AppChoiceRow extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    super.key,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppDimens.targetLog),
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: AppDimens.md,
              vertical: AppDimens.sm,
            ),
            child: Row(
              spacing: AppDimens.sm2,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How loud an [AppDangerButton] is.
enum AppDangerStyle {
  /// Error-tinted pill: delete a day, an exercise.
  tinted,

  /// Transparent with an error border: a way out that must not be hit by
  /// habit (profile → Delete account).
  outlined,

  /// Solid error fill, white text: the final confirm of an irreversible act.
  solid,
}

/// A destructive action: warning haptic. Pair it with [AppSecondaryButton]
/// to cancel.
class AppDangerButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = AppDangerStyle.tinted,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppDangerStyle style;

  @override
  Widget build(BuildContext context) {
    final error = context.palette.error;
    return _PillButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      fill: switch (style) {
        AppDangerStyle.tinted => error.withValues(alpha: 0.16),
        AppDangerStyle.outlined => Colors.transparent,
        AppDangerStyle.solid => error,
      },
      // The design's white text on the dark theme's #F87171 is 2.8:1, under
      // the 3:1 large-text minimum: dark mode uses the dark brand ink.
      foreground: style == AppDangerStyle.solid
          ? (Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBg
                : Colors.white)
          : error,
      outline: style == AppDangerStyle.outlined
          ? error.withValues(alpha: 0.6)
          : null,
      haptic: HapticFeedback.mediumImpact,
    );
  }
}

/// A labelled one-line text field: label above, helper or error and a
/// character counter below. [textDirection] pins the field's direction
/// (an English name in an Arabic screen stays LTR).
class AppTextField extends StatelessWidget {
  const new({
    required this.label,
    required this.controller,
    this.helper,
    this.error,
    this.maxLength,
    this.textDirection,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.keyboardType,
    this.autofillHints,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;

  /// Shown instead of [helper], in the error color, with a red outline.
  final String? error;

  /// Shown as "n/max"; typing past it is allowed so the error can explain.
  final int? maxLength;
  final TextDirection? textDirection;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final hasError = error != null;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd + 4),
      borderSide: BorderSide(color: color, width: width),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Read once, as the field's name.
        ExcludeSemantics(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: palette.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: AppDimens.xs + 2),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            textDirection: textDirection,
            textInputAction: textInputAction,
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: AppTextStyles.body.copyWith(color: palette.textPrimary),
            decoration: InputDecoration(
              semanticCounterText: '',
              filled: true,
              fillColor: palette.fillSubtle,
              constraints: BoxConstraints(minHeight: AppDimens.targetLog),
              contentPadding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.md,
                vertical: AppDimens.md,
              ),
              enabledBorder: border(
                hasError ? palette.error : palette.fillSubtle,
                hasError ? 2 : 1,
              ),
              focusedBorder: border(
                hasError ? palette.error : scheme.primary,
                2,
              ),
            ),
          ),
        ),
        SizedBox(height: AppDimens.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                error ?? helper ?? '',
                style: AppTextStyles.caption.copyWith(
                  color: hasError ? palette.error : palette.textSecondary,
                  fontWeight: hasError ? FontWeight.w700 : null,
                ),
              ),
            ),
            if (maxLength != null)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${value.text.runes.length}/$maxLength',
                    style: AppTextStyles.caption.copyWith(
                      color: hasError ? palette.error : palette.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A row with a label, optional detail and an adaptive switch; the whole
/// row toggles. At least [AppDimens.targetLog] high.
class AppSwitchRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
    super.key,
  });

  final String label;
  final String? detail;
  final bool value;

  /// null disables the row.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppDimens.targetLog),
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm),
            child: Row(
              spacing: AppDimens.sm2,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? palette.textPrimary
                              : palette.textSecondary,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch.adaptive(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice in a wrapping row of choices (e.g. weight step 2.5 kg): at
/// least 48×48, primary outline and tint when selected.
class AppChoiceChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Read instead of [label] (e.g. "2.5 kg" for "2.5").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Material(
        color: selected ? palette.brandTint : palette.fillSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd + 2),
          side: BorderSide(
            color: selected ? primary : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppDimens.minTouchTarget,
              minHeight: AppDimens.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.sm2,
              ),
              child: Center(
                widthFactor: 1,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short fixed-length code (the gym invite code) drawn as separate boxes.
/// One invisible [TextField] takes the typing, so paste, autofill and every
/// keyboard behave normally; the boxes are only the picture. Boxes run
/// left-to-right in every language (a code is Latin text), they never move
/// between states, and an error only recolors them.
///
/// [clean] decides what may be typed (it is applied to every edit and paste).
class AppCodeField extends StatefulWidget {
  const new({
    required this.label,
    required this.controller,
    required this.length,
    required this.clean,
    this.hasError = false,
    this.autofocus = false,
    this.keyboardType,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// The field's name for screen readers.
  final String label;
  final TextEditingController controller;
  final int length;
  final String Function(String input) clean;
  final bool hasError;
  final bool autofocus;

  /// The keyboard (a numeric one for a code of digits) and what autofill may
  /// offer (`AutofillHints.oneTimeCode` brings the code from an SMS or mail).
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppCodeField> createState() => _AppCodeFieldState();
}

class _AppCodeFieldState extends State<AppCodeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final cursor = _focus.hasFocus
        ? text.length.clamp(0, widget.length - 1)
        : -1;
    // Design (.codes b): 62 high, 16 radius, 28 px / 800 digits, 8 gap.
    final boxHeight = AppDimens.scaled(62);
    return SizedBox(
      height: boxHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  spacing: AppDimens.sm,
                  children: [
                    for (var i = 0; i < widget.length; i++)
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.fillSubtle,
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusMd + 4,
                            ),
                            border: Border.all(
                              width: 2,
                              color: widget.hasError
                                  ? palette.error
                                  : i == cursor
                                  ? scheme.primary
                                  : palette.fillSubtle,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              i < text.length ? text[i] : '',
                              style: AppTextStyles.numL.copyWith(
                                fontSize: AppDimens.scaled(28),
                                fontWeight: FontWeight.w800,
                                color: widget.hasError
                                    ? palette.error
                                    : palette.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Semantics(
              label: widget.label,
              textField: true,
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableInteractiveSelection: false,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  keyboardType: widget.keyboardType,
                  autofillHints: widget.autofillHints,
                  maxLength: widget.length,
                  inputFormatters: [_CleanFormatter(widget.clean)],
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
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

/// Replaces every edit by its cleaned form, cursor at the end (a code is
/// short, and pasting "k7m-2qx " must give `K7M2QX`).
class _CleanFormatter extends TextInputFormatter {
  const new(this.clean);

  final String Function(String input) clean;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = clean(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
