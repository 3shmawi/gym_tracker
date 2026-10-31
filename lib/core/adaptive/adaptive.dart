import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform-adaptive building blocks: Cupertino look on iOS/macOS,
/// Material on Android. Prefer Flutter's own `.adaptive` constructors
/// (`Switch.adaptive`, `AlertDialog.adaptive`,
/// `CircularProgressIndicator.adaptive`, `showAdaptiveDialog`) and these
/// widgets over platform checks inside feature code.
extension AdaptivePlatform on BuildContext {
  bool get isCupertino {
    final platform = Theme.of(this).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }
}

/// Primary call-to-action button.
class AdaptiveButton extends StatelessWidget {
  const new({required this.onPressed, required this.child, super.key});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.isCupertino) {
      return CupertinoButton.filled(onPressed: onPressed, child: child);
    }
    return FilledButton(onPressed: onPressed, child: child);
  }
}

/// An action button for `AlertDialog.adaptive`.
class AdaptiveDialogAction extends StatelessWidget {
  const new({
    required this.onPressed,
    required this.child,
    this.isDefault = false,
    this.isDestructive = false,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget child;
  final bool isDefault;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    if (context.isCupertino) {
      return CupertinoDialogAction(
        onPressed: onPressed,
        isDefaultAction: isDefault,
        isDestructiveAction: isDestructive,
        child: child,
      );
    }
    final color = isDestructive ? Theme.of(context).colorScheme.error : null;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: color),
      child: child,
    );
  }
}

/// Adaptive icons for the few icons that differ between platforms.
abstract final class AdaptiveIcons {
  static IconData settings(BuildContext context) =>
      context.isCupertino ? CupertinoIcons.settings : Icons.settings_outlined;

  static IconData check(BuildContext context) =>
      context.isCupertino ? CupertinoIcons.check_mark : Icons.check;

  static IconData back(BuildContext context) =>
      context.isCupertino ? CupertinoIcons.back : Icons.arrow_back;
}
