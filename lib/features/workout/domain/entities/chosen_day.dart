import 'package:meta/meta.dart';

/// The plan day that is next instead of the one after the last finished
/// workout. Cleared when a workout is finished.
@immutable
class ChosenDay {
  const new(this.dayId, {this.byEdit = false});

  /// Unknown shapes (hand-edited or hostile data) read as no choice: the
  /// plan then simply follows the history.
  static ChosenDay? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return ChosenDay(id, byEdit: json['by_edit'] == true);
  }

  /// The day's id (`WorkoutDay.id`).
  final String dayId;

  /// Set by a plan edit to keep the waiting workout the same, not picked by
  /// the member: the "waiting since" banner still shows.
  final bool byEdit;

  Map<String, Object?> toJson() => {'id': dayId, 'by_edit': byEdit};

  @override
  bool operator ==(Object other) =>
      other is ChosenDay && other.dayId == dayId && other.byEdit == byEdit;

  @override
  int get hashCode => Object.hash(dayId, byEdit);

  @override
  String toString() => 'ChosenDay($dayId, byEdit: $byEdit)';
}
