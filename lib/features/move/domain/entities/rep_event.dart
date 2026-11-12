import 'package:meta/meta.dart';

/// Something a rep detector noticed in a frame. Screens and games react to
/// events; only detectors know about joints.
@immutable
sealed class RepEvent {
  const new();
}

/// A full, controlled rep. [total] is the count so far, [took] the time from
/// the top position back to the top, [depth] the deepest point (0..1).
final class RepCounted extends RepEvent {
  const new({required this.total, required this.took, required this.depth});

  final int total;
  final Duration took;
  final double depth;

  @override
  bool operator ==(Object other) =>
      other is RepCounted &&
      other.total == total &&
      other.took == took &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(total, took, depth);

  @override
  String toString() => 'RepCounted($total, $took, $depth)';
}

/// The member went part of the way down and came back up. Not counted.
final class HalfRep extends RepEvent {
  const new({required this.depth});

  final double depth;

  @override
  bool operator ==(Object other) => other is HalfRep && other.depth == depth;

  @override
  int get hashCode => depth.hashCode;

  @override
  String toString() => 'HalfRep($depth)';
}

/// A full rep, but faster than the minimum time. Not counted.
final class TooFast extends RepEvent {
  const new({required this.took});

  final Duration took;

  @override
  bool operator ==(Object other) => other is TooFast && other.took == took;

  @override
  int get hashCode => took.hashCode;

  @override
  String toString() => 'TooFast($took)';
}

/// The body has not been visible for a while: the round should pause. A rep
/// that was in progress is dropped.
final class BodyLost extends RepEvent {
  const new();

  @override
  bool operator ==(Object other) => other is BodyLost;

  @override
  int get hashCode => (BodyLost).hashCode;

  @override
  String toString() => 'BodyLost()';
}

/// The body is visible again (also the first time it is found).
final class BodyFound extends RepEvent {
  const new();

  @override
  bool operator ==(Object other) => other is BodyFound;

  @override
  int get hashCode => (BodyFound).hashCode;

  @override
  String toString() => 'BodyFound()';
}

/// Advice for the member. Never changes the count.
final class FormHint extends RepEvent {
  const new(this.kind);

  final FormHintKind kind;

  @override
  bool operator ==(Object other) => other is FormHint && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'FormHint(${kind.name})';
}

enum FormHintKind {
  /// Hips sagging or piked: keep the body in one line (advice only).
  straightBody,

  /// Part of the body is out of the picture: move the phone back.
  moveBack,

  /// The body is small in the picture: move the phone closer.
  moveCloser,

  /// The model is unsure about every joint: probably too dark.
  moreLight,
}
