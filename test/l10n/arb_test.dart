import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every string exists in English and Arabic, nothing is left empty, and
/// placeholders ({name}) match between the two languages.
void main() {
  Map<String, String> strings(String path) {
    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final entry in json.entries)
        if (!entry.key.startsWith('@')) entry.key: entry.value as String,
    };
  }

  Set<String> placeholders(String text) =>
      RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

  final en = strings('lib/l10n/app_en.arb');
  final ar = strings('lib/l10n/app_ar.arb');

  test('Arabic has exactly the English keys', () {
    expect(ar.keys.toSet().difference(en.keys.toSet()), isEmpty);
    expect(en.keys.toSet().difference(ar.keys.toSet()), isEmpty);
  });

  test('no empty translations', () {
    final empty = [
      ...en.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => 'en.${e.key}'),
      ...ar.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => 'ar.${e.key}'),
    ];
    expect(empty, isEmpty);
  });

  test('placeholders match between languages', () {
    final mismatched = [
      for (final key in en.keys)
        if (ar.containsKey(key) &&
            !placeholders(en[key]!).containsAll(placeholders(ar[key]!)))
          key
        else if (ar.containsKey(key) &&
            !placeholders(ar[key]!).containsAll(placeholders(en[key]!)))
          key,
    ];
    expect(mismatched, isEmpty);
  });
}
