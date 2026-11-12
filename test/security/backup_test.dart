import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Backing up a member's own training (docs/designs/never_lose_history.md §6).
void main() {
  final files = [
    for (final f in Directory('lib/features/backup').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('it reports only these events, with only this property', () {
    final events = <String>{};
    final properties = <String>{};
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final m in RegExp(
        r"Analytics\.capture\(\s*'([a-z_]+)'(?:,\s*\{([^}]*)\})?",
      ).allMatches(text)) {
        events.add(m.group(1)!);
        for (final p in RegExp(
          r"(?:^|,)\s*'([a-z_]+)'\s*:",
        ).allMatches(m.group(2) ?? '')) {
          properties.add(p.group(1)!);
        }
      }
    }
    expect(events, {
      'backup_sign_in_started',
      'backup_code_failed',
      'restore_done',
      'backup_enabled',
      'backup_synced',
      'backup_failed',
      'backup_disabled',
      'backup_offer_shown',
      'backup_offer_dismissed',
      'backup_erased',
    });
    // One word: network | signin | refused, or the kind of code problem.
    // Never an email, a code, an id, a name, a workout or a count.
    expect(properties, {'reason', 'place'});
  });

  test('nothing logs or prints, and no secret is kept in preferences', () {
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(
        RegExp(r'\b(print|debugPrint|log)\(').hasMatch(text),
        isFalse,
        reason: f.path,
      );
      for (final banned in ['access_token', 'refresh_token', 'password']) {
        expect(text, isNot(contains(banned)), reason: '${f.path}: $banned');
      }
    }
  });

  test('SQL is fixed text: only placeholders, never a value', () {
    final queue = File('lib/features/backup/data/sqlite_backup_queue.dart')
        .readAsStringSync();
    // The one dynamic piece is a list of "?" marks.
    expect(queue, contains("List.filled(ids.length, '?')"));
    expect(queue, isNot(contains(r'$clientId')));
  });

  test('the backup runs only for a signed in member who turned it on', () {
    final sync = File('lib/features/backup/presentation/backup_sync.dart')
        .readAsStringSync();
    expect(sync, contains('!settings.enabled'));
    expect(sync, contains('isSignedIn'));
  });
}
