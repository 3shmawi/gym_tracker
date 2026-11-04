import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// Shared formats for the progress screens.
abstract final class ProgressFormat {
  /// "Mon, Oct 20" / "الاثنين، 20 أكتوبر", with Western digits like every
  /// number in the app; "Today" for today.
  static String date(AppLocalizations l10n, DateTime date, DateTime now) {
    final d = date.toLocal();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return l10n.progressToday;
    }
    final format = d.year == now.year
        ? DateFormat.MMMEd(l10n.localeName)
        : DateFormat.yMMMEd(l10n.localeName);
    return (format..useNativeDigits = false).format(d);
  }

  /// A weight change as a badge: "↑ +2.5", "↓ −2.5" or "Same".
  static (String, AppTone) change(AppLocalizations l10n, double kg) {
    if (kg > 0) {
      return (WorkoutFormat.ltr('↑ +${WorkoutFormat.weight(kg)}'), AppTone.up);
    }
    if (kg < 0) {
      return (
        WorkoutFormat.ltr('↓ −${WorkoutFormat.weight(-kg)}'),
        AppTone.down,
      );
    }
    return (l10n.progressSame, AppTone.keep);
  }

  /// "52.5 kg", "plate 7", or "Reps only" (no weight to show).
  static String kg(
    AppLocalizations l10n,
    double weight, [
    ExerciseUnit unit = ExerciseUnit.kg,
  ]) => switch (unit) {
    ExerciseUnit.kg => l10n.weightKg(WorkoutFormat.weight(weight)),
    ExerciseUnit.plate => l10n.weightPlate(WorkoutFormat.weight(weight)),
    ExerciseUnit.reps => l10n.planUnitReps,
  };
}
