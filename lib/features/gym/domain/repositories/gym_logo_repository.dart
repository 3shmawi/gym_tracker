import 'dart:typed_data';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';

/// The gym's logo file on the server (the private `gym-logos` bucket; a
/// member reads their own gyms' folders only).
abstract interface class GymLogoRepository {
  /// The bytes of [logo], unchecked (the caller checks them).
  Future<Result<Uint8List>> fetch(GymLogoRef logo);
}

/// A logo the phone keeps: which one, and the file it is in.
class StoredGymLogo {
  const new({required this.logo, required this.filePath});

  final GymLogoRef logo;

  /// The file on the phone. Its name holds the version, so a new logo is a
  /// new file (Flutter's image cache knows a file by its path).
  final String filePath;
}

/// The phone's copy of the gyms' logos, so the tiles show them offline
/// (docs/designs/gym_logo.md §5).
abstract interface class GymLogoStore {
  /// Every logo kept, by gym id. Entries whose file is gone are left out.
  Future<Map<String, StoredGymLogo>> load();

  /// Keeps [bytes] (already checked) as [logo]'s file, replacing the gym's
  /// previous one.
  Future<Result<StoredGymLogo>> save(GymLogoRef logo, Uint8List bytes);

  /// Forgets the gym's logo and deletes its file.
  Future<Result<void>> remove(String gymId);

  /// Forgets every logo (sign-out, a session ended, the account deleted).
  Future<Result<void>> clear();
}
