import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/catalog_picture.dart';
import 'package:gym_tracker/features/gym/domain/repositories/picture_catalog_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `exercise_images` (migration 0013; anyone may read). The dashboard
/// contract's "any word" search: `keywords` overlaps the words
/// (docs/features/gym_exercise_images.md, "Find pictures").
class SupabasePictureCatalogRepository implements PictureCatalogRepository {
  const new(this._client, {this.retries = 2, this.readRows});

  final SupabaseClient _client;
  final int retries;

  /// Reads the rows; tests pass rows.
  final Future<List<Object?>> Function(List<String> words)? readRows;

  /// One screen of results (two frames per move).
  static const maxRows = 60;

  @override
  Future<Result<List<CatalogPicture>>> search(List<String> words) =>
      guard(() async {
        if (words.isEmpty) return const <CatalogPicture>[];
        if (words.length > CatalogQuery.maxWords ||
            words.any((w) => CatalogQuery.words(w).singleOrNull != w)) {
          throw const FormatException('search words');
        }
        final rows = await (readRows ?? _read)(words);
        return rows.map(CatalogPicture.tryParse).nonNulls.toList();
      }, retries: retries);

  /// Explicit columns; the words go as values of the array filter.
  Future<List<Object?>> _read(List<String> words) => _client
      .from('exercise_images')
      .select('public_id, exercise_key, frame, title_en')
      .overlaps('keywords', words)
      .order('exercise_key')
      .order('frame', ascending: false)
      .limit(maxRows);
}
