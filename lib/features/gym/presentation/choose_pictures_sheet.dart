import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/media/cloudinary_url.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/catalog_picture.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/choose_pictures_view.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';

/// Opens the picker for a solo member's [exerciseId]. Searching starts with
/// the exercise's English name ([search]).
Future<void> showChoosePicturesSheet({
  required BuildContext context,
  required String exerciseId,
  required String exerciseName,
  required String search,
}) => showAppSheet<void>(
  context: context,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: ChoosePicturesSheet(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      search: search,
    ),
  ),
);

/// Wires [ChoosePicturesView] to the picture library and the phone's copy.
class ChoosePicturesSheet extends ConsumerStatefulWidget {
  const new({
    required this.exerciseId,
    required this.exerciseName,
    required this.search,
    super.key,
  });

  final String exerciseId;
  final String exerciseName;
  final String search;

  @override
  ConsumerState<ChoosePicturesSheet> createState() =>
      _ChoosePicturesSheetState();
}

class _ChoosePicturesSheetState extends ConsumerState<ChoosePicturesSheet> {
  late final TextEditingController _query = TextEditingController(
    text: widget.search,
  );
  AsyncValue<List<CatalogPicture>>? _results;
  List<String> _chosen = [];
  bool _hadAny = false;
  bool _saving = false;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChosen());
    unawaited(_search(widget.search));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadChosen() async {
    final media = await ref.read(soloPicturesProvider).load();
    if (!mounted) return;
    final mine = [
      for (final p in media.picturesFor(widget.exerciseId)) p.publicId,
    ];
    setState(() {
      _chosen = mine;
      _hadAny = mine.isNotEmpty;
    });
  }

  Future<void> _search(String text) async {
    final words = CatalogQuery.words(text);
    if (words.isEmpty) {
      setState(() => _results = null);
      return;
    }
    final id = ++_searchId;
    setState(() => _results = const AsyncLoading());
    final result = await ref.read(pictureCatalogProvider).search(words);
    if (!mounted || id != _searchId) return;
    setState(() {
      _results = switch (result) {
        Success(:final value) => AsyncData(value),
        Failed(:final failure) => AsyncError(failure, StackTrace.current),
      };
    });
  }

  void _toggle(CatalogPicture p) => setState(() {
    final id = p.publicId;
    _chosen = _chosen.contains(id)
        ? [
            for (final c in _chosen)
              if (c != id) c,
          ]
        : [..._chosen, id];
  });

  Future<void> _save(List<String> ids) async {
    setState(() => _saving = true);
    final result = await ref
        .read(soloPicturesProvider)
        .choose(widget.exerciseId, ids);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Success) {
      unawaited(
        Analytics.capture('solo_pictures_saved', {'count': ids.length}),
      );
      ref.invalidate(activeGymMediaProvider);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final toImage = ref.watch(gymPictureImageProvider);
    return ChoosePicturesView(
      exerciseName: widget.exerciseName,
      query: _query,
      results: _results,
      chosen: _chosen,
      image: (id) => toImage(id, PictureSize.thumb),
      offline: !(ref.watch(deviceOnlineProvider).value ?? true),
      saving: _saving,
      actions: ChoosePicturesActions(
        onSearch: (text) => unawaited(_search(text)),
        onToggle: _toggle,
        onSave: () => unawaited(_save(_chosen)),
        onRetry: () => unawaited(_search(_query.text)),
        onRemoveAll: _hadAny ? () => unawaited(_save(const [])) : null,
      ),
    );
  }
}
