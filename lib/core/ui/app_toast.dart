import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';

/// A short message at the top of the screen ("Your captain updated your
/// plan"). It does not take focus, never blocks a tap below it, is read out
/// as a live region, and goes away by itself. Only one is shown at a time.
abstract final class AppToast {
  static const duration = Duration(seconds: 6);

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Shows [message] over the whole app. [overlay] is for tests; the app uses
  /// the root navigator's.
  static void show(
    String message, {
    required TextDirection direction,
    OverlayState? overlay,
    Duration lasts = duration,
  }) {
    final target = overlay ?? rootNavigatorKey.currentState?.overlay;
    if (target == null) return;
    dismiss();
    final entry = OverlayEntry(
      builder: (context) => _Toast(message: message, direction: direction),
    );
    _entry = entry;
    target.insert(entry);
    _timer = Timer(lasts, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry
      ?..remove()
      ..dispose();
    _entry = null;
  }
}

class _Toast extends StatelessWidget {
  const new({required this.message, required this.direction});

  final String message;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: direction,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.all(AppDimens.md),
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(
                  key: const Key('app_toast'),
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppDimens.md,
                      vertical: AppDimens.sm2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sync,
                          color: scheme.onInverseSurface,
                          size: AppDimens.iconMd,
                        ),
                        SizedBox(width: AppDimens.sm),
                        Flexible(
                          child: Text(
                            message,
                            style: AppTextStyles.body.copyWith(
                              color: scheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ],
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
