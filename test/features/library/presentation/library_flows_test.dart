import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_toast.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';
import 'package:gym_tracker/features/video/presentation/video_providers.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/pump_app.dart' show l10nEn;

/// The library on the real router, controllers and on-phone storage.
void main() {
  late SharedPreferences prefs;

  Future<void> pumpApp(
    WidgetTester tester, {
    String at = '/plan/day-3',
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(
            LocalWorkoutRepository(prefs),
          ),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 18)),
          ...overrides,
        ],
        child: AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: appRouter,
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    appRouter.go(at);
    await tester.pumpAndSettle();
  }

  WorkoutPlan savedPlan() => WorkoutPlan.fromJson(
    jsonDecode(prefs.getString(LocalWorkoutRepository.planKey)!)
        as Map<String, Object?>,
  );

  List<String> idsOf(String dayId) => [
    for (final e in savedPlan().dayById(dayId)!.exercises) e.id,
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      LocalWorkoutRepository.planKey: jsonEncode(
        PlanTemplates.fiveDaySplit.toJson(),
      ),
    });
    prefs = await SharedPreferences.getInstance();
    appRouter.go(AppRoutes.home);
  });

  tearDown(AppToast.dismiss);

  Future<void> openLibraryFromDay(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('plan_add_exercise')));
    await tester.pumpAndSettle();
    expect(find.text('Add an exercise'), findsWidgets);
    await tester.tap(find.byKey(const Key('add_from_library')));
    await tester.pumpAndSettle();
    expect(find.text('Exercise library'), findsOneWidget);
  }

  testWidgets('Add an exercise → library → Add: saved with its own id', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(idsOf('day-3'), isNot(contains('pec_deck')));
    await openLibraryFromDay(tester);

    await tester.enterText(find.byKey(const Key('library_search')), 'pec');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_add_pec_deck')));
    await tester.pumpAndSettle();

    expect(idsOf('day-3').last, 'pec_deck');
    final added = savedPlan().dayById('day-3')!.exercises.last;
    expect(added.name.en, 'Pec Deck');
    expect(added.targetSets, 3);
    expect(find.text('Added'), findsOneWidget);
    expect(
      find.byKey(const Key('library_add_pec_deck')),
      findsNothing,
      reason: 'once in the day, it can only be opened',
    );
  });

  testWidgets('the same exercise can go to another day, once per day', (
    tester,
  ) async {
    await pumpApp(tester);
    // pec_deck is already in day 1 of the template.
    expect(idsOf('day-1'), contains('pec_deck'));
    await openLibraryFromDay(tester);
    await tester.enterText(find.byKey(const Key('library_search')), 'pec deck');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_add_pec_deck')));
    await tester.pumpAndSettle();
    expect(idsOf('day-3'), contains('pec_deck'));
    expect(idsOf('day-1').where((id) => id == 'pec_deck'), hasLength(1));
  });

  testWidgets('open an exercise, read it, add it from there', (tester) async {
    await pumpApp(tester);
    await openLibraryFromDay(tester);
    await tester.enterText(find.byKey(const Key('library_search')), 'pec');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_row_pec_deck')));
    await tester.pumpAndSettle();

    expect(find.text('How to do it'), findsOneWidget);
    expect(find.text('Add to Legs'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide_add')));
    await tester.pumpAndSettle();
    expect(idsOf('day-3'), contains('pec_deck'));
    // Back on the picker, showing it as added.
    expect(find.text('Exercise library'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
  });

  testWidgets('"Write your own" from the library keeps the typed text', (
    tester,
  ) async {
    await pumpApp(tester);
    await openLibraryFromDay(tester);
    await tester.enterText(
      find.byKey(const Key('library_search')),
      'Bulgarian split squat',
    );
    await tester.pumpAndSettle();
    expect(find.text('No exercise with that name'), findsOneWidget);
    await tester.tap(find.byKey(const Key('library_write_query')));
    await tester.pumpAndSettle();
    // The name sheet opens with the text in both languages.
    expect(
      find.widgetWithText(TextField, 'Bulgarian split squat'),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('plan_name_save')));
    await tester.pumpAndSettle();

    final added = savedPlan().dayById('day-3')!.exercises.last;
    expect(added.name.en, 'Bulgarian split squat');
    expect(added.id, startsWith('ex-'), reason: 'a written exercise');
    // Back on the day.
    expect(find.byKey(const Key('plan_add_exercise')), findsOneWidget);
  });

  testWidgets('"Write your own" in the sheet still works as before', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('plan_add_exercise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('plan_name_en')),
      'Farmer walk',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('plan_name_save')));
    await tester.pumpAndSettle();
    expect(savedPlan().dayById('day-3')!.exercises.last.name.en, 'Farmer walk');
  });

  testWidgets('a day in progress refuses with a reason, nothing saved', (
    tester,
  ) async {
    await LocalWorkoutRepository(prefs).saveDraft(
      WorkoutDraft(dayId: 'day-3', startedAt: DateTime(2026, 11, 2, 17)),
    );
    // The day is locked, so the editor offers no "Add" there; a crafted link
    // to the picker is refused too.
    await pumpApp(tester, at: AppRoutes.libraryFor('day-3'));
    await tester.enterText(find.byKey(const Key('library_search')), 'pec');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_add_pec_deck')));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.planLocked), findsOneWidget);
    expect(idsOf('day-3'), isNot(contains('pec_deck')));
    AppToast.dismiss();
    await tester.pump();
  });

  testWidgets('a gym that keeps the exercises to the captain: no picker', (
    tester,
  ) async {
    await pumpApp(
      tester,
      at: AppRoutes.libraryFor('day-3'),
      overrides: [
        planPermissionsProvider.overrideWithValue(
          const PlanPermissions(editStructure: false, buildOwnPlan: false),
        ),
      ],
    );
    expect(find.text(l10nEn.planManagedTitle), findsOneWidget);
    expect(find.byKey(const Key('library_search')), findsNothing);
    expect(find.byKey(const Key('library_add_pec_deck')), findsNothing);
  });

  testWidgets('the same member may still read an exercise', (tester) async {
    await pumpApp(
      tester,
      at: AppRoutes.libraryExercise('pec_deck', dayId: 'day-3'),
      overrides: [
        planPermissionsProvider.overrideWithValue(
          const PlanPermissions(editStructure: false, buildOwnPlan: false),
        ),
      ],
    );
    expect(find.text('Pec Deck'), findsOneWidget);
    expect(find.text('How to do it'), findsOneWidget);
    expect(find.byKey(const Key('guide_add')), findsNothing);
  });

  group('links are untrusted', () {
    testWidgets('no day, an unknown day, a crafted day', (tester) async {
      for (final path in [
        AppRoutes.library,
        '${AppRoutes.library}?day=',
        AppRoutes.libraryFor('nope'),
        AppRoutes.libraryFor("'; DROP TABLE plans; --"),
        AppRoutes.libraryFor('../../etc/passwd'),
        '${AppRoutes.library}?day=%00',
        '${AppRoutes.library}?day=day-3&day=day-1',
      ]) {
        await pumpApp(tester, at: path);
        expect(tester.takeException(), isNull, reason: path);
        final days = savedPlan().days.length;
        expect(days, 5, reason: path);
        // Either the picker (a real day) or "isn't in your plan".
        final ok =
            find.text(l10nEn.planDayNotFound).evaluate().isNotEmpty ||
            find.text('Exercise library').evaluate().isNotEmpty;
        expect(ok, isTrue, reason: path);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('an unknown or crafted exercise id', (tester) async {
      for (final id in [
        'does_not_exist',
        '../x',
        "'; DROP TABLE plans; --",
        '<script>alert(1)</script>',
        '%00',
        'FLAT_DB_PRESS',
        'a' * 500,
      ]) {
        await pumpApp(tester, at: AppRoutes.libraryExercise(id));
        expect(tester.takeException(), isNull, reason: id);
        expect(
          find.text("This exercise isn't in the library."),
          findsOneWidget,
          reason: id,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a known exercise with a crafted day only reads', (
      tester,
    ) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('pec_deck', dayId: 'nope'),
      );
      expect(find.text('Pec Deck'), findsOneWidget);
      expect(find.byKey(const Key('guide_add')), findsNothing);
    });
  });

  testWidgets(
    'the plan exercise screen links to the steps, only for library ones',
    (tester) async {
      await pumpApp(tester, at: AppRoutes.planExercise('day-1', 'pec_deck'));
      await tester.tap(find.byKey(const Key('plan_exercise_guide')));
      await tester.pumpAndSettle();
      expect(find.text('How to do it'), findsOneWidget);
      expect(find.byKey(const Key('guide_add')), findsNothing);
      appRouter.go(AppRoutes.home);

      // A written exercise has no steps.
      final plan = savedPlan();
      final custom = WorkoutPlan(
        days: [
          WorkoutDay(
            id: 'day-1',
            name: plan.days.first.name,
            exercises: const [
              Exercise(
                id: 'ex-custom',
                name: LocalizedName(ar: 'مشي', en: 'Walk'),
              ),
            ],
          ),
        ],
      );
      await prefs.setString(
        LocalWorkoutRepository.planKey,
        jsonEncode(custom.toJson()),
      );
      await pumpApp(tester, at: AppRoutes.planExercise('day-1', 'ex-custom'));
      expect(find.byKey(const Key('plan_exercise_guide')), findsNothing);
    },
  );

  group("the gym's pictures (real router and providers)", () {
    final media = GymMedia.fromPictures(const [
      GymExercisePicture(
        exerciseId: 'flat_db_press',
        publicId: 'exercises/ek-0055-tension',
        position: 1,
      ),
      GymExercisePicture(
        exerciseId: 'flat_db_press',
        publicId: 'exercises/ek-0055-relaxation',
        position: 2,
      ),
    ]);
    // Bundled drawings stand in for Cloudinary; a refused id is null.
    ImageProvider? fakeImage(String publicId, _) => publicId.endsWith('tension')
        ? const AssetImage('assets/exercises/flat_db_press.webp')
        : const AssetImage('assets/exercises/incline_machine_press.webp');

    List<Override> withMedia(GymMedia m) => [
      activeGymMediaProvider.overrideWith((ref) async => m),
      gymPictureImageProvider.overrideWithValue(fakeImage),
      deviceOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ];

    testWidgets('the exercise screen shows the two frames and moves', (
      tester,
    ) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('flat_db_press'),
        overrides: withMedia(media),
      );
      expect(find.text('\u20662 / 2\u2069'), findsOneWidget);
      expect(find.text('Everkinetic · CC BY-SA 4.0'), findsOneWidget);
    });

    testWidgets('no gym pictures: the bundled drawing, no carousel', (
      tester,
    ) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('flat_db_press'),
        overrides: withMedia(GymMedia.empty),
      );
      expect(find.byKey(const Key('gym_pictures_pages')), findsNothing);
      expect(find.text('Everkinetic · CC BY-SA 4.0'), findsOneWidget);
    });

    testWidgets('without a cloud name no network picture is ever built', (
      tester,
    ) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('flat_db_press'),
        overrides: [
          activeGymMediaProvider.overrideWith((ref) async => media),
          deviceOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
      );
      expect(find.byKey(const Key('gym_pictures_pages')), findsNothing);
      expect(find.byKey(const Key('gym_picture_0')), findsNothing);
    });

    testWidgets("the library list shows the gym's cover", (tester) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryFor('day-3'),
        overrides: withMedia(media),
      );
      expect(find.text('Pictures from your gym'), findsOneWidget);
    });
  });

  group('the how-to video (real router, fake YouTube)', () {
    final opened = <Uri>[];

    List<Override> fakeYouTube(VideoInfo info) => [
      videoInfoRepositoryProvider.overrideWithValue(_FakeInfo(info)),
      videoSurfaceProvider.overrideWithValue(
        (v, {required onProblem}) =>
            ColoredBox(key: Key('fake_player_${v.id}'), color: Colors.black),
      ),
      externalOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
      deviceOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ];

    setUp(opened.clear);

    testWidgets("the library's video: card, play, the player sheet", (
      tester,
    ) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('flat_db_press'),
        overrides: fakeYouTube(
          const VideoInfo(
            availability: VideoAvailability.available,
            title: 'Bench',
            channel: 'Coach',
          ),
        ),
      );
      expect(find.text('Watch how'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);
      // Never plays by itself.
      expect(find.byKey(const Key('fake_player_mCEIUZySRPY')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('video_play')));
      await tester.tap(find.byKey(const Key('video_play')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake_player_mCEIUZySRPY')), findsOneWidget);
      await tester.tap(find.byKey(const Key('video_open_in_youtube')).last);
      expect(opened, [
        Uri.parse('https://www.youtube.com/watch?v=mCEIUZySRPY'),
      ]);
      await tester.tap(find.byKey(const Key('video_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake_player_mCEIUZySRPY')), findsNothing);
    });

    testWidgets("the gym's own video comes before the library's", (
      tester,
    ) async {
      final gymMedia = GymMedia.fromPictures(
        const [],
        videos: [
          GymExerciseVideo.tryParse({
            'exercise_id': 'flat_db_press',
            'video_id': 'amgXq2ThD0c',
            'start_seconds': 15,
          })!,
        ],
      );
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('flat_db_press'),
        overrides: [
          ...fakeYouTube(
            const VideoInfo(
              availability: VideoAvailability.available,
              title: 'Our bench',
              channel: 'Gym',
            ),
          ),
          activeGymMediaProvider.overrideWith((ref) async => gymMedia),
        ],
      );
      await tester.ensureVisible(find.byKey(const Key('video_play')));
      await tester.tap(find.byKey(const Key('video_play')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake_player_amgXq2ThD0c')), findsOneWidget);
      expect(find.byKey(const Key('fake_player_mCEIUZySRPY')), findsNothing);
      await tester.tap(find.byKey(const Key('video_open_in_youtube')).last);
      expect(opened.single.queryParameters['v'], 'amgXq2ThD0c');
    });

    testWidgets('embedding off: Open in YouTube from the card', (tester) async {
      await pumpApp(
        tester,
        at: AppRoutes.libraryExercise('flat_db_press'),
        overrides: fakeYouTube(
          const VideoInfo(availability: VideoAvailability.embedDisabled),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('video_open_in_youtube')),
      );
      await tester.tap(find.byKey(const Key('video_open_in_youtube')));
      expect(opened.single.host, 'www.youtube.com');
      expect(opened.single.queryParameters['v'], 'mCEIUZySRPY');
    });
  });
}

class _FakeInfo implements VideoInfoRepository {
  const new(this.info);

  final VideoInfo info;

  @override
  Future<Result<VideoInfo>> fetch(YouTubeVideoRef video) async => Success(info);
}
