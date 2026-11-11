import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';

/// Azm's own colours for what belongs to the app and not to a gym: the
/// update gate and the consent sheet stay Azm's even inside a gym's
/// workspace (docs/designs/gym_brand_colours.md → "What never changes").
class AzmTheme extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: AppTheme.of(Theme.of(context).brightness), child: child);
}
