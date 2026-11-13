import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_check_page.dart';
import 'package:gym_tracker/features/move/presentation/move_check_view.dart';
import 'package:gym_tracker/features/move/presentation/widgets/pose_body_painter.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../helpers/fake_pose_source.dart';
import '../helpers/synthetic_pose.dart';

/// A frame of the synthetic member, [into] the set.
PoseFrame frameOf(
  SynthView view, {
  Duration into = const Duration(seconds: 2),
}) {
  final frames = SynthSet.reps(1, view: view).frames();
  return frames.lastWhere((f) => f.at <= into);
}

MoveCheckView view(
  MoveCheckState state, {
  VoidCallback? onStart,
  VoidCallback? onStop,
  VoidCallback? onReset,
  VoidCallback? onOpenSettings,
}) => MoveCheckView(
  state: state,
  onStart: onStart ?? () {},
  onStop: onStop ?? () {},
  onReset: onReset ?? () {},
  onOpenSettings: onOpenSettings,
);

final running = MoveCheckState(
  status: const PoseSourceStatus(PoseSourceState.running, fps: 14.5),
  rep: const RepState(
    phase: RepPhase.bottom,
    depth: 0.9,
    reps: 7,
    view: PoseView.side,
  ),
  frame: frameOf(SynthView.sideLeft),
  lastEvent: const RepCounted(
    total: 7,
    took: Duration(milliseconds: 1500),
    depth: 1,
  ),
  frames: 240,
);

final front = MoveCheckState(
  status: const PoseSourceStatus(PoseSourceState.running, fps: 9.8),
  rep: const RepState(
    phase: RepPhase.goingDown,
    depth: 0.4,
    reps: 3,
    view: PoseView.front,
  ),
  frame: frameOf(SynthView.front),
  lastEvent: const FormHint(FormHintKind.moveBack),
  frames: 90,
);

const denied = MoveCheckState(
  status: PoseSourceStatus(PoseSourceState.failed, problem: PoseProblem.denied),
);

const modelFailed = MoveCheckState(
  status: PoseSourceStatus(
    PoseSourceState.failed,
    problem: PoseProblem.modelFailed,
  ),
);

void main() {
  group(MoveCheckView, () {
    testWidgets('idle: only Start; nothing to reset yet', (tester) async {
      var started = 0;
      await tester.pumpApp(
        view(const MoveCheckState(), onStart: () => started++),
      );
      expect(find.text(l10nEn.moveCheckIntro), findsOneWidget);
      expect(find.byKey(const Key('move_check_stop')), findsNothing);
      await tester.tap(find.byKey(const Key('move_check_start')));
      expect(started, 1);
      final reset = tester.widget<Widget>(
        find.byKey(const Key('move_check_reset')),
      );
      expect((reset as dynamic).onPressed, isNull);
    });

    testWidgets('running: the count, speed, view, position and last event', (
      tester,
    ) async {
      var stopped = 0;
      var reset = 0;
      await tester.pumpApp(
        view(running, onStop: () => stopped++, onReset: () => reset++),
      );
      expect(find.text('7'), findsOneWidget);
      expect(find.text(l10nEn.moveCheckFps('14.5')), findsOneWidget);
      expect(find.text(l10nEn.moveCheckViewSide), findsOneWidget);
      expect(find.text(l10nEn.moveCheckPhaseBottom), findsOneWidget);
      expect(find.text(l10nEn.moveCheckEventCounted), findsOneWidget);
      expect(find.bySemanticsLabel(l10nEn.moveCheckBodyLabel), findsOneWidget);
      for (final key in ['move_check_stop', 'move_check_reset']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
      }
      expect([stopped, reset], [1, 1]);
    });

    testWidgets('starting: the loading logo instead of the buttons', (
      tester,
    ) async {
      await tester.pumpApp(
        view(
          const MoveCheckState(
            status: PoseSourceStatus(PoseSourceState.starting),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byKey(const Key('move_check_start')), findsNothing);
      expect(find.byKey(const Key('move_check_stop')), findsNothing);
    });

    testWidgets('a hint is shown in words', (tester) async {
      await tester.pumpApp(view(front));
      expect(find.text(l10nEn.moveHintMoveBack), findsOneWidget);
      expect(find.text(l10nEn.moveCheckViewFront), findsOneWidget);
    });

    testWidgets('refused: says why and offers Settings', (tester) async {
      var settings = 0;
      await tester.pumpApp(view(denied, onOpenSettings: () => settings++));
      expect(find.text(l10nEn.moveCheckDenied), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('move_check_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move_check_settings')));
      expect(settings, 1);
      // Never a dead end: Start is there to try again.
      expect(find.byKey(const Key('move_check_start')), findsOneWidget);
    });

    testWidgets('the model failing has no Settings button', (tester) async {
      await tester.pumpApp(view(modelFailed, onOpenSettings: () {}));
      expect(find.text(l10nEn.moveCheckModelFailed), findsOneWidget);
      expect(find.byKey(const Key('move_check_settings')), findsNothing);
    });

    testWidgets('every event has words', (tester) async {
      await tester.pumpApp(const SizedBox());
      final l10n = l10nEn;
      for (final e in <RepEvent>[
        const RepCounted(total: 1, took: Duration.zero, depth: 1),
        const HalfRep(depth: 0.5),
        const TooFast(took: Duration.zero),
        const BodyLost(),
        const BodyFound(),
        for (final k in FormHintKind.values) FormHint(k),
      ]) {
        expect(eventLabel(l10n, e), isNotEmpty);
      }
      for (final p in RepPhase.values) {
        expect(phaseLabel(l10n, p), isNotEmpty);
      }
    });
  });

  group(MoveCheckPage, () {
    testWidgets('opening it never starts the camera; a tap does', (
      tester,
    ) async {
      final source = FakePoseSource();
      var made = 0;
      await tester.pumpApp(
        ProviderScope(
          overrides: [
            poseSourceFactoryProvider.overrideWithValue(() {
              made++;
              return source;
            }),
          ],
          child: const MoveCheckPage(),
        ),
      );
      expect(made, 0);
      await tester.tap(find.byKey(const Key('move_check_start')));
      await tester.pump();
      expect(source.starts, 1);
      SynthSet.reps(2).frames().forEach(source.emit);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('leaving the app releases the camera', (tester) async {
      final source = FakePoseSource();
      await tester.pumpApp(
        ProviderScope(
          overrides: [
            poseSourceFactoryProvider.overrideWithValue(() => source),
          ],
          child: const MoveCheckPage(),
        ),
      );
      await tester.tap(find.byKey(const Key('move_check_start')));
      await tester.pump();
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      // The release awaits the subscriptions, then stops the source.
      await tester.pumpAndSettle();
      expect(source.stops, 1);
      expect(find.byKey(const Key('move_check_start')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  group(PoseBodyPainter, () {
    void paint(PoseFrame? frame, Size size) {
      final recorder = ui.PictureRecorder();
      PoseBodyPainter(
        frame: frame,
        outline: Colors.black,
        fill: Colors.white,
        farFill: Colors.grey,
        dot: Colors.green,
      ).paint(Canvas(recorder), size);
      recorder.endRecording().dispose();
    }

    test('draws every view and an empty or missing frame', () {
      for (final v in SynthView.values) {
        paint(frameOf(v), const Size(300, 400));
      }
      paint(null, const Size(300, 400));
      paint(const PoseFrame(at: Duration.zero, joints: {}), Size.zero);
    });

    test('garbage joints and a stacked body never throw', () {
      paint(
        PoseFrame(
          at: Duration.zero,
          aspect: double.nan,
          joints: {
            for (final j in PoseJoint.values)
              j: const Landmark(x: 0.5, y: 0.5, likelihood: 1),
          },
        ),
        const Size(300, 400),
      );
      paint(
        PoseFrame(
          at: Duration.zero,
          joints: {
            for (final j in PoseJoint.values)
              j: const Landmark(
                x: double.nan,
                y: double.infinity,
                likelihood: 1,
              ),
          },
        ),
        const Size(300, 400),
      );
    });

    test('repaints only when something changed', () {
      final f = frameOf(SynthView.sideLeft);
      PoseBodyPainter p(PoseFrame frame) => PoseBodyPainter(
        frame: frame,
        outline: Colors.black,
        fill: Colors.white,
        farFill: Colors.grey,
        dot: Colors.green,
      );
      expect(p(f).shouldRepaint(p(f)), isFalse);
      expect(p(f).shouldRepaint(p(frameOf(SynthView.front))), isTrue);
    });
  });

  screensUiTests({
    'move_check_idle': () => view(const MoveCheckState()),
    'move_check_running_side': () => view(running),
    'move_check_running_front': () => view(front),
    'move_check_denied': () => view(denied, onOpenSettings: () {}),
    'move_check_model_failed': () => view(modelFailed),
  });
}
