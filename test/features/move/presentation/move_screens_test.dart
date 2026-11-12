import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/domain/usecases/placement.dart';
import 'package:gym_tracker/features/move/presentation/camera_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/camera_round_view.dart';
import 'package:gym_tracker/features/move/presentation/game/stack_game.dart';
import 'package:gym_tracker/features/move/presentation/game/stack_game_view.dart';
import 'package:gym_tracker/features/move/presentation/manual_counter_view.dart';
import 'package:gym_tracker/features/move/presentation/manual_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_hub_view.dart';
import 'package:gym_tracker/features/move/presentation/move_pages.dart';
import 'package:gym_tracker/features/move/presentation/move_setup_view.dart';
import 'package:gym_tracker/features/move/presentation/round_outcome.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../helpers/synthetic_pose.dart';

final now = DateTime(2026, 11, 12, 18, 0, 20);
final t0 = DateTime(2026, 11, 12, 18);
final LibraryExercise pushUps = catalogEntryOf(MoveExerciseId.pushUps);

PoseFrame frameAt(int ms, {SynthView view = SynthView.sideLeft}) =>
    SynthSet.reps(
      1,
      view: view,
    ).frames().lastWhere((f) => f.at <= Duration(milliseconds: ms));

RoundState round(
  RoundPhase phase, {
  RoundMode mode = RoundMode.camera,
  int reps = 0,
  PauseReason? pause,
}) => RoundState(
  exercise: MoveExerciseId.pushUps,
  kind: RoundKind.s60,
  mode: mode,
  phase: phase,
  reps: reps,
  steady: reps ~/ 2,
  halfReps: phase == RoundPhase.finished ? 2 : 0,
  banked: const Duration(seconds: 12),
  runningSince: phase == RoundPhase.running ? t0 : null,
  countdownEnds: phase == RoundPhase.countdown
      ? now.add(const Duration(milliseconds: 1500))
      : null,
  startedAt: t0,
  endedAt: phase == RoundPhase.finished
      ? t0.add(const Duration(minutes: 1))
      : null,
  pauseReason: pause,
);

RoundOutcome outcome({
  int reps = 26,
  RoundMode mode = RoundMode.camera,
  SaveState save = SaveState.idle,
  bool best = true,
}) => RoundOutcome(
  result: RoundResult(
    exercise: MoveExerciseId.pushUps,
    kind: RoundKind.s60,
    mode: mode,
    reps: reps,
    steady: 6,
    halfReps: 3,
    duration: const Duration(minutes: 1),
    startedAt: t0,
    finishedAt: t0.add(const Duration(minutes: 1)),
  ),
  newBest: best,
  save: save,
);

/// A tower of [floors] blocks (every other one steady, every third a bit
/// shallow), and maybe a rep that didn't count [ago].
StackState tower(
  int floors, {
  GameMomentKind? last,
  Duration ago = const Duration(seconds: 1),
}) {
  const rules = StackRules();
  var s = rules.start();
  for (var i = 0; i < floors; i++) {
    s = rules.onEvent(
      s,
      RepCounted(
        total: i + 1,
        took: Duration(milliseconds: i.isEven ? 1500 : 1000),
        depth: i % 3 == 0 ? 0.86 : 1,
      ),
      t0,
    );
  }
  final at = now.subtract(ago);
  return switch (last) {
    GameMomentKind.halfRep => rules.onEvent(s, const HalfRep(depth: 0.5), at),
    GameMomentKind.tooFast => rules.onEvent(
      s,
      const TooFast(took: Duration(milliseconds: 400)),
      at,
    ),
    GameMomentKind.rep || null => s,
  };
}

CameraRoundView camera(CameraRoundState state, {VoidCallback? onToggleSound}) =>
    CameraRoundView(
      state: state,
      onToggleSound: onToggleSound ?? () {},
      now: now,
      exerciseName: 'Push-ups',
      onClose: () {},
      onPause: () {},
      onResume: () {},
      onEnd: () {},
      onManual: () {},
      onSave: () {},
      onPlayAgain: () {},
      onDone: () {},
      onOpenSettings: () {},
      onOpenProgress: () {},
    );

CameraRoundState cam({
  CameraStage stage = CameraStage.live,
  RoundState? r,
  PlacementChecks checks = const PlacementChecks(),
  FormHintKind? hint,
  CameraTrouble? trouble,
  RoundOutcome? done,
  PoseFrame? frame,
  GameState? game,
  bool soundOn = true,
}) => CameraRoundState(
  stage: stage,
  round: r ?? round(RoundPhase.ready),
  checks: checks,
  hint: hint,
  trouble: trouble,
  outcome: done,
  frame: frame,
  game: game ?? tower(r?.reps ?? 0),
  soundOn: soundOn,
  rep: const RepState(phase: RepPhase.goingDown, depth: 0.6, reps: 7),
  cameraOn: true,
);

ManualCounterView manual(
  ManualRoundState state, {
  VoidCallback? onTap,
  VoidCallback? onUndo,
  VoidCallback? onStart,
}) => ManualCounterView(
  state: state,
  now: now,
  exerciseName: 'Push-ups',
  onStart: onStart ?? () {},
  onTap: onTap ?? () {},
  onUndo: onUndo ?? () {},
  onPause: () {},
  onResume: () {},
  onEnd: () {},
  onSave: () {},
  onPlayAgain: () {},
  onDone: () {},
  onOpenProgress: () {},
);

MoveHubView hub({
  int? best,
  bool manualFirst = false,
  ValueChanged<RoundKind>? onKind,
}) => MoveHubView(
  exercise: pushUps,
  kind: RoundKind.s60,
  best: best,
  manualFirst: manualFirst,
  onKind: onKind ?? (_) {},
  onCamera: () {},
  onManual: () {},
);

void main() {
  group(MoveHubView, () {
    testWidgets('round lengths, the best and the two ways to play', (
      tester,
    ) async {
      final picked = <RoundKind>[];
      await tester.pumpApp(hub(best: 24, onKind: picked.add));
      expect(find.text(l10nEn.moveBest(24, '60 s')), findsOneWidget);
      await tester.tap(find.byKey(const Key('move_round_r10')));
      expect(picked, [RoundKind.r10]);
      expect(find.byKey(const Key('move_hub_camera')), findsOneWidget);
      expect(find.byKey(const Key('move_hub_manual')), findsOneWidget);
    });

    testWidgets('with a screen reader, counting by hand comes first', (
      tester,
    ) async {
      await tester.pumpApp(hub(manualFirst: true));
      final manualY = tester.getTopLeft(
        find.byKey(const Key('move_hub_manual')),
      );
      final cameraY = tester.getTopLeft(
        find.byKey(const Key('move_hub_camera')),
      );
      expect(manualY.dy, lessThan(cameraY.dy));
    });
  });

  group(MoveSetupView, () {
    testWidgets('the why screen promises nothing is recorded', (tester) async {
      var next = 0;
      var manualTaps = 0;
      await tester.pumpApp(
        MoveSetupView(
          step: MoveSetupStep.why,
          exercise: pushUps,
          onNext: () => next++,
          onManual: () => manualTaps++,
        ),
      );
      expect(find.text(l10nEn.moveWhyNoRecording), findsOneWidget);
      await tester.tap(find.byKey(const Key('move_setup_next')));
      await tester.tap(find.byKey(const Key('move_setup_manual')));
      expect([next, manualTaps], [1, 1]);
    });
  });

  group(CameraRoundView, () {
    testWidgets('placement: checks, the hint, and how to place the phone', (
      tester,
    ) async {
      await tester.pumpApp(
        camera(
          cam(
            stage: CameraStage.placement,
            checks: const PlacementChecks(bodyFound: true, viewFound: true),
            hint: FormHintKind.moveBack,
            frame: frameAt(500),
          ),
        ),
      );
      expect(find.text(l10nEn.moveHintMoveBack), findsOneWidget);
      expect(find.text(l10nEn.movePlacementView), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('running: time and reps, a pause button', (tester) async {
      await tester.pumpApp(camera(cam(r: round(RoundPhase.running, reps: 7))));
      expect(find.byKey(const Key('move_reps')), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      // 12 s before a pause + 20 s since: 28 s left of 60.
      expect(find.text('0:28'), findsOneWidget);
      expect(find.byKey(const Key('move_round_pause')), findsOneWidget);
    });

    testWidgets('the reps build the tower; a screen reader hears a label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpApp(
        camera(cam(r: round(RoundPhase.running, reps: 7), game: tower(7))),
      );
      expect(find.byType(StackGameView), findsOneWidget);
      expect(find.bySemanticsLabel('Stack: 7 floors'), findsOneWidget);
      expect(find.text(l10nEn.moveGameName), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a block lands, then the engine rests (Reduce Motion too)', (
      tester,
    ) async {
      for (final reduce in [false, true]) {
        Widget at(int floors) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: camera(
            cam(
              r: round(RoundPhase.running, reps: floors),
              game: tower(floors),
            ),
          ),
        );
        await tester.pumpApp(at(3));
        final game = tester
            .widget<GameWidget<StackGame>>(find.byType(GameWidget<StackGame>))
            .game!;
        expect(game.paused, isTrue, reason: 'idle: nothing to draw');
        await tester.pumpApp(at(4));
        expect(game.tower.state.floors, hasLength(4));
        expect(game.paused, isFalse, reason: 'the new block falls');
        await tester.pumpAndSettle();
        expect(game.paused, isTrue);
        // A long tower scrolls down instead of growing off the screen.
        await tester.pumpApp(at(40));
        await tester.pumpAndSettle();
        expect(game.paused, isTrue);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a half rep or a rushed rep says why, for a moment', (
      tester,
    ) async {
      await tester.pumpApp(
        camera(
          cam(
            r: round(RoundPhase.running, reps: 4),
            game: tower(4, last: GameMomentKind.halfRep),
          ),
        ),
      );
      expect(find.text(l10nEn.moveHalfRepNotice), findsOneWidget);

      await tester.pumpApp(
        camera(
          cam(
            r: round(RoundPhase.running, reps: 4),
            hint: FormHintKind.straightBody,
            game: tower(4, last: GameMomentKind.tooFast),
          ),
        ),
      );
      expect(find.text(l10nEn.moveTooFastNotice), findsOneWidget);
      expect(
        find.text(l10nEn.moveHintStraightBody),
        findsNothing,
        reason: 'one message at a time',
      );

      // Gone after a few seconds: the form hint shows again.
      await tester.pumpApp(
        camera(
          cam(
            r: round(RoundPhase.running, reps: 4),
            hint: FormHintKind.straightBody,
            game: tower(
              4,
              last: GameMomentKind.tooFast,
              ago: const Duration(seconds: 5),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('move_game_notice')), findsNothing);
      expect(find.text(l10nEn.moveHintStraightBody), findsOneWidget);
    });

    testWidgets('the sound button mutes and unmutes', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        camera(
          cam(r: round(RoundPhase.running, reps: 2)),
          onToggleSound: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byTooltip(l10nEn.moveSoundMute), findsOneWidget);
      await tester.tap(find.byKey(const Key('move_round_sound')));
      expect(taps, 1);

      await tester.pumpApp(
        camera(cam(r: round(RoundPhase.running, reps: 2), soundOn: false)),
      );
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(find.byTooltip(l10nEn.moveSoundUnmute), findsOneWidget);
    });

    testWidgets('body lost: come back, the reps are kept', (tester) async {
      await tester.pumpApp(
        camera(
          cam(
            r: round(RoundPhase.paused, reps: 5, pause: PauseReason.bodyLost),
          ),
        ),
      );
      expect(find.text(l10nEn.moveComeBack), findsOneWidget);
      expect(find.byKey(const Key('move_resume')), findsNothing);
      expect(find.byKey(const Key('move_switch_manual')), findsOneWidget);
    });

    testWidgets('refused: Settings or count by hand, never a dead end', (
      tester,
    ) async {
      await tester.pumpApp(
        camera(cam(stage: CameraStage.failed, trouble: CameraTrouble.denied)),
      );
      expect(find.text(l10nEn.moveDeniedTitle), findsOneWidget);
      expect(find.byKey(const Key('move_trouble_settings')), findsOneWidget);
      expect(find.byKey(const Key('move_trouble_manual')), findsOneWidget);
    });

    testWidgets('results: save is offered, never automatic', (tester) async {
      await tester.pumpApp(
        camera(cam(r: round(RoundPhase.finished, reps: 26), done: outcome())),
      );
      expect(find.byKey(const Key('move_results_save')), findsOneWidget);
      expect(find.text(l10nEn.moveNewBest('60 s')), findsOneWidget);
      expect(find.text(l10nEn.moveSaveWhat('Push-ups', 26)), findsOneWidget);
    });

    testWidgets('results with no reps: nothing to save', (tester) async {
      await tester.pumpApp(
        camera(
          cam(
            r: round(RoundPhase.finished),
            done: outcome(reps: 0, best: false),
          ),
        ),
      );
      expect(find.byKey(const Key('move_results_save')), findsNothing);
      expect(find.text(l10nEn.moveDone), findsOneWidget);
    });

    testWidgets('saved: says so and leads to progress', (tester) async {
      await tester.pumpApp(
        camera(
          cam(
            r: round(RoundPhase.finished, reps: 26),
            done: outcome(save: SaveState.saved),
          ),
        ),
      );
      expect(find.byKey(const Key('move_results_saved')), findsOneWidget);
      expect(find.byKey(const Key('move_results_progress')), findsOneWidget);
      expect(find.byKey(const Key('move_results_save')), findsNothing);
    });
  });

  group(ManualCounterView, () {
    testWidgets('one big target and −1; −1 is off at zero', (tester) async {
      var taps = 0;
      var undos = 0;
      await tester.pumpApp(
        manual(
          ManualRoundState(
            round: round(RoundPhase.running, mode: RoundMode.manual, reps: 3),
          ),
          onTap: () => taps++,
          onUndo: () => undos++,
        ),
      );
      await tester.tap(find.byKey(const Key('move_manual_tap')));
      await tester.tap(find.byKey(const Key('move_manual_undo')));
      expect([taps, undos], [1, 1]);
      expect(
        find.bySemanticsLabel(l10nEn.moveTapLabel(3)),
        findsOneWidget,
        reason: 'a screen reader hears the count on the button',
      );

      await tester.pumpApp(
        manual(
          ManualRoundState(
            round: round(RoundPhase.running, mode: RoundMode.manual),
          ),
          onUndo: () => undos++,
        ),
      );
      await tester.tap(find.byKey(const Key('move_manual_undo')));
      expect(undos, 1);
    });

    testWidgets('ready: Start', (tester) async {
      var started = 0;
      await tester.pumpApp(
        manual(
          ManualRoundState(
            round: round(RoundPhase.ready, mode: RoundMode.manual),
          ),
          onStart: () => started++,
        ),
      );
      await tester.tap(find.byKey(const Key('move_manual_start')));
      expect(started, 1);
    });
  });

  screensUiTests({
    'move_hub': () => hub(best: 24),
    'move_hub_first_time': hub,
    'move_tip': () => MoveSetupView(
      step: MoveSetupStep.tip,
      exercise: pushUps,
      onNext: () {},
      onManual: () {},
    ),
    'move_why': () => MoveSetupView(
      step: MoveSetupStep.why,
      exercise: pushUps,
      onNext: () {},
      onManual: () {},
    ),
    'move_placement_empty': () => camera(cam(stage: CameraStage.placement)),
    'move_placement_checks': () => camera(
      cam(
        stage: CameraStage.placement,
        checks: const PlacementChecks(
          bodyFound: true,
          viewFound: true,
          light: true,
        ),
        hint: FormHintKind.moveBack,
        frame: frameAt(500),
      ),
    ),
    'move_countdown': () =>
        camera(cam(r: round(RoundPhase.countdown), frame: frameAt(500))),
    'move_running': () => camera(
      cam(r: round(RoundPhase.running, reps: 7), frame: frameAt(2400)),
    ),
    'move_running_tall': () => camera(
      cam(
        r: round(RoundPhase.running, reps: 24),
        frame: frameAt(1200),
        game: tower(24),
        soundOn: false,
      ),
    ),
    'move_running_half_rep': () => camera(
      cam(
        r: round(RoundPhase.running, reps: 5),
        frame: frameAt(2400),
        game: tower(5, last: GameMomentKind.halfRep),
      ),
    ),
    'move_running_front': () => camera(
      cam(
        r: round(RoundPhase.running, reps: 3),
        frame: frameAt(2400, view: SynthView.front),
        hint: FormHintKind.straightBody,
      ),
    ),
    'move_paused': () => camera(
      cam(r: round(RoundPhase.paused, reps: 12, pause: PauseReason.tap)),
    ),
    'move_body_lost': () => camera(
      cam(r: round(RoundPhase.paused, reps: 5, pause: PauseReason.bodyLost)),
    ),
    'move_results': () =>
        camera(cam(r: round(RoundPhase.finished, reps: 26), done: outcome())),
    'move_results_saved': () => camera(
      cam(
        r: round(RoundPhase.finished, reps: 26),
        done: outcome(save: SaveState.saved, best: false),
      ),
    ),
    'move_denied': () =>
        camera(cam(stage: CameraStage.failed, trouble: CameraTrouble.denied)),
    'move_too_slow': () =>
        camera(cam(stage: CameraStage.failed, trouble: CameraTrouble.tooSlow)),
    'move_manual_ready': () => manual(
      ManualRoundState(round: round(RoundPhase.ready, mode: RoundMode.manual)),
    ),
    'move_manual_running': () => manual(
      ManualRoundState(
        round: round(RoundPhase.running, mode: RoundMode.manual, reps: 14),
      ),
    ),
    'move_manual_paused': () => manual(
      ManualRoundState(
        round: round(
          RoundPhase.paused,
          mode: RoundMode.manual,
          reps: 9,
          pause: PauseReason.tap,
        ),
      ),
    ),
    'move_manual_results': () => manual(
      ManualRoundState(
        round: round(RoundPhase.finished, mode: RoundMode.manual, reps: 18),
        outcome: outcome(reps: 18, mode: RoundMode.manual),
      ),
    ),
  });
}
