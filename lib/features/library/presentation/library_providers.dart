import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/connectivity.dart';
import 'package:gym_tracker/features/library/data/catalog_exercise_library.dart';
import 'package:gym_tracker/features/library/domain/repositories/exercise_library.dart';

/// The exercise library. Override in tests:
/// `exerciseLibraryProvider.overrideWithValue(fake)`.
final exerciseLibraryProvider = Provider<ExerciseLibrary>(
  (ref) => CatalogExerciseLibrary(),
);

/// Whether the device has a network connection (true until known).
final deviceOnlineProvider = StreamProvider<bool>(
  (ref) => ConnectivityStatus.onlineChanges,
);
