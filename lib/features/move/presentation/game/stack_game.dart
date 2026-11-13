import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/presentation/game/move_game_theme.dart';

/// Draws a [StackState]: the tower, the block that just landed, a half
/// rep's fading outline, the glow every fifth block. All game logic is in
/// [StackRules]; this only animates what the state says.
///
/// The engine runs only while something moves and pauses itself after, so
/// an idle round costs nothing (and tests can settle).
class StackGame extends FlameGame {
  new({
    required MoveGameTheme theme,
    StackState state = const StackState(),
    bool reduceMotion = false,
  }) : _tower = TowerComponent(
         theme: theme,
         state: state,
         reduceMotion: reduceMotion,
       );

  final TowerComponent _tower;

  TowerComponent get tower => _tower;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await add(_tower);
  }

  /// A new state, theme or motion setting from the screen.
  void show(
    StackState state, {
    required MoveGameTheme theme,
    required bool reduceMotion,
  }) {
    final changed = _tower.show(
      state,
      theme: theme,
      reduceMotion: reduceMotion,
    );
    if (changed) resumeEngine();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_tower.moving) pauseEngine();
  }
}

/// The tower, in the game's own pixels (no camera: it is a direct child of
/// the game).
class TowerComponent extends Component with HasGameReference<StackGame> {
  new({
    required this._theme,
    required StackState state,
    required this._reduceMotion,
  }) : _state = state,
       _shown = state.floors.length;

  /// A block falls this long.
  static const drop = 0.35;

  /// With Reduce Motion, things fade in place this long.
  static const fade = 0.15;

  /// A half rep's outline stays this long.
  static const ghostTime = 1.2;

  /// Every fifth block glows this long.
  static const glowTime = 0.6;

  MoveGameTheme _theme;
  StackState _state;
  bool _reduceMotion;

  /// Floors already landed (the newest may still be falling).
  int _shown;

  /// Time since the newest block started to fall, or null.
  double? _dropT;
  double? _ghostT;
  double? _glowT;

  /// Floors scrolled out of the bottom, eased towards [_targetScroll].
  double _scroll = 0;
  bool _scrollKnown = false;

  StackState get state => _state;

  /// Something is still animating.
  bool get moving =>
      _dropT != null ||
      _ghostT != null ||
      _glowT != null ||
      (_targetScroll(game.size) - _scroll).abs() > 0.001;

  /// Takes a new state; true when something must be drawn again.
  bool show(
    StackState state, {
    required MoveGameTheme theme,
    required bool reduceMotion,
  }) {
    final redraw =
        theme != _theme ||
        reduceMotion != _reduceMotion ||
        state.floors.length != _state.floors.length ||
        state.last?.seq != _state.last?.seq;
    final last = state.last;
    final isNew = last != null && last.seq != _state.last?.seq;
    _theme = theme;
    _reduceMotion = reduceMotion;
    if (state.floors.length < _shown) {
      // A new round: start again without animating.
      _shown = state.floors.length;
      _dropT = _ghostT = _glowT = null;
      _scrollKnown = false;
    }
    _state = state;
    if (isNew) {
      switch (last.kind) {
        case GameMomentKind.rep:
          _shown = state.floors.length;
          _dropT = 0;
          if (last.milestone && !reduceMotion) _glowT = 0;
        case GameMomentKind.halfRep:
          _ghostT = 0;
        case GameMomentKind.tooFast:
          break;
      }
    }
    _shown = state.floors.length;
    return redraw;
  }

  @override
  void update(double dt) {
    double? on(double? t, double end) {
      if (t == null) return null;
      final next = t + dt;
      return next >= end ? null : next;
    }

    _dropT = on(_dropT, _reduceMotion ? fade : drop);
    _ghostT = on(_ghostT, ghostTime);
    _glowT = on(_glowT, glowTime);
    final target = _targetScroll(game.size);
    if (!_scrollKnown || _reduceMotion) {
      _scroll = target;
      _scrollKnown = true;
    } else {
      // Eases most of the way in a quarter of a second.
      final k = 1 - math.exp(-12 * dt);
      _scroll += (target - _scroll) * k;
      if ((target - _scroll).abs() < 0.001) _scroll = target;
    }
  }

  // ---- Layout -------------------------------------------------------------

  static double _blockWidth(Vector2 size) =>
      math.min(size.x * 0.62, size.y * 0.55);

  static double _blockHeight(Vector2 size) {
    final byHeight = size.y / 10;
    return byHeight.clamp(8.0, math.max(8, _blockWidth(size) * 0.24));
  }

  /// The ground line, from the top.
  static double _groundY(Vector2 size) => size.y - _blockHeight(size) * 0.6;

  /// How many floors fit under the top margin.
  static int _capacity(Vector2 size) => math.max(
    1,
    ((_groundY(size) - _blockHeight(size) * 1.5) / _blockHeight(size)).floor(),
  );

  /// Floors pushed out of the bottom so the top block and one more fit.
  double _targetScroll(Vector2 size) {
    if (size.x <= 0 || size.y <= 0) return 0;
    return math.max(0, _state.floors.length + 1 - _capacity(size)).toDouble();
  }

  // ---- Drawing ------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final size = game.size;
    if (size.x <= 0 || size.y <= 0) return;
    final bw = _blockWidth(size);
    final bh = _blockHeight(size);
    final ground = _groundY(size) + _scroll * bh;
    final cx = size.x / 2;

    if (ground < size.y + bh) {
      canvas.drawLine(
        Offset(cx - bw * 0.75, ground),
        Offset(cx + bw * 0.75, ground),
        Paint()
          ..color = _theme.ground
          ..strokeWidth = math.max(1, bh * 0.08)
          ..strokeCap = StrokeCap.round,
      );
    }

    final floors = _state.floors;
    // Only what is on screen.
    final first = math.max(0, _scroll.floor() - 1);
    for (var i = first; i < floors.length; i++) {
      final f = floors[i];
      var top = ground - (i + 1) * bh;
      var alpha = 1.0;
      final falling = i == floors.length - 1 ? _dropT : null;
      if (falling != null) {
        if (_reduceMotion) {
          alpha = (falling / fade).clamp(0.0, 1.0);
        } else {
          final p = Curves.easeOutCubic.transform(
            (falling / drop).clamp(0.0, 1.0),
          );
          top -= (1 - p) * bh * 3;
          alpha = (0.3 + 0.7 * p).clamp(0.0, 1.0);
        }
      }
      if (top > size.y) continue;
      final rect = Rect.fromLTWH(cx - bw / 2 + f.offset * bw, top, bw, bh);
      final glow = _glowT;
      if (glow != null && i == floors.length - 1) {
        final g = 1 - glow / glowTime;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(bh * 0.3), Radius.circular(bh)),
          Paint()
            ..color = _theme.glow.withValues(alpha: 0.45 * g)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, bh * 0.4),
        );
      }
      _block(canvas, rect, bh, steady: f.steady, alpha: alpha);
    }

    final ghost = _ghostT;
    if (ghost != null) {
      final a = 1 - ghost / ghostTime;
      final top = ground - (floors.length + 1) * bh;
      final rect = Rect.fromLTWH(cx - bw / 2, top, bw, bh).deflate(1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(bh * 0.25)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, bh * 0.08)
          ..color = _theme.ghost.withValues(alpha: 0.8 * a),
      );
    }
  }

  void _block(
    Canvas canvas,
    Rect rect,
    double bh, {
    required bool steady,
    required double alpha,
  }) {
    final inner = rect.deflate(math.max(0.5, bh * 0.03));
    final rrect = RRect.fromRectAndRadius(inner, Radius.circular(bh * 0.25));
    Color a(Color c) => c.withValues(alpha: c.a * alpha);
    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..shader = Gradient.linear(inner.topCenter, inner.bottomCenter, [
            a(_theme.blockTop),
            a(_theme.blockBottom),
          ]),
      )
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = steady ? math.max(1.5, bh * 0.05) : 1
          ..color = a(steady ? _theme.steadyRim : _theme.rim),
      )
      // The glass shine along the top.
      ..drawLine(
        Offset(inner.left + bh * 0.3, inner.top + bh * 0.22),
        Offset(inner.right - bh * 0.3, inner.top + bh * 0.22),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.35 * alpha)
          ..strokeWidth = math.max(1, bh * 0.06)
          ..strokeCap = StrokeCap.round,
      );
  }
}
