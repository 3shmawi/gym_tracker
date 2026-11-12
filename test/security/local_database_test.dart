import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The phone's workout database (docs/designs/never_lose_history.md §6).
void main() {
  final files = Directory('lib/features/workout/data/local')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('it reports only these events, with only these properties', () {
    final events = <String>{};
    final properties = <String>{};
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final m in RegExp(
        r"onEvent\(\s*'([a-z_]+)'(?:,\s*\{([^}]*)\})?",
      ).allMatches(text)) {
        events.add(m.group(1)!);
        for (final p in RegExp(
          r"(?:^|,)\s*'([a-z_]+)'\s*:",
        ).allMatches(m.group(2) ?? '')) {
          properties.add(p.group(1)!);
        }
      }
    }
    expect(events, {'local_db_migrated', 'local_db_migration_failed'});
    // Buckets and one word. Never a workout, a weight, a name or an id.
    expect(properties, {'sessions', 'ms', 'reason'});
  });

  test('nothing in it logs or prints stored data', () {
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(
        RegExp(r'\b(print|debugPrint|log)\(').hasMatch(text),
        isFalse,
        reason: f.path,
      );
    }
  });

  test('SQL is fixed text: values go through arguments, never into it', () {
    for (final f in files) {
      final text = f.readAsStringSync();
      // A `$` inside rawQuery / execute text would put a value into SQL.
      for (final m in RegExp(
        r"(?:rawQuery|execute|rawInsert|rawUpdate|rawDelete)\(\s*'([^']*)'",
      ).allMatches(text)) {
        expect(m.group(1), isNot(contains(r'$')), reason: f.path);
      }
    }
  });
}
