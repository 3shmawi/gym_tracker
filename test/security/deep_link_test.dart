import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/not_found_page.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_page.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deep links are untrusted input: unknown or crafted paths must land on a
/// safe screen, never crash or open something unexpected.
void main() {
  Future<void> pumpRouter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(
            LocalWorkoutRepository(prefs),
          ),
          activeWorkoutEnabledProvider.overrideWith((ref) => false),
        ],
        child: AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: appRouter,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unknown and crafted paths show the not-found page', (
    tester,
  ) async {
    await pumpRouter(tester);

    for (final path in [
      '/does-not-exist',
      '/settings/../../etc/passwd',
      '/%2e%2e/admin',
    ]) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      expect(find.byType(NotFoundPage), findsOneWidget, reason: path);
    }
  });

  testWidgets('query parameters cannot redirect the app', (tester) async {
    await pumpRouter(tester);

    appRouter.go('/?redirect=https://evil.example.com');
    await tester.pumpAndSettle();

    expect(find.byType(NextWorkoutPage), findsOneWidget);
  });
}
