import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/l10n/l10n.dart';

String muscleLabel(AppLocalizations l10n, MuscleGroup muscle) =>
    switch (muscle) {
      MuscleGroup.chest => l10n.muscleChest,
      MuscleGroup.back => l10n.muscleBack,
      MuscleGroup.shoulders => l10n.muscleShoulders,
      MuscleGroup.arms => l10n.muscleArms,
      MuscleGroup.legs => l10n.muscleLegs,
      MuscleGroup.core => l10n.muscleCore,
    };

String equipmentLabel(AppLocalizations l10n, Equipment equipment) =>
    switch (equipment) {
      Equipment.dumbbell => l10n.equipDumbbell,
      Equipment.barbell => l10n.equipBarbell,
      Equipment.bench => l10n.equipBench,
      Equipment.rack => l10n.equipRack,
      Equipment.machine => l10n.equipMachine,
      Equipment.cable => l10n.equipCable,
      Equipment.bodyweight => l10n.equipBodyweight,
    };

/// "Dumbbells + Bench".
String equipmentList(AppLocalizations l10n, List<Equipment> equipment) =>
    equipment.map((e) => equipmentLabel(l10n, e)).join(' + ');
