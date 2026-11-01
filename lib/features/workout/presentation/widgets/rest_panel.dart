import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The dock while resting: a big countdown, what's next, +15 s and Skip.
/// Counts down to [endsAt] (a timestamp, so it is right after the app was
/// in the background), then buzzes and calls [onRestOver].
class RestPanel extends StatefulWidget {
  const new({
    required this.endsAt,
    required this.totalSeconds,
    required this.now,
    required this.nextLabel,
    required this.onAdd15,
    required this.onSkip,
    required this.onRestOver,
    super.key,
  });

  final DateTime endsAt;

  /// Full length of this rest, for the progress bar.
  final int totalSeconds;
  final DateTime Function() now;
  final String nextLabel;
  final VoidCallback onAdd15;
  final VoidCallback onSkip;
  final VoidCallback onRestOver;

  @override
  State<RestPanel> createState() => _RestPanelState();
}

class _RestPanelState extends State<RestPanel> {
  Timer? _tick;
  bool _over = false;

  int get _secondsLeft {
    final left = widget.endsAt.difference(widget.now());
    return left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_secondsLeft == 0 && !_over) {
        _over = true;
        unawaited(HapticFeedback.heavyImpact());
        widget.onRestOver();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final left = _secondsLeft;
    final clock = '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    final total = widget.totalSeconds <= 0 ? 1 : widget.totalSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppDimens.sm2,
      children: [
        Text(
          l10n.workoutRest,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: palette.textSecondary),
        ),
        Semantics(
          label: l10n.workoutRestLeft(left),
          child: ExcludeSemantics(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                clock,
                key: const Key('rest_countdown'),
                textAlign: TextAlign.center,
                style: AppTextStyles.numHero.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (left / total).clamp(0, 1).toDouble(),
            minHeight: 6,
            color: AppColors.primary,
            backgroundColor: palette.fillSubtle,
          ),
        ),
        Text(
          widget.nextLabel,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: palette.textSecondary),
        ),
        Row(
          spacing: AppDimens.sm,
          children: [
            Expanded(
              child: AppSecondaryButton(
                key: const Key('rest_add_15'),
                label: l10n.workoutAdd15,
                onPressed: widget.onAdd15,
              ),
            ),
            Expanded(
              child: AppSecondaryButton(
                key: const Key('rest_skip'),
                label: l10n.workoutSkipRest,
                onPressed: widget.onSkip,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
