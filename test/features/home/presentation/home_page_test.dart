import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/home/presentation/home_page.dart';
import 'package:gym_tracker/features/workout/presentation/workout_controller.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/workout_fakes.dart';

void main() {
  group(HomePage, () {
    testWidgets("opens on today's workout with a settings button", (
      tester,
    ) async {
      await tester.pumpApp(
        ProviderScope(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(
              FakeWorkoutRepository(plan: testPlan),
            ),
          ],
          child: const HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.workoutTitle), findsOneWidget);
      expect(find.byKey(const Key('home_settings_button')), findsOneWidget);
    });
  });
}
