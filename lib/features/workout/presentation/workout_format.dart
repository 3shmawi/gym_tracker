import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Number formats for weights and sets. Western digits in both languages,
/// as on gym plates and machines.
abstract final class WorkoutFormat {
  /// Keeps [text] left-to-right inside Arabic text (Unicode isolate), so
  /// "22.5×12, 12, 11" is never reordered into "11 ,12 ,12×22.5".
  static String ltr(String text) => '\u2066$text\u2069';

  /// 52.5 → "52.5", 50 → "50".
  static String weight(double kg) {
    final fixed = kg.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// The load in [unit]: kg "52.5", a plate "#7", reps only and seconds ""
  /// (none).
  static String amount(double value, [ExerciseUnit unit = ExerciseUnit.kg]) =>
      switch (unit) {
        ExerciseUnit.kg => weight(value),
        ExerciseUnit.plate => '#${weight(value)}',
        ExerciseUnit.reps || ExerciseUnit.seconds => '',
      };

  /// A hold as a clock, the same in both languages: 30 → "0:30", 75 →
  /// "1:15".
  static String hold(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// A set's count without a weight: reps "12", seconds "0:30".
  static String _count(int reps, ExerciseUnit unit) =>
      unit == ExerciseUnit.seconds ? hold(reps) : '$reps';

  /// One set: "52.5×12", "#7×12", reps only "12", seconds "0:30".
  static String set(
    double value,
    int reps, [
    ExerciseUnit unit = ExerciseUnit.kg,
  ]) => unit.hasWeight ? '${amount(value, unit)}×$reps' : _count(reps, unit);

  /// Last time's sets, as short as it stays clear:
  /// - same weight and reps: "50×12 ×3"
  /// - same weight: "22.5×12, 12, 11"
  /// - otherwise: "30×12, 50×10".
  /// Plates read "#7×12 ×3"; reps only "12 ×3" or "12, 12, 10"; seconds
  /// "0:30 ×3" or "0:45, 0:40".
  static String sets(
    List<LoggedSet> sets, [
    ExerciseUnit unit = ExerciseUnit.kg,
  ]) {
    if (sets.isEmpty) return '';
    final first = sets.first;
    if (!unit.hasWeight) {
      final one = _count(first.reps, unit);
      if (sets.every((s) => s.reps == first.reps)) {
        return sets.length == 1 ? one : '$one ×${sets.length}';
      }
      return sets.map((s) => _count(s.reps, unit)).join(', ');
    }
    String w(double value) => amount(value, unit);
    final sameWeight = sets.every((s) => s.weight == first.weight);
    if (sameWeight && sets.every((s) => s.reps == first.reps)) {
      final one = '${w(first.weight)}×${first.reps}';
      return sets.length == 1 ? one : '$one ×${sets.length}';
    }
    if (sameWeight) {
      final reps = sets.skip(1).map((s) => s.reps).join(', ');
      return '${w(first.weight)}×${first.reps}, $reps';
    }
    return sets.map((s) => '${w(s.weight)}×${s.reps}').join(', ');
  }

  /// "52.5 × 12", isolated so it reads the same inside Arabic text.
  /// Plates: "#7 × 12"; reps only: "12"; seconds "0:30".
  static String weightTimesReps(
    double kg,
    int reps, [
    ExerciseUnit unit = ExerciseUnit.kg,
  ]) =>
      ltr(unit.hasWeight ? '${amount(kg, unit)} × $reps' : _count(reps, unit));

  /// "3×12": sets × reps; "2×6–10" with a rep range.
  static String target(int sets, int reps, [int? top]) =>
      top == null ? '$sets×$reps' : '$sets×$reps–$top';
}
