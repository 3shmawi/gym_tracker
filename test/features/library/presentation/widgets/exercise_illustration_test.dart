import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_illustration.dart';

import '../../../../helpers/pump_app.dart';
import '../../helpers/no_picture.dart';

void main() {
  group(ExerciseIllustration, () {
    for (final large in [true, false]) {
      testWidgets('every library exercise has its picture '
          '(${large ? 'large' : 'small'})', (tester) async {
        for (final e in ExerciseCatalog.all) {
          await tester.pumpApp(
            Scaffold(
              body: ExerciseIllustration(exercise: e, large: large),
            ),
          );
          expect(find.byType(Image), findsOneWidget, reason: e.id);
          expect(find.byIcon(Icons.fitness_center), findsNothing);
        }
      });
    }

    for (final large in [true, false]) {
      testWidgets(
        'no picture: the placeholder (${large ? 'large' : 'small'})',
        (tester) async {
          expect(ExerciseImages.has(noPicture.id), isFalse);
          await tester.pumpApp(
            Scaffold(
              body: ExerciseIllustration(exercise: noPicture, large: large),
            ),
          );
          expect(find.byType(Image), findsNothing);
          expect(find.byIcon(Icons.fitness_center), findsOneWidget);
        },
      );
    }

    testWidgets('the picture has no background and takes the text colour', (
      tester,
    ) async {
      final e = ExerciseCatalog.all.firstWhere((e) => e.id == 'flat_db_press');
      await tester.pumpApp(
        Scaffold(body: ExerciseIllustration(exercise: e, large: true)),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.color, isNotNull);
      expect(image.colorBlendMode, BlendMode.srcIn);
      // No filled box behind it: nothing but the sized box around the image.
      expect(
        find.descendant(
          of: find.byType(ExerciseIllustration),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });
  });
}
