import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/presentation/camera_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/camera_round_view.dart';
import 'package:gym_tracker/features/move/presentation/manual_counter_view.dart';
import 'package:gym_tracker/features/move/presentation/manual_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_hub_view.dart';
import 'package:gym_tracker/features/move/presentation/move_providers.dart';
import 'package:gym_tracker/features/move/presentation/move_setup_view.dart';

/// The library entry a Move exercise is saved as (both names, picture).
LibraryExercise catalogEntryOf(MoveExerciseId id) => ExerciseCatalog.all
    .firstWhere((e) => e.defaults.id == id.catalogExerciseId);

String _nameOf(BuildContext context, MoveExerciseId id) =>
    catalogEntryOf(id).defaults.name
        .of(Localizations.localeOf(context).languageCode);

/// Back to where the member came from, or the hub.
void _leave(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.move);
  }
}

/// `/move`.
class MoveHubPage extends ConsumerStatefulWidget {
  const new({this.source = MoveSource.link, super.key});

  final MoveSource source;

  @override
  ConsumerState<MoveHubPage> createState() => _MoveHubPageState();
}

class _MoveHubPageState extends ConsumerState<MoveHubPage> {
  static const MoveExerciseId _exercise = MoveExerciseId.pushUps;
  RoundKind _kind = RoundKind.fallback;
  int? _best;

  @override
  void initState() {
    super.initState();
    unawaited(Analytics.capture('move_opened', {'source': widget.source.name}));
    unawaited(_loadBest());
  }

  Future<void> _loadBest() async {
    final best = await ref
        .read(moveLocalRepositoryProvider)
        .best(_exercise, _kind);
    if (!mounted) return;
    setState(() => _best = best is Success<int?> ? best.value : null);
  }

  @override
  Widget build(BuildContext context) => MoveHubView(
    exercise: catalogEntryOf(_exercise),
    kind: _kind,
    best: _best,
    manualFirst: MediaQuery.accessibleNavigationOf(context),
    onKind: (k) {
      setState(() {
        _kind = k;
        _best = null;
      });
      unawaited(_loadBest());
    },
    onCamera: () => unawaited(
      context
          .push<void>(AppRoutes.moveSetup(_exercise.id, round: _kind.id))
          .then((_) => _loadBest()),
    ),
    onManual: () => unawaited(
      context
          .push<void>(AppRoutes.moveCount(_exercise.id, round: _kind.id))
          .then((_) => _loadBest()),
    ),
  );
}

/// `/move/<exercise>`: the form tip (first time) and the "why the camera"
/// screen (until the camera was allowed once). Never starts the camera.
class MoveSetupPage extends ConsumerStatefulWidget {
  const new({required this.exercise, required this.kind, super.key});

  final MoveExerciseId exercise;
  final RoundKind kind;

  @override
  ConsumerState<MoveSetupPage> createState() => _MoveSetupPageState();
}

class _MoveSetupPageState extends ConsumerState<MoveSetupPage> {
  MoveSetupStep? _step;

  @override
  void initState() {
    super.initState();
    unawaited(_decide());
  }

  Future<void> _decide() async {
    final local = ref.read(moveLocalRepositoryProvider);
    final tip = await local.tipSeen(widget.exercise);
    if (!mounted) return;
    if (tip is! Success<bool> || !tip.value) {
      setState(() => _step = MoveSetupStep.tip);
      return;
    }
    // The why screen every time until the camera has been allowed once:
    // the camera plugin cannot read the permission without asking.
    setState(() => _step = MoveSetupStep.why);
  }

  void _play() => context.pushReplacement(
    AppRoutes.movePlay(widget.exercise.id),
    extra: MoveLaunch(widget.exercise, widget.kind),
  );

  Future<void> _next() async {
    final local = ref.read(moveLocalRepositoryProvider);
    if (_step == MoveSetupStep.tip) {
      await local.markTipSeen(widget.exercise);
      final allowed = await local.cameraAllowedBefore();
      if (!mounted) return;
      if (allowed is Success<bool> && allowed.value) {
        _play();
      } else {
        setState(() => _step = MoveSetupStep.why);
      }
      return;
    }
    _play();
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (step == null) return const SizedBox.shrink();
    return MoveSetupView(
      step: step,
      exercise: catalogEntryOf(widget.exercise),
      onNext: () => unawaited(_next()),
      onManual: () => context.pushReplacement(
        AppRoutes.moveCount(widget.exercise.id, round: widget.kind.id),
      ),
    );
  }
}

/// Ticks the round clock a few times a second while the screen is open.
mixin _Ticker<T extends StatefulWidget> on State<T> {
  Timer? _timer;

  void startTicking(VoidCallback tick) {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// `/move/<exercise>/play` (needs a [MoveLaunch]: only the app opens it).
class CameraRoundPage extends ConsumerStatefulWidget {
  const new({required this.launch, super.key});

  final MoveLaunch launch;

  @override
  ConsumerState<CameraRoundPage> createState() => _CameraRoundPageState();
}

class _CameraRoundPageState extends ConsumerState<CameraRoundPage>
    with _Ticker {
  late final AppLifecycleListener _lifecycle;

  CameraRoundController get _c =>
      ref.read(cameraRoundControllerProvider(widget.launch).notifier);

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(() => mounted ? _c.start() : null));
    startTicking(() => _c.tick());
    _lifecycle = AppLifecycleListener(
      // The camera plugin leaves this to the app: release it at once.
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed && mounted) {
          unawaited(_c.background());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _manual() => context.pushReplacement(
    AppRoutes.moveCount(
      widget.launch.exercise.id,
      round: widget.launch.kind.id,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cameraRoundControllerProvider(widget.launch));
    final exercise = widget.launch.exercise;
    return CameraRoundView(
      state: state,
      now: ref.read(moveClockProvider)(),
      exerciseName: _nameOf(context, exercise),
      preview: state.cameraOn ? _c.preview() : null,
      onClose: () => _leave(context),
      onPause: _c.pause,
      onResume: () => unawaited(_c.resume()),
      onEnd: _c.end,
      onManual: _manual,
      onSave: () => unawaited(_c.save()),
      onPlayAgain: () => context.pushReplacement(
        AppRoutes.movePlay(exercise.id),
        extra: widget.launch,
      ),
      onDone: () => _leave(context),
      onOpenSettings: () => unawaited(AppSettings.openAppSettings()),
      onOpenProgress: () => unawaited(
        context.push<void>(
          AppRoutes.exerciseHistory(exercise.catalogExerciseId),
        ),
      ),
    );
  }
}

/// `/move/<exercise>/count`: no camera, safe from a link.
class ManualCounterPage extends ConsumerStatefulWidget {
  const new({required this.launch, super.key});

  final MoveLaunch launch;

  @override
  ConsumerState<ManualCounterPage> createState() => _ManualCounterPageState();
}

class _ManualCounterPageState extends ConsumerState<ManualCounterPage>
    with _Ticker {
  late final AppLifecycleListener _lifecycle;

  ManualRoundController get _c =>
      ref.read(manualRoundControllerProvider(widget.launch).notifier);

  @override
  void initState() {
    super.initState();
    startTicking(() => _c.tick());
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed && mounted) _c.background();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualRoundControllerProvider(widget.launch));
    final exercise = widget.launch.exercise;
    return ManualCounterView(
      state: state,
      now: ref.read(moveClockProvider)(),
      exerciseName: _nameOf(context, exercise),
      onStart: _c.start,
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        _c.tap();
      },
      onUndo: _c.undo,
      onPause: _c.pause,
      onResume: _c.resume,
      onEnd: _c.end,
      onSave: () => unawaited(_c.save()),
      onPlayAgain: () => context.pushReplacement(
        AppRoutes.moveCount(exercise.id, round: widget.launch.kind.id),
      ),
      onDone: () => _leave(context),
      onOpenProgress: () => unawaited(
        context.push<void>(
          AppRoutes.exerciseHistory(exercise.catalogExerciseId),
        ),
      ),
    );
  }
}
