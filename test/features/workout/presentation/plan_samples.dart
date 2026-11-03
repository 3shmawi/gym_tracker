import 'package:flutter/widgets.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';

/// The 5-day template, day 1 waiting.
const planState = PlanEditorState(
  plan: PlanTemplates.fiveDaySplit,
  nextDayId: 'day-1',
);

/// The 5-day template while day 1's workout is in progress.
const lockedState = PlanEditorState(
  plan: PlanTemplates.fiveDaySplit,
  nextDayId: 'day-1',
  lockedDayId: 'day-1',
);

/// A gym member who may only follow the plan (the captain manages it).
const captainOnlyState = PlanEditorState(
  plan: PlanTemplates.fiveDaySplit,
  nextDayId: 'day-1',
  permissions: PlanPermissions(
    editTargets: false,
    editStructure: false,
    buildOwnPlan: false,
  ),
);

/// A gym member who may change sets, reps and rest, not days or exercises.
const targetsOnlyState = PlanEditorState(
  plan: PlanTemplates.fiveDaySplit,
  nextDayId: 'day-1',
  permissions: PlanPermissions(editStructure: false, buildOwnPlan: false),
);

/// A gym member whose captain has not made a plan, and who may not.
const waitingState = PlanEditorState(
  plan: WorkoutPlan(days: []),
  permissions: PlanPermissions(
    editTargets: false,
    editStructure: false,
    buildOwnPlan: false,
  ),
);

/// A new plan with no days yet ("Build your plan").
const emptyPlanState = PlanEditorState(plan: WorkoutPlan(days: []));

/// One new day with no exercises.
const emptyDayState = PlanEditorState(
  plan: WorkoutPlan(
    days: [
      WorkoutDay(
        id: 'new-day',
        name: LocalizedName(ar: 'صدر وتراي', en: 'Chest & Triceps'),
        exercises: [],
      ),
    ],
  ),
  nextDayId: 'new-day',
);

/// Shows [background] and opens a sheet over it after the first frame, so
/// screen tests (and their screenshots) can include sheets.
class SheetHost extends StatefulWidget {
  const new({required this.background, required this.open, super.key});

  final Widget background;
  final void Function(BuildContext context) open;

  @override
  State<SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<SheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.background;
}
