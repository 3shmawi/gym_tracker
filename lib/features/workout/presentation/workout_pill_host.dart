import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/features/video/presentation/mini_player.dart';
import 'package:gym_tracker/features/video/presentation/widgets/mini_player_view.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/train_again_sheet.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/workout_pill_view.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Where the pill sits; moved by dragging it (board 5).
final workoutPillCornerProvider =
    NotifierProvider<WorkoutPillCornerController, MiniCorner>(
      WorkoutPillCornerController.new,
    );

class WorkoutPillCornerController extends Notifier<MiniCorner> {
  @override
  MiniCorner build() => MiniCorner.bottomEnd;

  // A method, like the mini player's: callers read it as an action.
  // ignore: use_setters_to_change_properties
  void moveTo(MiniCorner corner) => state = corner;
}

/// The path of the screen on top of the stack. Not the router's `uri`:
/// that is only the page the stack started from, so every screen pushed
/// from home (the workout, Settings, the plan) read as "/".
String topPathOf(RouteMatchList stack) {
  if (stack.isEmpty) return stack.uri.path;
  return Uri.tryParse(stack.last.matchedLocation)?.path ?? stack.uri.path;
}

/// The screen the router shows now (its path), for the pill's visibility
/// and the rest alarm.
final currentPathProvider = NotifierProvider<CurrentPathController, String>(
  CurrentPathController.new,
);

class CurrentPathController extends Notifier<String> {
  @override
  String build() {
    final delegate = appRouter.routerDelegate;
    void update() {
      final path = topPathOf(delegate.currentConfiguration);
      if (ref.mounted && path != state) state = path;
    }

    delegate.addListener(update);
    ref.onDispose(() => delegate.removeListener(update));
    return topPathOf(delegate.currentConfiguration);
  }
}

/// Screens without the pill: the workout itself (the member is already in
/// it), the home screen (its own button starts or continues the workout),
/// the plan editor (its action buttons sit in the same bottom corner, and
/// the pill covered "Add exercise") and the screens before the app
/// (welcome, joining a gym).
bool workoutPillHiddenOn(String path) =>
    path == AppRoutes.workout ||
    path == AppRoutes.home ||
    path == AppRoutes.plan ||
    path.startsWith('${AppRoutes.plan}/') ||
    path == AppRoutes.welcome ||
    path == AppRoutes.join ||
    path.startsWith('${AppRoutes.join}/');

/// What the pill shows now, from the workout in progress (if any) and the
/// waiting day; null: nothing to start (no plan, or an empty day).
WorkoutPillData? workoutPillData({
  required ActiveWorkout? active,
  required String? nextDayName,
  required int? nextDayNumber,
  required bool nextDayEmpty,
  required DateTime now,
  required String lang,
}) {
  if (active != null) {
    final cursor = active.cursor;
    final ends = active.draft.restEndsAt;
    if (cursor != null && ends != null) {
      if (ends.isAfter(now)) {
        final last = active.draft.sets.lastOrNull;
        final restOf = active.day.exercises
            .where((e) => e.id == last?.exerciseId)
            .firstOrNull;
        return PillResting(
          endsAt: ends,
          totalSeconds: (restOf ?? active.day.exercises[cursor.exerciseIndex])
              .restSeconds,
          nextSet: cursor.setNumber,
        );
      }
      final exercise = active.day.exercises[cursor.exerciseIndex];
      return PillRestOver(
        nextSet: cursor.setNumber,
        amount: exercise.unit == ExerciseUnit.reps
            ? null
            : WorkoutFormat.amount(cursor.weight, exercise.unit),
      );
    }
    final index = cursor?.exerciseIndex;
    final exercise = index == null
        ? active.day.exercises.lastOrNull
        : active.day.exercises[index];
    if (exercise == null) return null;
    return PillActive(
      exerciseId: exercise.id,
      exerciseName: exercise.name.of(lang),
      done: active.exercisesDone,
      total: active.day.exercises.length,
    );
  }
  if (nextDayName == null || nextDayNumber == null || nextDayEmpty) {
    return null;
  }
  return PillStart(dayNumber: nextDayNumber, dayName: nextDayName);
}

/// Floats the workout pill over every screen but the workout's own and the
/// home screen (design board 5): start the waiting workout, or go back to
/// the one in progress, from anywhere else. Drag it to any corner; drag it
/// past a side to tuck it there as a tab. It keeps clear of the video mini
/// player in the same corner and of the keyboard.
class WorkoutPillHost extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<WorkoutPillHost> createState() => _WorkoutPillHostState();
}

class _WorkoutPillHostState extends ConsumerState<WorkoutPillHost> {
  Offset _drag = Offset.zero;
  bool _docked = false;
  bool _starting = false;
  Timer? _tick;
  final GlobalKey _key = GlobalKey();

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// A running rest repaints every second; nothing else needs a timer.
  void _keepTicking(bool resting) {
    if (resting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!resting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _open(WorkoutPillData data) async {
    unawaited(
      Analytics.capture('workout_pill_tapped', {
        'state': switch (data) {
          PillStart() => 'start',
          PillActive() => 'resume',
          PillResting() => 'rest',
          PillRestOver() => 'rest_over',
        },
      }),
    );
    if (data is! PillStart) {
      _showWorkout();
      return;
    }
    if (_starting) return;
    _starting = true;
    try {
      final next = ref.read(nextWorkoutControllerProvider).value;
      final navigator = rootNavigatorKey.currentContext;
      if (next == null || navigator == null) return;
      if (next.trainedToday && !await confirmTrainAgain(navigator)) return;
      final controller = ref.read(nextWorkoutControllerProvider.notifier);
      if (!await controller.startWorkout()) return;
      ref.invalidate(activeWorkoutControllerProvider);
      _showWorkout();
    } finally {
      _starting = false;
    }
  }

  /// Back to the workout when it is under this screen (the how-to page
  /// opened from it); else opens it on top.
  void _showWorkout() {
    String path() => topPathOf(appRouter.routerDelegate.currentConfiguration);
    final inStack = appRouter.routerDelegate.currentConfiguration.matches.any(
      (m) => m.matchedLocation == AppRoutes.workout,
    );
    if (!inStack) {
      unawaited(appRouter.push<void>(AppRoutes.workout));
      return;
    }
    for (var i = 0; i < 20 && path() != AppRoutes.workout; i++) {
      if (!appRouter.canPop()) break;
      appRouter.pop();
    }
  }

  Offset _centre() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset.zero) +
        box.size.center(Offset.zero) +
        _drag;
  }

  @override
  Widget build(BuildContext context) {
    final path = ref.watch(currentPathProvider);
    final active = ref.watch(activeWorkoutControllerProvider).value;
    final next = ref.watch(nextWorkoutControllerProvider).value;
    final now = ref.watch(clockProvider)();
    final media = MediaQuery.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final data = workoutPillData(
      active: active,
      nextDayName: next?.day.name.of(lang),
      nextDayNumber: next == null ? null : next.dayIndex + 1,
      nextDayEmpty: next?.exercises.isEmpty ?? true,
      now: now,
      lang: lang,
    );
    _keepTicking(data is PillResting);
    final hidden =
        data == null ||
        workoutPillHiddenOn(path) ||
        media.viewInsets.bottom > 0;
    // The app keeps its place in the tree whether the pill shows or not
    // (swapping the Stack for the bare child re-parented the whole app
    // and broke semantics on iOS).
    if (hidden) return Stack(children: [widget.child]);

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final corner = ref.watch(workoutPillCornerProvider);
    final atTop = corner == MiniCorner.topStart || corner == MiniCorner.topEnd;
    final atStart =
        corner == MiniCorner.topStart || corner == MiniCorner.bottomStart;
    // Stacked over (or under) the video in the same corner.
    final video = ref.watch(miniPlayerProvider);
    final videoRoom = video != null && video.corner == corner
        ? MiniPlayerView.playerSide +
              AppDimens.scaled(6) * 3 +
              AppDimens.minTouchTarget +
              AppDimens.sm
        : 0.0;
    final margin = AppDimens.md;
    final top = media.padding.top + kToolbarHeight + AppDimens.sm2 + videoRoom;
    final bottom = media.padding.bottom + AppDimens.sm2 + videoRoom;
    final l10n = context.l10n;

    Widget positioned({required double edge, required Widget child}) =>
        PositionedDirectional(
          top: atTop ? top : null,
          bottom: atTop ? null : bottom,
          start: atStart ? edge : null,
          end: atStart ? null : edge,
          child: child,
        );

    final progress = switch (data) {
      PillActive(:final done, :final total) when total > 0 => done / total,
      _ => 0.0,
    };
    return Stack(
      children: [
        widget.child,
        if (_docked)
          positioned(
            edge: 0,
            child: WorkoutPillTab(
              atStart: atStart,
              progress: progress,
              onTap: () => setState(() => _docked = false),
            ),
          )
        else
          positioned(
            edge: margin,
            child: Transform.translate(
              offset: _drag,
              child: Semantics(
                hint: l10n.pillMoveHint,
                customSemanticsActions: {
                  CustomSemanticsAction(label: l10n.pillHide): () =>
                      setState(() => _docked = true),
                },
                child: GestureDetector(
                  key: _key,
                  onPanUpdate: (d) => setState(() => _drag += d.delta),
                  onPanEnd: (_) {
                    final centre = _centre();
                    final width = media.size.width;
                    final pastLeft = centre.dx < 0;
                    final pastRight = centre.dx > width;
                    ref
                        .read(workoutPillCornerProvider.notifier)
                        .moveTo(
                          nearestCorner(
                            x: pastLeft
                                ? 0
                                : pastRight
                                ? width
                                : centre.dx,
                            y: centre.dy,
                            width: width,
                            height: media.size.height,
                            rtl: rtl,
                          ),
                        );
                    setState(() {
                      _drag = Offset.zero;
                      if (pastLeft || pastRight) _docked = true;
                    });
                  },
                  child: WorkoutPillView(
                    data: data,
                    now: now,
                    onTap: () => unawaited(_open(data)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
