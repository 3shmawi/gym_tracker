import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The bar as the phone draws it: glass (screen tests use the lite bar), on
/// a 320-wide phone with a home indicator.
Future<void> _pumpGlass(
  WidgetTester tester,
  Widget screen, {
  TextDirection direction = TextDirection.ltr,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view
    ..physicalSize = const Size(960, 1704)
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(top: 141, bottom: 102);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScreenScale(
      builder: (context) => MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        locale: Locale(direction == TextDirection.rtl ? 'ar' : 'en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pump();
}

Widget _button(String key, IconData icon) =>
    AppIconButton(key: Key(key), icon: icon, tooltip: key, onPressed: () {});

const _dockKey = Key('dock');

/// A body that ends in a dock padding itself, like the workout screen.
Widget _withDock() => Column(
  children: [
    const Expanded(child: SizedBox.expand()),
    ColoredBox(
      key: _dockKey,
      color: const Color(0xFF101010),
      child: SafeArea(top: false, child: SizedBox(height: AppDimens.xl)),
    ),
  ],
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('glass bar: start button, title and actions never overlap '
        '(${direction.name})', (tester) async {
      await _pumpGlass(
        tester,
        AppScaffold(
          title: 'A long day name that has to be cut off at the end',
          leading: _button('start', Icons.close),
          actions: [
            _button('a1', Icons.flag_outlined),
            _button('a2', Icons.more_horiz),
          ],
          body: const SizedBox.expand(),
        ),
        direction: direction,
      );
      expect(tester.takeException(), isNull);

      final width = tester.view.physicalSize.width / 3;
      final rects = {
        for (final k in ['start', 'a1', 'a2'])
          k: tester.getRect(
            find.descendant(
              of: find.byKey(Key(k)),
              matching: find.byType(GlassButton),
            ),
          ),
        'title': tester.getRect(find.byType(Text).first),
      };
      for (final MapEntry(key: name, value: r) in rects.entries) {
        expect(r.left, greaterThanOrEqualTo(0), reason: name);
        expect(r.right, lessThanOrEqualTo(width), reason: name);
        if (name != 'title') {
          expect(r.width, AppDimens.minTouchTarget, reason: name);
          expect(r.height, AppDimens.minTouchTarget, reason: name);
        }
      }
      final names = rects.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final overlap = rects[names[i]]!.intersect(rects[names[j]]!);
          expect(
            overlap.width <= 0 || overlap.height <= 0,
            isTrue,
            reason: '${names[i]} overlaps ${names[j]}',
          );
        }
      }

      // The start button hugs the start edge, the actions the end edge, and
      // the title is really shown between them.
      final pad = AppDimens.md;
      final startRect = rects['start']!;
      final endRect = rects['a2']!;
      final ltrBar = direction == TextDirection.ltr;
      expect(
        ltrBar ? startRect.left : width - startRect.right,
        closeTo(pad, 1),
        reason: 'start button at the start edge',
      );
      expect(
        ltrBar ? width - endRect.right : endRect.left,
        closeTo(pad, 1),
        reason: 'actions at the end edge',
      );
      expect(rects['title']!.width, greaterThan(100), reason: 'title shown');

      // The start button is at the start edge, the actions at the end.
      final ltr = direction == TextDirection.ltr;
      final start = rects['start']!;
      final end = rects['a2']!;
      expect(ltr ? start.left < end.left : start.left > end.left, isTrue);
      final title = rects['title']!;
      expect(
        ltr ? title.left > start.right : title.right < start.left,
        isTrue,
        reason: 'the title follows the start button',
      );
    });
  }

  testWidgets('glass bar: a page that can pop gets a back button', (
    tester,
  ) async {
    await _pumpGlass(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const AppScaffold(title: 'Settings', body: SizedBox.expand()),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a leading button replaces back', (tester) async {
    await _pumpGlass(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AppScaffold(
                leading: _button('close', Icons.close),
                body: const SizedBox.expand(),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('close')), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  for (final lite in [false, true]) {
    final mode = lite ? 'lite' : 'glass';
    testWidgets('$mode: a self-padding dock reaches the bottom edge', (
      tester,
    ) async {
      final screen = AppScaffold(
        title: 'Workout',
        padBottom: false,
        body: _withDock(),
      );
      await _pumpGlass(tester, lite ? AppUi.testWrap(screen) : screen);
      final height = tester.view.physicalSize.height / 3;
      final dock = tester.getRect(find.byKey(_dockKey));
      expect(dock.bottom, height);
      // …and its content stays above the home indicator (34 pt).
      expect(dock.height, closeTo(AppDimens.xl + 34, .001));
    });

    testWidgets('$mode: by default the body stays above the home indicator', (
      tester,
    ) async {
      final screen = AppScaffold(title: 'Workout', body: _withDock());
      await _pumpGlass(tester, lite ? AppUi.testWrap(screen) : screen);
      final height = tester.view.physicalSize.height / 3;
      expect(tester.getRect(find.byKey(_dockKey)).bottom, height - 34);
    });
  }

  test('every adaptive icon font ships with the app', () async {
    // CupertinoIcons draws from the cupertino_icons package's font. Without
    // the package every iOS settings / back / check icon was a "?" box.
    final manifest = await rootBundle.loadString('FontManifest.json');
    for (final icon in const [
      CupertinoIcons.settings,
      CupertinoIcons.back,
      CupertinoIcons.check_mark,
    ]) {
      final family = icon.fontPackage == null
          ? icon.fontFamily!
          : 'packages/${icon.fontPackage}/${icon.fontFamily}';
      expect(manifest, contains('"$family"'), reason: family);
    }
  });

  testWidgets('iOS uses the Cupertino icons', (tester) async {
    late IconData settings;
    await _pumpGlass(
      tester,
      Builder(
        builder: (context) {
          settings = AdaptiveIcons.settings(context);
          return const SizedBox.shrink();
        },
      ),
      platform: TargetPlatform.iOS,
    );
    expect(settings.fontPackage, 'cupertino_icons');
  });
}
