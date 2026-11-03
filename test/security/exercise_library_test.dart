import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The exercise library is bundled content plus a search box: it must stay
/// offline, send only fixed words to analytics, and never look at secrets.
void main() {
  final files = [
    for (final f in Directory('lib/features/library').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('the library feature has code files to check', () {
    expect(files.length, greaterThan(8));
  });

  test('it never touches the network, storage, secrets or the console', () {
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final banned in [
        'package:supabase',
        'package:http',
        'dart:io',
        'HttpClient',
        'Backend.',
        'shared_preferences',
        'flutter_secure_storage',
        'print(',
        'debugPrint',
        'Env.',
        'launchUrl',
      ]) {
        expect(text, isNot(contains(banned)), reason: '${file.path}: $banned');
      }
    }
  });

  test('analytics: only the agreed events, with a fixed word as property', () {
    final events = <String>{};
    final properties = <String>{};
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final m in RegExp(
        r"Analytics\.capture\(\s*'([a-z_]+)'(?:,\s*\{([^}]*)\})?",
      ).allMatches(text)) {
        events.add(m.group(1)!);
        for (final p in RegExp(
          r"(?:^|,)\s*'([a-z_]+)'\s*:",
        ).allMatches(m.group(2) ?? '')) {
          properties.add(p.group(1)!);
        }
        // Whatever is typed in the search box never goes in a property.
        expect(m.group(2) ?? '', isNot(contains('query')));
      }
    }
    expect(events, {
      'library_opened',
      'library_exercise_viewed',
      'library_custom_chosen',
    });
    // `muscle`: chest | back | shoulders | arms | legs | core.
    expect(properties, {'muscle'});
  });

  test('the catalog is data: no code, links or markup in its text', () {
    final text = File('lib/features/library/data/exercise_catalog.dart')
        .readAsStringSync();
    for (final banned in [
      'http:',
      'https:',
      '<script',
      'javascript:',
      'eval(',
    ]) {
      expect(text, isNot(contains(banned)), reason: banned);
    }
  });
}
