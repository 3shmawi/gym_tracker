import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/presentation/game/move_game_theme.dart';
import 'package:gym_tracker/features/move/presentation/game/stack_game.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The Stack game inside the app's UI. To a screen reader it is one
/// picture with a label ("Stack: 7 floors"); the HUD around it is real
/// widgets.
class StackGameView extends StatefulWidget {
  const new({required this.state, super.key});

  final StackState state;

  @override
  State<StackGameView> createState() => _StackGameViewState();
}

class _StackGameViewState extends State<StackGameView> {
  StackGame? _game;

  @override
  Widget build(BuildContext context) {
    final theme = MoveGameTheme.of(context.palette);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // show() is idempotent: only a new state, theme or setting wakes the
    // engine.
    final game = (_game ??= StackGame(
      theme: theme,
      state: widget.state,
      reduceMotion: reduceMotion,
    ))..show(widget.state, theme: theme, reduceMotion: reduceMotion);
    return Semantics(
      key: const Key('move_game'),
      image: true,
      label: context.l10n.moveStackLabel(widget.state.floors.length),
      excludeSemantics: true,
      // The tower scrolls out of the bottom: nothing is drawn outside.
      child: ClipRect(child: GameWidget(game: game)),
    );
  }
}
