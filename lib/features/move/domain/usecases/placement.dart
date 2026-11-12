import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:meta/meta.dart';

/// The live checks of the placement guide (docs/designs/move_games.md §5.5):
/// they turn green one by one, and the round starts by itself once all of
/// them have been green for a second (the member is on the floor).
@immutable
class PlacementChecks {
  const new({
    this.bodyFound = false,
    this.viewFound = false,
    this.inFrame = false,
    this.light = false,
    this.plank = false,
  });

  final bool bodyFound;
  final bool viewFound;

  /// Not too far, not too close, nothing out of the picture.
  final bool inFrame;
  final bool light;

  /// Holding the top position.
  final bool plank;

  bool get allGood => bodyFound && viewFound && inFrame && light && plank;

  @override
  bool operator ==(Object other) =>
      other is PlacementChecks &&
      other.bodyFound == bodyFound &&
      other.viewFound == viewFound &&
      other.inFrame == inFrame &&
      other.light == light &&
      other.plank == plank;

  @override
  int get hashCode => Object.hash(bodyFound, viewFound, inFrame, light, plank);
}

/// Turns detector updates into [PlacementChecks] and says when to start.
class PlacementTracker {
  /// A hint keeps its check red this long after it was given.
  static const hintWindow = Duration(seconds: 3);

  /// The top position held this long counts as "in the plank".
  static const plankHold = Duration(seconds: 1);

  /// Everything green this long: start.
  static const readyHold = Duration(seconds: 1);

  Duration? _framingHintAt;
  Duration? _lightHintAt;
  Duration? _topSince;
  Duration? _goodSince;
  PlacementChecks _checks = const PlacementChecks();
  FormHintKind? _lastHint;

  PlacementChecks get checks => _checks;

  /// The latest hint about placement (move back/closer, more light).
  FormHintKind? get lastHint => _lastHint;

  /// Feeds one detector update at frame time [at]; true when the round
  /// should start.
  bool update(RepUpdate update, Duration at) {
    for (final e in update.events) {
      if (e case FormHint(:final kind)) {
        switch (kind) {
          case FormHintKind.moveBack || FormHintKind.moveCloser:
            _framingHintAt = at;
            _lastHint = kind;
          case FormHintKind.moreLight:
            _lightHintAt = at;
            _lastHint = kind;
          case FormHintKind.straightBody:
            break;
        }
      }
    }
    final s = update.state;
    final found = s.phase != RepPhase.notVisible;
    bool quiet(Duration? hint) => hint == null || at - hint > hintWindow;
    final framingNow =
        s.issues.contains(FormHintKind.moveBack) ||
        s.issues.contains(FormHintKind.moveCloser);
    final darkNow = s.issues.contains(FormHintKind.moreLight);
    final atTop = found && s.phase == RepPhase.ready && s.depth <= 0.2;
    if (atTop) {
      _topSince ??= at;
    } else {
      _topSince = null;
    }
    final top = _topSince;
    _checks = PlacementChecks(
      bodyFound: found,
      viewFound: found && s.view != null,
      inFrame: found && !framingNow && quiet(_framingHintAt),
      light: found && !darkNow && quiet(_lightHintAt),
      plank: top != null && at - top >= plankHold,
    );
    if (_checks.inFrame && _checks.light) _lastHint = null;
    if (!_checks.allGood) {
      _goodSince = null;
      return false;
    }
    final good = _goodSince ??= at;
    return at - good >= readyHold;
  }

  void reset() {
    _framingHintAt = null;
    _lightHintAt = null;
    _topSince = null;
    _goodSince = null;
    _lastHint = null;
    _checks = const PlacementChecks();
  }
}
