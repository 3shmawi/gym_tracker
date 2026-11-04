import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/catalog_picture.dart';

/// Searches the shared picture library (public read; works without a gym).
abstract interface class PictureCatalogRepository {
  /// The pictures matching any of [words] (from `CatalogQuery.words`),
  /// both frames of a move next to each other; empty words → empty.
  Future<Result<List<CatalogPicture>>> search(List<String> words);
}

/// No backend configured (tests, a build without Supabase).
class UnconfiguredPictureCatalogRepository implements PictureCatalogRepository {
  const new();

  @override
  Future<Result<List<CatalogPicture>>> search(List<String> words) async =>
      const Success([]);
}
