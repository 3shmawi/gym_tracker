import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_logo_repository.dart';

/// A real 32 × 32 yellow PNG (decodes in tests and on a device).
final Uint8List testLogoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAK0lEQVR4nGP4dUaU'
  'pohh1IJRC0YtGLVg1IJRC0YtGLVg1IJRC0YtGCoWAAADa2xqaANxTAAAAABJRU5E'
  'rkJggg==',
);

/// The same picture as a tile image.
final MemoryImage testLogoImage = MemoryImage(testLogoPng);

/// Gym ids that pass the logo path rule (a UUID).
const gymA = 'd0000000-0000-4000-8000-00000000000a';
const gymB = 'd0000000-0000-4000-8000-00000000000b';
String logoPathOf(String gymId, [String ext = 'png']) => '$gymId/logo.$ext';

/// The logos bucket: answers from [files] (by path), or fails offline.
/// Counts downloads.
class FakeGymLogoRepository implements GymLogoRepository {
  new([Map<String, Uint8List>? files]) : files = {...?files};

  final Map<String, Uint8List> files;
  bool online = true;
  final List<GymLogoRef> fetched = [];

  @override
  Future<Result<Uint8List>> fetch(GymLogoRef logo) async {
    fetched.add(logo);
    if (!online) return const Failed(NetworkFailure());
    final bytes = files[logo.path];
    return bytes == null ? const Failed(UnknownFailure()) : Success(bytes);
  }
}
