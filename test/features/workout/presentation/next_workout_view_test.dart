import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_view.dart';

import '../../../helpers/home_menu.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

/// Day 1 after a Day-4 session with the brief's real numbers, finished on
/// Monday and opened on Thursday: the workout waited.
NextWorkout day1Waiting() =>
    const GetNextWorkout()(PlanTemplates.fiveDaySplit, [
      WorkoutSession(
        dayId: legacyDayId(4),
        finishedAt: DateTime(2026, 11, 2, 19),
        sets: [
          for (final r in [12, 12, 11])
            LoggedSet(exerciseId: 'flat_db_press', weight: 22.5, reps: r),
          for (var i = 0; i < 3; i++)
            const LoggedSet(
              exerciseId: 'wide_lat_pulldown',
              weight: 50,
              reps: 12,
            ),
          for (final r in [8, 7, 7])
            LoggedSet(exerciseId: 'close_grip_row', weight: 50, reps: r),
        ],
      ),
    ], now: DateTime(2026, 11, 5, 18));

NextWorkout day2() => const GetNextWorkout()(PlanTemplates.fiveDaySplit, [
  WorkoutSession(
    dayId: legacyDayId(0),
    finishedAt: DateTime(2026, 11, 2),
    sets: const [],
  ),
], now: DateTime(2026, 11, 3));

/// Day 2 with [level].
NextWorkout withLevel(LevelProgress level) => const GetNextWorkout()(
  PlanTemplates.fiveDaySplit,
  [
    WorkoutSession(
      dayId: legacyDayId(0),
      finishedAt: DateTime(2026, 11, 2),
      sets: const [],
    ),
  ],
  now: DateTime(2026, 11, 3),
  level: level,
);

const intermediate = LevelProgress(
  level: Level.intermediate,
  streakWeeks: 6,
  weeksToNext: 6,
  best: Level.intermediate,
);
const proComeback = LevelProgress(
  level: Level.intermediate,
  streakWeeks: 1,
  weeksToNext: 3,
  comeback: true,
  best: Level.pro,
);
const pro = LevelProgress(level: Level.pro, streakWeeks: 14, best: Level.pro);

Widget view(
  AsyncValue<NextWorkout?> state, {
  VoidCallback? onStart,
  VoidCallback? onRetry,
  VoidCallback? onUseTemplate,
  ValueChanged<int>? onChooseDay,
  VoidCallback? onOpenPlan,
  VoidCallback? onBuildPlan,
  ValueChanged<String>? onEditDay,
  VoidCallback? onOpenWorkspace,
  void Function({required bool fromCard})? onOpenMove,
  bool inProgress = false,
  DateTime? restEndsAt,
  DateTime Function()? now,
}) => NextWorkoutView(
  state: state,
  onRetry: onRetry ?? () {},
  onUseTemplate: onUseTemplate ?? () {},
  onOpenSettings: () {},
  onChooseDay: onChooseDay ?? (_) {},
  onStart: onStart,
  inProgress: inProgress,
  restEndsAt: restEndsAt,
  now: now ?? DateTime.now,
  onOpenPlan: onOpenPlan ?? () {},
  onBuildPlan: onBuildPlan ?? () {},
  onEditDay: onEditDay ?? (_) {},
  onOpenWorkspace: onOpenWorkspace,
  onOpenMove: onOpenMove,
);

/// The waiting day has no exercises yet (a day just added in the editor).
NextWorkout emptyDay() => const GetNextWorkout()(
  const WorkoutPlan(
    days: [
      WorkoutDay(
        id: 'chest',
        name: LocalizedName(ar: 'صدر', en: 'Chest'),
        exercises: [
          Exercise(
            id: 'bench',
            name: LocalizedName(ar: 'بنش', en: 'Bench'),
          ),
        ],
      ),
      WorkoutDay(
        id: 'back',
        name: LocalizedName(ar: 'ضهر وباي', en: 'Back & Biceps'),
        exercises: [],
      ),
    ],
  ),
  [
    WorkoutSession(
      dayId: 'chest',
      finishedAt: DateTime(2026, 11, 2, 19),
      sets: const [],
    ),
  ],
  now: DateTime(2026, 11, 3),
);

/// Finds text ignoring the LTR isolates around numbers.
Finder textPlain(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp('[\u2066\u2069]'), '') == text,
);

void main() {
  group('plan editor entry points', () {
    testWidgets('the plan button on the bar opens the editor', (tester) async {
      var opened = 0;
      await tester.pumpApp(view(AsyncData(day2()), onOpenPlan: () => opened++));
      await openHomeMenu(tester);
      expect(find.text('Your plan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home_plan_button')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('no plan: build one, or start with the template', (
      tester,
    ) async {
      var built = 0;
      var template = 0;
      await tester.pumpApp(
        view(
          const AsyncData(null),
          onBuildPlan: () => built++,
          onUseTemplate: () => template++,
        ),
      );
      // No plan yet: nothing to edit on the bar.
      await openHomeMenu(tester);
      expect(find.byKey(const Key('home_plan_button')), findsNothing);
      expect(find.byKey(const Key('home_settings_button')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('build_plan_button')));
      await tester.tap(find.byKey(const Key('use_template_button')));
      expect(built, 1);
      expect(template, 1);
      expect(find.text('Build your plan'), findsOneWidget);
    });

    testWidgets('a waiting day with no exercises: add them, no Start', (
      tester,
    ) async {
      final edited = <String>[];
      await tester.pumpApp(
        view(AsyncData(emptyDay()), onStart: () {}, onEditDay: edited.add),
      );
      expect(find.text('Back & Biceps'), findsOneWidget);
      expect(find.text('No exercises in this day yet'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
      await tester.tap(find.byKey(const Key('home_add_exercises')));
      expect(edited, ['back']);
    });
  });

  group(NextWorkoutView, () {
    testWidgets('shows the day, last time and the suggestion', (tester) async {
      await tester.pumpApp(view(AsyncData(day1Waiting()), onStart: () {}));

      expect(find.text('Day 1 of 5'), findsOneWidget);
      expect(find.text('Chest & Back'), findsOneWidget);
      expect(find.text('7 exercises · 21 sets'), findsOneWidget);
      expect(find.text('Wide Lat Pulldown'), findsOneWidget);
      expect(find.text('سحب عالي واسع'), findsOneWidget);
      expect(textPlain('3×12 · Last: 50×12 ×3'), findsOneWidget);
      expect(find.text('52.5 kg'), findsOneWidget);
      expect(find.text('↑ Increase'), findsOneWidget);
      expect(textPlain('3×12 · Last: 22.5×12, 12, 11'), findsOneWidget);
      expect(find.text('→ Keep'), findsOneWidget);
      expect(find.text('↓ Decrease'), findsOneWidget);
      expect(find.text('First time'), findsWidgets);
    });

    testWidgets('says the workout waited after a missed day', (tester) async {
      await tester.pumpApp(view(AsyncData(day1Waiting())));
      expect(find.textContaining('waiting since Tuesday'), findsOneWidget);
    });

    testWidgets('no banner when nothing was missed', (tester) async {
      await tester.pumpApp(view(AsyncData(day2())));
      expect(find.textContaining('waiting since'), findsNothing);
    });

    testWidgets('marks supersets (day 2)', (tester) async {
      await tester.pumpApp(view(AsyncData(day2())));
      expect(find.text('Superset with the next exercise'), findsNWidgets(2));
      expect(find.byIcon(Icons.swap_vert), findsNWidgets(2));
    });

    testWidgets('Start appears only when available and calls back', (
      tester,
    ) async {
      await tester.pumpApp(view(AsyncData(day2())));
      expect(find.text('Start workout'), findsNothing);

      var started = 0;
      await tester.pumpApp(view(AsyncData(day2()), onStart: () => started++));
      await tester.tap(find.text('Start workout'));
      expect(started, 1);
    });

    group('a second workout today', () {
      NextWorkout trainedToday() =>
          const GetNextWorkout()(PlanTemplates.fiveDaySplit, [
            WorkoutSession(
              dayId: legacyDayId(0),
              finishedAt: DateTime(2026, 11, 3, 7),
              sets: const [],
            ),
          ], now: DateTime(2026, 11, 3, 19));

      testWidgets('asks first; Start another goes on', (tester) async {
        var started = 0;
        await tester.pumpApp(
          view(AsyncData(trainedToday()), onStart: () => started++),
        );
        await tester.tap(find.text('Start workout'));
        await tester.pumpAndSettle();
        expect(find.text('You already trained today'), findsOneWidget);
        expect(started, 0);
        await tester.tap(find.byKey(const Key('start_again_confirm')));
        await tester.pumpAndSettle();
        expect(started, 1);
      });

      testWidgets('a workout in progress: Continue goes straight back, no '
          'question', (tester) async {
        var opened = 0;
        await tester.pumpApp(
          view(
            AsyncData(trainedToday()),
            onStart: () => opened++,
            inProgress: true,
          ),
        );
        expect(find.text('Start workout'), findsNothing);
        await tester.tap(find.text('Continue workout'));
        await tester.pumpAndSettle();
        expect(find.text('You already trained today'), findsNothing);
        expect(opened, 1);
      });

      testWidgets('resting: the countdown shows above Continue and ticks', (
        tester,
      ) async {
        var clock = DateTime(2026, 11, 3, 19);
        final ends = clock.add(const Duration(seconds: 72));
        await tester.pumpApp(
          view(
            AsyncData(day1Waiting()),
            onStart: () {},
            inProgress: true,
            restEndsAt: ends,
            now: () => clock,
          ),
        );
        expect(find.textContaining('1:12'), findsOneWidget);
        clock = clock.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('1:10'), findsOneWidget);
        // It runs out: it says so, and the ticking stops.
        clock = ends.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Rest is over. Next set!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Rest is over. Next set!'), findsOneWidget);
        expect(tester.binding.transientCallbackCount, 0);
      });

      testWidgets('no rest line without a rest, or without a workout', (
        tester,
      ) async {
        await tester.pumpApp(
          view(AsyncData(day1Waiting()), onStart: () {}, inProgress: true),
        );
        expect(find.byKey(const Key('home_rest_line')), findsNothing);
        // A stale rest time with no workout in progress shows nothing.
        await tester.pumpApp(
          view(
            AsyncData(day1Waiting()),
            onStart: () {},
            restEndsAt: DateTime(2030),
          ),
        );
        expect(find.byKey(const Key('home_rest_line')), findsNothing);
        expect(find.text('Start workout'), findsOneWidget);
      });

      testWidgets('Cancel starts nothing', (tester) async {
        var started = 0;
        await tester.pumpApp(
          view(AsyncData(trainedToday()), onStart: () => started++),
        );
        await tester.tap(find.text('Start workout'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('start_again_cancel')));
        await tester.pumpAndSettle();
        expect(started, 0);
        expect(find.text('You already trained today'), findsNothing);
      });

      testWidgets('Arabic', (tester) async {
        await tester.pumpApp(
          view(AsyncData(trainedToday()), onStart: () {}),
          locale: const Locale('ar'),
        );
        await tester.tap(find.text('ابدأ التمرين'));
        await tester.pumpAndSettle();
        expect(find.text('اتمرّنت النهارده خلاص'), findsOneWidget);
        expect(find.text('ابدأ تمرين كمان'), findsOneWidget);
      });
    });

    testWidgets('change day: pick legs for tomorrow', (tester) async {
      int? chosen;
      await tester.pumpApp(
        view(AsyncData(day2()), onChooseDay: (d) => chosen = d),
      );
      await tester.tap(find.byKey(const Key('change_day_button')));
      await tester.pumpAndSettle();
      expect(find.text('Which workout is next?'), findsOneWidget);
      expect(find.text('Day 3'), findsOneWidget);
      expect(find.text('Legs'), findsOneWidget);

      await tester.tap(find.byKey(const Key('choose_day_2')));
      await tester.pumpAndSettle();
      expect(chosen, 2);
      expect(find.text('Which workout is next?'), findsNothing);
    });

    testWidgets('picking the current day changes nothing', (tester) async {
      int? chosen;
      await tester.pumpApp(
        view(AsyncData(day2()), onChooseDay: (d) => chosen = d),
      );
      await tester.tap(find.byKey(const Key('change_day_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose_day_1')));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });

    testWidgets('no plan: offers the 5-day template', (tester) async {
      var used = 0;
      await tester.pumpApp(
        view(const AsyncData(null), onUseTemplate: () => used++),
      );
      await tester.tap(find.text('Start with the 5-day plan'));
      expect(used, 1);
    });

    testWidgets('error: friendly message and retry', (tester) async {
      var retried = 0;
      await tester.pumpApp(
        view(
          const AsyncError(NetworkFailure(), StackTrace.empty),
          onRetry: () => retried++,
        ),
      );
      expect(find.text(l10nEn.errorNetwork), findsOneWidget);
      await tester.tap(find.text(l10nEn.retry));
      expect(retried, 1);
    });

    testWidgets('an unexpected error never shows its details', (tester) async {
      await tester.pumpApp(
        view(AsyncError(StateError('secret path'), StackTrace.empty)),
      );
      expect(find.textContaining('secret'), findsNothing);
      expect(find.text(l10nEn.errorUnknown), findsOneWidget);
    });

    testWidgets('loading shows the looping logo animation', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(view(const AsyncLoading()));
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(AzmLogoAnimation), findsOneWidget);
      expect(find.bySemanticsLabel(l10nEn.loading), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Arabic shows Arabic names first', (tester) async {
      await tester.pumpApp(
        view(AsyncData(day1Waiting())),
        locale: const Locale('ar'),
      );
      expect(find.text('بنش وضهر'), findsOneWidget);
      expect(find.text('اليوم 1 من 5'), findsOneWidget);
      expect(find.text('52.5 كجم'), findsOneWidget);
      expect(find.text('↑ زوّد'), findsOneWidget);
      // Numbers stay in reading order inside Arabic text.
      expect(
        find.text('\u20663×12\u2069 · آخر مرة: \u206622.5×12, 12, 11\u2069'),
        findsOneWidget,
      );
    });
  });

  group('level card', () {
    /// The card is under the exercises: scroll to it.
    Future<void> showLevel(
      WidgetTester tester,
      Widget screen, {
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpApp(screen, locale: locale);
      await tester.scrollUntilVisible(
        find.byKey(const Key('level_card')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('a new member: beginner, how a week counts', (tester) async {
      await showLevel(tester, view(AsyncData(day2())));
      expect(find.text('Your level · Beginner'), findsOneWidget);
      expect(
        find.text(
          'No weeks in a row yet · 4 more weeks to Intermediate · '
          'A week counts with 3 workouts or more.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<AzmLevelFigure>(find.byType(AzmLevelFigure)).figure,
        LevelFigure.beginner,
      );
    });

    testWidgets('intermediate: streak and weeks to pro', (tester) async {
      await showLevel(tester, view(AsyncData(withLevel(intermediate))));
      expect(find.text('Your level · Intermediate'), findsOneWidget);
      expect(
        find.text('6 weeks in a row · 6 more weeks to Pro'),
        findsOneWidget,
      );
    });

    testWidgets('after a break: says the comeback is faster', (tester) async {
      await showLevel(tester, view(AsyncData(withLevel(proComeback))));
      expect(
        find.text(
          '1 week in a row · 3 more weeks to Pro · '
          'Coming back is twice as fast.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('pro: top level and the pro figure', (tester) async {
      await showLevel(tester, view(AsyncData(withLevel(pro))));
      expect(find.text('Your level · Pro'), findsOneWidget);
      expect(
        find.text('14 weeks in a row · Top level. Keep it going.'),
        findsOneWidget,
      );
      expect(
        tester.widget<AzmLevelFigure>(find.byType(AzmLevelFigure)).figure,
        LevelFigure.pro,
      );
    });

    testWidgets('the figure is one labelled image', (tester) async {
      final handle = tester.ensureSemantics();
      await showLevel(tester, view(AsyncData(withLevel(pro))));
      expect(
        find.bySemanticsLabel('Pro: a bodybuilder in a double-biceps pose'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Arabic', (tester) async {
      await showLevel(
        tester,
        view(AsyncData(withLevel(proComeback))),
        locale: const Locale('ar'),
      );
      expect(find.text('مستواك · متوسط'), findsOneWidget);
      expect(
        find.text(
          'أسبوع واحد ورا بعض · فاضل 3 أسابيع على محترف · الرجوع أسرع بالنص.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Move games (behind move_games)', () {
    testWidgets('the card and the menu row open Move, saying from where', (
      tester,
    ) async {
      final opened = <bool>[];
      await tester.pumpApp(
        view(
          AsyncData(day1Waiting()),
          onOpenMove: ({required fromCard}) => opened.add(fromCard),
        ),
      );
      final card = find.byKey(const Key('home_move_card'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home_move_card')));
      await openHomeMenu(tester);
      await tester.tap(find.byKey(const Key('home_move_button')));
      await tester.pumpAndSettle();
      expect(opened, [true, false]);
    });

    testWidgets('flag off: no card, no row', (tester) async {
      await tester.pumpApp(view(AsyncData(day1Waiting())));
      expect(find.byKey(const Key('home_move_card')), findsNothing);
      await openHomeMenu(tester);
      expect(find.byKey(const Key('home_move_button')), findsNothing);
    });

    testWidgets('during a workout the card hides; the menu row stays', (
      tester,
    ) async {
      await tester.pumpApp(
        view(
          AsyncData(day1Waiting()),
          inProgress: true,
          onStart: () {},
          onOpenMove: ({required fromCard}) {},
        ),
      );
      expect(find.byKey(const Key('home_move_card')), findsNothing);
      await openHomeMenu(tester);
      expect(find.byKey(const Key('home_move_button')), findsOneWidget);
    });
  });

  group('the workspace button (gym accounts)', () {
    testWidgets('is there only for people with an account', (tester) async {
      await tester.pumpApp(view(AsyncData(day1Waiting())));
      await openHomeMenu(tester);
      expect(find.byKey(const Key('home_workspace_button')), findsNothing);
    });

    testWidgets('opens "Where are you training?"', (tester) async {
      var opened = 0;
      await tester.pumpApp(
        view(AsyncData(day1Waiting()), onOpenWorkspace: () => opened++),
      );
      await openHomeMenu(tester);
      expect(find.text(l10nEn.homeMenuWorkspace), findsOneWidget);
      await tester.tap(find.byKey(const Key('home_workspace_button')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  screensUiTests({
    'next_workout_move_card': () => view(
      AsyncData(withLevel(intermediate)),
      onStart: () {},
      onOpenMove: ({required fromCard}) {},
    ),
    'next_workout_with_workspace_button': () =>
        view(AsyncData(day1Waiting()), onStart: () {}, onOpenWorkspace: () {}),
    'next_workout_intermediate': () =>
        view(AsyncData(withLevel(intermediate)), onStart: () {}),
    'next_workout_comeback': () => view(AsyncData(withLevel(proComeback))),
    'next_workout_pro': () => view(AsyncData(withLevel(pro))),
    'next_workout': () => view(AsyncData(day1Waiting()), onStart: () {}),
    'next_workout_in_progress': () =>
        view(AsyncData(day1Waiting()), onStart: () {}, inProgress: true),
    'next_workout_resting': () => view(
      AsyncData(day1Waiting()),
      onStart: () {},
      inProgress: true,
      restEndsAt: DateTime(2026, 11, 3, 19, 1, 12),
      now: () => DateTime(2026, 11, 3, 19),
    ),
    'next_workout_supersets': () => view(AsyncData(day2())),
    'next_workout_no_plan': () => view(const AsyncData(null)),
    'next_workout_empty_day': () => view(AsyncData(emptyDay()), onStart: () {}),
    'next_workout_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
  });
}
