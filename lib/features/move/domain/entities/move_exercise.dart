/// The exercises Move games can count. The [id] is stored (analytics, the
/// route) and never reused; [catalogExerciseId] is the library exercise a
/// round is saved as.
enum MoveExerciseId {
  pushUps('push_ups', catalogExerciseId: 'push_ups');

  new(this.id, {required this.catalogExerciseId});

  final String id;
  final String catalogExerciseId;

  /// Null for anything unknown (a link, an old value).
  static MoveExerciseId? fromId(String? id) =>
      values.where((e) => e.id == id).firstOrNull;
}
