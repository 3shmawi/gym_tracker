import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// pgTAP cannot read a JSON file, so the valid and refused colour codes are
/// written out in `supabase/tests/gym_brand_color.test.sql`. This keeps that
/// list equal to the shared vectors the app and the dashboard test against
/// (docs/features/brand_colour_vectors.json).
void main() {
  final vectors = jsonDecode(
    File('docs/features/brand_colour_vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final sql = File('supabase/tests/gym_brand_color.test.sql')
      .readAsStringSync();

  String literal(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", "''")
        .replaceAll('\n', r'\n');
    return "E'$escaped'";
  }

  test('every valid shared code is checked as valid in pgTAP', () {
    final valid = (vectors['valid']! as List<Object?>).cast<String>();
    expect(valid, isNotEmpty);
    for (final v in valid) {
      expect(
        sql,
        contains('private.brand_color_ok(${literal(v)}), true'),
        reason: v,
      );
    }
  });

  test('every refused shared code is checked as refused in pgTAP', () {
    final invalid = (vectors['invalid']! as List<Object?>).cast<String>();
    expect(invalid.length, greaterThanOrEqualTo(15));
    for (final v in invalid) {
      expect(
        sql,
        contains('private.brand_color_ok(${literal(v)}), false'),
        reason: v,
      );
    }
  });

  test('the migration checks the value and grants only that column', () {
    final migration = File('supabase/migrations/0021_gym_brand_color.sql')
        .readAsStringSync();
    expect(migration, contains(r"p_color ~ '^#[0-9a-f]{6}$'"));
    expect(migration, contains('grant update (brand_color)'));
    expect(migration, isNot(contains('grant update on')));
    expect(migration, isNot(contains('to anon')));
  });
}
