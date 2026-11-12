import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// What is remembered of a plan or state that was sent or taken, so an
/// unchanged one is not sent again.
String planFingerprint(WorkoutPlan plan) =>
    sha256.convert(utf8.encode(jsonEncode(plan.toJson()))).toString();

String stateFingerprint(Level bestLevel, ChosenDay? chosenDay) => sha256
    .convert(
      utf8.encode('${bestLevel.name}|${jsonEncode(chosenDay?.toJson())}'),
    )
    .toString();
