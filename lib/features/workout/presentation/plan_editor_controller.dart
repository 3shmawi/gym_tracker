import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:meta/meta.dart';

/// What the plan editor screens show.
@immutable
class PlanEditorState {
  const new({
    required this.plan,
    this.nextDayId,
    this.lockedDayId,
    this.saveFailure,
    this.permissions = PlanPermissions.solo,
  });

  /// The plan as edited; a new plan has no days until the first is added.
  final WorkoutPlan plan;

  /// The day waiting on the home screen ("Next" badge).
  final String? nextDayId;

  /// The day of the workout in progress: shown, but not editable.
  final String? lockedDayId;

  /// The last change couldn't be saved. [plan] still shows it; retrying
  /// saves it again.
  final AppFailure? saveFailure;

  /// What the gym lets this member change (everything when training solo).
  /// The screens hide and lock the rest; the controller refuses it too.
  final PlanPermissions permissions;

  PlanEditorState copyWith({
    WorkoutPlan? plan,
    String? Function()? nextDayId,
    AppFailure? Function()? saveFailure,
  }) => PlanEditorState(
    plan: plan ?? this.plan,
    nextDayId: nextDayId == null ? this.nextDayId : nextDayId(),
    lockedDayId: lockedDayId,
    saveFailure: saveFailure == null ? this.saveFailure : saveFailure(),
    permissions: permissions,
  );
}

/// Disposed when the last plan screen closes, so opening it again reads
/// the current plan and workout in progress.
final AsyncNotifierProvider<PlanEditorController, PlanEditorState>
planEditorControllerProvider = AsyncNotifierProvider.autoDispose(
  PlanEditorController.new,
  retry: (_, _) => null,
);

/// Edits the plan: every change is checked by [EditPlan], shown at once and
/// saved on the phone right away. After each save the waiting workout stays
/// the same ([KeepNextWorkout]). Edits return a [PlanEditError] when refused
/// (the screens disable those actions, so it is a safety net).
class PlanEditorController extends AsyncNotifier<PlanEditorState> {
  static const _edit = EditPlan();
  static const _keepNext = KeepNextWorkout();
  static const _getNext = GetNextWorkout();

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);
  DateTime _now() => ref.read(clockProvider)();

  WorkoutPlan? _saved;
  List<WorkoutSession> _history = const [];
  ChosenDay? _chosen;

  /// Ids handed out by this editor, kept even when the day or exercise is
  /// deleted again, so none is ever issued twice.
  final _issued = <String>{};

  @override
  Future<PlanEditorState> build() async {
    // A right taken away (or given) while the editor is open: start over from
    // what is saved, with the screens locked to the new rights. A change the
    // old rights allowed but the new ones refuse was not saved, so it goes.
    ref.listen(planPermissionsProvider, (previous, next) {
      if (previous != next) ref.invalidateSelf();
    });
    final permissions = ref.read(planPermissionsProvider);
    _saved = _unwrap(await _repo.loadPlan());
    _history = _unwrap(await _repo.loadHistory());
    _chosen = _unwrap(await _repo.loadChosenDay());
    final draft = _unwrap(await _repo.loadDraft());
    final plan = _saved ?? const WorkoutPlan(days: []);
    return PlanEditorState(
      plan: plan,
      nextDayId: _nextDayId(plan),
      lockedDayId: draft?.dayId,
      permissions: permissions,
    );
  }

  Future<void> retry() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // Shown by the error state.
    }
  }

  /// Saves the shown plan again after a failed save.
  Future<void> retrySave() async {
    final current = state.value;
    if (current == null) return;
    // The captain's plan came in while this one was being edited: the edit
    // is gone, show theirs.
    if (current.saveFailure is PlanChangedFailure) {
      await retry();
      return;
    }
    await _persist(current.plan);
  }

  /// Returns the new day's id, or null when refused.
  Future<String?> addDay(LocalizedName name) async {
    final id = _newId('day');
    final error = await _apply(
      (plan, _) => _edit.addDay(plan, name, id: id),
      'plan_day_added',
    );
    return error == null ? id : null;
  }

  Future<PlanEditError?> renameDay(String dayId, LocalizedName name) => _apply(
    (plan, locked) => _edit.renameDay(plan, dayId, name, lockedDayId: locked),
    'plan_day_renamed',
  );

  Future<PlanEditError?> deleteDay(String dayId) => _apply(
    (plan, locked) => _edit.deleteDay(plan, dayId, lockedDayId: locked),
    'plan_day_deleted',
  );

  Future<PlanEditError?> moveDay(int from, int to) => from == to
      ? Future.value()
      : _apply((plan, _) => _edit.moveDay(plan, from, to), 'plan_day_moved');

  /// Returns the new exercise's id, or null when refused.
  Future<String?> addExercise(String dayId, LocalizedName name) async {
    final id = _newId('ex');
    final error = await _apply(
      (plan, locked) =>
          _edit.addExercise(plan, dayId, name, id: id, lockedDayId: locked),
      'plan_exercise_added',
      properties: const {'source': 'custom'},
    );
    return error == null ? id : null;
  }

  /// Adds an exercise of the library to the day, with its own id (so history
  /// matches) and starting targets. Returns an error when refused (it is
  /// already in that day, the day is full or locked, the gym doesn't allow it).
  Future<PlanEditError?> addLibraryExercise(String dayId, Exercise exercise) =>
      _apply(
        (plan, locked) => _edit.addLibraryExercise(
          plan,
          dayId,
          exercise,
          lockedDayId: locked,
        ),
        'plan_exercise_added',
        properties: const {'source': 'library'},
      );

  Future<PlanEditError?> renameExercise(
    String dayId,
    String exerciseId,
    LocalizedName name,
  ) => _apply(
    (plan, locked) => _edit.renameExercise(
      plan,
      dayId,
      exerciseId,
      name,
      lockedDayId: locked,
    ),
    'plan_exercise_renamed',
  );

  Future<PlanEditError?> deleteExercise(String dayId, String exerciseId) =>
      _apply(
        (plan, locked) =>
            _edit.deleteExercise(plan, dayId, exerciseId, lockedDayId: locked),
        'plan_exercise_deleted',
      );

  Future<PlanEditError?> moveExercise(String dayId, int from, int to) =>
      from == to
      ? Future.value()
      : _apply(
          (plan, locked) =>
              _edit.moveExercise(plan, dayId, from, to, lockedDayId: locked),
          'plan_exercise_moved',
        );

  Future<PlanEditError?> setSuperset(
    String dayId,
    String exerciseId, {
    required bool withNext,
  }) => _apply(
    (plan, locked) => _edit.setSuperset(
      plan,
      dayId,
      exerciseId,
      withNext: withNext,
      lockedDayId: locked,
    ),
    'plan_superset_changed',
    properties: {'on': withNext},
  );

  Future<PlanEditError?> setTargets(
    String dayId,
    String exerciseId, {
    int? sets,
    int? reps,
    int? restSeconds,
    double? weightStep,
    ExerciseUnit? unit,
  }) => _apply(
    (plan, locked) => _edit.setTargets(
      plan,
      dayId,
      exerciseId,
      sets: sets,
      reps: reps,
      restSeconds: restSeconds,
      weightStep: weightStep,
      unit: unit,
      lockedDayId: locked,
    ),
    'plan_targets_changed',
    properties: {
      'field': sets != null
          ? 'sets'
          : reps != null
          ? 'reps'
          : restSeconds != null
          ? 'rest'
          : unit != null
          ? 'unit'
          : 'weight_step',
    },
    targetsOnly: true,
  );

  Future<PlanEditError?> _apply(
    WorkoutPlan Function(WorkoutPlan plan, String? lockedDayId) edit,
    String event, {
    Map<String, Object> properties = const {},
    bool targetsOnly = false,
  }) async {
    final current = state.value;
    if (current == null) return PlanEditError.notFound;
    if (!_allowed(targetsOnly: targetsOnly)) {
      unawaited(
        Analytics.capture('plan_change_refused', {
          'kind': targetsOnly ? 'targets' : 'structure',
        }),
      );
      return PlanEditError.notAllowed;
    }
    final WorkoutPlan plan;
    try {
      plan = edit(current.plan, current.lockedDayId);
    } on PlanEditException catch (e) {
      return e.reason;
    }
    state = AsyncData(current.copyWith(plan: plan));
    unawaited(
      Analytics.capture(event, {...properties, 'days': plan.days.length}),
    );
    await _persist(plan);
    return null;
  }

  /// Whether the member's gym lets them make this kind of change now. A
  /// trainee may build the first plan when the captain made none.
  bool _allowed({required bool targetsOnly}) {
    final p = ref.read(planPermissionsProvider);
    if (!p.canSave) return false;
    final building = p.buildOwnPlan && _saved == null;
    return building || (targetsOnly ? p.editTargets : p.editStructure);
  }

  Future<void> _persist(WorkoutPlan plan) async {
    // Nothing to save until the new plan has its first day.
    if (plan.days.isEmpty) return;
    final isNew = _saved == null;
    final chosen = _keepNext(
      before: _saved,
      after: plan,
      history: _history,
      chosen: _chosen,
      now: _now(),
    );
    final saved = await _repo.savePlan(plan);
    final chosenSaved = saved is Failed<void> || chosen == _chosen
        ? saved
        : await _repo.saveChosenDay(chosen);
    if (chosenSaved case Failed(:final failure)) {
      state = AsyncData(
        state.requireValue.copyWith(plan: plan, saveFailure: () => failure),
      );
      return;
    }
    _saved = plan;
    _chosen = chosen;
    state = AsyncData(
      state.requireValue.copyWith(
        plan: plan,
        nextDayId: () => _nextDayId(plan),
        saveFailure: () => null,
      ),
    );
    if (isNew) {
      unawaited(
        Analytics.capture('plan_created', {
          'source': 'editor',
          'days': plan.days.length,
        }),
      );
    }
    ref
      ..invalidate(nextWorkoutControllerProvider)
      ..invalidate(activeWorkoutControllerProvider);
  }

  String? _nextDayId(WorkoutPlan plan) => plan.days.isEmpty
      ? null
      : _getNext(plan, _history, now: _now(), chosenDay: _chosen).day.id;

  String _newId(String prefix) {
    final plan = state.value?.plan ?? const WorkoutPlan(days: []);
    final id = newPlanId(prefix, {
      ..._issued,
      ...takenIds(plan, _history),
      ...?_saved == null ? null : takenIds(_saved!, const []),
    }, _now());
    _issued.add(id);
    return id;
  }

  static T _unwrap<T>(Result<T> result) => switch (result) {
    Success(:final value) => value,
    Failed(:final failure) => throw failure,
  };
}
