import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/domain/repositories/exercise_library.dart';

/// The library bundled in the app ([ExerciseCatalog]).
class CatalogExerciseLibrary implements ExerciseLibrary {
  new([List<LibraryExercise> exercises = ExerciseCatalog.all])
    : all = List.unmodifiable(exercises),
      _byId = {for (final e in exercises) e.id: e};

  @override
  final List<LibraryExercise> all;
  final Map<String, LibraryExercise> _byId;

  @override
  LibraryExercise? byId(String id) => _byId[id];
}
