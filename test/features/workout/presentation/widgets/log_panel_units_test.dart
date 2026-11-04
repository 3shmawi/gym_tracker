import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/log_panel.dart';

import '../../../../helpers/pump_app.dart';
import '../../../../helpers/ui_check.dart';

LogPanel panel(
  ExerciseUnit unit, {
  void Function(double, int)? onLog,
  double weight = 7,
  int reps = 12,
}) => LogPanel(
  setNumber: 2,
  totalSets: 3,
  targetReps: 12,
  weight: weight,
  reps: reps,
  weightStep: unit == ExerciseUnit.plate ? 1 : 2.5,
  unit: unit,
  onLog: onLog ?? (_, _) {},
);

/// The log dock for a machine plate and for reps only, stacked.
class _Showcase extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: SingleChildScrollView(
      padding: EdgeInsets.all(AppDimens.md),
      child: Column(
        spacing: AppDimens.lg,
        children: [
          panel(ExerciseUnit.plate),
          panel(ExerciseUnit.reps, weight: 0, reps: 20),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('machine plate: plate number, one plate per tap', (tester) async {
    final logs = <(double, int)>[];
    await tester.pumpApp(
      AppScaffold(
        body: panel(ExerciseUnit.plate, onLog: (w, r) => logs.add((w, r))),
      ),
    );
    expect(find.text('plate'), findsOneWidget);
    expect(find.text('kg'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Next plate'));
    await tester.pump();
    expect(find.text('8'), findsOneWidget);
    await tester.tap(find.byKey(const Key('log_set_button')));
    expect(logs, [(8.0, 12)]);
  });

  testWidgets('reps only: no weight stepper, "Log 20 reps"', (tester) async {
    final logs = <(double, int)>[];
    await tester.pumpApp(
      AppScaffold(
        body: panel(
          ExerciseUnit.reps,
          weight: 0,
          reps: 20,
          onLog: (w, r) => logs.add((w, r)),
        ),
      ),
    );
    expect(find.byKey(const Key('weight_stepper')), findsNothing);
    expect(find.text('Log 20 reps'), findsOneWidget);
    await tester.tap(find.byKey(const Key('log_set_button')));
    expect(logs, [(0.0, 20)]);
  });

  screenUiTests('log_panel_units', () => const _Showcase());
}
