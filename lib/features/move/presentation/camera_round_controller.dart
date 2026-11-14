import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/camera/camera_preview_source.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/screen_awake/screen_awake.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_sound_mode.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/move_analytics.dart';
import 'package:gym_tracker/features/move/domain/move_exercises.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_local_repository.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_sounds.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_voice.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:gym_tracker/features/move/domain/usecases/placement.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_providers.dart';
import 'package:gym_tracker/features/move/presentation/round_outcome.dart';

enum CameraStage {
  /// Asking for the camera and loading the model.
  starting,

  /// The placement guide: live checks until the member is in position.
  placement,

  /// 3-2-1, the round, pauses and the results (see [RoundState.phase]).
  live,

  /// The camera can't be used; the screen offers the manual counter.
  failed,
}

enum CameraTrouble { denied, noCamera, modelFailed, tooSlow }

@immutable
class CameraRoundState {
  const new({
    required this.round,
    this.stage = CameraStage.starting,
    this.trouble,
    this.checks = const PlacementChecks(),
    this.frame,
    this.rep = const RepState(),
    this.hint,
    this.fps,
    this.cameraOn = false,
    this.outcome,
    this.game,
    this.sound = MoveSoundMode.fallback,
    this.voiceReady = false,
    this.zoom,
  });

  final CameraStage stage;
  final CameraTrouble? trouble;
  final RoundState round;
  final PlacementChecks checks;

  /// The latest frame (the dots over the preview); dropped on the next.
  final PoseFrame? frame;
  final RepState rep;

  /// The latest hint to show (one at a time).
  final FormHintKind? hint;
  final double? fps;

  /// The front camera's zoom, when the phone lets it change (null: no
  /// control is shown).
  final CameraZoom? zoom;

  /// Zoom changes only while getting in position: during the round a
  /// change would change how deep a rep looks.
  bool get canZoom =>
      zoom?.adjustable == true && cameraOn && stage == CameraStage.placement;

  /// The camera and model are running.
  final bool cameraOn;
  final RoundOutcome? outcome;

  /// The game the reps build (null until the controller starts it).
  final GameState? game;

  /// The sound the member chose (the button cycles it).
  final MoveSoundMode sound;

  /// The phone has a voice for the app's language (else tones play).
  final bool voiceReady;

  /// What actually plays now.
  MoveSoundMode get playing => sound.effective(voiceAvailable: voiceReady);

  CameraRoundState copyWith({
    CameraStage? stage,
    CameraTrouble? trouble,
    RoundState? round,
    PlacementChecks? checks,
    PoseFrame? frame,
    RepState? rep,
    FormHintKind? Function()? hint,
    double? fps,
    bool? cameraOn,
    RoundOutcome? outcome,
    GameState? game,
    MoveSoundMode? sound,
    bool? voiceReady,
    CameraZoom? Function()? zoom,
  }) => CameraRoundState(
    stage: stage ?? this.stage,
    trouble: trouble ?? this.trouble,
    round: round ?? this.round,
    checks: checks ?? this.checks,
    frame: frame ?? this.frame,
    rep: rep ?? this.rep,
    hint: hint == null ? this.hint : hint(),
    fps: fps ?? this.fps,
    cameraOn: cameraOn ?? this.cameraOn,
    outcome: outcome ?? this.outcome,
    game: game ?? this.game,
    sound: sound ?? this.sound,
    voiceReady: voiceReady ?? this.voiceReady,
    zoom: zoom == null ? this.zoom : zoom(),
  );
}

final NotifierProviderFamily<
  CameraRoundController,
  CameraRoundState,
  MoveLaunch
>
cameraRoundControllerProvider = NotifierProvider.autoDispose
    .family<CameraRoundController, CameraRoundState, MoveLaunch>(
      CameraRoundController.new,
    );

/// A camera round: the front camera and the pose model count the reps
/// (docs/designs/move_games.md §3–§5). Frames are used once and dropped.
class CameraRoundController extends Notifier<CameraRoundState>
    with RoundEnding {
  new(this.launch);

  final MoveLaunch launch;

  /// Below this the detector can't follow a rep: offer the manual counter.
  static const minFps = 8.0;

  /// The speed is not judged until the model has been answering this long:
  /// its first frames are slow on every phone (loading, warm-up, and on a
  /// first run ML Kit's own speed test in another process).
  static const warmUp = Duration(seconds: 3);

  /// Too slow only when it stays below [minFps] this long in a row: one
  /// slow reading is not a slow phone.
  static const slowFor = Duration(seconds: 5);

  PoseSource? _source;
  RepDetector? _detector;
  final _placement = PlacementTracker();
  // Both are cancelled in _release (through local copies, which the lint
  // does not follow): the camera is stopped first.
  // ignore: cancel_subscriptions
  StreamSubscription<PoseFrame>? _frames;
  // Cancelled in _release too.
  // ignore: cancel_subscriptions
  StreamSubscription<PoseSourceStatus>? _status;

  /// When the speed started being judged (the round under way, the body in
  /// place), and since when it has been too slow without a break.
  DateTime? _judgedSince;
  DateTime? _slowSince;
  bool _finishing = false;

  DateTime get _now => ref.read(moveClockProvider)();

  /// Read once: the release after the screen closes can't use `ref`.
  late ScreenAwake _awake;
  late GameRules<GameState> _rules;
  late MoveSounds _sounds;
  late MoveVoice _voice;
  String _language = 'en';
  bool _voiceAsked = false;

  @override
  CameraRoundState build() {
    _awake = ref.read(screenAwakeProvider);
    _rules = MoveExercises.gameFor(launch.exercise);
    final sounds = _sounds = ref.read(moveSoundsFactoryProvider)();
    final voice = _voice = ref.read(moveVoiceFactoryProvider)();
    ref.onDispose(() {
      unawaited(_release());
      unawaited(sounds.dispose());
      unawaited(voice.dispose());
    });
    return CameraRoundState(
      round: RoundState(
        exercise: launch.exercise,
        kind: launch.kind,
        mode: RoundMode.camera,
      ),
      game: _rules.start(),
    );
  }

  /// The sound button: count out loud → tones → off (kept for the next
  /// rounds).
  Future<void> cycleSound() async {
    // From what plays (the button shows that), not from what was chosen:
    // without a voice, "voice" plays tones and the next tap must turn off.
    final next = state.playing.next(voiceAvailable: state.voiceReady);
    state = state.copyWith(sound: next);
    _readySounds();
    await ref.read(moveLocalRepositoryProvider).setSoundMode(next);
  }

  /// Loads the tones when they may play (also the voice's fallback).
  void _readySounds() {
    if (state.playing == MoveSoundMode.tones) unawaited(_sounds.load());
  }

  /// Asks once whether the phone can speak [_language].
  Future<void> _prepareVoice() async {
    if (_voiceAsked) return;
    _voiceAsked = true;
    final ready = await _voice.prepare(_language);
    if (!ref.mounted) return;
    state = state.copyWith(voiceReady: ready);
    _readySounds();
  }

  /// Starts (or restarts) the camera. The screen calls it once it opens:
  /// only the app can open that screen, after the member's tap. [language]
  /// is the app's ("ar", "en"), for the spoken count.
  Future<void> start({String? language}) async {
    if (language != null) _language = language;
    if (_source != null || state.round.phase == RoundPhase.finished) return;
    final local = ref.read(moveLocalRepositoryProvider);
    final allowedBefore = switch (await local.cameraAllowedBefore()) {
      Success(:final value) => value,
      Failed() => false,
    };
    final sound = switch (await local.soundMode()) {
      Success(:final value) => value,
      Failed() => MoveSoundMode.fallback,
    };
    if (!ref.mounted || _source != null) return;
    state = state.copyWith(sound: sound);
    _readySounds();
    if (sound != MoveSoundMode.off) unawaited(_prepareVoice());
    final source = ref.read(poseSourceFactoryProvider)();
    _source = source;
    // A new camera's frames start again from 0 s: a detector kept from the
    // last one would drop them all as older than the last frame it saw.
    // The round keeps its own count, so nothing done is lost.
    _detector = MoveExercises.detectorFor(launch.exercise);
    _placement.reset();
    state = state.copyWith(rep: const RepState());
    if (state.stage != CameraStage.live) {
      state = state.copyWith(stage: CameraStage.starting);
    }
    _status = source.status.listen(_onStatus);
    _frames = source.frames.listen(_onFrame);
    await source.start();
    if (!ref.mounted || _source != source) return;
    final status = source.currentStatus;
    if (status.state == PoseSourceState.failed) {
      final trouble = switch (status.problem) {
        PoseProblem.denied => CameraTrouble.denied,
        PoseProblem.modelFailed => CameraTrouble.modelFailed,
        PoseProblem.noCamera || null => CameraTrouble.noCamera,
      };
      if (trouble == CameraTrouble.denied) {
        unawaited(
          Analytics.capture('move_camera_answered', {'result': 'denied'}),
        );
      }
      await _fail(trouble);
      return;
    }
    if (!allowedBefore) {
      unawaited(local.markCameraAllowed());
      unawaited(
        Analytics.capture('move_camera_answered', {'result': 'granted'}),
      );
    }
    unawaited(_awake.keepOn(on: true));
    final zoom = await _restoreZoom(source, local);
    if (!ref.mounted || _source != source) return;
    state = state.copyWith(
      zoom: () => zoom,
      cameraOn: true,
      stage: state.stage == CameraStage.live
          ? CameraStage.live
          : CameraStage.placement,
    );
  }

  /// The widest the camera goes, or the level the member chose last time.
  static Future<CameraZoom?> _restoreZoom(
    PoseSource source,
    MoveLocalRepository local,
  ) async {
    if (source is! ZoomablePoseSource) return null;
    final saved = switch (await local.cameraZoom()) {
      Success(:final value) => value,
      Failed() => null,
    };
    if (saved == null) return source.zoom;
    return await source.setZoom(saved);
  }

  /// One step wider (−) or closer (+), remembered on this phone. The
  /// placement checks start again: the body's size in the picture changed.
  Future<void> zoomOut() => _zoomBy(-CameraZoom.step);
  Future<void> zoomIn() => _zoomBy(CameraZoom.step);

  Future<void> _zoomBy(double delta) async {
    final source = _source;
    final zoom = state.zoom;
    if (!state.canZoom || source is! ZoomablePoseSource || zoom == null) {
      return;
    }
    final next = await source.setZoom(zoom.level + delta);
    if (!ref.mounted || next == null || next == zoom) return;
    _placement.reset();
    state = state.copyWith(zoom: () => next);
    unawaited(ref.read(moveLocalRepositoryProvider).setCameraZoom(next.level));
    unawaited(
      Analytics.capture('move_zoom_changed', {
        'direction': delta < 0 ? 'wider' : 'closer',
      }),
    );
  }

  /// The live camera picture, when the source has one (not in tests or on
  /// the simulator, where the body is drawn from the joints instead).
  Widget? preview() => switch (_source) {
    final CameraPreviewSource s => s.buildPreview(),
    _ => null,
  };

  void _onStatus(PoseSourceStatus s) {
    if (!ref.mounted) return;
    if (s.fps case final fps?) state = state.copyWith(fps: fps);
  }

  void _onFrame(PoseFrame frame) {
    final detector = _detector;
    if (!ref.mounted || detector == null) return;
    final update = detector.onFrame(frame);
    final hint = update.events.whereType<FormHint>().lastOrNull?.kind;
    var next = state.copyWith(
      frame: frame,
      rep: update.state,
      hint: hint == null ? null : () => hint,
    );
    final now = _now;
    switch (state.stage) {
      case CameraStage.placement:
        final go = _placement.update(update, frame.at);
        next = next.copyWith(
          checks: _placement.checks,
          hint: () => _placement.lastHint,
        );
        if (go) {
          next = next.copyWith(
            stage: CameraStage.live,
            round: next.round.startCountdown(now),
          );
          reportStarted(next.round, sound: state.playing);
        }
      case CameraStage.live:
        var round = next.round;
        var game = next.game ?? _rules.start();
        for (final e in update.events) {
          // The game only sees what happens while the round runs (the last
          // rep of a target round included).
          if (round.phase == RoundPhase.running) {
            final before = game.last?.seq;
            game = _rules.onEvent(game, e, now);
            if (game.last?.seq != before) _sound(game.last, round.reps + 1);
          }
          round = round.onEvent(e, now);
          // Back in the picture after a body-lost pause: 3-2-1 again.
          if (e is BodyFound &&
              round.phase == RoundPhase.paused &&
              round.pauseReason == PauseReason.bodyLost) {
            round = round.startCountdown(now);
          }
        }
        next = next.copyWith(round: round, game: game);
      case CameraStage.starting || CameraStage.failed:
        break;
    }
    state = next;
    _afterRound();
  }

  /// A new block: [count] out loud, or a tone (another every fifth).
  void _sound(GameMoment? moment, int count) {
    if (moment == null || moment.kind != GameMomentKind.rep) return;
    switch (state.playing) {
      case MoveSoundMode.voice:
        _voice.count(count);
      case MoveSoundMode.tones:
        moment.milestone ? _sounds.milestone() : _sounds.rep();
      case MoveSoundMode.off:
        break;
    }
  }

  /// Called a few times a second by the screen: the clock, the end of a
  /// timed round, and the speed check.
  void tick() {
    final now = _now;
    state = state.copyWith(round: state.round.tick(now));
    if (_tooSlow(now)) {
      unawaited(_fail(CameraTrouble.tooSlow));
      return;
    }
    _afterRound();
  }

  /// Below [minFps] for [slowFor] in a row, judged only during 3-2-1 and
  /// the round, after [warmUp].
  ///
  /// Not during placement or a pause: with nobody in position (sitting,
  /// walking to the phone, out of the picture) ML Kit runs its person
  /// detector on every frame and is much slower than while it tracks a
  /// body, so a fine phone looked "too slow" before the member was even
  /// down (owner's OPPO, 2026-11-14). Placement keeps guiding instead.
  bool _tooSlow(DateTime now) {
    final phase = state.round.phase;
    final judging =
        state.cameraOn &&
        state.stage == CameraStage.live &&
        (phase == RoundPhase.countdown || phase == RoundPhase.running);
    if (!judging) {
      _judgedSince = null;
      _slowSince = null;
      return false;
    }
    final since = _judgedSince ??= now;
    final fps = state.fps;
    if (fps == null || fps >= minFps) {
      _slowSince = null;
      return false;
    }
    final slowSince = _slowSince ??= now;
    return now.difference(since) >= warmUp &&
        now.difference(slowSince) >= slowFor;
  }

  void pause() =>
      state = state.copyWith(round: state.round.pause(PauseReason.tap, _now));

  /// From a pause: the camera again if it was released, then 3-2-1.
  Future<void> resume() async {
    if (state.round.phase != RoundPhase.paused) return;
    if (_source == null) await start();
    if (!ref.mounted || state.stage == CameraStage.failed) return;
    final now = _now;
    var round = state.round.startCountdown(now);
    // Not in the picture (a new camera has seen nobody yet): wait for them;
    // the detector's "found" starts 3-2-1.
    if (state.rep.phase == RepPhase.notVisible) {
      round = round.pause(PauseReason.bodyLost, now);
    }
    state = state.copyWith(round: round);
  }

  /// Back on screen. If the camera was released before the round started
  /// (on the loader or at placement), start it again; a round that had
  /// started stays paused until "Resume".
  Future<void> foreground() async {
    if (_source != null || state.cameraOn) return;
    final waiting =
        state.stage == CameraStage.starting ||
        state.stage == CameraStage.placement;
    if (!waiting || state.round.phase != RoundPhase.ready) return;
    await start();
  }

  /// The app left the foreground: pause, and release the camera at once.
  Future<void> background() async {
    state = state.copyWith(
      round: state.round.pause(PauseReason.background, _now),
    );
    await _release();
    if (ref.mounted) state = state.copyWith(cameraOn: false);
  }

  void end() {
    state = state.copyWith(round: state.round.end(_now));
    _afterRound(ended: 'quit');
  }

  void _afterRound({String ended = 'completed'}) {
    if (state.round.phase != RoundPhase.finished || _finishing) return;
    _finishing = true;
    unawaited(_finish(ended));
  }

  Future<void> _finish(String ended) async {
    final fps = state.fps;
    await _release();
    final result = RoundResult.of(state.round);
    if (!ref.mounted) return;
    state = state.copyWith(cameraOn: false);
    if (result == null) return;
    final outcome = await finishRound(result, ended: ended, fps: fps);
    if (ref.mounted) state = state.copyWith(outcome: outcome);
  }

  Future<void> save() async {
    final outcome = state.outcome;
    if (outcome == null || outcome.save == SaveState.saving) return;
    state = state.copyWith(outcome: outcome.copyWith(save: SaveState.saving));
    final saved = await saveRound(outcome);
    if (ref.mounted) {
      state = state.copyWith(outcome: outcome.copyWith(save: saved));
    }
  }

  Future<void> _fail(CameraTrouble trouble) async {
    await _release();
    if (!ref.mounted) return;
    if (trouble != CameraTrouble.denied) {
      unawaited(
        Analytics.capture('move_unsupported', {
          'reason': switch (trouble) {
            CameraTrouble.tooSlow => 'too_slow',
            CameraTrouble.modelFailed => 'model_failed',
            CameraTrouble.noCamera || CameraTrouble.denied => 'no_camera',
          },
          // How slow, in a range: tells a nearly-fast-enough phone from a
          // hopeless one.
          if (trouble == CameraTrouble.tooSlow)
            'fps_band': ?MoveAnalytics.fpsBand(state.fps),
        }),
      );
    }
    state = state.copyWith(
      stage: CameraStage.failed,
      trouble: trouble,
      cameraOn: false,
    );
  }

  /// The camera goes off first; the listeners are dropped after.
  Future<void> _release() async {
    final source = _source;
    final frames = _frames;
    final status = _status;
    _source = null;
    _frames = null;
    _status = null;
    _judgedSince = null;
    _slowSince = null;
    if (source == null) return;
    await source.stop();
    // Not awaited: the source is already stopped, and a cancel can take a
    // while to settle; the round's end must not wait for it.
    unawaited(frames?.cancel());
    unawaited(status?.cancel());
    // Fire and forget, like keeping it on: never hold the round's end up.
    unawaited(_awake.keepOn(on: false));
  }
}
