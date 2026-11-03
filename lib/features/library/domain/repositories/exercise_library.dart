import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';

/// The shared exercise library. Today it is bundled with the app; the
/// interface lets it come from the server later (one list for every gym)
/// without changing the screens.
abstract interface class ExerciseLibrary {
  /// Every exercise, in a stable order.
  List<LibraryExercise> get all;

  /// The exercise with this id, or null (an unknown or crafted id).
  LibraryExercise? byId(String id);
}
