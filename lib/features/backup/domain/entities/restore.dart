import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// Where the download of the account's workouts stopped: the finish time (as
/// the server wrote it) and the row id of the last workout taken. Pages are
/// ordered by both, so a dropped connection carries on exactly after it.
@immutable
class RestoreCursor {
  const new(this.finishedAt, this.id);

  /// `null` for no cursor, [done] once everything was taken, else the saved
  /// `finishedAt|id` text.
  static RestoreCursor? parse(String? text) {
    if (text == null || text == done) return null;
    final at = text.indexOf('|');
    if (at <= 0 || at == text.length - 1) return null;
    final time = text.substring(0, at);
    if (DateTime.tryParse(time) == null) return null;
    return RestoreCursor(time, text.substring(at + 1));
  }

  /// The saved text that means "everything was taken".
  static const done = 'done';

  final String finishedAt;
  final String id;

  @override
  String toString() => '$finishedAt|$id';

  @override
  bool operator ==(Object other) =>
      other is RestoreCursor &&
      other.finishedAt == finishedAt &&
      other.id == id;

  @override
  int get hashCode => Object.hash(finishedAt, id);
}

/// A page of the account's workouts: only rows the app can read (the rest
/// are counted in [skipped], never an error). [next] is null on the last page.
@immutable
class RestorePage {
  const new({required this.sessions, this.skipped = 0, this.next});

  final List<WorkoutSession> sessions;
  final int skipped;
  final RestoreCursor? next;
}

/// The plan on the account and its version.
@immutable
class RemotePlan {
  const new(this.plan, this.version);

  final WorkoutPlan plan;
  final int version;
}

/// The best level and chosen day on the account.
@immutable
class RemoteState {
  const new(this.bestLevel, this.chosenDay);

  final Level bestLevel;
  final ChosenDay? chosenDay;
}

/// What a restore did with the plan.
sealed class PlanOutcome {
  const new();
}

/// The account has no plan: nothing to do.
final class PlanNone extends PlanOutcome {
  const new();
}

/// The phone had none: the account's plan was taken.
final class PlanTookAccount extends PlanOutcome {
  const new();
}

/// Both are the same: nothing changed.
final class PlanSame extends PlanOutcome {
  const new();
}

/// Both exist and differ: the person chooses (nothing was changed yet).
final class PlanNeedsChoice extends PlanOutcome {
  const new(this.account, this.phone);

  final RemotePlan account;
  final WorkoutPlan phone;
}

/// The two plans of a conflict: which one stays.
enum PlanChoice { thisPhone, account }

@immutable
class RestoreSummary {
  const new({
    required this.sessionsAdded,
    required this.skipped,
    required this.plan,
    this.levelRaised = false,
    this.chosenDayTaken = false,
  });

  /// Workouts new to this phone.
  final int sessionsAdded;

  /// Rows of the account the app could not read (kept there, not restored).
  final int skipped;
  final PlanOutcome plan;
  final bool levelRaised;
  final bool chosenDayTaken;
}
