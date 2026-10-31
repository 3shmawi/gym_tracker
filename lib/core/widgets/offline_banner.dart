import 'package:flutter/material.dart';
import 'package:gym_tracker/core/network/connectivity.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Shows a slim banner at the bottom of every screen while offline.
class OfflineBanner extends StatelessWidget {
  const new({required this.child, this.onlineChanges, super.key});

  final Widget child;

  /// Defaults to the device connectivity; tests pass their own stream.
  final Stream<bool>? onlineChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: onlineChanges ?? ConnectivityStatus.onlineChanges,
      initialData: true,
      builder: (context, snapshot) {
        final offline = snapshot.data == false;
        final scheme = Theme.of(context).colorScheme;
        return Column(
          children: [
            Expanded(child: child),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: offline
                  ? Material(
                      color: scheme.inverseSurface,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppDimens.md,
                            vertical: AppDimens.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                color: scheme.onInverseSurface,
                                size: AppDimens.iconMd,
                              ),
                              SizedBox(width: AppDimens.sm),
                              Expanded(
                                child: Text(
                                  context.l10n.offlineBanner,
                                  style: AppTextStyles.body.copyWith(
                                    color: scheme.onInverseSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}
