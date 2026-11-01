import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/level_card.dart';

import '../../../../helpers/pump_app.dart';
import '../../../../helpers/ui_check.dart';

/// Every level state, stacked (on the home screen the card sits under the
/// exercises, out of the screen tests' first view).
class _Showcase extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: SingleChildScrollView(
      padding: EdgeInsets.all(AppDimens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: const [
          LevelCard(progress: LevelProgress.start),
          LevelCard(
            progress: LevelProgress(
              level: Level.intermediate,
              streakWeeks: 6,
              weeksToNext: 6,
              best: Level.intermediate,
            ),
          ),
          LevelCard(
            progress: LevelProgress(
              level: Level.intermediate,
              streakWeeks: 1,
              weeksToNext: 3,
              comeback: true,
              best: Level.pro,
            ),
          ),
          LevelCard(
            progress: LevelProgress(
              level: Level.pro,
              streakWeeks: 14,
              best: Level.pro,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('each level gets its figure', (tester) async {
    await tester.pumpApp(const _Showcase());
    final figures = tester
        .widgetList<AzmLevelFigure>(find.byType(AzmLevelFigure))
        .map((f) => f.figure);
    expect(figures, [
      LevelFigure.beginner,
      LevelFigure.intermediate,
      LevelFigure.intermediate,
      LevelFigure.pro,
    ]);
  });

  testWidgets('the figure follows the theme brightness', (tester) async {
    await tester.pumpApp(const LevelCard(progress: LevelProgress.start));
    expect(
      tester.widget<AzmLevelFigure>(find.byType(AzmLevelFigure)).brightness,
      Brightness.light,
    );
  });

  screenUiTests('level_card', () => const _Showcase());
}
