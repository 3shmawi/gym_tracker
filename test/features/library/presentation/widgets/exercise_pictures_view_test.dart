import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/media_cache.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_pictures_view.dart';

import '../../../../helpers/pump_app.dart';
import '../../helpers/no_picture.dart';

LibraryExercise exercise(String id) =>
    ExerciseCatalog.all.firstWhere((e) => e.id == id);

ImageProvider asset(String id) => AssetImage('assets/exercises/$id.webp');

/// A picture that never loads (404, offline with no cached copy).
ImageProvider broken(String name) => CachedMediaImage(
  Uri.parse('https://res.cloudinary.com/azm/$name.png'),
  fetch: (_) => Future.error(StateError('404')),
);

final List<ImageProvider> pair = [
  asset('flat_db_press'),
  asset('incline_machine_press'),
];
final List<ImageProvider> four = [
  asset('flat_db_press'),
  asset('incline_machine_press'),
  asset('pec_deck'),
  asset('leg_press'),
];

Widget host(Widget child) => Scaffold(body: ListView(children: [child]));

Future<void> pumpPictures(
  WidgetTester tester, {
  List<ImageProvider> pictures = const [],
  bool movePair = false,
  bool offline = false,
  LibraryExercise? of,
  VoidCallback? onOpenCredits,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpApp(
    host(
      ExercisePicturesView(
        exercise: of ?? exercise('flat_db_press'),
        gymPictures: pictures,
        movePair: movePair,
        offline: offline,
        onOpenCredits: onOpenCredits,
      ),
    ),
    locale: locale,
  );
  await tester.pump();
}

/// The counter, as shown: an LTR isolate around "n / total".
Finder badge(String text) => find.text('\u2066$text\u2069');

const Duration step = ExercisePicturesView.stepEvery;
const Duration slide = ExercisePicturesView.transition;

/// One later auto-advance step: steps come every 3 s + the slide; the slide
/// needs a frame to start (a ticker counts from its first frame).
Future<void> nextStep(WidgetTester tester) async {
  await tester.pump(step);
  await finishSlide(tester);
}

Future<void> finishSlide(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(slide);
  await tester.pump();
}

void main() {
  group('source order', () {
    testWidgets('no gym pictures: the bundled drawing and the credit', (
      tester,
    ) async {
      await pumpPictures(tester);
      expect(find.byKey(const Key('gym_picture_0')), findsNothing);
      expect(find.text('Everkinetic · CC BY-SA 4.0'), findsOneWidget);
      expect(find.text('Illustration coming soon'), findsNothing);
    });

    testWidgets('no gym and no bundled picture: placeholder, no credit', (
      tester,
    ) async {
      await pumpPictures(tester, of: noPicture);
      expect(find.text('Illustration coming soon'), findsOneWidget);
      expect(find.text('Everkinetic · CC BY-SA 4.0'), findsNothing);
    });

    testWidgets('one gym picture: shown alone, no dots or button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPictures(tester, pictures: [asset('pec_deck')]);
      expect(find.byKey(const Key('gym_picture_0')), findsOneWidget);
      expect(find.byKey(const Key('gym_pictures_pages')), findsNothing);
      expect(find.byKey(const Key('gym_pictures_toggle')), findsNothing);
      expect(
        find.bySemanticsLabel('Illustration of Flat Dumbbell Press'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a picture that fails is dropped; all fail: bundled', (
      tester,
    ) async {
      await pumpPictures(
        tester,
        pictures: [broken('a'), asset('pec_deck'), asset('leg_press')],
      );
      await tester.pump();
      await tester.pump();
      expect(badge('1 / 2'), findsOneWidget);

      await pumpPictures(tester, pictures: [broken('a'), broken('b')]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('gym_pictures_pages')), findsNothing);
      expect(find.text('Everkinetic · CC BY-SA 4.0'), findsOneWidget);
      expect(find.byKey(const Key('gym_pictures_hint')), findsNothing);
    });

    testWidgets('offline and nothing cached: bundled + "when back online"', (
      tester,
    ) async {
      await pumpPictures(
        tester,
        pictures: [broken('a'), broken('b')],
        offline: true,
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text("· Your gym's pictures show when you're back online"),
        findsOneWidget,
      );
    });

    testWidgets('the credit opens the licenses', (tester) async {
      final handle = tester.ensureSemantics();
      var opened = 0;
      await pumpPictures(tester, onOpenCredits: () => opened++);
      await tester.tap(find.byKey(const Key('gym_pictures_credit')));
      expect(opened, 1);
      expect(
        find.bySemanticsLabel(
          'Picture credits: Everkinetic, CC BY-SA 4.0. Opens the licenses.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('carousel', () {
    testWidgets('several unrelated pictures: swipe only, never moves', (
      tester,
    ) async {
      await pumpPictures(tester, pictures: four);
      expect(badge('1 / 4'), findsOneWidget);
      expect(find.byKey(const Key('gym_pictures_toggle')), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(badge('1 / 4'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('gym_pictures_pages')),
        const Offset(-250, 0),
      );
      await tester.pumpAndSettle();
      expect(badge('2 / 4'), findsOneWidget);
    });

    testWidgets('Arabic: the next picture comes from the left (mirrored)', (
      tester,
    ) async {
      await pumpPictures(tester, pictures: four, locale: const Locale('ar'));
      await tester.drag(
        find.byKey(const Key('gym_pictures_pages')),
        const Offset(250, 0),
      );
      await tester.pumpAndSettle();
      expect(badge('2 / 4'), findsOneWidget);
    });

    testWidgets('screen readers: "Picture n of total" and swipe actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPictures(tester, pictures: four);
      final label = find.bySemanticsLabel(
        'Picture 1 of 4: Flat Dumbbell Press',
      );
      expect(label, findsOneWidget);
      tester.semantics.increase(
        find.semantics.byLabel('Picture 1 of 4: Flat Dumbbell Press'),
      );
      await tester.pumpAndSettle();
      expect(badge('2 / 4'), findsOneWidget);
      handle.dispose();
    });
  });

  group('auto-advance (the two frames of one move)', () {
    testWidgets('moves every 3 s, at most 3 loops, then rests on the last', (
      tester,
    ) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      expect(badge('1 / 2'), findsOneWidget);
      await tester.pump(step - const Duration(milliseconds: 100));
      expect(badge('1 / 2'), findsOneWidget, reason: 'not before 3 s');
      await tester.pump(const Duration(milliseconds: 100));
      await finishSlide(tester);
      expect(badge('2 / 2'), findsOneWidget);
      await nextStep(tester); // loop 2 starts
      expect(badge('1 / 2'), findsOneWidget);
      await nextStep(tester);
      await nextStep(tester); // loop 3 starts
      await nextStep(tester);
      expect(badge('2 / 2'), findsOneWidget);
      // Three loops done: it rests on the last picture.
      await tester.pump(const Duration(seconds: 30));
      expect(badge('2 / 2'), findsOneWidget);
      expect(find.byTooltip('Play motion'), findsOneWidget);
    });

    testWidgets('play after resting starts again from the first picture', (
      tester,
    ) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      for (var i = 0; i < 6; i++) {
        await nextStep(tester);
      }
      await tester.tap(find.byKey(const Key('gym_pictures_toggle')));
      await tester.pump();
      expect(badge('1 / 2'), findsOneWidget);
      await nextStep(tester);
      expect(badge('2 / 2'), findsOneWidget);
    });

    testWidgets('a touch pauses it; it resumes after 6 s with no touch', (
      tester,
    ) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('gym_pictures_pages'))),
      );
      await gesture.up();
      await tester.pump(const Duration(seconds: 5));
      expect(badge('1 / 2'), findsOneWidget, reason: 'paused by the touch');
      // 6 s idle, then one step.
      await tester.pump(const Duration(seconds: 1));
      await nextStep(tester);
      expect(badge('2 / 2'), findsOneWidget);
    });

    testWidgets('the pause button stops it until play', (tester) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      expect(find.byTooltip('Pause motion'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gym_pictures_toggle')));
      await tester.pump(const Duration(seconds: 30));
      expect(badge('1 / 2'), findsOneWidget);
      expect(find.byTooltip('Play motion'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gym_pictures_toggle')));
      await tester.pump(const Duration(seconds: 6));
      await nextStep(tester);
      expect(badge('2 / 2'), findsOneWidget);
    });

    testWidgets('the button is 48×48 and labelled', (tester) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      final size = tester.getSize(find.byKey(const Key('gym_pictures_toggle')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.expectAccessible();
    });

    testWidgets('never with Reduce Motion: static, no button', (tester) async {
      await tester.pumpApp(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(
            ExercisePicturesView(
              exercise: exercise('flat_db_press'),
              gymPictures: pair,
              movePair: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(badge('1 / 2'), findsOneWidget);
      expect(find.byKey(const Key('gym_pictures_toggle')), findsNothing);
    });

    testWidgets('never with a screen reader on', (tester) async {
      await tester.pumpApp(
        MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: host(
            ExercisePicturesView(
              exercise: exercise('flat_db_press'),
              gymPictures: pair,
              movePair: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(badge('1 / 2'), findsOneWidget);
    });

    testWidgets('never while another screen is on top', (tester) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final pushed = navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      navigator.pop();
      await pushed;
      // Only the route transition (the progress line would settle for 3 s).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(badge('1 / 2'), findsOneWidget, reason: 'did not move under');
      await nextStep(tester);
      expect(badge('2 / 2'), findsOneWidget, reason: 'moves again on top');
    });

    testWidgets('never while the app is in the background', (tester) async {
      await pumpPictures(tester, pictures: pair, movePair: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(badge('1 / 2'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await nextStep(tester);
      expect(badge('2 / 2'), findsOneWidget);
    });

    testWidgets('unrelated pair (movePair false): never moves', (tester) async {
      await pumpPictures(tester, pictures: pair);
      await tester.pump(const Duration(seconds: 30));
      expect(badge('1 / 2'), findsOneWidget);
      expect(find.byKey(const Key('gym_pictures_toggle')), findsNothing);
    });
  });
}
