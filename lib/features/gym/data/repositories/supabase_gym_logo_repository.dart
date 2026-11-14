import 'dart:typed_data';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_logo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Downloads a logo from the private `gym-logos` bucket with the member's
/// session (Storage RLS, migration 0008: members read their gyms' folders).
class SupabaseGymLogoRepository implements GymLogoRepository {
  const new(this._client, {this.retries = 2, this.download});

  final SupabaseClient _client;
  final int retries;

  /// Downloads the object; tests pass their own.
  final Future<Uint8List> Function(String path, String nonce)? download;

  static const bucket = 'gym-logos';

  @override
  Future<Result<Uint8List>> fetch(GymLogoRef logo) => guard(() async {
    // The path came through `Gym.readLogoPath`; checked again here because
    // it goes into a URL.
    if (Gym.readLogoPath(logo.gymId, logo.path) != logo.path) {
      throw const FormatException('logo path');
    }
    // The version as a cache nonce: the dashboard uploads with a 60 s
    // cache-control already; a CDN copy of the previous file is skipped too.
    final nonce = '${logo.version}';
    return await (download ?? _download)(logo.path, nonce);
  }, retries: retries);

  Future<Uint8List> _download(String path, String nonce) =>
      _client.storage.from(bucket).download(path, cacheNonce: nonce);
}
