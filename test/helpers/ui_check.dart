import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

import '../flutter_test_config.dart';
import 'pump_app.dart';

/// Screens every UI is checked on (logical pixels).
const uiDevices = <String, Size>{
  'small': Size(320, 568), // iPhone SE 1st gen, small Android
  'phone': Size(375, 812), // the design frame
  'large': Size(430, 932), // Pro Max
  'tablet': Size(820, 1180), // iPad Air portrait
};

/// One way a user can see a screen.
class UiVariant {
  const new({
    required this.device,
    this.locale = const Locale('en'),
    this.brightness = Brightness.light,
    this.textScale = 1,
  });

  final String device;
  final Locale locale;
  final Brightness brightness;
  final double textScale;

  Size get size => uiDevices[device]!;

  String get id =>
      '${device}_${locale.languageCode}_${brightness.name}'
      '${textScale == 1 ? '' : '_x$textScale'}';

  @override
  String toString() => id;
}

/// Every device × language × theme × text size (1.0 and 1.3): 32 variants.
/// Cheap layout checks run on all of them.
final List<UiVariant> uiMatrix = [
  for (final device in uiDevices.keys)
    for (final locale in const [Locale('en'), Locale('ar')])
      for (final brightness in Brightness.values)
        for (final textScale in const [1.0, 1.3])
          UiVariant(
            device: device,
            locale: locale,
            brightness: brightness,
            textScale: textScale,
          ),
];

/// The screenshots kept as goldens, picked to cover the worst cases:
/// the design frame both ways, the smallest screen with big Arabic text in
/// dark mode, and a tablet.
const uiGoldenVariants = <UiVariant>[
  UiVariant(device: 'phone'),
  UiVariant(device: 'phone', locale: Locale('ar'), brightness: Brightness.dark),
  UiVariant(
    device: 'small',
    locale: Locale('ar'),
    brightness: Brightness.dark,
    textScale: 1.3,
  ),
  UiVariant(device: 'tablet'),
];

/// Limits for "nothing too big, nothing too small".
abstract final class UiLimits {
  /// Smallest readable text, before the user's text scale.
  static const minFontSize = 11.0;

  /// Biggest text a screen may use outside hero numbers, before the
  /// user's text scale (display 32 × max scale 1.15 = 36.8 fits).
  static const maxFontSize = 40.0;

  /// Hero numbers (rest timer 64 × 1.15) may go up to this.
  static const maxHeroFontSize = 76.0;
}

extension UiCheck on WidgetTester {
  /// Pumps [widget] the way [variant] sees it: screen size, language,
  /// theme and system text size.
  Future<void> pumpVariant(Widget widget, UiVariant variant) async {
    view
      ..physicalSize = variant.size * 3
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
    await pumpWidget(
      AppUi.testWrap(
        AppScreenScale(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: variant.locale,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: variant.brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(variant.textScale)),
              child: child!,
            ),
            home: widget,
          ),
        ),
      ),
    );
    await pumpAndSettle();
  }

  /// Fails when anything on screen is out of proportion or broken:
  /// - a box sticks out of the screen (outside scrolling lists),
  /// - text is not in the app fonts (Inter / Cairo),
  /// - text is cut off or ellipsized,
  /// - text is too small to read or blown up (see [UiLimits]),
  /// - a RenderFlex overflowed (the yellow-black stripes).
  void expectSaneLayout(UiVariant variant) {
    final screen = Offset.zero & variant.size;
    final problems = <String>[];

    void visit(RenderObject node, {required bool inScrollable}) {
      if (node is RenderOffstage && node.offstage) return;
      final scrolls = inScrollable || node is RenderAbstractViewport;
      if (node is RenderBox && node.hasSize && !inScrollable) {
        final rect = MatrixUtils.transformRect(
          node.getTransformTo(null),
          Offset.zero & node.size,
        );
        if (rect.width > 0 &&
            rect.height > 0 &&
            (rect.left < screen.left - 0.5 ||
                rect.top < screen.top - 0.5 ||
                rect.right > screen.right + 0.5 ||
                rect.bottom > screen.bottom + 0.5)) {
          problems.add('${_describe(node)} is off screen: $rect');
        }
      }
      if (node is RenderParagraph) {
        final text = node.text.toPlainText().trim();
        if (text.isNotEmpty) {
          if (node.didExceedMaxLines) {
            problems.add('Text "$text" is cut off');
          }
          final family = node.text.style?.fontFamily;
          final isIcon = family?.contains('Icons') ?? false;
          if (!isIcon && family != 'Inter' && family != 'Cairo') {
            problems.add(
              'Text "$text" uses font "$family", not Inter/Cairo: pass an '
              'AppTextStyles style or read it from the theme',
            );
          }
          final scaled = _fontSizes(node.text, node.textScaler);
          for (final size in scaled) {
            final base = size / variant.textScale;
            if (base < UiLimits.minFontSize - 0.01) {
              problems.add(
                'Text "$text" is too small: ${base.toStringAsFixed(1)} px',
              );
            }
            if (base > UiLimits.maxHeroFontSize) {
              problems.add(
                'Text "$text" is too big: ${base.toStringAsFixed(1)} px',
              );
            }
          }
        }
      }
      node.visitChildren((child) => visit(child, inScrollable: scrolls));
    }

    visit(renderObject(find.byType(MaterialApp)), inScrollable: false);
    expect(problems, isEmpty, reason: '[$variant]\n${problems.join('\n')}');
  }

  /// Fails when the UI is zoomed: the screen scale must stay in
  /// [AppDimens.minScale]–[AppDimens.maxScale], and no text may pass
  /// [UiLimits.maxFontSize] unless it is a hero number (tabular figures,
  /// like the rest timer).
  void expectNotZoomed(UiVariant variant) {
    final problems = <String>[];
    final scale = AppDimens.scale;
    if (scale < AppDimens.minScale || scale > AppDimens.maxScale) {
      problems.add('Screen scale $scale is outside the allowed range');
    }
    for (final element in find.byType(RichText).evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      final style = paragraph.text.style;
      final isHeroNumber =
          style?.fontFeatures?.contains(const FontFeature.tabularFigures()) ??
          false;
      for (final size in _fontSizes(paragraph.text, TextScaler.noScaling)) {
        if (size > UiLimits.maxFontSize && !isHeroNumber) {
          problems.add(
            '"${paragraph.text.toPlainText().trim()}" is '
            '${size.toStringAsFixed(1)} px (max ${UiLimits.maxFontSize})',
          );
        }
      }
    }
    expect(problems, isEmpty, reason: '[$variant]\n${problems.join('\n')}');
  }

  static String _describe(RenderBox box) {
    final creator = box.debugCreator;
    return creator is DebugCreator
        ? creator.element.widget.runtimeType.toString()
        : box.runtimeType.toString();
  }

  static List<double> _fontSizes(InlineSpan span, TextScaler scaler) {
    final sizes = <double>[];
    void walk(InlineSpan s, double inherited) {
      final size = s.style?.fontSize ?? inherited;
      final family = s.style?.fontFamily ?? '';
      final isIcon = family.contains('Icons');
      if (s is TextSpan && !isIcon && (s.text?.trim().isNotEmpty ?? false)) {
        sizes.add(scaler.scale(size));
      }
      s.visitDirectChildren((child) {
        walk(child, size);
        return true;
      });
    }

    walk(span, 14);
    return sizes;
  }
}

/// The full UI test for one screen; see [screensUiTests].
void screenUiTests(
  String name,
  Widget Function() build, {
  List<UiVariant>? variants,
  bool goldens = true,
}) => screensUiTests({name: build}, variants: variants, goldens: goldens);

/// The full UI test for the screens (or states of one screen) in a test
/// file. Call it once, last in `main()`:
///
/// ```dart
/// screensUiTests({
///   'next_workout': () => view(AsyncData(next)),
///   'next_workout_error': () => view(AsyncError(...)),
/// });
/// ```
///
/// For each of the 32 [uiMatrix] variants: no overflow, nothing off screen,
/// no cut-off text, readable text sizes, no zoomed UI on tablets, app fonts,
/// tap targets, labels and contrast ([AccessibilityChecks.expectAccessible]).
/// For [uiGoldenVariants]: a golden screenshot in `goldens/<name>/`.
///
/// Accessibility runs first for every screen, with the test font (Flutter's
/// contrast check is built for it); layout and screenshots then load the
/// real fonts, which stay loaded for the rest of the file.
void screensUiTests(
  Map<String, Widget Function()> screens, {
  List<UiVariant>? variants,
  bool goldens = true,
}) {
  for (final MapEntry(key: name, value: build) in screens.entries) {
    group('$name UI', () {
      for (final variant in variants ?? uiMatrix) {
        testWidgets('accessibility · $variant', (tester) async {
          if (appFontsLoaded) {
            fail(
              'Real fonts are already loaded in this file, so the contrast '
              'check would be wrong. Call screensUiTests once per file with '
              'every screen.',
            );
          }
          await tester.pumpVariant(build(), variant);
          await tester.expectAccessible(
            checkContrast: variant.locale.languageCode != 'ar',
          );
        });
      }
    });
  }
  for (final MapEntry(key: name, value: build) in screens.entries) {
    group('$name UI', () {
      for (final variant in variants ?? uiMatrix) {
        testWidgets('layout · $variant', (tester) async {
          await tester.runAsync(loadAppFonts);
          await tester.pumpVariant(build(), variant);
          tester
            ..expectSaneLayout(variant)
            ..expectNotZoomed(variant);
        });
      }
      if (goldens) {
        for (final variant in uiGoldenVariants) {
          testWidgets('screenshot · $variant', tags: ['golden'], (
            tester,
          ) async {
            await tester.runAsync(loadAppFonts);
            await tester.pumpVariant(build(), variant);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/$name/${variant.id}.png'),
            );
          });
        }
      }
    });
  }
}
