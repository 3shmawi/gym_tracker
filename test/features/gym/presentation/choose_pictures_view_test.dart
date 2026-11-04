import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/catalog_picture.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/choose_pictures_view.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

CatalogPicture pic(int n, String frame) => CatalogPicture(
  publicId: 'exercises/ek-${n.toString().padLeft(4, '0')}-$frame',
  exerciseKey: 'ek-${n.toString().padLeft(4, '0')}',
  frame: frame,
  title: 'Dumbbell Bench Press',
);

final List<CatalogPicture> results = [
  for (var n = 1; n <= 4; n++) ...[pic(n, 'tension'), pic(n, 'relaxation')],
];

class Calls {
  final searches = <String>[];
  final toggles = <CatalogPicture>[];
  int saves = 0;
  int retries = 0;
  int removes = 0;
}

Widget view({
  AsyncValue<List<CatalogPicture>>? state,
  List<String> chosen = const [],
  bool offline = false,
  bool canRemove = false,
  Calls? calls,
}) {
  final c = calls ?? Calls();
  return AppScaffold(
    body: ChoosePicturesView(
      exerciseName: 'Flat Dumbbell Press',
      query: TextEditingController(text: 'flat dumbbell press'),
      results: state,
      chosen: chosen,
      // A bundled drawing stands in for the library's pictures.
      image: (_) => AssetImage(ExerciseImages.thumb('flat_db_press')),
      offline: offline,
      saving: false,
      actions: ChoosePicturesActions(
        onSearch: c.searches.add,
        onToggle: c.toggles.add,
        onSave: () => c.saves++,
        onRetry: () => c.retries++,
        onRemoveAll: canRemove ? () => c.removes++ : null,
      ),
    ),
  );
}

void main() {
  testWidgets('tap to choose, numbered in order; save', (tester) async {
    final calls = Calls();
    await tester.pumpApp(
      view(
        state: AsyncData(results),
        chosen: [results[2].publicId, results[0].publicId],
        calls: calls,
      ),
    );
    expect(find.text('2 of 6 chosen · the first is the cover'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Dumbbell Bench Press, start of the move, chosen, number 1',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.bySemanticsLabel('Dumbbell Bench Press, end of the move').first,
    );
    expect(calls.toggles.single.frame, 'relaxation');
    await tester.tap(find.byKey(const Key('pictures_save')));
    expect(calls.saves, 1);
  });

  testWidgets('six chosen: the rest are off', (tester) async {
    final calls = Calls();
    await tester.pumpApp(
      view(
        state: AsyncData(results),
        chosen: [for (final p in results.take(6)) p.publicId],
        calls: calls,
      ),
    );
    expect(find.text('6 chosen, the most there can be'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('number')).first);
    await tester.tap(
      find.bySemanticsLabel('Dumbbell Bench Press, start of the move').last,
    );
    expect(calls.toggles, hasLength(1), reason: 'only the chosen one');
  });

  testWidgets('search on submit; remove all; retry', (tester) async {
    final calls = Calls();
    await tester.pumpApp(
      view(
        state: const AsyncError(NetworkFailure(), StackTrace.empty),
        canRemove: true,
        calls: calls,
      ),
    );
    await tester.enterText(find.byType(TextField), 'chest');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(calls.searches, ['chest']);
    await tester.tap(find.byKey(const Key('pictures_retry')));
    expect(calls.retries, 1);
    await tester.tap(find.byKey(const Key('pictures_remove_all')));
    expect(calls.removes, 1);
  });

  testWidgets('offline: says search needs internet', (tester) async {
    await tester.pumpApp(view(offline: true));
    expect(find.textContaining('needs internet'), findsOneWidget);
  });

  screensUiTests({
    'choose_pictures_results': () => view(
      state: AsyncData(results),
      chosen: [results[0].publicId, results[3].publicId],
      canRemove: true,
    ),
    'choose_pictures_idle': view,
    'choose_pictures_loading': () => view(state: const AsyncLoading()),
    'choose_pictures_empty': () => view(state: const AsyncData([])),
    'choose_pictures_error': () =>
        view(state: const AsyncError(NetworkFailure(), StackTrace.empty)),
    'choose_pictures_offline': () => view(offline: true),
  });
}
