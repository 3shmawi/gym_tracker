import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "30 s", "10 reps"…
String roundLabel(AppLocalizations l10n, RoundKind k) => switch (k) {
  RoundKind.s30 || RoundKind.s60 => l10n.moveRoundSeconds(k.time!.inSeconds),
  RoundKind.r10 || RoundKind.r20 => l10n.moveRoundReps(k.target!),
};

/// A hint, in words (spoken by the screen reader too).
String hintLabel(AppLocalizations l10n, FormHintKind kind) => switch (kind) {
  FormHintKind.straightBody => l10n.moveHintStraightBody,
  FormHintKind.moveBack => l10n.moveHintMoveBack,
  FormHintKind.moveCloser => l10n.moveHintMoveCloser,
  FormHintKind.moreLight => l10n.moveHintMoreLight,
};

/// m:ss, always with Western digits (as the rest of the app).
String clockLabel(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
