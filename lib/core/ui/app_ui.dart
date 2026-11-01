import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

export 'app_controls.dart';
export 'azm_level_figure.dart';
export 'azm_logo_animation.dart';

/// The app's UI style: Liquid Glass (iOS 26/27 look) on every platform,
/// via liquid_glass_widgets. Screens use these wrappers, never a glass
/// widget directly, so the style can change in this one file — e.g. to
/// Flutter's own Cupertino Liquid Glass when it ships.
///
/// Quality: premium (Impeller shader) on iOS, standard elsewhere; Reduce
/// Motion and Increase Contrast are respected automatically.
abstract final class AppUi {
  static const style = 'glass';

  /// Devices without a real GPU (software-rendered emulators) can't keep up
  /// with the glass shaders. `--dart-define=GLASS_LITE=true` draws plain
  /// solid surfaces instead and skips the shader preload.
  static const lite = bool.fromEnvironment('GLASS_LITE');

  static Future<void> initialize() => lite
      ? LiquidGlassWidgets.initialize(warmUpMode: GlassWarmUpMode.never)
      : LiquidGlassWidgets.initialize();

  static Widget wrap(Widget app) {
    final glass = LiquidGlassWidgets.wrap(
      child: app,
      brightnessResolver: Theme.maybeBrightnessOf,
      theme: GlassThemeData.simple(
        blur: 10,
        thickness: 30,
        quality: defaultTargetPlatform == TargetPlatform.iOS
            ? GlassQuality.premium
            : GlassQuality.standard,
      ),
    );
    return lite ? testWrap(glass) : glass;
  }

  /// Tests (and accessibility checks) run with solid surfaces: the most
  /// readable variant, and no shader needed in flutter_test.
  static Widget testWrap(Widget child) =>
      GlassAccessibilityScope(reduceTransparency: true, child: child);

  /// Whether to draw plain surfaces here: `GLASS_LITE`, or Reduce
  /// Transparency / Increase Contrast (and widget tests, via [testWrap]).
  /// Lite draws no shader, no blur, no blurred shadow and no screen
  /// capture, so it stays cheap even in software rendering.
  static bool isLite(BuildContext context) =>
      lite || GlassAccessibilityData.of(context).reduceTransparency;
}

/// Glass needs something behind it: a soft gradient from the brand color.
/// Screens with photos pass their own [AppScaffold.background].
class AppBackground extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.lerp(AppColors.primary, scheme.surface, 0.55)!,
            scheme.surface,
            Color.lerp(scheme.tertiary, scheme.surface, 0.7)!,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Centers [child] at most [AppDimens.maxContentWidth] wide (tablets).
Widget _constrained(Widget child) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: AppDimens.maxContentWidth),
    child: child,
  ),
);

class AppScaffold extends StatelessWidget {
  const new({
    required this.body,
    this.title,
    this.leading,
    this.actions = const [],
    this.background,
    this.padBottom = true,
    super.key,
  });

  final String? title;

  /// The button at the bar's start edge. Defaults to a back button when the
  /// page can pop; pass one (e.g. close) to replace it.
  final Widget? leading;

  /// Buttons at the bar's end edge.
  final List<Widget> actions;
  final Widget body;

  /// Keeps the body above the home indicator. Pass false when the body ends
  /// in a dock that pads itself (`SafeArea(top: false)`), so the dock's
  /// surface reaches the bottom edge instead of stopping above a strip of
  /// background.
  final bool padBottom;

  /// The glass bar's height: room for the 48-pt buttons (design: `.ib`).
  static const barHeight = 56.0;

  /// Defaults to [AppBackground]; pass a photo for image-rich screens.
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final start =
        leading ??
        (canPop
            ? AppIconButton(
                icon: AdaptiveIcons.back(context),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);
    final hasBar = title != null || actions.isNotEmpty || start != null;
    if (AppUi.isLite(context)) {
      return _lite(context, start: start, hasBar: hasBar);
    }
    return GlassScaffold(
      background: background ?? const AppBackground(),
      // The body sits below the bar, not behind it: our screens don't add a
      // spacer for the bar, so their top row (e.g. "change day") was under
      // the glass bar and could not be tapped.
      extendBody: false,
      appBar: hasBar
          ? GlassAppBar(
              toolbarHeight: AppScaffold.barHeight,
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.md,
              ),
              // Like the design and the lite bar: the title follows the
              // start button; the actions sit at the end edge.
              centerTitle: false,
              leading: start,
              title: title == null
                  ? null
                  : Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: actions.isEmpty ? null : actions,
            )
          : null,
      // Transparent Material: ListTile, InkWell, TextField… need one, and
      // GlassScaffold (unlike Scaffold) doesn't provide it.
      body: Material(
        type: MaterialType.transparency,
        // With a bar, the scaffold already places the body below the
        // status bar and the bar.
        child: SafeArea(
          top: !hasBar,
          bottom: padBottom,
          child: _constrained(body),
        ),
      ),
    );
  }
}

/// Lite mode: a plain bar and body. GlassScaffold re-captures the screen
/// behind it every frame, which slow devices and software-rendered
/// emulators can't keep up with.
extension on AppScaffold {
  Widget _lite(
    BuildContext context, {
    required Widget? start,
    required bool hasBar,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Stack(
        children: [
          if (background != null) Positioned.fill(child: background!),
          SafeArea(
            bottom: padBottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasBar)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppDimens.sm,
                      vertical: AppDimens.xs,
                    ),
                    child: Row(
                      children: [
                        ?start,
                        SizedBox(width: AppDimens.sm),
                        Expanded(
                          child: title == null
                              ? const SizedBox.shrink()
                              : Semantics(
                                  header: true,
                                  child: Text(
                                    title!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                        ),
                        ...actions,
                      ],
                    ),
                  ),
                Expanded(child: _constrained(body)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppUi.isLite(context)) return GlassContainer.card(child: child);
    // Lite: a near-solid fill, no blur and no blurred shadow (cheap to draw,
    // even in software). Material, so ListTile / InkWell ink stays visible.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(AppDimens.md), child: child),
    );
  }
}

/// A glass icon button with a tooltip (also its accessibility label).
class AppIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // One semantics node with label + action, at least 48×48 (Android and
    // iOS tap-target guidelines).
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            // Shrink-wrapped: a plain Center grows to the whole slot it gets
            // (the bar's leading slot is as wide as the bar), which pushed
            // the button to the middle and left the title no room.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: AppUi.isLite(context)
                  ? _LiteIconButton(icon: icon, onPressed: onPressed)
                  : GlassButton(
                      icon: Icon(icon),
                      onTap: onPressed,
                      // The default (56) drew past the 48-pt slot, so
                      // neighbouring buttons and the title overlapped.
                      width: AppDimens.minTouchTarget,
                      height: AppDimens.minTouchTarget,
                      iconSize: AppDimens.iconMd,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lite mode: a solid round button, no shader or blur.
class _LiteIconButton extends StatelessWidget {
  const new({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox.square(
        dimension: 44,
        child: Icon(icon, size: AppDimens.iconMd),
      ),
    ),
  );
}
