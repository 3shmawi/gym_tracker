import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/splash/animated_splash.dart';
import 'package:gym_tracker/core/splash/splash_play_log.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/ui/azm_logo_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appKey = Key('the_app');

class _FakeLog implements SplashPlayLog {
  new({this.full = true, this.error});

  final bool full;
  final Error? error;
  int calls = 0;

  @override
  Future<bool> shouldPlayFull(DateTime now) async {
    calls++;
    if (error != null) throw error!;
    return full;
  }
}

Widget _splash(
  Future<void> ready,
  SplashPlayLog log, {
  bool reduceMotion = false,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: AnimatedSplash(
    ready: ready,
    playLog: log,
    app: (_) => const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('app', key: _appKey),
    ),
  ),
);

double? _progress(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(AzmLogoAnimation),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as AzmLogoPainter)
        .progress;

void main() {
  testWidgets('starts on the static logo, the size of the native mark, '
      'with no text', (tester) async {
    await tester.pumpWidget(_splash(Completer<void>().future, _FakeLog()));
    expect(_progress(tester), 1);
    expect(
      tester.getSize(find.byType(AzmLogoAnimation)),
      const Size.square(AzmLogoAnimation.nativeSplashSize),
    );
    expect(
      tester.getCenter(find.byType(AzmLogoAnimation)),
      tester.getCenter(find.byType(AnimatedSplash)),
    );
    expect(find.byType(RichText), findsNothing);
  });

  testWidgets('first launch of the day: plays in full, then the app', (
    tester,
  ) async {
    await tester.pumpWidget(_splash(Future.value(), _FakeLog()));
    await tester.pump();
    expect(_progress(tester), 0);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byKey(_appKey), findsNothing, reason: 'still animating');

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
    expect(find.byType(AzmLogoAnimation), findsNothing);
  });

  testWidgets('waits for loading when it takes longer than the animation', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_splash(ready.future, _FakeLog()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(_appKey), findsNothing);
    expect(_progress(tester), 1, reason: 'holds the static logo');

    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
  });

  testWidgets('second launch the same day: short, opens when loaded', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_splash(ready.future, _FakeLog(full: false)));
    await tester.pump();
    expect(_progress(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);

    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
    expect(find.byType(AzmLogoAnimation), findsNothing);
  });

  testWidgets('never blocks when loading fails', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(_splash(ready.future, _FakeLog(full: false)));
    ready.completeError(StateError('backend down'));
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
  });

  testWidgets('never blocks when the play log fails', (tester) async {
    await tester.pumpWidget(
      _splash(Future.value(), _FakeLog(error: StateError('prefs'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
  });

  testWidgets('Reduce Motion: static logo, opens as soon as loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _splash(Future.value(), _FakeLog(), reduceMotion: true),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_appKey), findsOneWidget);
  });

  group(SharedPrefsSplashPlayLog, () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('full on the first launch of the day, short after that', () async {
      final log = SharedPrefsSplashPlayLog(
        await SharedPreferences.getInstance(),
      );
      expect(await log.shouldPlayFull(DateTime(2026, 11, 1, 7)), isTrue);
      expect(await log.shouldPlayFull(DateTime(2026, 11, 1, 22)), isFalse);
      expect(await log.shouldPlayFull(DateTime(2026, 11, 2, 0, 1)), isTrue);
      expect(await log.shouldPlayFull(DateTime(2026, 11, 2, 9)), isFalse);
    });

    test('stores only the local date', () async {
      final prefs = await SharedPreferences.getInstance();
      await SharedPrefsSplashPlayLog(prefs)
          .shouldPlayFull(DateTime(2026, 1, 5, 13, 45));
      expect(prefs.getKeys(), {SharedPrefsSplashPlayLog.key});
      expect(prefs.getString(SharedPrefsSplashPlayLog.key), '2026-01-05');
    });

    test('a corrupted value just plays in full', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsSplashPlayLog.key: '<script>',
      });
      final log = SharedPrefsSplashPlayLog(
        await SharedPreferences.getInstance(),
      );
      expect(await log.shouldPlayFull(DateTime(2026, 11, 2)), isTrue);
    });
  });
}
